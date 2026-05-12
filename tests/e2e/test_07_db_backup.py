from __future__ import annotations

from pathlib import Path

import pytest

from .backup_flow import run_backup_upgrade_and_cron_flow


@pytest.mark.e2e
def test_backup_upgrade_and_cron_create_successive_backups(
    installer,
    temp_workdir: Path,
) -> None:
    run_backup_upgrade_and_cron_flow(
        installer,
        temp_workdir,
        restricted_namespace=False,
    )
