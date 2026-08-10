from __future__ import annotations

import json
import time
from pathlib import Path

import pytest
import yaml

from .conftest import helm_install
from .helpers import (
    exec_in_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
    wait_for_condition,
)


@pytest.mark.e2e
def test_observability_filelogs_sidecar(installer, temp_workdir: Path) -> None:
    """observability.fileLogs.enabled=true: api/manager/guac get a log-tailing sidecar that reads
    JSON lines from a shared volume and forwards them to the forwarder Collector.

    Run with `make e2e-observability-filelogs`.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    low_resources_otel = {"requests": {"cpu": "50m", "memory": "128Mi"}}
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
            "fileLogs": {"enabled": True},
            "collector": {
                "forwarder": {"resources": low_resources_otel},
                "gateway": {"resources": low_resources_otel},
            },
            "clickhouse": {
                "resources": {"requests": {"cpu": "100m", "memory": "512Mi"}},
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
    )

    from .helpers import kubectl

    for component in ("api", "manager", "guac"):
        pod_name = get_first_pod_by_selector(namespace, f"app.kubernetes.io/component={component}")
        pod_obj = json.loads(kubectl(["get", "pod", pod_name, "-o", "json"], namespace=namespace).stdout)
        containers = pod_obj["spec"]["containers"]
        assert len(containers) == 2, f"{component} pod {pod_name} does not have 2 containers: {containers}"
        container_names = {c["name"] for c in containers}
        assert "otel-sidecar" in container_names, f"{component} pod missing otel-sidecar container: {container_names}"

    # JSON lines exist in the shared volume.
    api_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=api")

    def _has_json_log_line() -> bool:
        result = exec_in_pod(
            namespace,
            api_pod,
            ["/bin/sh", "-c", "cat /opt/kasm/current/log/*.log 2>/dev/null | head -n1"],
        )
        line = result.stdout.strip()
        if not line:
            return False
        try:
            json.loads(line)
        except ValueError:
            return False
        return True

    wait_for_condition(
        "api pod has at least one JSON log line under /opt/kasm/current/log",
        _has_json_log_line,
        timeout_seconds=120,
        poll_seconds=5,
    )

    # Those records reach ClickHouse (same query pattern as test_12).
    from .test_12_observability import _wait_for_query_nonzero  # local import, e2e-only helper reuse

    time.sleep(15)
    _wait_for_query_nonzero(
        namespace,
        "kasm_otel",
        "SELECT count() FROM otel_logs WHERE ServiceName IN ('kasm-api', 'kasm-manager', 'kasm-guac')",
        description="fileLogs-sourced log rows reach ClickHouse",
    )
