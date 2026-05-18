from __future__ import annotations

import base64
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
import yaml
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

from .helpers import (
    assert_login_page,
    curl_from_pod,
    exec_in_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
    kubectl,
)
from .conftest import helm_install


@pytest.mark.e2e
def test_trusted_ca_init_and_curl_trusts_custom_cert(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    server_dns_name = f"nginx-trust.{namespace}.svc.cluster.local"

    # Generate CA + server cert
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    ca_subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "kasm-e2e-ca")])
    ca_cert = (
        x509.CertificateBuilder()
        .subject_name(ca_subject)
        .issuer_name(ca_subject)
        .public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(timezone.utc) - timedelta(days=1))
        .not_valid_after(datetime.now(timezone.utc) + timedelta(days=30))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(ca_key, hashes.SHA256())
    )

    server_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    server_subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, server_dns_name)])
    server_cert = (
        x509.CertificateBuilder()
        .subject_name(server_subject)
        .issuer_name(ca_cert.subject)
        .public_key(server_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(timezone.utc) - timedelta(days=1))
        .not_valid_after(datetime.now(timezone.utc) + timedelta(days=30))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(server_dns_name)]), critical=False)
        .sign(ca_key, hashes.SHA256())
    )

    ca_pem = ca_cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
    server_cert_pem = server_cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
    server_key_pem = server_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")

    # Create nginx TLS secret + deployment/service
    tls_cert_b64 = base64.b64encode(server_cert_pem.encode()).decode()
    tls_key_b64 = base64.b64encode(server_key_pem.encode()).decode()
    nginx_manifest = f"""
apiVersion: v1
kind: Secret
metadata:
  name: nginx-trust-tls
type: kubernetes.io/tls
data:
  tls.crt: {tls_cert_b64}
  tls.key: {tls_key_b64}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-trust
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-trust
  template:
    metadata:
      labels:
        app: nginx-trust
    spec:
      containers:
        - name: nginx
          image: nginx:1.30-alpine
          ports:
            - containerPort: 443
          volumeMounts:
            - name: tls
              mountPath: /etc/nginx/tls
              readOnly: true
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: tls
          secret:
            secretName: nginx-trust-tls
        - name: nginx-conf
          configMap:
            name: nginx-trust-conf
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-trust-conf
data:
  default.conf: |
    server {{
      listen 443 ssl;
      ssl_certificate /etc/nginx/tls/tls.crt;
      ssl_certificate_key /etc/nginx/tls/tls.key;
      location / {{
        return 200 "ok\\n";
      }}
    }}
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-trust
spec:
  selector:
    app: nginx-trust
  ports:
    - name: https
      port: 443
      targetPort: 443
"""
    manifest_path = temp_workdir / "nginx.yaml"
    manifest_path.write_text(nginx_manifest)
    def apply_nginx_trust() -> None:
        kubectl(["apply", "-f", str(manifest_path)], namespace=namespace)

    apply_nginx_trust()

    # Install Kasm with trusted CA enabled and CA injected as configmap data
    values_path = temp_workdir / "values.yaml"
    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "certificate": {
            "secretName": "kasm-deployment-tls",
        },
        "trustedCaBundle": {
            "enabled": True,
            "caCerts": {
                "kasm-e2e-ca.crt": ca_pem,
            },
        },
    }
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
        setup_namespace_fn=apply_nginx_trust,
    )

    # Basic proxy check (SPA-tolerant HTML validation)
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)

    # Verify trusted-ca-init ran successfully by checking init container termination code in proxy pod
    init_status = exec_in_pod(
        namespace,
        proxy_pod,
        ["sh", "-lc", "cat /proc/1/cgroup >/dev/null; echo ok"],
    )
    assert init_status.returncode == 0

    # The real point: curl WITHOUT -k to our nginx server using CA-trusted cert
    curl_result = exec_in_pod(
        namespace,
        proxy_pod,
        ["curl", "-sS", "--max-time", "20", f"https://{server_dns_name}:443/"],
    )
    assert curl_result.returncode == 0
    assert "ok" in curl_result.stdout
