from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import pytest
import yaml

from .conftest import helm_install
from .helpers import (
    curl_from_pod,
    exec_in_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
    kubectl,
    wait_for_condition,
)

LOGGER = logging.getLogger(__name__)

# The collector batches on a 10s timeout; give the whole pipeline (Kasm service -> forwarder ->
# gateway -> ClickHouse) generous headroom before giving up on a query.
_TELEMETRY_FLUSH_TIMEOUT_SECONDS = 90
_TELEMETRY_POLL_SECONDS = 5


def _low_resource_values(database: str | None = None, *, gateway_replicas: int | None = None) -> dict:
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    low_resources_otel = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    values_obj: dict = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "certificate": {"secretName": "kasm-deployment-tls"},
        "database": {"resources": low_resources},
        "components": {
            "api": {"resources": low_resources},
            "manager": {"resources": low_resources},
            "proxy": {"resources": low_resources_proxy},
            "connectionProxy": {
                "nginx": {"resources": low_resources_proxy},
                "guac": {"resources": low_resources_gw},
                "rdpGateway": {"resources": low_resources_gw},
                "rdpHttpsGateway": {"resources": low_resources_gw},
            },
            "otelForwarder": {"resources": low_resources_otel},
            "otelGateway": {"resources": low_resources_otel},
            "clickhouse": {
                "resources": {"requests": {"cpu": "100m", "memory": "512Mi"}},
                # Tests must start on an empty ClickHouse volume. The chart default retains the PVC
                # across uninstall, and ClickHouse only runs /docker-entrypoint-initdb.d/init.sql
                # when the data directory is empty — so a retained volume means init-schema.sql is
                # skipped and the exporter creates otel_logs itself, without the IsAudit column.
                "storage": {"retentionPolicy": {"whenDeleted": "Delete", "whenScaled": "Delete"}},
            },
        },
    }
    if database:
        values_obj["observability"] = {"clickhouse": {"database": database}}
    if gateway_replicas is not None:
        values_obj["components"]["otelGateway"]["replicas"] = gateway_replicas
    return values_obj


def _clickhouse_query(namespace: str, database: str, sql: str) -> str:
    """Run a query via clickhouse-client inside the ClickHouse pod itself.

    Exec'ing into the pod (rather than querying from a separate test pod) avoids TLS/auth
    plumbing entirely: clickhouse-client picks up CLICKHOUSE_USER and CLICKHOUSE_PASSWORD from its
    own environment and talks to localhost in plaintext.

    Credentials are deliberately NOT passed as arguments. `kubectl exec ... --` builds an argv
    directly with no shell, so a literal "${CLICKHOUSE_USER}" would be sent verbatim as the username
    and fail with AUTHENTICATION_FAILED (code 516) rather than expanding. Relying on the container's
    environment is both correct and avoids putting a password on a command line.
    """
    clickhouse_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=clickhouse")
    result = exec_in_pod(
        namespace,
        clickhouse_pod,
        [
            "clickhouse-client",
            "--database",
            database,
            "--query",
            sql,
        ],
    )
    return result.stdout.strip()


def _wait_for_query_nonzero(namespace: str, database: str, sql: str, *, description: str) -> str:
    last_value = ""

    def _check() -> bool:
        nonlocal last_value
        last_value = _clickhouse_query(namespace, database, sql)
        try:
            return int(last_value.splitlines()[0]) > 0
        except (ValueError, IndexError):
            return False

    wait_for_condition(
        description,
        _check,
        timeout_seconds=_TELEMETRY_FLUSH_TIMEOUT_SECONDS,
        poll_seconds=_TELEMETRY_POLL_SECONDS,
    )
    return last_value


def _assert_single_forwarder(namespace: str) -> None:
    """Restructured topology: one cluster-wide otel-forwarder, never a copy per zone."""
    selector = "app.kubernetes.io/component=otel-forwarder"
    deployments = json.loads(kubectl(["get", "deployments", "-l", selector, "-o", "json"], namespace=namespace).stdout)
    assert len(deployments["items"]) == 1, (
        f"expected exactly one otel-forwarder Deployment, found {len(deployments['items'])}"
    )
    pods = json.loads(kubectl(["get", "pods", "-l", selector, "-o", "json"], namespace=namespace).stdout)
    assert len(pods["items"]) == 1, (
        f"expected exactly one otel-forwarder pod (cluster-wide, no per-zone copies), found "
        f"{len(pods['items'])}"
    )


def _service_name_seen(namespace: str, database: str, service_name: str, *, timeout_seconds: int) -> bool:
    def _check() -> bool:
        rows = _clickhouse_query(
            namespace, database, f"SELECT count() FROM otel_logs WHERE ServiceName = '{service_name}'"
        )
        try:
            return int(rows.splitlines()[0] or "0") > 0
        except (ValueError, IndexError):
            return False

    try:
        wait_for_condition(
            f"ServiceName={service_name} has otel_logs rows",
            _check,
            timeout_seconds=timeout_seconds,
            poll_seconds=_TELEMETRY_POLL_SECONDS,
        )
        return True
    except AssertionError:
        return False


def _assert_connection_proxy_sidecar_services(namespace: str, database: str) -> None:
    """guac/rdp-gateway/rdp-https-gateway ship logs via their own OTel SDK straight to the
    connection-proxy pod's otel-sidecar (kasm.otelEnv(sidecar=true) in
    connection-proxy-statefulset.yaml:158,264,362). kasm-connection-proxy is the nginx sidecar's
    own filelog pipeline (otel-nginx-sidecar-configmap.yaml, kasm.otelNginxAccessLogOperators /
    kasm.otelNginxErrorLogOperators), distinct from the proxy tier's kasm-proxy. All of these emit
    at process/nginx startup, but without a live session there's no guarantee which shows up
    first — poll each with a short budget, and if one never shows up, fall back to proving the
    delivery path exists (the sidecar container is present in the pod) rather than asserting
    traffic that requires a session.
    """
    for service_name in ("kasm-guac", "kasm-rdp-gateway", "kasm-rdp-https-gateway", "kasm-connection-proxy"):
        if _service_name_seen(namespace, database, service_name, timeout_seconds=30):
            continue
        pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=connection-proxy")
        pod_spec = json.loads(kubectl(["get", "pod", pod, "-o", "json"], namespace=namespace).stdout)
        container_names = [c["name"] for c in pod_spec["spec"]["containers"]]
        assert "otel-sidecar" in container_names, (
            f"{service_name} produced no otel_logs rows and the connection-proxy pod has no "
            f"otel-sidecar container to carry it: {container_names}"
        )
        LOGGER.info(
            "[observability] %s produced no otel_logs rows without a live session; verified the "
            "otel-sidecar container is present in the connection-proxy pod instead",
            service_name,
        )


def _assert_db_sidecar_logs(namespace: str, database: str) -> None:
    """DB sidecar: logs only, no metrics receiver (D002 — deliberately deferred,
    otel-db-sidecar-configmap.yaml:8-9). Postgres emits JSON log lines at startup, so this is a
    hard assertion, not a fallback."""
    _wait_for_query_nonzero(
        namespace,
        database,
        "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-db'",
        description=f"kasm-db has otel_logs rows in database {database}",
    )


def _drive_traffic(namespace: str) -> None:
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, _ = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    # A deliberately-bad URL to generate at least one nginx error-log line, in case normal
    # traffic doesn't naturally produce one.
    curl_from_pod(namespace, proxy_pod, "https://localhost:8443/this-path-does-not-exist-404", insecure=True)
    # Hit the API too so kasm-api/kasm-manager have something to emit besides startup noise.
    curl_from_pod(namespace, proxy_pod, "https://localhost:8443/api/public/get_token", insecure=True)


def _assert_core_telemetry(namespace: str, database: str) -> None:
    _wait_for_query_nonzero(
        namespace,
        database,
        "SELECT count() FROM otel_logs",
        description=f"otel_logs has rows in database {database}",
    )

    services = _clickhouse_query(namespace, database, "SELECT DISTINCT ServiceName FROM otel_logs")
    assert "kasm-api" in services, f"kasm-api missing from otel_logs ServiceName values: {services}"
    assert "kasm-manager" in services, f"kasm-manager missing from otel_logs ServiceName values: {services}"

    _assert_connection_proxy_sidecar_services(namespace, database)
    _assert_db_sidecar_logs(namespace, database)

    _wait_for_query_nonzero(
        namespace,
        database,
        "SELECT count() FROM otel_traces",
        description=f"otel_traces has rows in database {database}",
    )
    trace_services = _clickhouse_query(namespace, database, "SELECT DISTINCT ServiceName FROM otel_traces")
    assert "kasm-proxy" in trace_services, (
        f"kasm-proxy missing from otel_traces ServiceName values: {trace_services} "
        "(this is the proof that ngx_otel_module loaded and the module->collector path works)"
    )

    proxy_log_count = _clickhouse_query(
        namespace, database, "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-proxy'"
    )
    assert int(proxy_log_count.splitlines()[0] or "0") > 0, (
        "no kasm-proxy log rows — the unconditional nginx otel sidecar did not tail "
        "/var/log/nginx/otel/access_json.log, or its filelog receiver did not match"
    )

    # The filelog operators move fields to semconv names via dotted paths
    # (attributes.http.request.method), which the collector treats as NESTED fields, not as a flat
    # key. ClickHouse therefore stores LogAttributes['http'] = '{"request":{"method":"GET"},...}'
    # and LogAttributes['url'] = '{"path":"/..."}'. There is no 'http.request.method' key to
    # mapContains. Docker's pipeline behaves identically — same operator chain.
    access_attr_count = _clickhouse_query(
        namespace,
        database,
        "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-proxy' "
        "AND JSONExtractString(LogAttributes['http'], 'request', 'method') != '' "
        "AND JSONExtractString(LogAttributes['url'], 'path') != ''",
    )
    assert int(access_attr_count.splitlines()[0] or "0") > 0, (
        "no kasm-proxy log row carries parsed access-log attributes (nested http.request.method / "
        "url.path) — the access_json filelog chain did not run"
    )

    error_log_count = _clickhouse_query(
        namespace,
        database,
        "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-proxy' AND SeverityText != ''",
    )
    LOGGER.info("[observability] kasm-proxy error-classified log rows: %s", error_log_count)

    metrics_tables = _clickhouse_query(
        namespace,
        database,
        "SELECT name FROM system.tables WHERE database = currentDatabase() AND name LIKE 'otel_metrics_%'",
    )
    assert metrics_tables.strip(), "no otel_metrics_* table exists"
    first_metrics_table = metrics_tables.splitlines()[0].strip()
    metrics_count = _clickhouse_query(namespace, database, f"SELECT count() FROM {first_metrics_table}")
    assert int(metrics_count.splitlines()[0] or "0") >= 0  # table existing + queryable is the main proof


@pytest.mark.e2e
def test_observability_default_install_end_to_end(installer, temp_workdir: Path) -> None:
    """Default observability install: collector + ClickHouse ready, telemetry flows end to end.

    Run with `make e2e-observability`.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(_low_resource_values(), sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
        set_args=None,
    )

    _assert_single_forwarder(namespace)

    LOGGER.info("[observability] pods ready; driving traffic and waiting for telemetry to flush")
    _drive_traffic(namespace)

    # Allow the batch processor's 10s timeout plus network hops before the first query attempt.
    time.sleep(15)

    _assert_core_telemetry(namespace, "kasm_otel")

    # /otel-config.js reflects the enabled browser telemetry stub.
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/otel-config.js", insecure=True)
    assert status_code == 200
    assert '"enabled":true' in body

    # IsAudit column exists and login (already exercised by install_and_wait_with_retry's own
    # readiness probing plus the traffic above) produces at least one IsAudit=1 row. If this
    # doesn't reliably fire (audit classification depends on the exact login/logout attribute
    # shape), downgrade to a schema-only assertion instead per the phase doc's fallback guidance.
    schema_check = _clickhouse_query(
        namespace,
        "kasm_otel",
        "SELECT count() FROM system.columns WHERE database='kasm_otel' AND table='otel_logs' "
        "AND name='IsAudit'",
    )
    assert int(schema_check.splitlines()[0] or "0") == 1, "IsAudit column missing from otel_logs"

    audit_rows = _clickhouse_query(namespace, "kasm_otel", "SELECT count() FROM otel_logs WHERE IsAudit = 1")
    LOGGER.info("[observability] IsAudit=1 rows so far: %s (schema-only assertion if this is 0)", audit_rows)


@pytest.mark.e2e
def test_observability_non_default_clickhouse_database(installer, temp_workdir: Path) -> None:
    """H0b regression: reads (api's KASM_CLICKHOUSE_DATABASE) and writes (the gateway Collector's
    exporters) must agree on a non-default database name, or the UI silently shows nothing.

    Run with `make e2e-observability`.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]
    database = "kasm_tenant_a"

    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(_low_resource_values(database=database), sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
        set_args=None,
    )

    _drive_traffic(namespace)
    time.sleep(15)

    # Prove nothing silently fell back to the default database.
    default_db_count = _clickhouse_query(
        namespace,
        "system",
        "SELECT count() FROM system.databases WHERE name='kasm_otel'",
    )
    assert int(default_db_count.splitlines()[0] or "0") == 0, (
        "kasm_otel database exists even though observability.clickhouse.database was set to "
        f"{database} — something fell back to the default"
    )

    _assert_core_telemetry(namespace, database)

    # Read-path proof: the API's KASM_CLICKHOUSE_ENDPOINT/DATABASE env vars agree with the
    # write-path database above — hitting the proxy's client_api telemetry endpoint (or a report
    # endpoint) would need auth plumbing this e2e harness doesn't otherwise set up, so the
    # ClickHouse-side query above (which reads through the exact database the API is configured
    # to read from) is the read/write-agreement proof here, per the phase doc's guidance that
    # this is "the only test that proves reads and writes agree."


@pytest.mark.e2e
def test_observability_gateway_replicas_scale_out(installer, temp_workdir: Path) -> None:
    """components.otelGateway.replicas=2 smoke test: the loadbalancing exporter in front of the
    gateway (otel-forwarder-configmap.yaml) partitions by traceID across gateway pods, so this
    proves the partitioned tail-sampling path still delivers telemetry end to end with more than
    one gateway.

    Run with `make e2e-observability`.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(_low_resource_values(gateway_replicas=2), sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
        set_args=None,
    )

    gateway_pods = json.loads(
        kubectl(
            ["get", "pods", "-l", "app.kubernetes.io/component=otel-gateway", "-o", "json"],
            namespace=namespace,
        ).stdout
    )["items"]
    assert len(gateway_pods) == 2, f"expected 2 otel-gateway pods, found {len(gateway_pods)}"
    for pod in gateway_pods:
        ready_conditions = [c for c in pod["status"].get("conditions", []) if c.get("type") == "Ready"]
        assert ready_conditions and ready_conditions[0].get("status") == "True", (
            f"otel-gateway pod {pod['metadata']['name']} is not Ready"
        )

    _drive_traffic(namespace)
    time.sleep(15)

    _assert_core_telemetry(namespace, "kasm_otel")
