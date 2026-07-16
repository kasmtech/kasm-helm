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

ZONE_NAME = "preseed-zone"
ZONE_PROXY_PORT = 9443
ZONE_PROXY_HOSTNAME = "kasm-preseed.example.com"
ZONE_UPSTREAM_AUTH = "auth-preseed.example.com"

POOL_NAME = "preseed-test-pool"
DO_CONFIG_NAME = "preseed-test-do"
DO_CONFIG_REGION = "nyc3"
AUTOSCALE_NAME = "preseed-test-autoscale"
AUTOSCALE_STANDBY_BYTES = 2147483648

preseed_values = {
    "deploymentSize": "small",
    "publicAddr": "kasm.example.com",
    "certificate": {
        "secretName": "kasm-deployment-tls",
    },
    "kasmZones": [
        {
            "name": ZONE_NAME,
            "primary": True,
            "proxy_port": ZONE_PROXY_PORT,
            "proxy_hostname": ZONE_PROXY_HOSTNAME,
            "upstream_auth_address": ZONE_UPSTREAM_AUTH,
        },
    ],
    "proxyService": {"type": "ClusterIP"},
    "kasmConfig": {
        "generatePreseed": True,
        "defaultUsers": True,
        "config": {
            "groups": [
                {
                    "name": "Preseed Test Group",
                    "description": "Created by preseed e2e test",
                    "priority": 500,
                }
            ],
            "server_pools": [
                {
                    "name": POOL_NAME,
                    "server_pool_type": "Docker",
                }
            ],
            "digital_ocean_vm_configs": [
                {
                    "config_name": DO_CONFIG_NAME,
                    "region": DO_CONFIG_REGION,
                    "max_instances": 5,
                }
            ],
            "autoscale": [
                {
                    "autoscale_config_name": AUTOSCALE_NAME,
                    "pool_name": POOL_NAME,
                    "zone_name": ZONE_NAME,
                    "digital_ocean_vm_config_name": DO_CONFIG_NAME,
                    "standby_memory_bytes": AUTOSCALE_STANDBY_BYTES,
                }
            ],
        },
    },
    "components": {
        "api": {"resources": {"requests": {"cpu": "50m", "memory": "256Mi"}}},
        "manager": {"resources": {"requests": {"cpu": "50m", "memory": "256Mi"}}},
        "proxy": {"resources": {"requests": {"cpu": "50m", "memory": "128Mi"}}},
        "guac": {"resources": {"requests": {"cpu": "50m", "memory": "256Mi"}}},
        "rdpGateway": {"resources": {"requests": {"cpu": "25m", "memory": "128Mi"}}},
        "rdpHttpsGateway": {"resources": {"requests": {"cpu": "25m", "memory": "128Mi"}}},
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
def test_preseed_group_and_settings_seeded(installer, temp_workdir: Path) -> None:
    """Deploy with generatePreseed=true and verify groups, users, and zone config are seeded."""
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    values_path = temp_workdir / "preseed-values.yaml"
    values_path.write_text(yaml.safe_dump(preseed_values, sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    api_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=api")
    LOGGER.info("Using API pod: %s", api_pod)

    # Verify the custom group was created.
    group_count = _query_db(
        namespace,
        api_pod,
        "SELECT COUNT(*) FROM groups WHERE name = 'Preseed Test Group'",
    )
    assert group_count.strip() == "1", (
        f"Expected 1 'Preseed Test Group' in groups table, got: {group_count!r}"
    )
    LOGGER.info("Preseed group verified: Preseed Test Group present")

    # Verify the admin user exists (created via defaultUsers).
    admin_count = _query_db(
        namespace,
        api_pod,
        "SELECT COUNT(*) FROM users WHERE username = 'admin@kasm.local'",
    )
    assert admin_count.strip() == "1", (
        f"Expected admin@kasm.local in users table, got: {admin_count!r}"
    )
    LOGGER.info("Admin user verified: admin@kasm.local present")

    # Verify the custom zone was seeded with the correct name.
    zone_count = _query_db(
        namespace,
        api_pod,
        f"SELECT COUNT(*) FROM zones WHERE zone_name = '{ZONE_NAME}'",
    )
    assert zone_count.strip() == "1", (
        f"Expected 1 zone with name {ZONE_NAME!r} in zones table, got: {zone_count!r}"
    )
    LOGGER.info("Zone name verified: %s present", ZONE_NAME)

    # Verify zone proxy_port was seeded from kasmZones config (not the 443 default).
    zone_port = _query_db(
        namespace,
        api_pod,
        f"SELECT proxy_port FROM zones WHERE zone_name = '{ZONE_NAME}'",
    )
    assert zone_port.strip() == str(ZONE_PROXY_PORT), (
        f"Expected proxy_port={ZONE_PROXY_PORT} for zone {ZONE_NAME!r}, got: {zone_port!r}"
    )
    LOGGER.info("Zone proxy_port verified: %s", ZONE_PROXY_PORT)

    # Verify zone proxy_hostname was seeded (not the $request_host$ default).
    zone_hostname = _query_db(
        namespace,
        api_pod,
        f"SELECT proxy_hostname FROM zones WHERE zone_name = '{ZONE_NAME}'",
    )
    assert zone_hostname.strip() == ZONE_PROXY_HOSTNAME, (
        f"Expected proxy_hostname={ZONE_PROXY_HOSTNAME!r} for zone {ZONE_NAME!r}, "
        f"got: {zone_hostname!r}"
    )
    LOGGER.info("Zone proxy_hostname verified: %s", ZONE_PROXY_HOSTNAME)

    # Verify upstream_auth_address was seeded from config.
    zone_auth = _query_db(
        namespace,
        api_pod,
        f"SELECT upstream_auth_address FROM zones WHERE zone_name = '{ZONE_NAME}'",
    )
    assert zone_auth.strip() == ZONE_UPSTREAM_AUTH, (
        f"Expected upstream_auth_address={ZONE_UPSTREAM_AUTH!r} for zone {ZONE_NAME!r}, "
        f"got: {zone_auth!r}"
    )
    LOGGER.info("Zone upstream_auth_address verified: %s", ZONE_UPSTREAM_AUTH)

    # --- Server pool ---
    pool_count = _query_db(
        namespace,
        api_pod,
        f"SELECT COUNT(*) FROM server_pools WHERE server_pool_name = '{POOL_NAME}'",
    )
    assert pool_count.strip() == "1", (
        f"Expected 1 server pool named {POOL_NAME!r}, got: {pool_count!r}"
    )
    LOGGER.info("Server pool verified: %s present", POOL_NAME)

    # --- Digital Ocean VM config ---
    do_count = _query_db(
        namespace,
        api_pod,
        f"SELECT COUNT(*) FROM digital_ocean_vm_configs WHERE config_name = '{DO_CONFIG_NAME}'",
    )
    assert do_count.strip() == "1", (
        f"Expected 1 DO config named {DO_CONFIG_NAME!r}, got: {do_count!r}"
    )
    LOGGER.info("Digital Ocean VM config verified: %s present", DO_CONFIG_NAME)

    # --- Autoscale config ---
    autoscale_count = _query_db(
        namespace,
        api_pod,
        f"SELECT COUNT(*) FROM autoscale_configs WHERE autoscale_config_name = '{AUTOSCALE_NAME}'",
    )
    assert autoscale_count.strip() == "1", (
        f"Expected 1 autoscale config named {AUTOSCALE_NAME!r}, got: {autoscale_count!r}"
    )
    LOGGER.info("Autoscale config verified: %s present", AUTOSCALE_NAME)

    # Verify autoscale → pool cross-reference resolved correctly (name → UUID).
    pool_xref = _query_db(
        namespace,
        api_pod,
        f"""SELECT COUNT(*) FROM autoscale_configs a
            JOIN server_pools p ON a.server_pool_id = p.server_pool_id
            WHERE a.autoscale_config_name = '{AUTOSCALE_NAME}'
              AND p.server_pool_name = '{POOL_NAME}'""",
    )
    assert pool_xref.strip() == "1", (
        f"Autoscale {AUTOSCALE_NAME!r} pool_name cross-reference to {POOL_NAME!r} failed: "
        f"got {pool_xref!r}"
    )
    LOGGER.info("Autoscale → pool cross-reference verified")

    # Verify autoscale → DO VM config cross-reference resolved correctly.
    do_xref = _query_db(
        namespace,
        api_pod,
        f"""SELECT COUNT(*) FROM autoscale_configs a
            JOIN digital_ocean_vm_configs d ON a.digital_ocean_vm_config_id = d.config_id
            WHERE a.autoscale_config_name = '{AUTOSCALE_NAME}'
              AND d.config_name = '{DO_CONFIG_NAME}'""",
    )
    assert do_xref.strip() == "1", (
        f"Autoscale {AUTOSCALE_NAME!r} DO config cross-reference to {DO_CONFIG_NAME!r} failed: "
        f"got {do_xref!r}"
    )
    LOGGER.info("Autoscale → Digital Ocean VM config cross-reference verified")

    # Verify autoscale → zone cross-reference resolved correctly.
    zone_xref = _query_db(
        namespace,
        api_pod,
        f"""SELECT COUNT(*) FROM autoscale_configs a
            JOIN zones z ON a.zone_id = z.zone_id
            WHERE a.autoscale_config_name = '{AUTOSCALE_NAME}'
              AND z.zone_name = '{ZONE_NAME}'""",
    )
    assert zone_xref.strip() == "1", (
        f"Autoscale {AUTOSCALE_NAME!r} zone cross-reference to {ZONE_NAME!r} failed: "
        f"got {zone_xref!r}"
    )
    LOGGER.info("Autoscale → zone cross-reference verified")

    # Verify standby_memory_bytes was seeded as a BIGINT (not float/scientific notation).
    standby = _query_db(
        namespace,
        api_pod,
        f"SELECT standby_memory_bytes FROM autoscale_configs WHERE autoscale_config_name = '{AUTOSCALE_NAME}'",
    )
    assert standby.strip() == str(AUTOSCALE_STANDBY_BYTES), (
        f"Expected standby_memory_bytes={AUTOSCALE_STANDBY_BYTES} for {AUTOSCALE_NAME!r}, "
        f"got: {standby!r}"
    )
    LOGGER.info("Autoscale standby_memory_bytes verified: %d", AUTOSCALE_STANDBY_BYTES)

