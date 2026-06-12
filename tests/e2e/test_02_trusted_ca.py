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

    # Install Kasm with trusted CA enabled and CA injected as configmap data.
    # Lower per-component resource requests so all pods (api, manager, proxy,
    # guac + nginx sidecar, rdpGateway + nginx sidecar, rdpHttpsGateway +
    # nginx sidecar, bundled db) fit on the single-node kind cluster in
    # gitlab runner.
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
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
        "components": {
            "api": {"resources": low_resources},
            "manager": {"resources": low_resources},
            "proxy": {"resources": low_resources_proxy},
            "guac": {"resources": low_resources},
            "rdpGateway": {"resources": low_resources_gw},
            "rdpHttpsGateway": {"resources": low_resources_gw},
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

    release = e2e_config.release_name

    # Verify trusted-ca-init actually completed on every workload that gets it.
    # Reads the real initContainerStatuses exitCode rather than merely proving we
    # can exec into the pod (the previous check ran a no-op in the main container
    # and asserted nothing about the init container).
    for component in ("proxy", "api", "manager", "guac", "rdp-gateway", "rdp-https-gateway"):
        pod = get_first_pod_by_selector(namespace, f"app.kubernetes.io/component={component}")
        status = kubectl(
            [
                "get",
                "pod",
                pod,
                "-o",
                "jsonpath={range .status.initContainerStatuses[?(@.name=='trusted-ca-init')]}"
                "{.state.terminated.exitCode}{end}",
            ],
            namespace=namespace,
        )
        assert status.stdout.strip() == "0", (
            f"trusted-ca-init did not complete successfully on {component} pod {pod}: "
            f"exitCode={status.stdout.strip()!r}"
        )

    # The real point: each runtime must trust our CA-signed nginx server when
    # connecting WITHOUT -k. Cover the OpenSSL-based stacks (curl). (component
    # label, app container name) — None uses the pod's default container.
    #   proxy             — nginx / OpenSSL
    #   guac              — C/C++ OpenSSL
    #   rdp-gateway       — Go crypto/tls (reads /etc/ssl/certs/ca-certificates.crt)
    #   rdp-https-gateway — C/C++ OpenSSL / Redemption
    openssl_curl_targets = [
        ("proxy", None),
        ("guac", f"{release}-guac"),
        ("rdp-gateway", f"{release}-rdp-gateway"),
        ("rdp-https-gateway", f"{release}-rdp-https-gateway"),
    ]
    for component, container in openssl_curl_targets:
        pod = get_first_pod_by_selector(namespace, f"app.kubernetes.io/component={component}")
        result = exec_in_pod(
            namespace,
            pod,
            ["curl", "-sS", "--max-time", "20", f"https://{server_dns_name}:443/"],
            container=container,
        )
        assert result.returncode == 0 and "ok" in result.stdout, (
            f"{component} CA trust check (curl) failed.\n"
            f"stdout: {result.stdout}\n"
            f"stderr: {result.stderr}"
        )

    # Python trust: the original customer bug was requests/certifi not honoring
    # the OS trust store. trustedCaEnv sets SSL_CERT_FILE (read by urllib via
    # ssl.create_default_context) AND REQUESTS_CA_BUNDLE (read by requests) — so
    # exercise BOTH, and on api AND manager (both get the env; the prior test
    # only covered api+urllib).
    for component in ("api", "manager"):
        pod = get_first_pod_by_selector(namespace, f"app.kubernetes.io/component={component}")
        urllib_result = exec_in_pod(
            namespace,
            pod,
            [
                "python3",
                "-c",
                "import urllib.request; "
                f"r = urllib.request.urlopen('https://{server_dns_name}:443/', timeout=20); "
                "assert r.status == 200, r.status",
            ],
        )
        assert urllib_result.returncode == 0, (
            f"{component} Python urllib (SSL_CERT_FILE) trust check failed.\n"
            f"stdout: {urllib_result.stdout}\n"
            f"stderr: {urllib_result.stderr}"
        )
        requests_result = exec_in_pod(
            namespace,
            pod,
            [
                "python3",
                "-c",
                "import requests; "
                f"r = requests.get('https://{server_dns_name}:443/', timeout=20); "
                "assert r.status_code == 200, r.status_code",
            ],
        )
        assert requests_result.returncode == 0, (
            f"{component} Python requests (REQUESTS_CA_BUNDLE) trust check failed.\n"
            f"stdout: {requests_result.stdout}\n"
            f"stderr: {requests_result.stderr}"
        )

    # Negative control: with the CA env unset, verification MUST fail. Without
    # this, the positive checks above could pass for the wrong reason (e.g. the
    # cert being acceptable via some other path) and we'd never know the injected
    # CA is what makes trust work. The script signals via stdout and always exits
    # 0 — exec_in_pod runs kubectl with check=True, so a non-zero process exit
    # (e.g. the expected SSLError) would raise CommandError before we could
    # inspect the result.
    negative_control_script = (
        "import requests\n"
        "try:\n"
        f"    requests.get('https://{server_dns_name}:443/', timeout=20)\n"
        "    print('UNEXPECTED_NO_SSL_ERROR')\n"
        "except requests.exceptions.SSLError:\n"
        "    print('EXPECTED_SSL_ERROR')\n"
        "except Exception as exc:\n"
        "    print('UNEXPECTED_ERROR:' + type(exc).__name__)\n"
    )
    api_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=api")
    negative_result = exec_in_pod(
        namespace,
        api_pod,
        ["env", "-u", "REQUESTS_CA_BUNDLE", "-u", "SSL_CERT_FILE", "python3", "-c", negative_control_script],
    )
    assert "EXPECTED_SSL_ERROR" in negative_result.stdout, (
        "Negative control failed: a request without the injected CA should raise "
        "requests.exceptions.SSLError.\n"
        f"stdout: {negative_result.stdout}\n"
        f"stderr: {negative_result.stderr}"
    )
