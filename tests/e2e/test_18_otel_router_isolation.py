from __future__ import annotations

import dataclasses
import time
import uuid
from pathlib import Path

import pytest
import yaml

from .conftest import E2EConfig, helm_install
from .helpers import (
    ensure_tls_secret,
    get_first_pod_by_selector,
    helm,
    install_and_wait_with_retry,
    kubectl,
)
from .test_12_observability import (
    _clickhouse_query,
    _drive_traffic,
    _get_secret_value,
    _low_resource_values,
    _wait_for_query_nonzero,
)
from .test_14_otel_router import _post_otlp_log, _put_literal_secret, _router_ns, _router_release, install_router_with_registrations

_CLICKHOUSE_DATABASE = "kasm_otel"


def _own_namespace_count(namespace: str, table: str, other_namespace: str) -> int:
    result = _clickhouse_query(
        namespace,
        _CLICKHOUSE_DATABASE,
        f"SELECT count() FROM {table} WHERE ResourceAttributes['service.namespace'] = '{other_namespace}'",
    )
    return int(result.splitlines()[0] or "0")


@pytest.mark.e2e
def test_otel_router_isolates_two_releases(installer, temp_workdir: Path) -> None:
    """Multi-tenant router isolation (kasm-helm-6a7, dep xc8): TWO kasm-helm releases in separate
    namespaces both export to ONE router; the router routes each release's telemetry back to
    THAT release's own gateway/ClickHouse only.

    DISCOVERED DEVIATION FROM THE BRIEF (see DECISIONS.md D029): the router chart's `ingestAuth`
    is a single Collector-wide bearer token (charts/kasm-otel-router/templates/configmap.yaml:32-49
    -- one `bearertokenauth/server` extension, one `${env:OTEL_BEARER_TOKEN}`), not a per-
    registration credential. Both releases' `observability.collector.upstream.token` MUST be the
    SAME value to be accepted at all; giving them "distinct ingest tokens" as the brief phrased it
    would just make one release's exports 401. What IS already distinct per release (and is what
    actually provides the routing, not the ingest auth) is:
      - each registration's own `tokenSecret`, authenticating the ROUTER to that release's own
        gateway (already a real per-release credential, read from that release's own `-secrets`
        Secret, same as `_install_router`'s single-registration case);
      - the `service.namespace` resource attribute (kasm.otelEnv, _helpers.tpl:1377), which
        `kasm.otelEnv` stamps to the k8s Release.Namespace automatically and which the router's
        `routing/<signal>` connectors key on (configmap.yaml:92-103) to pick the destination
        registration.

    This also flips the brief's proposed negative-control hypothesis. The router's own
    values.yaml (lines 61-63, "TENANT-TRUST LIMITATION") documents that routing follows the
    CLAIMED `service.namespace` attribute, not the sender's identity/token -- the exact opposite
    of "routing is by token/registration, not by claimed attrs". The negative control below is
    the well-defined version of that: inject via release A's proxy pod, using the one shared
    ingest token (the only token there is), but CLAIMING release B's `service.namespace` -- and
    assert it lands in B's ClickHouse, not A's. That demonstrates routing is attribute-driven
    (matching the chart's documented trust model), which is a stronger, more specific claim than
    the brief's version would have been.

    Run with `make e2e-otel-isolation`.
    """
    e2e_config: E2EConfig = installer["config"]
    namespace_a = installer["namespace"]
    config_a = e2e_config

    namespace_b = f"{namespace_a}-b"
    release_b = f"{e2e_config.release_name}-b"
    config_b = dataclasses.replace(e2e_config, namespace=namespace_b, release_name=release_b)

    router_ns = _router_ns(namespace_a)
    router_release = _router_release(e2e_config.release_name)
    router_service_dns = f"{router_release}-otel-router.{router_ns}.svc.cluster.local"
    ingest_token = uuid.uuid4().hex

    def _values_for() -> dict:
        values_obj = _low_resource_values()
        values_obj["observability"]["collector"] = {
            "gateway": {"tailSamplePercentage": 100},
            "upstream": {
                "endpoint": f"http://{router_service_dns}:4318",
                "token": ingest_token,
            },
        }
        return values_obj

    # --- Install both releases FIRST (D028's ordering, same reason as test_17: the router's
    # registrations each need that release's real gateway bearer token, which only exists once
    # the release itself has installed). ---
    values_path_a = temp_workdir / "values-a.yaml"
    values_path_a.write_text(yaml.safe_dump(_values_for(), sort_keys=False))
    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=config_a,
        namespace=namespace_a,
        values_file=str(values_path_a),
        set_args=None,
    )

    kubectl(["create", "namespace", namespace_b], namespace=None, check=False)
    ensure_tls_secret(namespace_b)
    values_path_b = temp_workdir / "values-b.yaml"
    values_path_b.write_text(yaml.safe_dump(_values_for(), sort_keys=False))
    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=config_b,
        namespace=namespace_b,
        values_file=str(values_path_b),
        set_args=None,
    )

    try:
        # --- Install the router SECOND, with one registration per release, sharing the one
        # ingest token but each pointed at its own release's gateway with its own real bearer
        # token. Namespace must exist before secrets can be created in it. ---
        kubectl(["create", "namespace", router_ns], namespace=None, check=False)
        _put_literal_secret(router_ns, "otel-router-ingest-token", f"token={ingest_token}")
        registrations = []
        for cfg, ns in ((config_a, namespace_a), (config_b, namespace_b)):
            gateway_token = _get_secret_value(ns, f"{cfg.release_name}-secrets", "otel-bearer-token")
            copy_secret = f"otel-gateway-token-copy-{ns}"
            _put_literal_secret(router_ns, copy_secret, f"otel-bearer-token={gateway_token}")
            registrations.append(
                {
                    "namespace": ns,
                    "endpoint": f"{cfg.release_name}-otel-gateway.{ns}.svc.cluster.local:4317",
                    "tokenSecret": {"name": copy_secret, "key": "otel-bearer-token"},
                    "insecure": True,
                }
            )

        actual_dns = install_router_with_registrations(
            router_ns=router_ns,
            router_release=router_release,
            ingest_token_secret="otel-router-ingest-token",
            registrations=registrations,
            temp_workdir=temp_workdir,
            k8s_events=False,
        )
        assert actual_dns == router_service_dns

        # --- Drive real traffic on both releases, through the router, to each one's own
        # ClickHouse. ---
        for _ in range(5):
            _drive_traffic(namespace_a)
            _drive_traffic(namespace_b)
            time.sleep(2)

        for ns in (namespace_a, namespace_b):
            _wait_for_own_traffic(ns)

        # --- Isolation assertions, both directions: neither release's ClickHouse has a single
        # row attributed to the OTHER release's namespace. ---
        for table in ("otel_logs", "otel_traces"):
            cross_in_a = _own_namespace_count(namespace_a, table, namespace_b)
            assert cross_in_a == 0, f"release A's ClickHouse ({table}) has {cross_in_a} row(s) from release B"
            cross_in_b = _own_namespace_count(namespace_b, table, namespace_a)
            assert cross_in_b == 0, f"release B's ClickHouse ({table}) has {cross_in_b} row(s) from release A"

        # --- Negative control (corrected framing, see docstring / D029): inject via A's proxy
        # pod with the one shared ingest token, but CLAIMING B's service.namespace. Routing keys
        # on the claimed attribute, so this must land in B, not A. ---
        proxy_pod_a = get_first_pod_by_selector(namespace_a, "app.kubernetes.io/component=proxy")
        marker = f"e2e-isolation-negctrl-{uuid.uuid4().hex}"
        service_name = f"e2e-isolation-negctrl-{uuid.uuid4().hex}"
        status_code, body = _post_otlp_log(
            pod_namespace=namespace_a,
            pod=proxy_pod_a,
            router_service_dns=router_service_dns,
            token=ingest_token,
            service_namespace=namespace_b,
            service_name=service_name,
            marker=marker,
        )
        assert status_code == 200, f"router rejected the negative-control send: HTTP {status_code}, body={body}"

        _wait_for_landed(namespace_b, service_name, marker)
        time.sleep(15)
        in_a = _clickhouse_query(
            namespace_a,
            _CLICKHOUSE_DATABASE,
            f"SELECT count() FROM otel_logs WHERE ServiceName = '{service_name}'",
        )
        assert int(in_a.splitlines()[0] or "0") == 0, (
            "negative-control record (sent from A's pod, claiming B's service.namespace) landed "
            f"in A's ClickHouse too (count={in_a}) -- routing is not attribute-only"
        )
    finally:
        helm(["uninstall", router_release, "-n", router_ns], check=False)
        kubectl(["delete", "namespace", router_ns, "--ignore-not-found"], namespace=None, check=False)
        helm(["uninstall", release_b, "-n", namespace_b], check=False)
        kubectl(["delete", "namespace", namespace_b, "--ignore-not-found"], namespace=None, check=False)


def _wait_for_own_traffic(namespace: str) -> None:
    _wait_for_query_nonzero(
        namespace,
        _CLICKHOUSE_DATABASE,
        "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-api'",
        description=f"real kasm-api log traffic reached {namespace}'s own ClickHouse via the router",
    )
    _wait_for_query_nonzero(
        namespace,
        _CLICKHOUSE_DATABASE,
        "SELECT count() FROM otel_traces WHERE ServiceName = 'kasm-api'",
        description=f"real kasm-api trace traffic reached {namespace}'s own ClickHouse via the router",
    )


def _wait_for_landed(namespace: str, service_name: str, marker: str) -> None:
    _wait_for_query_nonzero(
        namespace,
        _CLICKHOUSE_DATABASE,
        f"SELECT count() FROM otel_logs WHERE ServiceName = '{service_name}' AND Body = '{marker}'",
        description=f"negative-control record (claimed service.namespace={namespace}) reached {namespace}'s ClickHouse",
    )
