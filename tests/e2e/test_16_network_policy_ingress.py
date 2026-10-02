from __future__ import annotations

import ipaddress
from pathlib import Path

import pytest

from .helpers import kubectl
from .netpol_flow import (
    assert_blocked,
    assert_reachable,
    create_probe,
    delete_probe,
    front_door_ingress_address,
    ingress_blocked,
    install_netpol_release,
    login_page_via_ingress,
    netpol_values,
    pod_ip,
    upgrade_release,
    write_values,
)

HOST = "kasm.example.test"


def _values(proxy_from: list[dict]) -> dict:
    values = netpol_values(
        extra={
            "proxyService": {"type": "ClusterIP"},
            "ingress": {"enabled": True, "tls": False, "backendProtocol": "http"},
        }
    )
    values["networkPolicies"]["proxy"] = {"from": proxy_from}
    values["dbManagement"]["initialize"] = False
    return values


@pytest.mark.e2e
def test_proxy_from_limited_to_ingress_controller(installer, temp_workdir: Path) -> None:
    """The kind ingress controller is cloud-provider-kind's Envoy, a container on the docker
    `kind` network, not a pod in an in-cluster ingress-nginx namespace. A namespaceSelector can
    therefore never match it; proxy.from uses the ipBlock of the docker network instead
    (derived from the node address), which is how a site fronts the cluster with an external LB."""
    e2e_config = installer["config"]
    namespace = installer["namespace"]
    release = e2e_config.release_name

    node_ip = kubectl(
        ["get", "nodes", "-o", "jsonpath={.items[0].status.addresses[?(@.type==\"InternalIP\")].address}"]
    ).stdout.split()[0]
    kind_net = str(ipaddress.ip_network(f"{node_ip}/16", strict=False))

    first = _values([{"ipBlock": {"cidr": kind_net}}])
    first["dbManagement"]["initialize"] = True
    install_netpol_release(e2e_config, namespace, write_values(temp_workdir, "values.yaml", first))

    address = front_door_ingress_address(namespace, release)
    login_page_via_ingress(address, HOST)

    # In-chart callers still reach the proxy: install waited for guac/rdp* Ready, and the
    # rule that lets them call the proxy is independent of proxy.from.
    probe = create_probe(namespace)
    try:
        proxy_ip = pod_ip(namespace, release, "proxy")
        # Pod network is outside the docker CIDR, so a direct connect is denied.
        assert_blocked(namespace, probe, proxy_ip, 8443, "release-ns probe -> proxy 8443 (proxy.from = ingress network)")
        assert_blocked(namespace, probe, proxy_ip, 8080, "release-ns probe -> proxy 8080 (proxy.from = ingress network)")

        # Control for the above: widen proxy.from to the pod network and the same probe gets in.
        pod_cidr = str(ipaddress.ip_network(f"{kubectl(['get', 'pod', 'np-probe', '-o', 'jsonpath={.status.podIP}'], namespace=namespace).stdout.strip()}/16", strict=False))
        upgrade_release(
            e2e_config,
            namespace,
            write_values(temp_workdir, "wide.yaml", _values([{"ipBlock": {"cidr": kind_net}}, {"ipBlock": {"cidr": pod_cidr}}])),
        )
        assert_reachable(namespace, probe, proxy_ip, 8443, "probe -> proxy 8443 with pod network allowed")

        # And the ingress path really is governed by proxy.from: a source that is not the
        # controller leaves the front door closed.
        upgrade_release(
            e2e_config,
            namespace,
            write_values(temp_workdir, "wrong.yaml", _values([{"ipBlock": {"cidr": "192.0.2.0/24"}}])),
        )
        ingress_blocked(address, HOST)

        # Control: re-open proxy.from to the ingress network and the same request is served
        # again, so the block above came from the policy and not from a broken controller.
        upgrade_release(
            e2e_config,
            namespace,
            write_values(temp_workdir, "reopen.yaml", _values([{"ipBlock": {"cidr": kind_net}}])),
        )
        login_page_via_ingress(address, HOST)
    finally:
        delete_probe(namespace)
