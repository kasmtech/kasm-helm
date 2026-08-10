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

    # Lower per-component resource requests so all pods (api, manager, proxy,
    # guac + nginx sidecar, rdpGateway + nginx sidecar, rdpHttpsGateway +
    # nginx sidecar, bundled db, and the manual db-backup job) fit on the
    # single-node kind cluster in gitlab runner.
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
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
            "api": {"resources": low_resources},
            "manager": {"resources": low_resources},
            "proxy": {"resources": low_resources_proxy},
            "guac": {
                "enabled": True,
                "resources": low_resources,
            },
            "rdpGateway": {
                "enabled": True,
                "resources": low_resources_gw,
            },
            "rdpHttpsGateway": {
                "enabled": True,
                "resources": low_resources_gw,
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
        # H6/H5 carve-out: the observability.hostLogs DaemonSet mounts a hostPath and runs as
        # root, both forbidden by the restricted Pod Security Standard (see plan §3a and the
        # "Kyverno/PSS handling of the DaemonSet" contract row in PROGRESS.md). A restricted
        # namespace install must therefore disable it and fall back to the nginxLogs sidecar,
        # which collects the same nginx logs (plus connection metrics) from inside the compliant
        # proxy pod instead. See test_observability_hostlogs_daemonset_rejected_in_restricted_ns
        # below for the proof that the DaemonSet really is rejected when left at its default.
        "observability": {
            "hostLogs": {"enabled": False},
            "nginxLogs": {"enabled": True},
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


@pytest.mark.e2e
def test_observability_hostlogs_daemonset_rejected_in_restricted_namespace(
    installer,
    temp_workdir: Path,
) -> None:
    """H6 addition: prove the hostLogs DaemonSet is genuinely rejected by `restricted` admission
    when left at its (enabled-by-default) setting, which is exactly why the main test above must
    install with hostLogs.enabled=false + nginxLogs.enabled=true instead.

    This does NOT do a full chart install (unnecessary and slow for what's being proven): it
    renders just the DaemonSet's pod template via `helm template` with default observability
    values, patches in a unique name/namespace, and applies it directly to a namespace enforcing
    the restricted Pod Security Standard. The `runAsUser: 0` + missing `runAsNonRoot: true`
    security context (see otel-collector-daemonset.yaml — deliberately not routed through
    kasm.securityContext, which never grants root) must be rejected by admission.

    Run with `make e2e-pss`.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    apply_restricted_pod_security(namespace)

    from .helpers import helm

    render_result = helm(
        [
            "template",
            "kasm-pss-daemonset-check",
            e2e_config.chart_dir,
            "-n",
            namespace,
            "--set",
            "publicAddr=kasm.example.com",
            "--set",
            "certificate.secretName=kasm-deployment-tls",
            "--show-only",
            "templates/otel-collector-daemonset.yaml",
        ]
    )
    daemonset_manifest_path = temp_workdir / "hostlogs-daemonset.yaml"
    daemonset_manifest_path.write_text(render_result.stdout)

    apply_result = kubectl(
        ["apply", "-f", str(daemonset_manifest_path)],
        namespace=namespace,
        check=False,
    )
    combined_output = "\n".join(
        part for part in [apply_result.stdout, apply_result.stderr] if part
    )

    assert apply_result.returncode != 0, (
        "expected the restricted namespace to reject the hostLogs DaemonSet's pod template "
        "(runAsUser: 0, no runAsNonRoot) — if this now succeeds, the chart's documented "
        "'use nginxLogs under restricted PSS' guidance is no longer accurate"
    )
    assert "podsecurity" in combined_output.lower(), combined_output
