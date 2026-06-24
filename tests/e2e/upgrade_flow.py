from __future__ import annotations

import json
import logging
import os
import subprocess
import time
from pathlib import Path

import yaml

from .conftest import E2EConfig
from .helpers import (
    assert_login_page,
    curl_from_pod,
    get_chart_app_version,
    get_first_pod_by_selector,
    helm,
    kubectl,
    wait_for_job_succeeded,
    wait_for_pods_ready,
    wait_for_pvc_files,
    wait_for_rollouts_complete,
)

LOGGER = logging.getLogger("e2e")

# Lower bound on tables in the ``public`` schema for a healthy 1.18.1
# db-init.  Healthy installs produce dozens; silent-failure leaves 0 or
# a handful.  Counting tables (vs. rows in a specific table) keeps the
# check version-agnostic.
_MIN_PUBLIC_TABLE_COUNT = 5

# Short polling window to absorb a race between Job-Completed and our
# query catching up.  If tables are still empty after this window, the
# 1.18.1 startup.sh silently failed; Phase 1 is retried up to
# _PHASE1_MAX_ATTEMPTS times before the test is declared a failure.
_VERIFY_TIMEOUT_SECONDS = 30
_VERIFY_POLL_SECONDS = 5

# Number of attempts for the full Phase 1 install when _verify_db_init
# detects the 1.18.1 silent-failure mode.
_PHASE1_MAX_ATTEMPTS = 3

# ---------------------------------------------------------------------------
# Old-version chart discovery
#
# The pytest container has no access to the host git repo, so the Makefile
# extracts the previous-version chart on the host (``make extract-old-chart``)
# and bind-mounts it into the container at ``E2E_OLD_CHART_DIR`` (default
# ``/old-chart``).  Layout under that path mirrors the source tree:
#   /old-chart/charts/kasm        (1.18.x)
#   /old-chart/charts/kasm-helm   (1.19+)
# ---------------------------------------------------------------------------

def find_old_chart_dir() -> Path:
    """Return the path to the extracted previous-version chart root.

    Raises ``AssertionError`` with an actionable message if the env var
    isn't set or the expected layout isn't present (e.g. the Makefile
    target wasn't run).
    """
    root = os.environ.get("E2E_OLD_CHART_DIR")
    if not root:
        raise AssertionError(
            "E2E_OLD_CHART_DIR is not set.  The upgrade test runs the old "
            "chart from a host-extracted directory.  Use the Makefile "
            "targets ``make e2e-upgrade-included`` or "
            "``make e2e-upgrade-standalone`` — they extract the chart and "
            "set this env var automatically."
        )

    base = Path(root)
    for candidate in ("charts/kasm-helm", "charts/kasm"):
        path = base / candidate
        if (path / "Chart.yaml").exists():
            return path

    raise AssertionError(
        f"Could not find a chart root under {base} "
        f"(looked for charts/kasm-helm and charts/kasm).  "
        f"Was ``make extract-old-chart`` run successfully?"
    )


def _helm_install_chart(
    *,
    e2e_config: E2EConfig,
    namespace: str,
    chart_dir: Path,
    values_file: Path,
) -> None:
    """Run a fresh ``helm install`` against an arbitrary *chart_dir*.

    Used only for Phase 1 of the upgrade flow.  Plain ``install`` (not
    ``upgrade --install``) so the command fails loudly if a release with
    this name already exists from a previous unclean run, instead of
    silently turning into an upgrade.
    """
    helm([
        "install",
        e2e_config.release_name,
        str(chart_dir),
        "-n", namespace,
        "--create-namespace",
        "--timeout", "15m",
        "--set", "imagePullPolicy=Never",
        "-f", str(values_file),
    ])


def _helm_uninstall_phase1(*, e2e_config: E2EConfig, namespace: str) -> None:
    """Tear down a failed Phase 1 install so it can be retried cleanly.

    Uninstalls the Helm release and waits for all pods to terminate.
    PVCs are left in place (the DB StatefulSet PVC retains data across
    chart uninstalls by default, but a fresh install will re-use it and
    the db-init job will re-seed it).
    """
    LOGGER.info("[upgrade] tearing down failed Phase 1 install for retry")
    try:
        helm(["uninstall", e2e_config.release_name, "-n", namespace, "--wait", "--timeout", "5m"])
    except Exception as exc:
        LOGGER.warning("[upgrade] helm uninstall returned non-zero (continuing): %s", exc)
    # Delete any PVCs so the next install starts with a fresh DB volume.
    kubectl(["delete", "pvc", "--all", "-n", namespace, "--ignore-not-found", "--wait=true", "--timeout=60s"])
    LOGGER.info("[upgrade] Phase 1 teardown complete")


# ---------------------------------------------------------------------------
# Standalone (external) PostgreSQL helpers
#
# Mirrors the contract used by test_04_external_db.py:
#   - The external postgres is provisioned outside the cluster by the
#     ``tests/e2e/start_external_postgres.sh`` script (called from the
#     Makefile, not from Python).
#   - The Makefile passes its IP and password into the pytest container
#     via the ``EXTERNAL_DB_HOST`` and ``EXTERNAL_DB_PASSWORD`` env vars.
#   - The external postgres ships with user ``kasmapp`` and DB ``postgres``.
# ---------------------------------------------------------------------------

_EXTERNAL_DB_SECRET = "external-postgres-secret"
_EXTERNAL_DB_USER = "kasmapp"


def _ensure_external_db_secret(
    namespace: str,
    password: str,
    work_dir: Path,
) -> None:
    """Create/refresh the secret holding the external postgres password.

    Same shape as the secret created in test_04_external_db.py so the chart
    sees an identical configuration.
    """
    manifest = (
        "apiVersion: v1\n"
        "kind: Secret\n"
        "metadata:\n"
        f"  name: {_EXTERNAL_DB_SECRET}\n"
        "type: Opaque\n"
        "stringData:\n"
        f"  db-password: {password}\n"
    )
    secret_path = work_dir / "external-db-secret.yaml"
    secret_path.write_text(manifest)
    kubectl(["apply", "-f", str(secret_path)], namespace=namespace)


def _wait_for_init_container_running(
    namespace: str,
    *,
    label_selector: str,
    container_name: str,
    timeout_seconds: int,
) -> str:
    """Block until a pod matching *label_selector* has an init container
    named *container_name* in Running state, and return that pod's name.

    Used to detect the moment the db-upgrade pod's
    ``db-major-version-is-ready`` init container starts polling for
    PostgreSQL 16 — that is the safe window to swap the external DB.
    """
    deadline = time.monotonic() + timeout_seconds
    last_phase: str | None = None
    while time.monotonic() < deadline:
        result = kubectl(
            ["get", "pods", "-l", label_selector, "-o", "json"],
            namespace=namespace,
            check=False,
        )
        if result.returncode == 0:
            pods = json.loads(result.stdout).get("items", [])
            for pod in pods:
                last_phase = pod.get("status", {}).get("phase")
                for status in pod.get("status", {}).get("initContainerStatuses", []):
                    if status.get("name") != container_name:
                        continue
                    if status.get("state", {}).get("running"):
                        return pod["metadata"]["name"]
        time.sleep(3)
    raise TimeoutError(
        f"No pod matching {label_selector!r} in namespace {namespace} reached an "
        f"init container {container_name!r} in Running state within "
        f"{timeout_seconds}s (last observed pod phase: {last_phase})"
    )


def _swap_external_postgres(new_version: str) -> None:
    """Run swap_external_postgres.sh inside the pytest container.

    Requires the host's docker socket to be bind-mounted (the Makefile
    target ``e2e-upgrade-standalone`` sets ``E2E_DOCKER_SOCK=true`` for
    this purpose).  The script reuses the fixed IP and SSL volume so
    chart-deployed resources continue to reach the same hostname.
    """
    script = Path(__file__).resolve().parent / "swap_external_postgres.sh"
    if not script.is_file():
        raise FileNotFoundError(f"swap_external_postgres.sh not found at {script}")
    proc = subprocess.run(
        [str(script), new_version],
        capture_output=True,
        text=True,
        timeout=180,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"swap_external_postgres.sh failed (rc={proc.returncode})\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )


def _external_db_values(host: str) -> dict:
    """Return the ``database:`` block for a standalone-DB install."""
    return {
        "database": {
            "standalone": True,
            "hostname": host,
            "port": 5432,
            "kasmDbUser": _EXTERNAL_DB_USER,
            "kasmDbSecret": {
                "name": _EXTERNAL_DB_SECRET,
                "key": "db-password",
            },
            "postgresMasterUser": {
                "username": _EXTERNAL_DB_USER,
                "secret": {
                    "name": _EXTERNAL_DB_SECRET,
                    "key": "db-password",
                },
            },
        }
    }


# ---------------------------------------------------------------------------
# Core upgrade flow
# ---------------------------------------------------------------------------

def _count_public_tables(namespace: str, db_pod: str) -> int:
    """Count tables in the ``public`` schema, or return ``-1`` if the
    query fails (DB not reachable yet — vs. ``0`` which means the
    schema is definitively empty).
    """
    result = kubectl(
        ["exec", db_pod, "--",
         "psql", "-U", "kasmapp", "-d", "kasm", "-tAc",
         "SELECT count(*) FROM pg_tables WHERE schemaname='public';"],
        namespace=namespace,
        check=False,
    )
    if result.returncode != 0:
        return -1
    try:
        return int(result.stdout.strip())
    except (ValueError, AttributeError):
        return -1


def _verify_db_init(
    namespace: str,
    *,
    release_name: str,
    job_name: str,
    work_dir: Path,
) -> None:
    """Assert the 1.18.1 db-init Job actually populated the schema.

    1.18.1's ``startup.sh`` swallows transient sqlalchemy errors
    (typically ``EAI_AGAIN`` from CoreDNS under CPU pressure) and
    exits 0, leaving the Job marked Completed against an empty schema.
    Without this check, the test instead times out 5+ minutes later
    in ``wait_for_rollouts_complete`` with no obvious cause.

    The 1.19 chart's db-init Job has a built-in retry+verify loop
    (charts/kasm-helm/templates/db-init-job.yaml); 1.18.1 doesn't.
    On failure: re-run the pipeline; persistent failures indicate the
    api image needs an upstream fix.
    """
    db_pod = get_first_pod_by_selector(
        namespace, "app.kubernetes.io/component=db",
    )
    deadline = time.monotonic() + _VERIFY_TIMEOUT_SECONDS
    last_count = -1
    attempt = 0
    while time.monotonic() < deadline:
        attempt += 1
        last_count = _count_public_tables(namespace, db_pod)
        LOGGER.info(
            "[upgrade] db-init verification attempt %d: public table count=%d "
            "(threshold=%d)",
            attempt, last_count, _MIN_PUBLIC_TABLE_COUNT,
        )
        if last_count >= _MIN_PUBLIC_TABLE_COUNT:
            return
        time.sleep(_VERIFY_POLL_SECONDS)

    raise AssertionError(
        f"1.18.1 db-init Job {job_name!r} reported success but the DB "
        f"seed never ran (public table count={last_count} after "
        f"{attempt} polls over {_VERIFY_TIMEOUT_SECONDS}s, expected >= "
        f"{_MIN_PUBLIC_TABLE_COUNT}). Known silent-failure mode of "
        f"kasmweb/api:1.18.1 startup.sh under CPU pressure; re-run "
        f"the pipeline. See _verify_db_init docstring for context."
    )


def run_upgrade_flow(
    installer,
    temp_workdir: Path,
    *,
    standalone_db: bool,
) -> None:
    """End-to-end upgrade test: install 1.18.1, upgrade to current chart.

    Two modes controlled by *standalone_db*:
      False — use the chart-bundled DB StatefulSet (included DB).
      True  — point Kasm at an external standalone PostgreSQL provisioned
              by ``tests/e2e/start_external_postgres.sh`` (same pattern as
              test_04_external_db.py).  The Makefile target is responsible
              for starting/stopping the postgres container and for setting
              ``EXTERNAL_DB_HOST`` / ``EXTERNAL_DB_PASSWORD`` env vars.

    Pre-requisites for CI:
      - KinD images loaded for BOTH 1.18.1 and the current branch.
      - For standalone mode: ``EXTERNAL_DB_HOST`` exported by the Makefile
        target before invoking pytest.
    """
    e2e_config = installer["config"]
    namespace = installer["namespace"]
    release_name = e2e_config.release_name

    app_version = get_chart_app_version()
    # Chart helper kasm.dbUpgradeBackupPvcName replaces "." with "-" in the
    # appVersion when constructing the PVC name (templates/_helpers.tpl).
    app_version_slug = app_version.replace(".", "-")
    backup_pvc_name = f"{release_name}-{app_version_slug}-db-pre-upgrade-backup"
    backup_job_name = f"{release_name}-pre-upgrade-backup"   # 1.19 pre-upgrade hook
    upgrade_job_name = f"{release_name}-db-upgrade"          # 1.19 upgrade job
    init_job_name_118 = f"{release_name}-db-init-job"        # 1.18 naming convention

    # -----------------------------------------------------------------------
    # Shared base values used in both installs.  Keep this minimal — the
    # chart defaults are what production users get, and matching them is the
    # whole point of an upgrade test.  See test_01_basic_deploy.py for the
    # same set of overrides.
    # -----------------------------------------------------------------------
    # Low per-component requests so the Phase 1 (1.18.1) + Phase 2 (current)
    # pods both fit on a busy GitLab runner. Mirrors test_03_multizone_ingress.
    # Tests don't drive real load; limits are intentionally omitted.
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    base_values: dict = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "certificate": {
            "secretName": "kasm-deployment-tls",
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

    if standalone_db:
        external_db_host = os.environ.get("EXTERNAL_DB_HOST")
        external_db_password = os.environ.get("EXTERNAL_DB_PASSWORD", "postgres")
        if not external_db_host:
            raise AssertionError(
                "EXTERNAL_DB_HOST is required for the standalone-DB upgrade "
                "test.  The Makefile target should start the external postgres "
                "container via tests/e2e/start_external_postgres.sh and export "
                "EXTERNAL_DB_HOST before invoking pytest."
            )
        _ensure_external_db_secret(namespace, external_db_password, temp_workdir)
        db_values = _external_db_values(external_db_host)
    else:
        db_values = {}

    # -----------------------------------------------------------------------
    # Phase 1: Install previous version (extracted by ``make extract-old-chart``)
    #
    # Wrapped in a retry loop because 1.18.1's startup.sh swallows transient
    # sqlalchemy/DNS errors under CPU pressure and exits 0 without seeding the
    # DB.  When _verify_db_init detects that silent failure we uninstall,
    # delete the PVC so the next install gets a clean volume, and retry.
    # -----------------------------------------------------------------------
    old_chart_dir = find_old_chart_dir()

    initial_values = {
        **base_values,
        **db_values,
        "dbManagement": {
            "initialize": True,
            "upgrade": {"enable": False},
            "backupCron": {"enabled": False},
        },
    }
    initial_values_path = temp_workdir / "initial-values.yaml"
    initial_values_path.write_text(yaml.safe_dump(initial_values, sort_keys=False))

    for phase1_attempt in range(1, _PHASE1_MAX_ATTEMPTS + 1):
        LOGGER.info(
            "[upgrade] phase 1 — installing previous chart from %s (attempt %d/%d)",
            old_chart_dir, phase1_attempt, _PHASE1_MAX_ATTEMPTS,
        )
        _helm_install_chart(
            e2e_config=e2e_config,
            namespace=namespace,
            chart_dir=old_chart_dir,
            values_file=initial_values_path,
        )

        # 1.18.1 names the init job differently from 1.19.
        wait_for_job_succeeded(
            namespace,
            job_name=init_job_name_118,
            timeout_seconds=360,
        )
        # Catch the 1.18.1 silent-failure mode (see _verify_db_init).
        # Skipped for standalone — no in-cluster db pod to exec into.
        if not standalone_db:
            try:
                _verify_db_init(
                    namespace,
                    release_name=release_name,
                    job_name=init_job_name_118,
                    work_dir=temp_workdir,
                )
            except AssertionError as exc:
                if phase1_attempt < _PHASE1_MAX_ATTEMPTS:
                    LOGGER.warning(
                        "[upgrade] phase 1 attempt %d/%d failed db-init verification, "
                        "retrying: %s",
                        phase1_attempt, _PHASE1_MAX_ATTEMPTS, exc,
                    )
                    _helm_uninstall_phase1(e2e_config=e2e_config, namespace=namespace)
                    continue
                raise
        break

    wait_for_rollouts_complete(namespace, timeout_seconds=1200)
    wait_for_pods_ready(namespace, timeout_seconds=1200, progress=True)

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(
        namespace, proxy_pod, "https://localhost:8443/", insecure=True
    )
    assert status_code == 200, f"Expected 200 after 1.18.1 install, got {status_code}"
    assert_login_page(body)
    LOGGER.info("[upgrade] phase 1 complete — 1.18.1 is healthy")

    # -----------------------------------------------------------------------
    # Phase 2: Upgrade to current chart (1.19)
    #
    # ``helm upgrade --timeout 15m`` blocks until all pre-upgrade hooks
    # complete.  By the time it returns:
    #   weight -10: backup PVC has been created
    #   weight  10: pre-upgrade backup job has run pg_dump to the PVC
    #   chart resources applied: upgrade job is now in the cluster
    # -----------------------------------------------------------------------
    LOGGER.info("[upgrade] phase 2 — upgrading to current chart")

    # Remove any leftover upgrade job so Helm can create it fresh (Jobs are
    # immutable; Helm cannot patch an existing one).
    kubectl(
        ["delete", "job", upgrade_job_name, "--ignore-not-found"],
        namespace=namespace,
        check=False,
    )

    upgrade_values = {
        **base_values,
        **db_values,
        "dbManagement": {
            "initialize": False,
            "upgrade": {
                "enable": True,
                # The backup job writes to /data/kasm-db-dump/$OLD_DB_BACKUP_FILENAME.
                # The upgrade job skips pg_restore when the settings table exists
                # (DB already initialised by 1.18.1), so this value is only used
                # as the dump filename — it still needs to be a valid string.
                "oldDbBackupFileName": "kasm_dump.tar",
            },
            "backupCron": {"enabled": False},
        },
    }
    upgrade_values_path = temp_workdir / "upgrade-values.yaml"
    upgrade_values_path.write_text(yaml.safe_dump(upgrade_values, sort_keys=False))

    # Strict ``helm upgrade`` (no ``--install``).  The release was created by
    # Phase 1; if it isn't there, we want this command to fail loudly rather
    # than silently fall through to a fresh install.
    helm([
        "upgrade",
        release_name,
        e2e_config.chart_dir,
        "-n", namespace,
        "--timeout", "15m",
        "--set", "imagePullPolicy=Never",
        "-f", str(upgrade_values_path),
    ])

    # -----------------------------------------------------------------------
    # Phase 3: Verify pre-upgrade backup job wrote a non-empty file to PVC
    # -----------------------------------------------------------------------
    LOGGER.info("[upgrade] phase 3 — verifying pre-upgrade backup")

    wait_for_job_succeeded(namespace, job_name=backup_job_name, timeout_seconds=600)

    backup_files = wait_for_pvc_files(
        namespace,
        backup_pvc_name,
        mount_path="/data/kasm-db-dump",
        filename_prefix="kasm_dump",
        min_count=1,
        timeout_seconds=180,
    )
    assert backup_files, "Expected at least one file on the pre-upgrade backup PVC"
    assert all(int(entry["size"]) > 0 for entry in backup_files), (
        f"Pre-upgrade backup file(s) are empty: {backup_files}"
    )
    LOGGER.info("[upgrade] backup verified: %s", backup_files)

    # -----------------------------------------------------------------------
    # Phase 3.5 (standalone only): in-place upgrade of the external
    # Postgres from 14 -> 16 via pg_upgrade.  Mirrors what real customers
    # do on managed services (RDS / CloudSQL / GCP) where the major
    # version bump preserves data.  swap_external_postgres.sh runs
    # tianon/postgres-upgrade:14-to-16 between the old and new data
    # volumes, then starts a PG16 container on the same IP / SSL config
    # so chart-deployed pods keep talking to the same hostname.
    #
    # Because data carries over, the chart's db-upgrade job will see
    # the existing ``settings`` table and SKIP pg_restore — we are
    # exercising the "Database exists, running upgrade now..." branch
    # in templates/db-upgrade-job.yaml.
    #
    # We wait for the db-upgrade pod's ``db-major-version-is-ready``
    # init container to enter Running state first, which guarantees:
    #   - helm upgrade has applied the new manifests,
    #   - the old 1.18.1 pods have been replaced (new pods are present
    #     and currently waiting on init),
    #   - the upgrade job is actively polling for PG16 — the exact
    #     window where swapping the DB is safe.
    # -----------------------------------------------------------------------
    if standalone_db:
        LOGGER.info(
            "[upgrade] phase 3.5 — waiting for db-upgrade init container "
            "before swapping external postgres 14 → 16"
        )
        _wait_for_init_container_running(
            namespace,
            label_selector="app.kubernetes.io/component=db-upgrade",
            container_name="db-major-version-is-ready",
            timeout_seconds=300,
        )
        _swap_external_postgres("16")
        LOGGER.info("[upgrade] external postgres swapped to 16")

    # -----------------------------------------------------------------------
    # Phase 4: Upgrade job detects existing DB and runs --upgrade-database
    # -----------------------------------------------------------------------
    LOGGER.info("[upgrade] phase 4 — waiting for upgrade job")
    wait_for_job_succeeded(namespace, job_name=upgrade_job_name, timeout_seconds=900)

    # -----------------------------------------------------------------------
    # Phase 5: All pods recover and login page is accessible
    # -----------------------------------------------------------------------
    LOGGER.info("[upgrade] phase 5 — verifying recovery")
    wait_for_rollouts_complete(namespace, timeout_seconds=1200)
    wait_for_pods_ready(namespace, timeout_seconds=1200, progress=True)

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(
        namespace, proxy_pod, "https://localhost:8443/", insecure=True
    )
    assert status_code == 200, f"Expected 200 after upgrade, got {status_code}"
    assert_login_page(body)
    LOGGER.info("[upgrade] upgrade flow complete — system healthy after upgrade")
