from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from .helpers import (
    assert_login_page,
    curl_from_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
)
from .conftest import helm_install


@pytest.mark.e2e
def test_multizone_ingress_routes_publicaddr_and_zone_hosts(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    # Use HTTP backend for ingress -> proxy to keep this deterministic in KinD.
    # Lower per-component resource requests so all 11 multizone pods schedule
    # on a single kind node.  Chart's small preset requests 500m per pod which
    # multiplies across the 2 zones; on CI runners that exceeds allocatable.
    # Tests don't drive real load, so small requests are plenty; limits are
    # intentionally omitted (Burstable QoS, no upper bound).
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.test",
        "certificate": {
            "secretName": "kasm-deployment-tls",
        },
        "proxyService": {"type": "ClusterIP"},
        "kasmZones": [
            {"name": "zonea", "proxyAddress": "zonea.kasm.example.test"},
            {"name": "zoneb", "proxyAddress": "zoneb.kasm.example.test"},
        ],
        "ingress": {
            "enabled": True,
            "tls": False,
            "backendProtocol": "http",
        },
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

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")

    # With Kind port mappings, access ingress via host-mapped port from the test container (host network).
    ingress_service_url = "http://localhost:8080/"

    for host in ["kasm.example.test", "zonea.kasm.example.test", "zoneb.kasm.example.test"]:
        status_code, body = curl_from_pod(
            namespace,
            proxy_pod,
            ingress_service_url,
            host_header=host,
            insecure=False,
        )
        assert status_code == 200, f"Expected 200 for host={host}, got {status_code}"
        assert_login_page(body)
