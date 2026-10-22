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


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):  # type: ignore[no-untyped-def]
    """Record each phase's outcome on the item so fixtures can see whether the test failed."""
    outcome = yield
    setattr(item, f"rep_{call.when}", outcome.get_result())


def _dump_diagnostics(namespace: str, release_name: str, label: str) -> None:
    """Write pod logs and describe output for the release into E2E_ARTIFACT_DIR."""
    root = Path(os.environ.get("E2E_ARTIFACT_DIR", "artifacts")) / label
    try:
        root.mkdir(parents=True, exist_ok=True)
    except OSError:
        return
    selector = f"app.kubernetes.io/instance={release_name}"
    written = []
    describe = kubectl(["describe", "pods", "-l", selector], namespace=namespace, check=False)
    (root / "describe-pods.txt").write_text(describe.stdout or "")
    written.append("describe-pods.txt")
    pods = kubectl(
        ["get", "pods", "-l", selector, "-o", "name"], namespace=namespace, check=False
    )
    for line in (pods.stdout or "").split():
        pod = line.split("/", 1)[-1]
        if not pod:
            continue
        for suffix, args in (("", []), (".previous", ["--previous"])):
            got = kubectl(
                ["logs", pod, "--all-containers", "--tail=2000", *args],
                namespace=namespace,
                check=False,
            )
            if got.stdout:
                name = f"{pod}{suffix}.log"
                (root / name).write_text(got.stdout)
                written.append(name)
    events = kubectl(
        ["get", "events", "--sort-by=.lastTimestamp"], namespace=namespace, check=False
    )
    (root / "events.txt").write_text(events.stdout or "")
    written.append("events.txt")
    print(f"\n[diag] wrote {len(written)} diagnostic file(s) to {root}")


@pytest.fixture()
def cleanup_release(
    request: pytest.FixtureRequest, e2e_config: E2EConfig, namespace: str
) -> Iterator[None]:
    yield
    failed = any(
        getattr(getattr(request.node, f"rep_{phase}", None), "failed", False)
        for phase in ("setup", "call", "teardown")
    )
    if failed:
        _dump_diagnostics(namespace, e2e_config.release_name, request.node.name)
    # E2E_KEEP=1 keeps the release for post-mortem; E2E_KEEP=onfail keeps it only after a failure.
    keep_mode = os.environ.get("E2E_KEEP", "").strip().lower()
    if keep_mode in ("1", "true", "yes", "always") or (keep_mode == "onfail" and failed):
        print(
            f"\n[diag] E2E_KEEP={keep_mode}: leaving release {e2e_config.release_name} "
            f"installed in namespace {namespace} for inspection"
        )
        return
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
    # Layered last so it wins: branch-build image overrides for scenarios that need code which only
    # exists on a feature branch. Released tags lack it and the scenario fails with no telemetry.
    image_values = os.environ.get("E2E_IMAGE_VALUES", "").strip()
    if image_values:
        if not Path(image_values).is_file():
            raise AssertionError(
                f"E2E_IMAGE_VALUES={image_values} does not exist inside the test container; "
                "tests/values is mounted at /e2e-values by the pytest-docker target"
            )
        command_args.extend(["-f", image_values])
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
