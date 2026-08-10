from __future__ import annotations

import json
import time
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
    wait_for_condition,
)
from .test_12_observability import _clickhouse_query, _wait_for_query_nonzero


@pytest.mark.e2e
def test_observability_sidecar_logs_pss_fallback(installer, temp_workdir: Path) -> None:
    """The PSS-restricted fallback path: hostLogs disabled, nginxLogs sidecar enabled.

    Proves: no DaemonSet exists; the proxy pod has 2 containers; nginx logs still reach
    ClickHouse via the sidecar; and nginx connection metrics (only collectible on this path,
    since a DaemonSet cannot reach the proxy pod's loopback stub_status) show up in
    otel_metrics_*.

    Run with `make e2e-observability-sidecar`.
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
            "hostLogs": {"enabled": False},
            "nginxLogs": {"enabled": True},
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

    # No DaemonSet exists.
    daemonsets = json.loads(
        kubectl(["get", "daemonset", "-o", "json"], namespace=namespace).stdout
    )["items"]
    assert not daemonsets, f"unexpected DaemonSet(s) with hostLogs.enabled=false: {daemonsets}"

    # The proxy pod has 2 containers.
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    proxy_pod_obj = json.loads(kubectl(["get", "pod", proxy_pod, "-o", "json"], namespace=namespace).stdout)
    container_names = {c["name"] for c in proxy_pod_obj["spec"]["containers"]}
    assert len(container_names) == 2, f"expected 2 containers on the proxy pod, got: {container_names}"
    assert "otel-sidecar" in container_names

    # Drive traffic, then wait for kasm-proxy log records in ClickHouse.
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)

    time.sleep(15)
    _wait_for_query_nonzero(
        namespace,
        "kasm_otel",
        "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-proxy'",
        description="kasm-proxy log rows reach ClickHouse via the nginxLogs sidecar",
    )

    # nginx connection metrics — only this path collects them (see plan §3b / PROGRESS.md
    # Cross-phase findings). Check the rendered metric names before asserting on an exact one:
    # `nginx/metrics` receiver output is typically `nginx.connections_accepted`,
    # `nginx.connections_handled`, `nginx.connections_current`, `nginx.requests`.
    metrics_tables = _clickhouse_query(
        namespace,
        "kasm_otel",
        "SELECT name FROM system.tables WHERE database = currentDatabase() AND name LIKE 'otel_metrics_%'",
    )
    assert metrics_tables.strip(), "no otel_metrics_* table exists"

    def _nginx_metric_present() -> bool:
        for table in metrics_tables.splitlines():
            table = table.strip()
            if not table:
                continue
            count = _clickhouse_query(
                namespace,
                "kasm_otel",
                f"SELECT count() FROM {table} WHERE MetricName LIKE 'nginx.%'",
            )
            if int(count.splitlines()[0] or "0") > 0:
                return True
        return False

    wait_for_condition(
        "at least one nginx.* metric row exists in an otel_metrics_* table",
        _nginx_metric_present,
        timeout_seconds=90,
        poll_seconds=5,
    )
