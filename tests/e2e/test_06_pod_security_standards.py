from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from .conftest import helm_install
from .helpers import (
    apply_restricted_pod_security,
    assert_login_page,
    curl_from_pod,
    get_api_image,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
    kubectl,
    wait_for_job_succeeded,
)


@pytest.mark.e2e
def test_chart_installs_in_restricted_namespace_and_rejects_noncompliant_pods(
    installer,
    temp_workdir: Path,
) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    apply_restricted_pod_security(namespace)

    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "certificate": {
            "secretName": "kasm-deployment-tls",
        },
        "proxyService": {
            "type": "ClusterIP",
        },
        "ingress": {
            "enabled": False,
        },
        "imagePullSecrets": {
            "enabled": False,
        },
        "components": {
            "guac": {
                "enabled": True,
            },
            "rdpGateway": {
                "enabled": True,
            },
            "rdpHttpsGateway": {
                "enabled": True,
            },
        },
        "dbManagement": {
            "initialize": True,
            "upgrade": {
                "enable": False,
            },
            "backupCron": {
                "enabled": True,
                "schedule": "0 * * * *",
            },
        },
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
        setup_namespace_fn=lambda: apply_restricted_pod_security(namespace),
    )

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)

    cronjob_name = f"{e2e_config.release_name}-db-backup"
    kubectl(["get", "cronjob", cronjob_name], namespace=namespace)

    manual_job_name = f"{e2e_config.release_name}-db-backup-manual"
    kubectl(["delete", "job", manual_job_name, "--ignore-not-found"], namespace=namespace, check=False)
    kubectl(
        ["create", "job", f"--from=cronjob/{cronjob_name}", manual_job_name],
        namespace=namespace,
    )
    wait_for_job_succeeded(namespace, job_name=manual_job_name, timeout_seconds=1200)

    bad_pod_manifest = f"""
apiVersion: v1
kind: Pod
metadata:
  name: pod-security-should-fail
spec:
  containers:
    - name: bad
      image: "{get_api_image()}"
      imagePullPolicy: Never
      command: ["/bin/sh", "-c", "sleep 3600"]
"""
    bad_pod_path = temp_workdir / "bad-pod.yaml"
    bad_pod_path.write_text(bad_pod_manifest)

    apply_result = kubectl(
        ["apply", "-f", str(bad_pod_path)],
        namespace=namespace,
        check=False,
    )
    combined_output = "\n".join(
        part for part in [apply_result.stdout, apply_result.stderr] if part
    )

    assert apply_result.returncode != 0, "expected the restricted namespace to reject a non-compliant pod"
    assert "podsecurity" in combined_output.lower(), combined_output
