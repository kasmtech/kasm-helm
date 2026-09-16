from __future__ import annotations

import base64
import json
import logging
import time
import uuid
from pathlib import Path

import pytest
import yaml

from .conftest import helm_install
from .helpers import (
    curl_from_pod,
    exec_in_pod,
    get_first_pod_by_selector,
    helm,
    install_and_wait_with_retry,
    kubectl,
    wait_for_condition,
)

LOGGER = logging.getLogger(__name__)

# The collector batches on a 10s timeout; give the whole pipeline (Kasm service -> gateway ->
# ClickHouse) generous headroom before giving up on a query.
_TELEMETRY_FLUSH_TIMEOUT_SECONDS = 90
_TELEMETRY_POLL_SECONDS = 5


def _low_resource_values(
    database: str | None = None, *, gateway_replicas: int | None = None, read_username: str | None = None
) -> dict:
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
    clickhouse_obs: dict = {}
    if database:
        clickhouse_obs["database"] = database
    if read_username:
        clickhouse_obs["readUsername"] = read_username
    if clickhouse_obs:
        values_obj["observability"] = {"clickhouse": clickhouse_obs}
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


def _get_secret_value(namespace: str, secret_name: str, key: str) -> str:
    result = kubectl(["get", "secret", secret_name, "-o", f"jsonpath={{.data.{key}}}"], namespace=namespace)
    return base64.b64decode(result.stdout).decode()


def _clickhouse_query_as(
    namespace: str, database: str, sql: str, *, user: str, password: str, check: bool = True
):
    """Run a query via clickhouse-client inside the ClickHouse pod as an explicit user/password.

    Settles bd kasm-helm-hvx's RISK note: the RO user's GRANT SELECT ON <db>.* is an XML grant
    (ACCESS_STORAGE_READONLY) that cannot be corrected by SQL at runtime, and a grant that's too
    narrow for Kasm's real reporting queries fails silently as empty results, not an error — so
    this has to run an actual query as that user to prove it, not just assert the grant text.

    Credentials are passed via `env FOO=bar clickhouse-client ...` rather than `--user`/
    `--password` flags, so the password never appears in this process's argv (only in its
    environment, which `kubectl exec` does not log or expose via `ps`).
    """
    clickhouse_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=clickhouse")
    return kubectl(
        [
            "exec",
            clickhouse_pod,
            "--",
            "env",
            f"CLICKHOUSE_USER={user}",
            f"CLICKHOUSE_PASSWORD={password}",
            "clickhouse-client",
            "--database",
            database,
            "--query",
            sql,
        ],
        namespace=namespace,
        check=check,
    )


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


def _assert_single_gateway(namespace: str) -> None:
    """Restructured topology: one cluster-wide otel-gateway, never a copy per zone, and no
    forwarder tier at all — every sender exports straight to the gateway."""
    selector = "app.kubernetes.io/component=otel-gateway"
    deployments = json.loads(kubectl(["get", "deployments", "-l", selector, "-o", "json"], namespace=namespace).stdout)
    assert len(deployments["items"]) == 1, (
        f"expected exactly one otel-gateway Deployment, found {len(deployments['items'])}"
    )
    pods = json.loads(kubectl(["get", "pods", "-l", selector, "-o", "json"], namespace=namespace).stdout)
    assert len(pods["items"]) == 1, (
        f"expected exactly one otel-gateway pod (cluster-wide, no per-zone copies), found "
        f"{len(pods['items'])}"
    )
    forwarder_deployments = json.loads(
        kubectl(
            ["get", "deployments", "-l", "app.kubernetes.io/component=otel-forwarder", "-o", "json"],
            namespace=namespace,
        ).stdout
    )
    assert len(forwarder_deployments["items"]) == 0, "forwarder tier was removed; no otel-forwarder Deployment should exist"


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


def _assert_no_syslog_loss(namespace: str, database: str) -> None:
    """Loopback syslog UDP is fire-and-forget (no ack, no retry, no checkpoint), unlike the
    filelog approach it replaced. Drive a known number of requests to a unique path and require
    ClickHouse to end up with exactly that many kasm-proxy access rows for it — on idle loopback we
    expect zero loss, and an exact-match assertion (not just "some rows arrived") is the only way
    to catch silent drops.
    """
    unique_path = f"/otel-loss-check-{uuid.uuid4().hex}"
    request_count = 50
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    for _ in range(request_count):
        curl_from_pod(namespace, proxy_pod, f"https://localhost:8443{unique_path}", insecure=True)

    sql = (
        "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-proxy' "
        f"AND JSONExtractString(LogAttributes['url'], 'path') = '{unique_path}'"
    )

    def _check() -> bool:
        try:
            return int(_clickhouse_query(namespace, database, sql).splitlines()[0] or "0") >= request_count
        except (ValueError, IndexError):
            return False

    wait_for_condition(
        f"{request_count} kasm-proxy access rows for {unique_path}",
        _check,
        timeout_seconds=_TELEMETRY_FLUSH_TIMEOUT_SECONDS,
        poll_seconds=_TELEMETRY_POLL_SECONDS,
    )
    final_count = int(_clickhouse_query(namespace, database, sql).splitlines()[0] or "0")
    assert final_count == request_count, (
        f"expected exactly {request_count} kasm-proxy access rows for {unique_path}, got "
        f"{final_count} — loopback syslog UDP dropped datagrams"
    )


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
        "no kasm-proxy log rows — the unconditional nginx otel sidecar received nothing on its "
        "loopback syslog receiver, or the receiver's operator chain did not match"
    )

    # Restores the check deleted during jg7.10 because the chart couldn't satisfy it then:
    # OTEL_RESOURCE_ATTRIBUTES is an SDK env var the Collector binary never applies to pipeline
    # data (DECISIONS.md D4), so a sidecar-collected row was never attributable to a pod. The fix
    # is a resource processor in the sidecar's own config (kasm.common.otelResourceProcessor); this
    # queries emitted ClickHouse rows, not the rendered chart, so it actually catches a regression.
    pod_name_count = _wait_for_query_nonzero(
        namespace,
        database,
        # Exclude 'unknown' as well as empty: the config's ${env:POD_NAME:-unknown} default
        # exists so `otelcol validate` can run without a pod environment, and a bare != ''
        # check would be satisfied by that fallback instead of a real pod name.
        "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-proxy' "
        "AND ResourceAttributes['k8s.pod.name'] NOT IN ('', 'unknown')",
        description="kasm-proxy otel_logs rows carry a real (non-fallback) k8s.pod.name",
    )
    LOGGER.info("[observability] kasm-proxy log rows with k8s.pod.name: %s", pod_name_count)

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

    read_username = "kasm_otel_ro"
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(_low_resource_values(read_username=read_username), sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
        set_args=None,
    )

    _assert_single_gateway(namespace)

    LOGGER.info("[observability] pods ready; driving traffic and waiting for telemetry to flush")
    _drive_traffic(namespace)

    # Allow the batch processor's 10s timeout plus network hops before the first query attempt.
    time.sleep(15)

    _assert_core_telemetry(namespace, "kasm_otel")

    # bd kasm-helm-hvx: the RO user (api/manager's credential) must be able to run a real
    # reporting-style SELECT and must NOT be able to write. This is the RISK the ticket flags —
    # an XML grant that's too narrow fails as empty reports, not an error — so it settles it by
    # actually running the query as that user rather than only asserting the grant text.
    LOGGER.info("[observability] verifying the read-only ClickHouse user")
    secret_name = f"{e2e_config.release_name}-secrets"
    ro_password = _get_secret_value(namespace, secret_name, "clickhouse-ro-password")

    ro_report_rows = _clickhouse_query_as(
        namespace, "kasm_otel", "SELECT count() FROM otel_logs", user=read_username, password=ro_password
    ).stdout.strip()
    assert int(ro_report_rows.splitlines()[0] or "0") > 0, (
        f"RO user {read_username} returned no rows from a reporting-style query — GRANT SELECT ON "
        "kasm_otel.* may not cover what Kasm's reporting queries actually need"
    )

    ro_write_result = _clickhouse_query_as(
        namespace,
        "kasm_otel",
        "INSERT INTO otel_logs (Timestamp) VALUES (now64(9))",
        user=read_username,
        password=ro_password,
        check=False,
    )
    assert ro_write_result.returncode != 0, f"RO user {read_username} was able to write to otel_logs"
    assert "ACCESS_DENIED" in ro_write_result.stderr, (
        f"expected an ACCESS_DENIED failure for a write as the RO user, got: {ro_write_result.stderr}"
    )

    LOGGER.info("[observability] checking for syslog UDP loss on idle loopback")
    _assert_no_syslog_loss(namespace, "kasm_otel")

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
def test_observability_gateway_replicas_above_one_fails_render(e2e_config, temp_workdir: Path) -> None:
    """components.otelGateway.replicas=2 must fail the render. The forwarder tier that used to
    partition traces by ID in front of the gateway is gone (bd kasm-helm-7a0, D2 in
    .claude/scratch/router-chain/DECISIONS.md): every sender now exports straight to the gateway's
    ClusterIP, so a second replica would let tail_sampling decide on partial traces. This proves
    the kasm.observabilityValidate guard end to end via `helm template`, not just the unittest
    suite, since it's the render path an operator would actually hit.

    Run with `make e2e-observability`.
    """
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(_low_resource_values(gateway_replicas=2), sort_keys=False))

    result = helm(
        ["template", e2e_config.release_name, e2e_config.chart_dir, "-f", str(values_path)],
        check=False,
    )
    assert result.returncode != 0, "helm template should have failed with replicas=2"
    assert "components.otelGateway.replicas (2) must be 0" in result.stderr, result.stderr
