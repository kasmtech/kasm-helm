from __future__ import annotations

from pathlib import Path

import pytest

from .upgrade_flow import run_upgrade_flow


@pytest.mark.e2e
def test_db_upgrade_included_db(
    installer,
    temp_workdir: Path,
) -> None:
    """Upgrade from 1.18.1 → current chart using the chart-bundled DB StatefulSet.

    Flow:
      1. Install 1.18.1 with the included Postgres StatefulSet.
      2. helm upgrade to current chart with upgrade.enable=true.
         Pre-upgrade hooks create the backup PVC and dump the DB.
      3. Upgrade job detects the existing DB (settings table present),
         skips pg_restore, and runs --upgrade-database.
      4. All pods recover; login page is accessible.
    """
    run_upgrade_flow(installer, temp_workdir, standalone_db=False)


@pytest.mark.e2e
def test_db_upgrade_standalone_db(
    installer,
    temp_workdir: Path,
) -> None:
    """Upgrade from 1.18.1 → current chart against a standalone external Postgres.

    Same external-DB contract as test_04_external_db.py: the Makefile
    target ``e2e-upgrade-standalone`` starts a postgres:16 container via
    ``tests/e2e/start_external_postgres.sh`` (attached to the kind Docker
    network with SSL) and exports ``EXTERNAL_DB_HOST`` /
    ``EXTERNAL_DB_PASSWORD`` before invoking pytest.

    Flow:
      1. Install 1.18.1 with database.standalone=true pointing at the
         external Postgres host.
      2. helm upgrade to current chart with upgrade.enable=true.
         Pre-upgrade hooks back up the external DB.
      3. Upgrade job runs --upgrade-database against the same external DB.
      4. All pods recover; login page is accessible.
    """
    run_upgrade_flow(installer, temp_workdir, standalone_db=True)
