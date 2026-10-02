from __future__ import annotations

from pathlib import Path

import pytest

from .helpers import assert_login_page, curl_from_pod, get_first_pod_by_selector
from .netpol_flow import (
    assert_blocked,
    assert_reachable,
    create_probe,
    delete_probe,
    install_netpol_release,
    netpol_values,
    pod_ip,
    upgrade_release,
    write_values,
)

HOST = "kasm.example.test"
CONTROLLER_NS = "ingress-nginx"


def _ns_peer(name: str) -> dict:
    return {"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": name}}}


def _values(proxy_from: list[dict], *, initialize: bool = False) -> dict:
    values = netpol_values(
        extra={
            "proxyService": {"type": "ClusterIP"},
            "ingress": {"enabled": True, "tls": False, "backendProtocol": "http", "ingressClassName": "nginx"},
        }
    )
    values["networkPolicies"]["proxy"] = {"from": proxy_from}
    values["dbManagement"]["initialize"] = initialize
    return values


def _login_via_controller() -> None:
    # Run curl inside the controller pod: the request leaves the controller and reaches the
    # proxy pod from the controller's own namespace, which is what proxy.from must allow.
    controller = get_first_pod_by_selector(CONTROLLER_NS, "app.kubernetes.io/component=controller")
    status, body = curl_from_pod(CONTROLLER_NS, controller, "http://127.0.0.1/", host_header=HOST)
    assert status == 200, f"login page through ingress-nginx returned HTTP {status}"
    assert_login_page(body)


@pytest.mark.e2e
def test_proxy_from_namespace_selector_for_ingress_nginx(installer, temp_workdir: Path) -> None:
    """Needs a real in-cluster ingress-nginx in namespace `ingress-nginx` (the Makefile target installs
    and removes it). proxy.from selects the controller by namespace, the pattern for in-cluster controllers."""
    e2e_config = installer["config"]
    namespace = installer["namespace"]
    release = e2e_config.release_name

    install_netpol_release(
        e2e_config, namespace, write_values(temp_workdir, "values.yaml", _values([_ns_peer(CONTROLLER_NS)], initialize=True))
    )

    _login_via_controller()

    probe = create_probe(namespace)
    try:
        proxy_ip = pod_ip(namespace, release, "proxy")
        assert_blocked(namespace, probe, proxy_ip, 8443, "release-ns probe -> proxy 8443 (proxy.from = ingress-nginx ns)")
        assert_blocked(namespace, probe, proxy_ip, 8080, "release-ns probe -> proxy 8080 (proxy.from = ingress-nginx ns)")

        # Control for the blocks above: also allow the release namespace and the same probe gets in,
        # while the controller keeps working.
        upgrade_release(
            e2e_config,
            namespace,
            write_values(temp_workdir, "wide.yaml", _values([_ns_peer(CONTROLLER_NS), _ns_peer(namespace)])),
        )
        proxy_ip = pod_ip(namespace, release, "proxy")
        assert_reachable(namespace, probe, proxy_ip, 8443, "probe -> proxy 8443 with release ns allowed")
        assert_reachable(namespace, probe, proxy_ip, 8080, "probe -> proxy 8080 with release ns allowed")
        _login_via_controller()
    finally:
        delete_probe(namespace)
