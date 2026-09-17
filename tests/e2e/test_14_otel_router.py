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
    exec_in_pod,
    get_api_image,
    get_first_pod_by_selector,
    helm,
    install_and_wait_with_retry,
    kubectl,
    wait_for_deployments_rolled_out,
    wait_for_pods_ready,
)
from .test_12_observability import (
    _clickhouse_query,
    _get_secret_value,
    _low_resource_values,
    _wait_for_query_nonzero,
)

LOGGER = logging.getLogger(__name__)

ROUTER_CHART_DIR = "/charts/kasm-otel-router"
_CLICKHOUSE_DATABASE = "kasm_otel"


def _router_ns(namespace: str) -> str:
    return f"{namespace}-router"


def _router_release(release_name: str) -> str:
    return f"{release_name}-router"


def _install_router(*, e2e_config, namespace: str, temp_workdir: Path) -> tuple[str, str, str]:
    """Install the router into its own namespace, registered at the Kasm install above.

    Returns (router_namespace, router_service_dns, ingest_token).
    """
    router_ns = _router_ns(namespace)
    router_release = _router_release(e2e_config.release_name)
    kubectl(["create", "namespace", router_ns], namespace=None, check=False)

    gateway_token = _get_secret_value(namespace, f"{e2e_config.release_name}-secrets", "otel-bearer-token")
    ingest_token = uuid.uuid4().hex

    for secret_name, literal in (
        ("otel-router-ingest-token", f"token={ingest_token}"),
        ("otel-gateway-token-copy", f"otel-bearer-token={gateway_token}"),
    ):
        kubectl(["delete", "secret", secret_name, "--ignore-not-found"], namespace=router_ns, check=False)
        kubectl(
            ["create", "secret", "generic", secret_name, f"--from-literal={literal}"],
            namespace=router_ns,
        )

    router_values = {
        "ingestAuth": {"existingSecret": {"name": "otel-router-ingest-token", "key": "token"}},
        "registrations": [
            {
                "namespace": namespace,
                "endpoint": f"{e2e_config.release_name}-otel-gateway.{namespace}.svc.cluster.local:4317",
                "tokenSecret": {"name": "otel-gateway-token-copy", "key": "otel-bearer-token"},
                # The gateway's otlp/remote grpc receiver has no tls block (plaintext, in-cluster,
                # bearer-token auth only) -- see charts/kasm-helm/templates/otel-gateway-configmap.yaml.
                # Without this, the router's exporter defaults to tls.insecure: false and attempts a
                # TLS handshake against a plaintext receiver, so the export silently never succeeds.
                "insecure": True,
            }
        ],
        "k8sEvents": {"enabled": True},
    }
    values_path = temp_workdir / "router-values.yaml"
    values_path.write_text(yaml.safe_dump(router_values, sort_keys=False))

    helm(
        [
            "upgrade",
            "--install",
            router_release,
            ROUTER_CHART_DIR,
            "-n",
            router_ns,
            "--create-namespace",
            "--timeout",
            "5m",
            "--set",
            "imagePullPolicy=Never",
            "-f",
            str(values_path),
        ]
    )
    wait_for_deployments_rolled_out(router_ns, timeout_seconds=300)
    wait_for_pods_ready(router_ns, timeout_seconds=300)

    router_service_dns = f"{router_release}-otel-router.{router_ns}.svc.cluster.local"
    return router_ns, router_service_dns, ingest_token


def _uninstall_router(*, e2e_config, namespace: str) -> None:
    router_ns = _router_ns(namespace)
    router_release = _router_release(e2e_config.release_name)
    helm(["uninstall", router_release, "-n", router_ns], check=False)
    kubectl(["delete", "namespace", router_ns, "--ignore-not-found"], namespace=None, check=False)


def _post_otlp_log(
    *, pod_namespace: str, pod: str, router_service_dns: str, token: str, service_namespace: str, service_name: str, marker: str
) -> tuple[int, str]:
    """POST a single OTLP/HTTP JSON log record into the router's ingest endpoint.

    Curl runs inside a Kasm pod (which already carries curl, per test_12's curl_from_pod usage)
    so the request travels the real in-cluster path (router Service DNS, cross-namespace).
    """
    payload = {
        "resourceLogs": [
            {
                "resource": {
                    "attributes": [
                        {"key": "service.namespace", "value": {"stringValue": service_namespace}},
                        {"key": "service.name", "value": {"stringValue": service_name}},
                    ]
                },
                "scopeLogs": [
                    {
                        "logRecords": [
                            {
                                "timeUnixNano": str(time.time_ns()),
                                "severityText": "INFO",
                                "body": {"stringValue": marker},
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
        f"http://{router_service_dns}:4318/v1/logs",
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
def test_otel_router_forwards_registered_telemetry_and_events(installer, temp_workdir: Path) -> None:
    """Router chain e2e (kasm-helm-56f): one Kasm install (the registration target) and the
    router in its own namespace, proving both that OTLP actually flows router -> gateway ->
    ClickHouse for a matching registration and NOT for a namespace with no registration, and
    that Kubernetes events reach ClickHouse via the same router.

    Run with `make e2e-router`.
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

    router_ns, router_service_dns, ingest_token = _install_router(
        e2e_config=e2e_config, namespace=namespace, temp_workdir=temp_workdir
    )
    try:
        proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")

        # --- Assertion 1: routed OTLP reaches the registered install's ClickHouse. ---
        routed_marker = f"e2e-router-routed-{uuid.uuid4().hex}"
        routed_service_name = f"e2e-router-routed-{uuid.uuid4().hex}"
        status_code, body = _post_otlp_log(
            pod_namespace=namespace,
            pod=proxy_pod,
            router_service_dns=router_service_dns,
            token=ingest_token,
            service_namespace=namespace,
            service_name=routed_service_name,
            marker=routed_marker,
        )
        assert status_code == 200, f"router rejected the routed OTLP send: HTTP {status_code}, body={body}"

        _wait_for_query_nonzero(
            namespace,
            _CLICKHOUSE_DATABASE,
            f"SELECT count() FROM otel_logs WHERE ServiceName = '{routed_service_name}' AND Body = '{routed_marker}'",
            description=f"routed OTLP record (ServiceName={routed_service_name}) reached ClickHouse via the router",
        )
        LOGGER.info("[otel-router] routed record confirmed in ClickHouse")

        # --- Assertion 1b: an OTLP record for an unregistered namespace must NOT land here. ---
        unmatched_service_name = f"e2e-router-unmatched-{uuid.uuid4().hex}"
        unmatched_marker = f"e2e-router-unmatched-{uuid.uuid4().hex}"
        status_code, body = _post_otlp_log(
            pod_namespace=namespace,
            pod=proxy_pod,
            router_service_dns=router_service_dns,
            token=ingest_token,
            service_namespace=f"no-such-namespace-{uuid.uuid4().hex}",
            service_name=unmatched_service_name,
            marker=unmatched_marker,
        )
        assert status_code == 200, f"router rejected the unmatched OTLP send: HTTP {status_code}, body={body}"

        # Give the batch processor and network hops the same headroom the routed record got,
        # then require it to still be absent -- this must fail loudly (nonzero count) if routing
        # broadcasts instead of discriminating, not pass silently.
        time.sleep(15)
        unmatched_count = _clickhouse_query(
            namespace,
            _CLICKHOUSE_DATABASE,
            f"SELECT count() FROM otel_logs WHERE ServiceName = '{unmatched_service_name}'",
        )
        assert int(unmatched_count.splitlines()[0] or "0") == 0, (
            f"OTLP record for an unregistered namespace reached the registered install's ClickHouse "
            f"anyway (count={unmatched_count}) -- the router is broadcasting, not routing"
        )

        # --- Assertion 2: a Kubernetes event in the registered namespace reaches ClickHouse. ---
        probe_pod_name = f"e2e-router-event-probe-{uuid.uuid4().hex[:8]}"
        probe_manifest = {
            "apiVersion": "v1",
            "kind": "Pod",
            "metadata": {"name": probe_pod_name},
            "spec": {
                "restartPolicy": "Never",
                "containers": [
                    {
                        "name": "probe",
                        "image": get_api_image(),
                        "imagePullPolicy": "Never",
                        "command": ["/bin/sh", "-c", "sleep 5"],
                    }
                ],
            },
        }
        manifest_path = temp_workdir / "event-probe.yaml"
        manifest_path.write_text(yaml.safe_dump(probe_manifest, sort_keys=False))
        kubectl(["apply", "-f", str(manifest_path)], namespace=namespace)
        try:
            _wait_for_query_nonzero(
                namespace,
                _CLICKHOUSE_DATABASE,
                "SELECT count() FROM otel_logs WHERE ServiceName = 'kasm-k8s-events'",
                description="a Kubernetes event (ServiceName=kasm-k8s-events, the router's stamp) reached ClickHouse",
            )
        finally:
            kubectl(
                ["delete", "pod", probe_pod_name, "--ignore-not-found", "--grace-period=0", "--force"],
                namespace=namespace,
                check=False,
            )
        LOGGER.info("[otel-router] k8s event confirmed in ClickHouse")
    finally:
        _uninstall_router(e2e_config=e2e_config, namespace=namespace)
