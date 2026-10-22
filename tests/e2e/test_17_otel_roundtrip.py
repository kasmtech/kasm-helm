from __future__ import annotations

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
    install_and_wait_with_retry,
    kubectl,
)
from .test_12_observability import _drive_traffic, _low_resource_values, _wait_for_query_nonzero
from .test_14_otel_router import _install_router, _post_otlp_log, _router_ns, _router_release, _uninstall_router

LOGGER = logging.getLogger(__name__)

_CLICKHOUSE_DATABASE = "kasm_otel"


def _post_otlp_trace(
    *, pod_namespace: str, pod: str, router_service_dns: str, token: str, service_namespace: str, service_name: str, marker: str
) -> tuple[int, str]:
    """POST a single OTLP/HTTP JSON span into the router's ingest endpoint.

    Same shape as test_14's _post_otlp_log, extended to the traces signal (kasm-helm-xc8 needs
    both traces AND logs proven through the router; test_14 only ever proved logs+k8s events).

    Duration is set to 2s so the gateway's tail_sampling "keep-slow" policy (>=1000ms,
    otel-gateway-configmap.yaml's tail_sampling.policies) always retains it -- the default
    "probabilistic-sample" policy that a normal-latency span would otherwise fall to only keeps
    tailSamplePercentage (10% by default), which makes a single injected span an unreliable,
    usually-dropped proof of the round trip.
    """
    trace_id = uuid.uuid4().hex  # 32 hex chars == 16 bytes, a valid OTLP trace_id
    span_id = uuid.uuid4().hex[:16]  # 16 hex chars == 8 bytes, a valid OTLP span_id
    now_ns = time.time_ns()
    payload = {
        "resourceSpans": [
            {
                "resource": {
                    "attributes": [
                        {"key": "service.namespace", "value": {"stringValue": service_namespace}},
                        {"key": "service.name", "value": {"stringValue": service_name}},
                    ]
                },
                "scopeSpans": [
                    {
                        "spans": [
                            {
                                "traceId": trace_id,
                                "spanId": span_id,
                                "name": marker,
                                "kind": 1,
                                "startTimeUnixNano": str(now_ns),
                                "endTimeUnixNano": str(now_ns + 2_000_000_000),
                            }
                        ]
                    }
                ],
            }
        ]
    }
    curl_args = [
        "curl",
        "-sS",
        "-o",
        "-",
        "-w",
        "\n%{http_code}",
        "--max-time",
        "30",
        "-X",
        "POST",
        f"http://{router_service_dns}:4318/v1/traces",
        "-H",
        "Content-Type: application/json",
        "-H",
        f"Authorization: Bearer {token}",
        "--data",
        json.dumps(payload),
    ]
    result = exec_in_pod(pod_namespace, pod, curl_args)
    body, status_code_text = result.stdout.rsplit("\n", 1)
    return int(status_code_text.strip()), body


@pytest.mark.e2e
def test_otel_roundtrip_release_router_gateway_clickhouse(installer, temp_workdir: Path) -> None:
    """Full round trip (kasm-helm-xc8/D026): kasm-api's own OTel exporter is redirected via
    `observability.collector.upstream` (values-driven, kasm.otelEnv's non-sidecar branch) at an
    external router instead of this release's local gateway; the router's registration for this
    namespace routes matched telemetry on to that SAME release's gateway, which writes it to
    ClickHouse. This is apps -> router -> gateway -> ClickHouse (a single hop through the
    router), NOT the gateway's own `forward` exporter looping back into itself (see D025 in
    DECISIONS.md -- that specific config is a genuine infinite loop for a self-registered single
    release and is deliberately not exercised live here).

    Order: kasm-helm is installed FIRST, with `observability.collector.upstream` pointed at the
    router's Service DNS and a pre-generated ingest token -- both deterministic/known before the
    router exists. The router is installed SECOND (it needs this release's real gateway bearer
    token, read from the `-secrets` Secret, to register back at it), pinned to that same
    pre-generated ingest token via `_install_router`'s `ingest_token` argument so the two installs
    agree on the credential without either depending on the other's internal state.

    Run with `make e2e-otel-roundtrip`.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    router_ns = _router_ns(namespace)
    router_release = _router_release(e2e_config.release_name)
    router_service_dns = f"{router_release}-otel-router.{router_ns}.svc.cluster.local"
    ingest_token = uuid.uuid4().hex

    values_obj = _low_resource_values()
    # tailSamplePercentage is deliberately 100 here (not the chart default of 10): this test
    # asserts on REAL, low-volume app traffic reaching ClickHouse, and builder-18 hit exactly
    # this pitfall with the default probabilistic-sample policy dropping a single injected
    # span -- pinning to 100 makes the assertion about the router/gateway wiring, not about
    # sampling odds.
    values_obj["observability"]["collector"] = {
        "gateway": {"tailSamplePercentage": 100},
        "upstream": {
            "endpoint": f"http://{router_service_dns}:4318",
            "token": ingest_token,
        },
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))
    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
        set_args=None,
    )

    actual_router_ns, actual_router_service_dns, actual_ingest_token = _install_router(
        e2e_config=e2e_config, namespace=namespace, temp_workdir=temp_workdir, ingest_token=ingest_token
    )
    assert (actual_router_ns, actual_router_service_dns, actual_ingest_token) == (
        router_ns,
        router_service_dns,
        ingest_token,
    ), "router install did not agree with the precomputed values kasm-helm was installed with"
    try:
        # --- Rendered-env proof: the api container's OTel exporter actually carries the router's
        # endpoint and token, not the local gateway (values-wiring proof, kasm-helm-xc8 part 2). ---
        api_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=api")
        api_env = json.loads(
            kubectl(
                ["get", "pod", api_pod, "-o", "jsonpath={.spec.containers[0].env}"], namespace=namespace
            ).stdout
        )
        env_by_name = {entry["name"]: entry for entry in api_env}
        assert env_by_name["OTEL_EXPORTER_OTLP_ENDPOINT"]["value"] == f"http://{router_service_dns}:4318", (
            "api container's OTEL_EXPORTER_OTLP_ENDPOINT did not pick up the "
            f"observability.collector.upstream override: {env_by_name.get('OTEL_EXPORTER_OTLP_ENDPOINT')}"
        )
        assert env_by_name["OTEL_BEARER_TOKEN"]["value"] == ingest_token, (
            "api container's OTEL_BEARER_TOKEN did not pick up the upstream override's literal token"
        )
        LOGGER.info("[otel-roundtrip] confirmed the api pod's rendered env targets the router, not the gateway")

        proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")

        # --- Fast pre-check (builder-18's mechanism, kept): proves the router -> gateway ->
        # ClickHouse leg works via direct injection before waiting on real, sparser app traffic. ---
        log_marker = f"e2e-roundtrip-log-{uuid.uuid4().hex}"
        log_service_name = f"e2e-roundtrip-log-{uuid.uuid4().hex}"
        status_code, body = _post_otlp_log(
            pod_namespace=namespace,
            pod=proxy_pod,
            router_service_dns=router_service_dns,
            token=ingest_token,
            service_namespace=namespace,
            service_name=log_service_name,
            marker=log_marker,
        )
        assert status_code == 200, f"router rejected the injected pre-check log: HTTP {status_code}, body={body}"
        _wait_for_query_nonzero(
            namespace,
            _CLICKHOUSE_DATABASE,
            f"SELECT count() FROM otel_logs WHERE ServiceName = '{log_service_name}' AND Body = '{log_marker}'",
            description="injected pre-check log reached ClickHouse via the router",
        )

        trace_marker = f"e2e-roundtrip-trace-{uuid.uuid4().hex}"
        trace_service_name = f"e2e-roundtrip-trace-{uuid.uuid4().hex}"
        status_code, body = _post_otlp_trace(
            pod_namespace=namespace,
            pod=proxy_pod,
            router_service_dns=router_service_dns,
            token=ingest_token,
            service_namespace=namespace,
            service_name=trace_service_name,
            marker=trace_marker,
        )
        assert status_code == 200, f"router rejected the injected pre-check span: HTTP {status_code}, body={body}"
        _wait_for_query_nonzero(
            namespace,
            _CLICKHOUSE_DATABASE,
            f"SELECT count() FROM otel_traces WHERE ServiceName = '{trace_service_name}' AND SpanName = '{trace_marker}'",
            description="injected pre-check span reached ClickHouse via the router",
        )
        LOGGER.info("[otel-roundtrip] fast pre-check confirmed router -> gateway -> ClickHouse plumbing")

        # --- Real path: kasm-api's OWN exporter (not injected) now goes through the router.
        # Real traffic is sparser than a synthetic injection, so drive several requests (test_12's
        # _drive_traffic hits the API's /api/public/get_token) and poll with a generous deadline,
        # not a single hit. ---
        for _ in range(5):
            _drive_traffic(namespace)
            time.sleep(2)

        _wait_for_query_nonzero(
            namespace,
            _CLICKHOUSE_DATABASE,
            "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-api'",
            description="real kasm-api log traffic (not injected) reached ClickHouse via the router",
        )
        _wait_for_query_nonzero(
            namespace,
            _CLICKHOUSE_DATABASE,
            "SELECT count() FROM otel_traces WHERE ServiceName = 'kasm-api'",
            description="real kasm-api trace traffic (not injected) reached ClickHouse via the router",
        )
        LOGGER.info(
            "[otel-roundtrip] confirmed REAL kasm-api telemetry flowing apps -> router -> gateway -> ClickHouse"
        )

        # --- Router health, as evidence the forwarded batches were actually processed by a
        # live, ready router (not just accepted at the HTTP layer). ---
        router_pods = kubectl(
            ["get", "pods", "-l", "app.kubernetes.io/component=otel-router", "-o", "json"],
            namespace=router_ns,
        )
        pods_obj = json.loads(router_pods.stdout)
        assert pods_obj["items"], "no router pod found"
        for pod in pods_obj["items"]:
            phase = pod["status"].get("phase")
            assert phase == "Running", f"router pod {pod['metadata']['name']} not Running: {phase}"

        # --- Login page still works throughout, proving the round trip coexists with normal
        # operation (the proxy's own telemetry stays on the local gateway; only api/api-worker
        # are redirected -- see values.yaml's observability.collector.upstream doc). ---
        status_code, _ = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
        assert status_code == 200
    finally:
        _uninstall_router(e2e_config=e2e_config, namespace=namespace)
