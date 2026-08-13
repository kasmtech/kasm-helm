"""
E2E tests for zone configuration — primary selection, region routing, and
per-zone resource fan-out.

These tests install the chart with various kasmZones configurations and verify
that Kubernetes creates the correct set of resources (StatefulSets, Deployments,
Services) with zone-specific names. Pod readiness is not required; the tests
only verify that the Kubernetes API reflects the expected resource topology.

Post connection-proxy-consolidation: guac, rdp-gateway, and rdp-https-gateway
are no longer separate workloads. They are three service containers inside a
single zone-scoped `connection-proxy` StatefulSet
(`<release>-connection-proxy-<zone>`). There is no longer a separate
`rdp-gateway` Deployment. api, manager, and proxy remain separate zone-scoped
Deployments.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import pytest
import yaml

from .helpers import helm, kubectl
from .conftest import helm_install


def _helm_install_no_wait(*, e2e_config, namespace: str, values_file: str) -> None:
    """Install chart without waiting for pod readiness — only applies resources."""
    helm(
        [
            "upgrade",
            "--install",
            e2e_config.release_name,
            e2e_config.chart_dir,
            "-n",
            namespace,
            "--create-namespace",
            "--timeout",
            "5m",
            "--set",
            "imagePullPolicy=Never",
            "-f",
            values_file,
        ]
    )


def _get_resource_names(namespace: str, kind: str) -> list[str]:
    """Return a sorted list of resource names for the given resource kind."""
    result = kubectl(
        ["get", kind, "-o", "custom-columns=NAME:.metadata.name", "--no-headers"],
        namespace=namespace,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return []
    return sorted(line.strip() for line in result.stdout.splitlines() if line.strip())


def _wait_for_resource_count(
    namespace: str,
    kind: str,
    expected_count: int,
    *,
    timeout_seconds: int = 60,
    poll_seconds: int = 3,
) -> list[str]:
    """Poll until the resource count matches or timeout is reached."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        names = _get_resource_names(namespace, kind)
        if len(names) == expected_count:
            return names
        time.sleep(poll_seconds)
    names = _get_resource_names(namespace, kind)
    assert len(names) == expected_count, (
        f"Expected {expected_count} {kind} in {namespace}, got {len(names)}: {names}"
    )
    return names


LOW = {"requests": {"cpu": "50m", "memory": "256Mi"}}
LOW_PROXY = {"requests": {"cpu": "50m", "memory": "128Mi"}}
LOW_GW = {"requests": {"cpu": "25m", "memory": "128Mi"}}

_COMPONENT_RESOURCES = {
    "components": {
        "api": {"resources": LOW},
        "manager": {"resources": LOW},
        "proxy": {"resources": LOW_PROXY},
        "connectionProxy": {
            "guac": {"resources": LOW},
            "rdpGateway": {"resources": LOW_GW},
            "rdpHttpsGateway": {"resources": LOW_GW},
        },
    },
}


@pytest.mark.e2e
def test_primary_zone_at_non_zero_index(installer, temp_workdir: Path) -> None:
    """
    When primary: true is on the second zone (index 1), the connection-proxy
    StatefulSet (housing guac, rdp-gateway, and rdp-https-gateway) must carry
    that zone's name, not the first zone's. API, Manager, and Proxy deploy for
    both zones.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.test",
        "certificate": {"secretName": "kasm-deployment-tls"},
        "proxyService": {"type": "ClusterIP"},
        "ingress": {"enabled": True, "tls": False, "backendProtocol": "http"},
        "kasmZones": [
            {"name": "zoneb", "proxyAddress": "zoneb.kasm.example.test"},
            {"name": "zonea", "proxyAddress": "zonea.kasm.example.test", "primary": True},
        ],
        **_COMPONENT_RESOURCES,
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    _helm_install_no_wait(
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    # Both zones get api, manager, and proxy deployments (2 zones x 3 = 6).
    api_names = _wait_for_resource_count(namespace, "deployments", 6)
    assert any("api-zonea" in n for n in api_names), f"No api-zonea deployment: {api_names}"
    assert any("api-zoneb" in n for n in api_names), f"No api-zoneb deployment: {api_names}"
    assert any("manager-zonea" in n for n in api_names), f"No manager-zonea deployment: {api_names}"
    assert any("manager-zoneb" in n for n in api_names), f"No manager-zoneb deployment: {api_names}"
    assert any("proxy-zonea" in n for n in api_names), f"No proxy-zonea deployment: {api_names}"
    assert any("proxy-zoneb" in n for n in api_names), f"No proxy-zoneb deployment: {api_names}"

    # The connection-proxy StatefulSet (guac + rdp-gateway + rdp-https-gateway
    # containers) is created only for the primary zone (zonea), plus the db
    # StatefulSet (not zone-scoped).
    sts_names = _wait_for_resource_count(namespace, "statefulsets", 2)
    assert any("connection-proxy-zonea" in n for n in sts_names), (
        f"Expected connection-proxy-zonea statefulset: {sts_names}"
    )
    assert not any("connection-proxy-zoneb" in n for n in sts_names), (
        f"Unexpected connection-proxy-zoneb statefulset: {sts_names}"
    )


@pytest.mark.e2e
def test_same_region_name_full_stack_per_zone(installer, temp_workdir: Path) -> None:
    """
    When two zones share the same region_name as the primary zone, the
    connection-proxy StatefulSet (housing guac, rdp-gateway, and
    rdp-https-gateway) deploys once per zone in that region.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.test",
        "certificate": {"secretName": "kasm-deployment-tls"},
        "proxyService": {"type": "ClusterIP"},
        "ingress": {"enabled": True, "tls": False, "backendProtocol": "http"},
        "kasmZones": [
            {
                "name": "zonea",
                "proxyAddress": "zonea.kasm.example.test",
                "primary": True,
                "region_name": "us-east",
            },
            {
                "name": "zoneb",
                "proxyAddress": "zoneb.kasm.example.test",
                "region_name": "us-east",
            },
        ],
        **_COMPONENT_RESOURCES,
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    _helm_install_no_wait(
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    # With 2 same-region zones: api-zonea + api-zoneb + manager-zonea +
    # manager-zoneb + proxy-zonea + proxy-zoneb = 6 deployments (guac,
    # rdp-gateway, rdp-https-gateway no longer add separate Deployments; they
    # are containers inside the connection-proxy StatefulSet).
    all_deploys = _wait_for_resource_count(namespace, "deployments", 6)

    api_deploys = [n for n in all_deploys if "api" in n and "manager" not in n]
    assert len(api_deploys) == 2, f"Expected 2 api deployments, got: {api_deploys}"

    # connection-proxy produces one StatefulSet per zone in the primary
    # region, plus the (non-zoned) db StatefulSet = 3 total.
    sts_names = _wait_for_resource_count(namespace, "statefulsets", 3)
    cp_sts = [n for n in sts_names if "connection-proxy" in n]
    assert len(cp_sts) == 2, f"Expected 2 connection-proxy statefulsets: {sts_names}"
    assert any("zonea" in n for n in cp_sts)
    assert any("zoneb" in n for n in cp_sts)


@pytest.mark.e2e
def test_cross_region_limits_full_stack_to_primary(installer, temp_workdir: Path) -> None:
    """
    When two zones have different region_names, the connection-proxy
    StatefulSet (guac/rdp-gateway/rdp-https-gateway) deploys only for the
    primary region zone. API, Manager, and Proxy deploy for both zones.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.test",
        "certificate": {"secretName": "kasm-deployment-tls"},
        "proxyService": {"type": "ClusterIP"},
        "ingress": {"enabled": True, "tls": False, "backendProtocol": "http"},
        "kasmZones": [
            {
                "name": "zonea",
                "proxyAddress": "zonea.kasm.example.test",
                "primary": True,
                "region_name": "us-east",
            },
            {
                "name": "zoneb",
                "proxyAddress": "zoneb.kasm.example.test",
                "region_name": "eu-west",
            },
        ],
        **_COMPONENT_RESOURCES,
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    _helm_install_no_wait(
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    # 2 zones → 2 api + 2 manager + 2 proxy = 6 deployments total. connection-proxy
    # is a StatefulSet (housing guac/rdp-gateway/rdp-https-gateway), not a
    # Deployment, so it does not appear here.
    all_deploys = _wait_for_resource_count(namespace, "deployments", 6)

    api_deploys = [n for n in all_deploys if "-api-" in n]
    assert len(api_deploys) == 2, f"Expected 2 api deployments: {api_deploys}"
    assert any("zonea" in n for n in api_deploys)
    assert any("zoneb" in n for n in api_deploys)

    proxy_deploys = [n for n in all_deploys if "-proxy-" in n]
    assert len(proxy_deploys) == 2, f"Expected 2 proxy deployments: {proxy_deploys}"

    # Only primary region (zonea) gets the connection-proxy StatefulSet, plus
    # the (non-zoned) db StatefulSet = 2 total.
    sts_names = _wait_for_resource_count(namespace, "statefulsets", 2)
    cp_sts = [n for n in sts_names if "connection-proxy" in n]
    assert len(cp_sts) == 1, f"Expected 1 connection-proxy statefulset: {sts_names}"
    assert "zonea" in cp_sts[0]
