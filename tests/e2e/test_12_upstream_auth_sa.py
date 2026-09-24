from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from .helpers import (
    assert_login_page,
    curl_from_host,
    curl_from_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
    kubectl,
    wait_for_gateway_programmed,
    wait_for_ingress_address,
    wait_for_service_lb_address,
)
from .conftest import helm_install


@pytest.mark.e2e
def test_serviceaccount_and_upstream_auth_service_lb(installer, temp_workdir: Path) -> None:
    """Covers two independent features in one install (they don't conflict):

    - components.api/components.manager serviceAccount: both point at the same
      name, so the chart must create exactly one ServiceAccount and both pods
      must run under it (dedupe, per templates/serviceaccount.yaml).
    - upstreamAuth.service: a LoadBalancer Service fronting the same proxy
      backend the front door uses, provisioned here by cloud-provider-kind. The
      request is made from the pytest container itself (curl_from_host, which
      runs with --network host - see the Makefile), not from a pod inside the
      cluster, so it goes through the real external envoy LB container on the
      docker `kind` network rather than potentially being answered by a node's
      kube-proxy rules for the Service's ClusterIP (see FINDINGS F14 note 5).

    upstreamAuth.ingress and the front-door httpRoute/Gateway are covered in
    separate tests below (they are mutually exclusive with upstreamAuth.service
    and with each other, respectively - see kasm.validateUpstreamAuthExposure /
    kasm.validateProxyExposure - so each needs its own install).

    tlsRoute/tcpRoute remain unit-test-only: cloud-provider-kind v0.9.0 installs
    no tlsroutes/tcproutes CRD in its standard gateway channel, and its
    experimental channel crashes on a malformed embedded kustomization.yaml
    (FINDINGS F11). Not affected by the KIND_VERSION/node-image bump (F13).
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    shared_sa_name = "kasm-shared-sa"
    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.test",
        "certificate": {
            "secretName": "kasm-deployment-tls",
        },
        "serviceAccount": {"create": True},
        "components": {
            "api": {
                "serviceAccount": {"name": shared_sa_name},
                "resources": low_resources,
            },
            "manager": {
                "serviceAccount": {"name": shared_sa_name},
                "resources": low_resources,
            },
            "proxy": {"resources": low_resources_proxy},
            "guac": {"resources": low_resources},
            "rdpGateway": {"resources": low_resources_gw},
            "rdpHttpsGateway": {"resources": low_resources_gw},
        },
        "upstreamAuth": {
            "hostname": "kasm-mgmt.example.test",
            "service": {
                "enabled": True,
                "type": "LoadBalancer",
            },
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

    # ServiceAccount dedupe: exactly one ServiceAccount rendered by the chart in
    # this namespace (label-selected count, not just "does the named one exist" -
    # a dedupe bug that created a second object under a different name would pass
    # a name-only exists check but fail this one), and it carries the shared name.
    sa_list = kubectl(
        [
            "get",
            "sa",
            "-l",
            f"app.kubernetes.io/component=service-account,app.kubernetes.io/instance={e2e_config.release_name}",
            "-o",
            "jsonpath={.items[*].metadata.name}",
        ],
        namespace=namespace,
    )
    sa_names = sa_list.stdout.split()
    assert sa_names == [shared_sa_name], f"expected exactly one ServiceAccount {shared_sa_name!r}, got {sa_names}"

    for component in ("api", "manager"):
        pod_name = get_first_pod_by_selector(namespace, f"app.kubernetes.io/component={component}")
        sa_name = kubectl(
            ["get", "pod", pod_name, "-o", "jsonpath={.spec.serviceAccountName}"],
            namespace=namespace,
        ).stdout.strip()
        assert sa_name == shared_sa_name, f"{component} pod {pod_name} runs under {sa_name!r}, expected {shared_sa_name!r}"

    # upstreamAuth.service: cloud-provider-kind assigns the LoadBalancer an
    # external IP; the backend is the same proxy Service the front door uses,
    # so a plain HTTPS request through it should reach the login page. Curled
    # from the host (see curl_from_host docstring) to actually exercise the
    # external LB datapath.
    lb_address = wait_for_service_lb_address(namespace, f"{e2e_config.release_name}-upstream-auth-default")
    status_code, body = curl_from_host(
        f"https://{lb_address}:443/",
        insecure=True,
    )
    assert status_code == 200, f"Expected 200 from upstream-auth LB, got {status_code}"
    assert_login_page(body)


@pytest.mark.e2e
def test_upstream_auth_ingress(installer, temp_workdir: Path) -> None:
    """upstreamAuth.ingress: mutually exclusive with upstreamAuth.service (see
    kasm.validateUpstreamAuthExposure), so it needs its own install. Uses the
    same http-backend/no-tls shortcut as test_03_multizone_ingress.py to keep
    this deterministic against cloud-provider-kind's Ingress controller.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.test",
        "certificate": {"secretName": "kasm-deployment-tls"},
        "components": {
            "api": {"resources": low_resources},
            "manager": {"resources": low_resources},
            "proxy": {"resources": low_resources_proxy},
            "guac": {"resources": low_resources},
            "rdpGateway": {"resources": low_resources_gw},
            "rdpHttpsGateway": {"resources": low_resources_gw},
        },
        "upstreamAuth": {
            "hostname": "kasm-mgmt.example.test",
            "ingress": {
                "enabled": True,
                "tls": False,
                "backendProtocol": "http",
            },
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

    ingress_address = wait_for_ingress_address(namespace, f"{e2e_config.release_name}-upstream-auth")
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(
        namespace,
        proxy_pod,
        f"http://{ingress_address}/",
        host_header="kasm-mgmt.example.test",
    )
    assert status_code == 200, f"Expected 200 from upstream-auth Ingress, got {status_code}"
    assert_login_page(body)


@pytest.mark.e2e
def test_front_door_httproute_via_gateway(installer, temp_workdir: Path) -> None:
    """httpRoute: publishes publicAddr through a Gateway API Gateway. The chart
    only renders the HTTPRoute (it never owns a Gateway - see templates/httproute.yaml),
    so the test creates the Gateway itself, gatewayClassName=cloud-provider-kind, the
    same class the ingress and service-LB tests rely on.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]
    gateway_name = "kasm-frontdoor-gateway"

    gateway_manifest = {
        "apiVersion": "gateway.networking.k8s.io/v1",
        "kind": "Gateway",
        "metadata": {"name": gateway_name},
        "spec": {
            "gatewayClassName": "cloud-provider-kind",
            "listeners": [{"name": "http", "protocol": "HTTP", "port": 80}],
        },
    }
    gateway_path = temp_workdir / "gateway.yaml"
    gateway_path.write_text(yaml.safe_dump(gateway_manifest))
    kubectl(["apply", "-f", str(gateway_path)], namespace=namespace)

    try:
        low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
        low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
        low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
        values_obj = {
            "deploymentSize": "small",
            "publicAddr": "kasm.example.test",
            "certificate": {"secretName": "kasm-deployment-tls"},
            "proxyService": {"type": "ClusterIP"},
            "components": {
                "api": {"resources": low_resources},
                "manager": {"resources": low_resources},
                "proxy": {"resources": low_resources_proxy},
                "guac": {"resources": low_resources},
                "rdpGateway": {"resources": low_resources_gw},
                "rdpHttpsGateway": {"resources": low_resources_gw},
            },
            "httpRoute": {
                "enabled": True,
                "parentRefs": [{"name": gateway_name}],
                "backendProtocol": "http",
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

        gateway_address = wait_for_gateway_programmed(namespace, gateway_name)
        proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
        status_code, body = curl_from_pod(
            namespace,
            proxy_pod,
            f"http://{gateway_address}/",
            host_header="kasm.example.test",
        )
        assert status_code == 200, f"Expected 200 from front-door HTTPRoute via Gateway, got {status_code}"
        assert_login_page(body)
    finally:
        kubectl(["delete", "gateway", gateway_name, "--ignore-not-found"], namespace=namespace, check=False)
