from __future__ import annotations

import os
from pathlib import Path

import pytest
import yaml

from .helpers import wait_for_job_succeeded, wait_for_pods_ready, wait_for_rollouts_complete
from .conftest import helm_install


@pytest.mark.e2e
def test_external_db_init_succeeds_and_pods_ready(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    external_db_host = os.environ.get("EXTERNAL_DB_HOST")
    external_db_password = os.environ.get("EXTERNAL_DB_PASSWORD", "postgres")
    if not external_db_host:
        raise AssertionError("EXTERNAL_DB_HOST is required for external DB test (pipeline should set it)")

    # Create secret containing postgres master password (used only when database.standalone and postgresMasterUser is set)
    secret_yaml = f"""
apiVersion: v1
kind: Secret
metadata:
  name: external-postgres-secret
type: Opaque
stringData:
  db-password: {external_db_password}
"""
    (temp_workdir / "secret.yaml").write_text(secret_yaml)

    from .helpers import kubectl  # avoid circular import

    kubectl(["apply", "-f", str(temp_workdir / "secret.yaml")], namespace=namespace)

    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "certificate": {
            "secretName": "kasm-deployment-tls",
        },
        "database": {
            "standalone": True,
            "hostname": external_db_host,
            "port": 5432,
            "kasmDbUser": "kasmapp",
            "kasmDbSecret": {
                "name": "external-postgres-secret",
                "key": "db-password",
            },
            "postgresMasterUser": {
                "username": "kasmapp",
                "secret": {
                    "name": "external-postgres-secret",
                    "key": "db-password"
                },
            },
        },
        # dbManagement.initialize default is true; keep it true to validate init
        "dbManagement": {
            "initialize": True,
            "backupCron": {
                "enabled": False
            },
        },
    }
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    helm_install(e2e_config=e2e_config, namespace=namespace, values_file=str(values_path))

    wait_for_job_succeeded(namespace, job_name=f"{e2e_config.release_name}-db-init", timeout_seconds=1500)
    wait_for_rollouts_complete(namespace, timeout_seconds=1200)
    wait_for_pods_ready(namespace, timeout_seconds=1500)
