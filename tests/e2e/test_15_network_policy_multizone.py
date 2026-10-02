from __future__ import annotations

from pathlib import Path

import pytest

from .helpers import kubectl
from .netpol_flow import (
    assert_blocked,
    assert_reachable,
    create_probe,
    delete_probe,
    front_door_ingress_address,
    install_netpol_release,
    iter_zone_pods,
    login_page_via_ingress,
    netpol_values,
    write_values,
)

HOSTS = ["kasm.example.test", "zonea.kasm.example.test", "zoneb.kasm.example.test"]


@pytest.mark.e2e
def test_multizone_ingress_under_network_policies(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]
    release = e2e_config.release_name

    values = netpol_values(
        zones=[
            {"name": "zonea", "proxyAddress": "zonea.kasm.example.test"},
            {"name": "zoneb", "proxyAddress": "zoneb.kasm.example.test"},
        ],
        extra={
            "proxyService": {"type": "ClusterIP"},
            "ingress": {"enabled": True, "tls": False, "backendProtocol": "http"},
        },
    )
    install_netpol_release(e2e_config, namespace, write_values(temp_workdir, "values.yaml", values))

    # Every pod is Ready (install waited on it); make sure both zones exist. guac and the rdp
    # gateways only render for the first zone.
    for component in ("proxy", "api", "manager"):
        assert len(list(iter_zone_pods(namespace, release, component))) == 2, f"expected one {component} pod per zone"
    for component in ("guac", "rdp-gateway", "rdp-https-gateway"):
        assert len(list(iter_zone_pods(namespace, release, component))) == 1, f"expected one {component} pod"

    # Through the controller, outside the cluster, for every host.
    address = front_door_ingress_address(namespace, release)
    for host in HOSTS:
        login_page_via_ingress(address, host)

    # An unlabeled pod reaches every zone's proxy (control) but no zone's api.
    probe = create_probe(namespace)
    try:
        for ip in iter_zone_pods(namespace, release, "proxy"):
            assert_reachable(namespace, probe, ip, 8443, f"probe -> proxy {ip}:8443")
        for ip in iter_zone_pods(namespace, release, "api"):
            assert_blocked(namespace, probe, ip, 8080, f"probe -> api {ip}:8080")
    finally:
        delete_probe(namespace)
