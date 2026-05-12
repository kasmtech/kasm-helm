from __future__ import annotations

import os
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import pytest
from .helpers import (
    ensure_cluster_dns,
    ensure_tls_secret,
    helm,
    kubectl,
)


@dataclass(frozen=True)
class E2EConfig:
    chart_dir: str
    namespace: str
    release_name: str


@pytest.fixture(scope="session")
def e2e_config() -> E2EConfig:
    chart_dir = os.environ.get("KASM_CHART_DIR", "charts/kasm-helm")
    namespace = os.environ.get("KASM_NAMESPACE", "kasm-e2e")
    release_name = os.environ.get("KASM_RELEASE", "kasm-e2e")
    return E2EConfig(chart_dir=chart_dir, namespace=namespace, release_name=release_name)


@pytest.fixture()
def temp_workdir() -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="kasm-e2e-") as temp_dir:
        yield Path(temp_dir)


def ensure_namespace(namespace: str) -> None:
    kubectl(
        ["create", "namespace", namespace],
        namespace=None,
        check=False,
    )


@pytest.fixture(scope="session")
def namespace(e2e_config: E2EConfig) -> str:
    ensure_namespace(e2e_config.namespace)
    return e2e_config.namespace


@pytest.fixture()
def cleanup_release(e2e_config: E2EConfig, namespace: str) -> Iterator[None]:
    yield
    try:
        helm(
            ["uninstall", e2e_config.release_name, "-n", namespace],
            check=False,
        )
        release_pods = kubectl(
            [
                "get",
                "pods",
                "-l",
                f"app.kubernetes.io/instance={e2e_config.release_name}",
                "-o",
                "name",
            ],
            namespace=namespace,
            check=False,
        )
        if release_pods.stdout:
            kubectl(
                [
                    "wait",
                    "--for=delete",
                    "pods",
                    "-l",
                    f"app.kubernetes.io/instance={e2e_config.release_name}",
                    "--timeout=300s",
                ],
                namespace=namespace,
                check=False,
            )
    except Exception:
        pass


def helm_install(
    *,
    e2e_config: E2EConfig,
    namespace: str,
    values_file: str | None = None,
    set_args: list[str] | None = None,
) -> None:
    command_args = [
        "upgrade",
        "--install",
        e2e_config.release_name,
        e2e_config.chart_dir,
        "-n",
        namespace,
        "--create-namespace",
        "--timeout",
        "15m",
        # Images are pre-loaded into kind via `make kind-load-images`.
        # Never pull from the registry during e2e tests.
        "--set", "imagePullPolicy=Never",
    ]
    if values_file:
        command_args.extend(["-f", values_file])
    if set_args:
        for set_arg in set_args:
            command_args.extend(["--set", set_arg])

    helm(command_args)


@pytest.fixture()
def installer(e2e_config: E2EConfig, namespace: str, deployment_tls_secret, cleanup_release):
    # Provide a callable without nesting functions in the shared codebase.
    return {
        "install": helm_install,
        "config": e2e_config,
        "namespace": namespace,
    }


@pytest.fixture(scope="session")
def deployment_tls_secret(e2e_config: E2EConfig) -> None:
    ensure_namespace(e2e_config.namespace)
    ensure_tls_secret(e2e_config.namespace)


@pytest.fixture(scope="session", autouse=True)
def cluster_warmup(e2e_config: E2EConfig) -> None:
    scenario = os.environ.get("E2E_SCENARIO", "")
    if scenario in ("e2e-externaldb", "e2e-upgrade-standalone"):
        return
    warmup_seconds = int(os.environ.get("E2E_CLUSTER_WARMUP_SECONDS", "20"))
    if warmup_seconds > 0:
        time.sleep(warmup_seconds)
    ensure_namespace(e2e_config.namespace)
    ensure_tls_secret(e2e_config.namespace)
