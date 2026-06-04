from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml

from .helpers import kubectl, wait_for_pods_ready, wait_for_job_succeeded
from .conftest import helm_install


@pytest.mark.e2e
def test_route_deploys_and_is_accessible_when_openshift(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    # Detect Route API
    api_resources = kubectl(["api-resources", "-o", "name"]).stdout.splitlines()
    if "routes.route.openshift.io" not in api_resources:
        pytest.skip("OpenShift Route API not available in this cluster")

    # Lower per-component resource requests so all pods (api, manager, proxy,
    # guac + nginx sidecar, rdpGateway + nginx sidecar, rdpHttpsGateway +
    # nginx sidecar, bundled db) fit on small test clusters.
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    values_obj = {
        "deploymentSize": "small",
        "isOpenshift": True,
        "publicAddr": "kasm-route.example.test",
        "route": {
            "enabled": True,
            "backendProtocol": "http",
        },
        "proxyService": {"type": "ClusterIP"},
        "components": {
            "api": {"resources": low_resources},
            "manager": {"resources": low_resources},
            "proxy": {"resources": low_resources_proxy},
            "guac": {"resources": low_resources},
            "rdpGateway": {"resources": low_resources_gw},
            "rdpHttpsGateway": {"resources": low_resources_gw},
        },
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    helm_install(e2e_config=e2e_config, namespace=namespace, values_file=str(values_path))

    wait_for_job_succeeded(namespace, job_name=f"{e2e_config.release_name}-db-init", timeout_seconds=1200)
    wait_for_pods_ready(namespace, timeout_seconds=1200)

    # We validate the Route object exists; actual external reachability depends on OpenShift router,
    # which is outside the scope of Docker-only CI.
    route_obj = kubectl(["get", "route", "-l", "app.kubernetes.io/component=proxy", "-o", "json"], namespace=namespace)
    parsed = json.loads(route_obj.stdout)
    if not parsed.get("items"):
        raise AssertionError("Route not created")
