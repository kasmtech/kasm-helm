from __future__ import annotations

import logging
from pathlib import Path

import pytest
import yaml

from .helpers import (
    exec_in_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
)
from .conftest import helm_install

LOGGER = logging.getLogger("e2e")

PRIMARY_ZONE = "zonea"
SECONDARY_ZONE = "zoneb"
GLOBAL_UPSTREAM_AUTH_HOSTNAME = "auth.kasm.example.test"
ZONE_OVERRIDE_UPSTREAM_AUTH = "auth-zoneb.kasm.example.test"

LOW = {"requests": {"cpu": "50m", "memory": "256Mi"}}
LOW_PROXY = {"requests": {"cpu": "50m", "memory": "128Mi"}}
LOW_GW = {"requests": {"cpu": "25m", "memory": "128Mi"}}

preseed_values = {
    "deploymentSize": "small",
    "publicAddr": "kasm.example.test",
    "certificate": {
        "secretName": "kasm-deployment-tls",
    },
    "proxyService": {"type": "ClusterIP"},
    "ingress": {
        "enabled": True,
        "tls": False,
        "backendProtocol": "http",
    },
    "kasmZones": [
        {"name": PRIMARY_ZONE, "proxyAddress": "zonea.kasm.example.test"},
        {
            "name": SECONDARY_ZONE,
            "proxyAddress": "zoneb.kasm.example.test",
            "upstream_auth_address": ZONE_OVERRIDE_UPSTREAM_AUTH,
        },
    ],
    "upstreamAuth": {
        "hostname": GLOBAL_UPSTREAM_AUTH_HOSTNAME,
    },
    "kasmConfig": {
        "generatePreseed": True,
    },
    "components": {
        "api": {"resources": LOW},
        "manager": {"resources": LOW},
        "proxy": {"resources": LOW_PROXY},
        "guac": {"resources": LOW},
        "rdpGateway": {"resources": LOW_GW},
        "rdpHttpsGateway": {"resources": LOW_GW},
    },
    "dbManagement": {
        "initialize": True,
    },
}


def _query_db(namespace: str, pod_name: str, query: str) -> str:
    result = exec_in_pod(
        namespace,
        pod_name,
        [
            "bash",
            "-c",
            f'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -t -A -c "{query}"',
        ],
    )
    return result.stdout.strip()


@pytest.mark.e2e
def test_upstream_auth_hostname_preseeded_per_zone(installer, temp_workdir: Path) -> None:
    """upstreamAuth.hostname falls back to the primary zone only; a zone with
    its own upstream_auth_address keeps that explicit value (see
    kasm.zoneUpstreamAuthAddress, _helpers.tpl:156)."""
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    values_path = temp_workdir / "upstream-auth-preseed-values.yaml"
    values_path.write_text(yaml.safe_dump(preseed_values, sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    api_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=api")
    LOGGER.info("Using API pod: %s", api_pod)

    primary_auth = _query_db(
        namespace,
        api_pod,
        f"SELECT upstream_auth_address FROM zones WHERE zone_name = '{PRIMARY_ZONE}'",
    )
    assert primary_auth.strip() == GLOBAL_UPSTREAM_AUTH_HOSTNAME, (
        f"Expected primary zone {PRIMARY_ZONE!r} to fall back to upstreamAuth.hostname="
        f"{GLOBAL_UPSTREAM_AUTH_HOSTNAME!r}, got: {primary_auth!r}"
    )
    LOGGER.info(
        "Primary zone upstream_auth_address verified: %s", GLOBAL_UPSTREAM_AUTH_HOSTNAME
    )

    secondary_auth = _query_db(
        namespace,
        api_pod,
        f"SELECT upstream_auth_address FROM zones WHERE zone_name = '{SECONDARY_ZONE}'",
    )
    assert secondary_auth.strip() == ZONE_OVERRIDE_UPSTREAM_AUTH, (
        f"Expected overridden zone {SECONDARY_ZONE!r} to keep its explicit "
        f"upstream_auth_address={ZONE_OVERRIDE_UPSTREAM_AUTH!r}, got: {secondary_auth!r}"
    )
    LOGGER.info(
        "Overridden zone upstream_auth_address verified: %s", ZONE_OVERRIDE_UPSTREAM_AUTH
    )
