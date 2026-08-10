from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml

from .conftest import helm_install
from .helpers import (
    assert_login_page,
    curl_from_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
    kubectl,
)


@pytest.mark.e2e
def test_observability_disabled_stays_deployable(installer, temp_workdir: Path) -> None:
    """observability.enabled=false must still be a fully deployable release.

    This is the deployability regression the H2/H5 amendments in PROGRESS.md exist to guard:
    KASM_LOG_FILE_ENABLED must still be emitted (else init_logging() crashes under
    readOnlyRootFilesystem) and the nginx load_module line must be gated off (else an unknown
    load_module path is fatal). Both are covered at the unit-test level
    (otel_env_test.yaml / nginx_load_module_test.yaml); this e2e scenario is the live-cluster
    proof that the combination actually boots.

    Run with `make e2e-observability-off`.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "certificate": {"secretName": "kasm-deployment-tls"},
        "components": {
            "api": {"resources": low_resources},
            "manager": {"resources": low_resources},
            "proxy": {"resources": low_resources_proxy},
            "guac": {"resources": low_resources},
            "rdpGateway": {"resources": low_resources_gw},
            "rdpHttpsGateway": {"resources": low_resources_gw},
        },
        "observability": {
            "enabled": False,
        },
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    # No collector/ClickHouse workloads or Services exist.
    for kind in ("deployment", "statefulset", "daemonset", "service"):
        result = kubectl(
            ["get", kind, "-l", "app.kubernetes.io/instance=" + e2e_config.release_name, "-o", "json"],
            namespace=namespace,
        )
        items = json.loads(result.stdout).get("items", [])
        component_labels = {
            item["metadata"].get("labels", {}).get("app.kubernetes.io/component", "")
            for item in items
        }
        otel_components = {c for c in component_labels if c.startswith("otel-") or c == "clickhouse"}
        assert not otel_components, f"unexpected observability {kind}(s) rendered: {otel_components}"

    # Every Kasm pod is Ready (install_and_wait_with_retry already asserted this via
    # wait_for_pods_ready, but re-confirm proxy specifically since that's the pod carrying the
    # gated load_module line).
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)

    # /otel-config.js still returns the disabled stub.
    status_code, config_body = curl_from_pod(
        namespace, proxy_pod, "https://localhost:8443/otel-config.js", insecure=True
    )
    assert status_code == 200
    assert '"enabled":false' in config_body

    # nginx actually started — proves load_module (unconditionally present in the base image but
    # gated out of the chart's rendered nginx.conf) did not break startup.
    logs = kubectl(["logs", proxy_pod, "--tail=200"], namespace=namespace).stdout
    assert "emerg" not in logs.lower(), f"nginx emitted an emerg-level line at startup:\n{logs}"
