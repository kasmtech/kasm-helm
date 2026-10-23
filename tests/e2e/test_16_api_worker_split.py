"""
E2E test for components.api.workerPool (kasm-helm-37c / kasm-helm-tzy).

Installs the chart from tests/values/api-worker-split-e2e.yaml (single zone, no
ingress, so it fits the single-node kind cluster without also standing up
ingress-nginx) with two workerPool entries (a full-queue "primary" pool and a
restricted-queue "restricted" pool, layered here with kind-sized resource
requests) and verifies the resulting Deployment fan-out: worker pods run
KASM_PROCESS=TRUE with the pool's queue list, api itself publishes only
(KASM_PROCESS=FALSE), there is no worker Service, each worker pool's own
/livez:8081 liveness endpoint responds 200, and the login page is reachable
through the proxy (proving api's readiness endpoint passed transitively).
"""

from __future__ import annotations

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

_LOW = {"requests": {"cpu": "50m", "memory": "256Mi"}}
_LOW_PROXY = {"requests": {"cpu": "50m", "memory": "128Mi"}}
_LOW_GW = {"requests": {"cpu": "25m", "memory": "128Mi"}}


def _pod_env(namespace: str, pod: str, var: str) -> str:
    result = kubectl(
        [
            "get",
            "pod",
            pod,
            "-o",
            f"jsonpath={{.spec.containers[0].env[?(@.name=='{var}')].value}}",
        ],
        namespace=namespace,
    )
    return result.stdout.strip()


@pytest.mark.e2e
def test_api_worker_split_mode(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    # tests/values/api-worker-split-e2e.yaml is the single source for the
    # scenario topology (deploymentSize, workerPool); this only layers on the
    # kind-sized resource requests and install-time fields that fixture
    # deliberately leaves out (see its header comment).
    fixture_path = Path("/e2e-values/api-worker-split-e2e.yaml")
    values_obj = yaml.safe_load(fixture_path.read_text())
    values_obj["publicAddr"] = "kasm.example.com"
    values_obj["certificate"] = {"secretName": "kasm-deployment-tls"}
    values_obj["components"] = {
        "api": {
            "resources": _LOW,
            "workerPool": [
                {**pool, "resources": _LOW}
                for pool in values_obj["components"]["api"]["workerPool"]
            ],
        },
        "proxy": {"resources": _LOW_PROXY},
        "connectionProxy": {
            "nginx": {"resources": _LOW_PROXY},
            "guac": {"resources": _LOW},
            "rdpGateway": {"resources": _LOW_GW},
            "rdpHttpsGateway": {"resources": _LOW_GW},
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

    release = e2e_config.release_name

    # install_and_wait_with_retry already blocked until every pod in the namespace
    # (api, both worker pools, proxy, connection-proxy, db) is Running and Ready —
    # which for api/api-worker means their readinessProbe (/api/__healthcheck) and,
    # transitively, their livenessProbe (/livez) both already passed. Per-pool
    # worker Deployments exist and are Ready (single default zone, so no zone
    # suffix beyond the pool name). D002: the Deployment's own name is shortened
    # to <release>-api-<pool>-default, but its pods still carry the
    # app.kubernetes.io/name selector label from the "apiWorker" component
    # (<release>-api-worker-<pool>-default) to stay distinct from the api pods.
    for pool in ("primary", "restricted"):
        deployment_name = f"{release}-api-{pool}-default"
        label_name = f"{release}-api-worker-{pool}-default"
        status = kubectl(
            ["get", "deployment", deployment_name, "-o", "jsonpath={.status.readyReplicas}"],
            namespace=namespace,
        )
        assert status.stdout.strip() == "1", (
            f"Expected {deployment_name} readyReplicas=1, got {status.stdout.strip()!r}"
        )
        # readyReplicas above is transitive on the readinessProbe only; hit the
        # worker's own liveness endpoint (D008: /livez:8081) directly so the
        # docstring's "liveness endpoint respond[s]" claim is actually checked.
        pod = get_first_pod_by_selector(
            namespace, f"app.kubernetes.io/name={label_name}"
        )
        status_code, _ = curl_from_pod(namespace, pod, "http://localhost:8081/livez")
        assert status_code == 200, f"{deployment_name} pod {pod} /livez returned {status_code}"

    # No worker Service: workers only consume queues, they're never addressed directly.
    worker_services = kubectl(
        ["get", "service", "-l", "app.kubernetes.io/component=api-worker", "-o", "name"],
        namespace=namespace,
    )
    assert worker_services.stdout.strip() == "", (
        f"Expected no api-worker Service, found: {worker_services.stdout.strip()}"
    )

    # Worker pods: KASM_PROCESS=TRUE and the pool's own queue list.
    expected_queues = {"primary": "all", "restricted": "session,heartbeat"}
    for pool, queues in expected_queues.items():
        pod = get_first_pod_by_selector(
            namespace,
            f"app.kubernetes.io/name={release}-api-worker-{pool}-default",
        )
        assert _pod_env(namespace, pod, "KASM_PROCESS") == "TRUE", (
            f"Expected KASM_PROCESS=TRUE on {pool} worker pod {pod}"
        )
        assert _pod_env(namespace, pod, "KASM_WORKER_QUEUES") == queues, (
            f"Expected KASM_WORKER_QUEUES={queues!r} on {pool} worker pod {pod}"
        )

    # api itself is publish-only with a non-empty workerPool: KASM_PROCESS=FALSE.
    api_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=api")
    assert _pod_env(namespace, api_pod, "KASM_PROCESS") == "FALSE", (
        f"Expected KASM_PROCESS=FALSE on publish-only api pod {api_pod}"
    )

    # api still serves the login page via the proxy (its /api/__healthcheck
    # readinessProbe already passed, above, or the pod would never have gone Ready).
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)
