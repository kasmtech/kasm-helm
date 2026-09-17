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


def _put_literal_secret(namespace: str, secret_name: str, literal: str) -> None:
    """Create/replace a single-key literal Secret. Shared by _install_router (single-registration)
    and test_18's multi-registration install (kasm-helm-6a7, which needs one gateway-token-copy
    Secret per release rather than the single one below)."""
    kubectl(["delete", "secret", secret_name, "--ignore-not-found"], namespace=namespace, check=False)
    kubectl(["create", "secret", "generic", secret_name, f"--from-literal={literal}"], namespace=namespace)


def install_router_with_registrations(
    *,
    router_ns: str,
    router_release: str,
    ingest_token_secret: str,
    registrations: list[dict],
    temp_workdir: Path,
    k8s_events: bool = True,
) -> str:
    """Install (or upgrade) the router with a caller-built `registrations[]` list.

    Generalizes `_install_router` below (which derives everything from a single Kasm install) so
    test_18's multi-tenant isolation scenario (kasm-helm-6a7) can register two releases against
    one router without duplicating the namespace/helm/wait plumbing. Caller creates the ingest
    Secret (named by `ingest_token_secret`) and every registration's own tokenSecret Secret
    beforehand -- this function only builds the values file and installs.

    Returns the router's Service DNS.
    """
    kubectl(["create", "namespace", router_ns], namespace=None, check=False)

    router_values = {
        "ingestAuth": {"existingSecret": {"name": ingest_token_secret, "key": "token"}},
        "registrations": registrations,
        "k8sEvents": {"enabled": k8s_events},
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

    return f"{router_release}-otel-router.{router_ns}.svc.cluster.local"


def _install_router(
    *, e2e_config, namespace: str, temp_workdir: Path, ingest_token: str | None = None
) -> tuple[str, str, str]:
    """Install the router into its own namespace, registered at the Kasm install above.

    `ingest_token` lets a caller (test_17's roundtrip scenario, kasm-helm-xc8 part 2) pin the
    router's ingest credential to a value it already handed to a kasm-helm install's
    `observability.collector.upstream.token` before this router install runs. Defaults to
    generating one, as before, when the caller has no such requirement (test_14 itself).

    Returns (router_namespace, router_service_dns, ingest_token). Requires the Kasm release at
    `namespace` to already exist: it reads that release's own gateway bearer token (via the
    `-secrets` Secret) to authenticate the router's registration back to that release's gateway.
    """
    router_ns = _router_ns(namespace)
    router_release = _router_release(e2e_config.release_name)

    gateway_token = _get_secret_value(namespace, f"{e2e_config.release_name}-secrets", "otel-bearer-token")
    ingest_token = ingest_token or uuid.uuid4().hex

    kubectl(["create", "namespace", router_ns], namespace=None, check=False)
    _put_literal_secret(router_ns, "otel-router-ingest-token", f"token={ingest_token}")
    _put_literal_secret(router_ns, "otel-gateway-token-copy", f"otel-bearer-token={gateway_token}")

    router_service_dns = install_router_with_registrations(
        router_ns=router_ns,
        router_release=router_release,
        ingest_token_secret="otel-router-ingest-token",
        registrations=[
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
        temp_workdir=temp_workdir,
        k8s_events=True,
    )

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
