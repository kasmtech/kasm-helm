from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import pytest
import yaml

from .helpers import (
    get_first_pod_by_selector,
    install_and_wait_with_retry,
    kubectl,
)
from .conftest import helm_install

LOGGER = logging.getLogger(__name__)

# After all pods are ready, wait briefly for the JSON logging subsystem to
# initialise and produce its first structured output. 10-30 seconds is
# sufficient; startup noise clears quickly and JSON samples appear early.
_POST_READY_SETTLE_SECONDS = 30

# How far back to look once the settle period has passed.
_LOG_SAMPLE_WINDOW = "20s"


def _collect_logs(namespace: str, pod: str, container: str | None) -> str:
    cmd = ["logs", pod, "--since", _LOG_SAMPLE_WINDOW]
    if container:
        cmd.extend(["-c", container])
    return kubectl(cmd, namespace=namespace).stdout


def _assert_json_logs(component: str, raw_logs: str) -> None:
    """
    Verify that every line beginning with '{' is valid JSON, and that at
    least one such line exists. Lines not starting with '{' are skipped —
    they are text-format startup messages or nginx error-log lines that
    remain in plain text regardless of the log format setting.
    """
    json_lines: list[str] = []
    bad_lines: list[str] = []

    for line in raw_logs.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            json.loads(line)
            json_lines.append(line)
        except json.JSONDecodeError:
            bad_lines.append(line)

    assert not bad_lines, (
        f"{component}: {len(bad_lines)} line(s) starting with '{{' failed JSON parsing:\n"
        + "\n".join(bad_lines[:5])
    )
    assert json_lines, (
        f"{component}: no JSON log lines found in the {_LOG_SAMPLE_WINDOW} sample window.\n"
        f"Raw log tail (last 20 lines):\n"
        + "\n".join(raw_logs.splitlines()[-20:])
    )
    LOGGER.info("[json-logging] %s: %d valid JSON line(s) in sample window", component, len(json_lines))


@pytest.mark.e2e
def test_json_log_format(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]
    release = e2e_config.release_name

    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    values_obj = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.com",
        "logFormat": "json",
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
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    # Allow startup log noise to clear before sampling. Initial output from
    # CherryPy, postgres, and the Go/C++ binaries is not necessarily in the
    # configured format — the format setting only takes effect after the
    # application fully initialises its logging subsystem.
    LOGGER.info(
        "[json-logging] pods ready; waiting %ds for JSON logging to initialise",
        _POST_READY_SETTLE_SECONDS,
    )
    time.sleep(_POST_READY_SETTLE_SECONDS)

    # Each tuple: (component label, container name or None for pod default)
    # Guac is intentionally excluded — its log format is not configurable
    # via logFormat in this release.
    components = [
        ("api",               None),
        ("manager",           None),
        ("proxy",             None),
        ("rdp-gateway",       f"{release}-rdp-gateway"),
        ("rdp-https-gateway", f"{release}-rdp-https-gateway"),
        ("db",                None),
    ]

    for component, container in components:
        pod = get_first_pod_by_selector(namespace, f"app.kubernetes.io/component={component}")
        LOGGER.info("[json-logging] sampling %s pod %s (container: %s)", component, pod, container or "default")
        raw_logs = _collect_logs(namespace, pod, container)
        _assert_json_logs(component, raw_logs)
