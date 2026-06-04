from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import yaml

from .conftest import helm_install
from .helpers import (
    apply_restricted_pod_security,
    assert_login_page,
    curl_from_pod,
    get_first_pod_by_selector,
    get_jobs_owned_by_cronjob,
    install_and_wait_with_retry,
    kubectl,
    wait_for_cronjob_jobs_succeeded,
    wait_for_job_succeeded,
    wait_for_pods_ready,
    wait_for_pvc_files,
    wait_for_rollouts_complete,
)


def run_backup_upgrade_and_cron_flow(
    installer,
    temp_workdir: Path,
    *,
    restricted_namespace: bool,
) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    if restricted_namespace:
        apply_restricted_pod_security(namespace)

    release_name = e2e_config.release_name
    backup_pvc_name = f"{release_name}-db-backup-e2e"
    cronjob_name = f"{release_name}-db-backup"
    manual_job_name = f"{release_name}-db-backup-manual"
    backup_mount_path = "/backups"

    # Lower per-component resource requests so all pods (api, manager, proxy,
    # bundled db, db-init job, manual db-backup job) fit on the single-node
    # kind cluster in gitlab runner. guac / rdpGateway / rdpHttpsGateway are
    # disabled below so they don't render and don't need overrides.
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    base_values = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "certificate": {
            "secretName": "kasm-deployment-tls",
        },
        "proxyService": {
            "type": "ClusterIP",
        },
        "ingress": {
            "enabled": False,
        },
        "imagePullSecrets": {
            "enabled": False,
        },
        "components": {
            "api": {"resources": low_resources},
            "manager": {"resources": low_resources},
            "proxy": {"resources": low_resources_proxy},
            "guac": {
                "enabled": False,
            },
            "rdpGateway": {
                "enabled": False,
            },
            "rdpHttpsGateway": {
                "enabled": False,
            },
        },
    }

    initial_values = {
        **base_values,
        "dbManagement": {
            "initialize": True,
            "upgrade": {
                "enable": False,
            },
            "backupCron": {
                "enabled": False,
                "pvcName": backup_pvc_name,
                "pvcSize": 1,
            },
        },
    }

    initial_values_path = temp_workdir / "initial-values.yaml"
    initial_values_path.write_text(yaml.safe_dump(initial_values, sort_keys=False))

    kubectl(["delete", "job", manual_job_name, "--ignore-not-found"], namespace=namespace, check=False)
    kubectl(["delete", "pvc", backup_pvc_name, "--ignore-not-found"], namespace=namespace, check=False)
    kubectl(["wait", "--for=delete", f"pvc/{backup_pvc_name}", "--timeout=180s"], namespace=namespace, check=False)

    setup_namespace_fn = None
    if restricted_namespace:
        setup_namespace_fn = lambda: apply_restricted_pod_security(namespace)

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(initial_values_path),
        setup_namespace_fn=setup_namespace_fn,
    )

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)

    upgrade_values = {
        **base_values,
        "dbManagement": {
            "initialize": False,
            "upgrade": {
                "enable": False,
            },
            "backupCron": {
                "enabled": True,
                "schedule": "* * * * *",
                "timeZone": "Etc/UTC",
                "pvcName": backup_pvc_name,
                "pvcSize": 1,
            },
        },
    }

    upgrade_values_path = temp_workdir / "upgrade-values.yaml"
    upgrade_values_path.write_text(yaml.safe_dump(upgrade_values, sort_keys=False))

    helm_install(
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(upgrade_values_path),
    )
    wait_for_rollouts_complete(namespace, timeout_seconds=1200)
    wait_for_pods_ready(namespace, timeout_seconds=1200, progress=True)

    kubectl(["get", "cronjob", cronjob_name], namespace=namespace)
    files_before_manual = wait_for_pvc_files(
        namespace,
        backup_pvc_name,
        mount_path=backup_mount_path,
        filename_prefix="kasm_dump_",
        min_count=0,
        timeout_seconds=180,
    )

    kubectl(["delete", "job", manual_job_name, "--ignore-not-found"], namespace=namespace, check=False)
    kubectl(
        ["create", "job", f"--from=cronjob/{cronjob_name}", manual_job_name],
        namespace=namespace,
    )
    wait_for_job_succeeded(namespace, job_name=manual_job_name, timeout_seconds=1200)

    files_after_manual = wait_for_pvc_files(
        namespace,
        backup_pvc_name,
        mount_path=backup_mount_path,
        filename_prefix="kasm_dump_",
        min_count=len(files_before_manual) + 1,
        timeout_seconds=180,
    )
    assert all(int(entry["size"]) > 0 for entry in files_after_manual)

    cron_wait_started_at = datetime.now(timezone.utc)
    cron_successes_before_wait = len(
        [
            job
            for job in get_jobs_owned_by_cronjob(
                namespace,
                cronjob_name,
                created_after=cron_wait_started_at,
            )
            if int(job.get("status", {}).get("succeeded", 0)) >= 1
        ]
    )
    wait_for_cronjob_jobs_succeeded(
        namespace,
        cronjob_name,
        min_successes=cron_successes_before_wait + 2,
        created_after=cron_wait_started_at,
        timeout_seconds=240,
    )

    final_files = wait_for_pvc_files(
        namespace,
        backup_pvc_name,
        mount_path=backup_mount_path,
        filename_prefix="kasm_dump_",
        min_count=len(files_after_manual) + 2,
        timeout_seconds=240,
    )

    final_file_names = [str(entry["name"]) for entry in final_files]
    assert all(int(entry["size"]) > 0 for entry in final_files)
    assert len(final_file_names) == len(set(final_file_names))
