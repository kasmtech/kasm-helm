from __future__ import annotations

import base64
import json
import logging
import os
import re
import subprocess
import tempfile
import time
from dataclasses import dataclass
from typing import Iterable, Optional
import yaml
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from datetime import datetime, timedelta, timezone

LOGGER = logging.getLogger("e2e")

@dataclass(frozen=True)
class CommandResult:
    stdout: str
    stderr: str
    returncode: int


class CommandError(RuntimeError):
    def __init__(self, message: str, result: CommandResult) -> None:
        super().__init__(message)
        self.result = result


def run_command(
    command_args: list[str],
    *,
    env: Optional[dict[str, str]] = None,
    timeout_seconds: int = 300,
    check: bool = True,
) -> CommandResult:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)

    process = subprocess.run(
        command_args,
        env=merged_env,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
    )
    result = CommandResult(
        stdout=process.stdout.strip(),
        stderr=process.stderr.strip(),
        returncode=process.returncode,
    )
    if check and result.returncode != 0:
        raise CommandError(
            message=(
                f"Command failed: {' '.join(command_args)}\n"
                f"stdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            ),
            result=result,
        )
    return result


def kubectl(
    command_args: list[str],
    *,
    namespace: Optional[str] = None,
    check: bool = True,
) -> CommandResult:
    base_args = ["kubectl"]
    if namespace:
        base_args.extend(["-n", namespace])
    return run_command(
        base_args + command_args,
        timeout_seconds=600,
        check=check,
    )


def helm(command_args: list[str], *, check: bool = True) -> CommandResult:
    return run_command(["helm"] + command_args, timeout_seconds=900, check=check)


def get_api_image() -> str:
    image = os.environ.get("KASM_API_IMAGE")
    if image:
        return image
    chart_dir = os.environ.get("KASM_CHART_DIR", "charts/kasm-helm")
    values_path = os.path.join(chart_dir, "values.yaml")
    try:
        with open(values_path) as f:
            v = yaml.safe_load(f)
        api = v["components"]["api"]
        # Mirror the chart's helper precedence: per-component image.tag wins
        # if set; otherwise fall back to the chart-wide useImageTags. If both
        # are empty fall through to the env-var/default fallback below.
        tag = api["image"].get("tag") or v.get("useImageTags") or ""
        if not tag:
            raise ValueError("api.image.tag and useImageTags are both empty")
        return f"{api['image']['repository']}:{tag}"
    except Exception:
        tag = os.environ.get("KASM_TAG", "develop")
        return f"kasmweb/api:{tag}"


def get_chart_app_version() -> str:
    """Return the appVersion from Chart.yaml (e.g. '1.19.0').

    Used to derive resource names that embed the chart version, such as the
    pre-upgrade backup PVC: ``{release}-{appVersion}-db-pre-upgrade-backup``.
    """
    chart_dir = os.environ.get("KASM_CHART_DIR", "charts/kasm-helm")
    chart_path = os.path.join(chart_dir, "Chart.yaml")
    try:
        with open(chart_path) as f:
            chart = yaml.safe_load(f)
        return chart["appVersion"]
    except Exception:
        return os.environ.get("KASM_APP_VERSION", "1.19.0")


def wait_for_condition(
    description: str,
    condition_fn,
    *,
    timeout_seconds: int = 600,
    poll_seconds: int = 5,
    diagnostics_namespace: Optional[str] = None,
) -> None:
    deadline = time.time() + timeout_seconds
    last_error: Optional[Exception] = None

    while time.time() < deadline:
        try:
            if condition_fn():
                return
        except Exception as exception:  # noqa: BLE001 (intentional for polling)
            last_error = exception
        time.sleep(poll_seconds)

    if diagnostics_namespace:
        dump_namespace_diagnostics(diagnostics_namespace, reason=f"timeout: {description}")
    if last_error:
        raise AssertionError(f"Timed out waiting for: {description}. Last error: {last_error}") from last_error
    raise AssertionError(f"Timed out waiting for: {description}")


def _container_state_summary(state: dict) -> str:
    if not state:
        return "<no state>"
    for key, payload in state.items():
        if not isinstance(payload, dict):
            continue
        bits = [key]
        for field in ("reason", "exitCode", "message"):
            value = payload.get(field)
            if value not in (None, ""):
                bits.append(f"{field}={value}")
        return " ".join(bits)
    return "<unknown state>"


def _container_has_started(status: dict) -> bool:
    """True if the container has actually run (running or terminated).

    A container in waiting/PodInitializing has no logs yet, so kubectl logs
    would error.  Skip those.
    """
    state = status.get("state", {}) or {}
    if "running" in state or "terminated" in state:
        return True
    return bool(status.get("started")) or int(status.get("restartCount", 0) or 0) > 0


def _pod_is_ready(pod: dict) -> bool:
    phase = pod.get("status", {}).get("phase")
    if phase == "Succeeded":
        return True
    if phase != "Running":
        return False
    for cond in pod.get("status", {}).get("conditions", []):
        if cond.get("type") == "Ready":
            return cond.get("status") == "True"
    return False


def _summarize_pods(namespace: str) -> str:
    result = kubectl(["get", "pods", "-o", "json"], namespace=namespace)
    pod_list = json.loads(result.stdout)
    pods = pod_list.get("items", [])
    if not pods:
        return "no pods found"

    summaries: list[str] = []
    for pod in pods:
        name = pod["metadata"].get("name", "<unknown>")
        phase = pod["status"].get("phase", "Unknown")
        container_statuses = pod["status"].get("containerStatuses", []) or []
        ready = sum(1 for cs in container_statuses if cs.get("ready"))
        total = len(container_statuses)
        reason = pod["status"].get("reason")
        if not reason:
            conditions = pod["status"].get("conditions", [])
            not_ready = [c for c in conditions if c.get("type") == "Ready" and c.get("status") != "True"]
            if not_ready:
                reason = not_ready[0].get("reason") or not_ready[0].get("message")
        suffix = f" ({reason})" if reason else ""
        summaries.append(f"{name}: {phase} {ready}/{total}{suffix}")
    return "; ".join(summaries)


def wait_for_pods_ready(
    namespace: str,
    *,
    timeout_seconds: int = 900,
    progress: bool = False,
    progress_seconds: int = 30,
) -> None:
    def all_ready() -> bool:
        result = kubectl(["get", "pods", "-o", "json"], namespace=namespace)
        pod_list = json.loads(result.stdout)

        pods = pod_list.get("items", [])
        if not pods:
            return False

        for pod in pods:
            phase = pod["status"].get("phase")
            # Ignore completed Jobs
            if phase == "Succeeded":
                continue
            if phase != "Running":
                return False

            conditions = pod["status"].get("conditions", [])
            ready_conditions = [cond for cond in conditions if cond.get("type") == "Ready"]
            if not ready_conditions or ready_conditions[0].get("status") != "True":
                return False

        return True

    deadline = time.time() + timeout_seconds
    next_log = 0.0
    while time.time() < deadline:
        if all_ready():
            return
        if progress and time.time() >= next_log:
            LOGGER.info("[pods] %s: %s", namespace, _summarize_pods(namespace))
            # Dump on every tick (not just timeout): some chart resources
            # have ttlSecondsAfterFinished as low as 100s, so by the time a
            # 15-minute wait gives up, their logs are gone.  Capturing
            # while the wait is still in progress preserves them.
            dump_namespace_diagnostics(namespace, reason="wait_for_pods_ready tick")
            next_log = time.time() + max(progress_seconds, 60)
        time.sleep(6)

    dump_namespace_diagnostics(namespace, reason="wait_for_pods_ready timed out")
    raise AssertionError(f"Timed out waiting for: all pods ready in namespace {namespace}")


def wait_for_job_succeeded(namespace: str, job_name: str, *, timeout_seconds: int = 900) -> None:
    LOGGER.info("[job] waiting for %s/%s to succeed", namespace, job_name)
    next_log = 0.0
    deadline = time.time() + timeout_seconds

    def job_done() -> bool:
        result = kubectl(["get", "job", job_name, "-o", "json"], namespace=namespace)
        job_obj = json.loads(result.stdout)
        status = job_obj.get("status", {})
        succeeded = int(status.get("succeeded", 0))
        failed = int(status.get("failed", 0))
        active = int(status.get("active", 0))
        nonlocal next_log
        if time.time() >= next_log:
            LOGGER.info(
                "[job] %s/%s status: active=%s succeeded=%s failed=%s",
                namespace,
                job_name,
                active,
                succeeded,
                failed,
            )
            next_log = time.time() + 60
        return succeeded >= 1

    wait_for_condition(
        f"job {job_name} succeeded",
        job_done,
        timeout_seconds=timeout_seconds,
        poll_seconds=5,
        diagnostics_namespace=namespace,
    )


def wait_for_pvc_bound(namespace: str, pvc_name: str, *, timeout_seconds: int = 300) -> None:
    LOGGER.info("[pvc] waiting for %s/%s to bind", namespace, pvc_name)

    def pvc_bound() -> bool:
        result = kubectl(["get", "pvc", pvc_name, "-o", "json"], namespace=namespace)
        pvc_obj = json.loads(result.stdout)
        return pvc_obj.get("status", {}).get("phase") == "Bound"

    wait_for_condition(
        f"pvc {pvc_name} bound",
        pvc_bound,
        timeout_seconds=timeout_seconds,
        poll_seconds=3,
    )


def list_files_in_pvc(
    namespace: str,
    pvc_name: str,
    *,
    mount_path: str,
    filename_prefix: str = "",
) -> list[dict[str, int | str]]:
    wait_for_pvc_bound(namespace, pvc_name)

    inspector_name = "pvc-inspector"
    image = get_api_image()
    manifest = {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {
            "name": inspector_name,
            "labels": {"app": inspector_name},
        },
        "spec": {
            "restartPolicy": "Never",
            "securityContext": {
                "runAsUser": 1000,
                "runAsGroup": 1000,
                "fsGroup": 1000,
                "fsGroupChangePolicy": "OnRootMismatch",
            },
            "containers": [
                {
                    "name": "inspector",
                    "image": image,
                    "imagePullPolicy": "Never",
                    "command": ["/bin/sh", "-c", "sleep 3600"],
                    "securityContext": {
                        "runAsUser": 1000,
                        "runAsGroup": 1000,
                        "runAsNonRoot": True,
                        "allowPrivilegeEscalation": False,
                        "readOnlyRootFilesystem": True,
                        "capabilities": {"drop": ["ALL"]},
                        "seccompProfile": {"type": "RuntimeDefault"},
                    },
                    "resources": {
                        "requests": {"cpu": "100m", "memory": "128Mi"},
                        "limits": {"cpu": "100m", "memory": "128Mi"},
                    },
                    "volumeMounts": [
                        {"name": "backup-data", "mountPath": mount_path},
                        {"name": "tmp-data", "mountPath": "/tmp"},
                    ],
                }
            ],
            "volumes": [
                {"name": "backup-data", "persistentVolumeClaim": {"claimName": pvc_name}},
                {"name": "tmp-data", "emptyDir": {}},
            ],
        },
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as temp_file:
        yaml.safe_dump(manifest, temp_file, sort_keys=False)
        manifest_path = temp_file.name

    try:
        kubectl(
            ["delete", "pod", inspector_name, "--ignore-not-found", "--grace-period=0", "--force"],
            namespace=namespace,
            check=False,
        )
        kubectl(["apply", "-f", manifest_path], namespace=namespace)
        kubectl(["wait", "--for=condition=Ready", f"pod/{inspector_name}", "--timeout=180s"], namespace=namespace)

        script = """
import json
import os
import sys

root = sys.argv[1]
prefix = sys.argv[2]
entries = []

if os.path.isdir(root):
    for name in sorted(os.listdir(root)):
        full_path = os.path.join(root, name)
        if os.path.isfile(full_path) and name.startswith(prefix):
            entries.append({"name": name, "size": os.path.getsize(full_path)})

print(json.dumps(entries))
"""
        result = exec_in_pod(
            namespace,
            inspector_name,
            ["python3", "-c", script, mount_path, filename_prefix],
        )
        return json.loads(result.stdout)
    finally:
        kubectl(
            ["delete", "pod", inspector_name, "--ignore-not-found", "--grace-period=0", "--force"],
            namespace=namespace,
            check=False,
        )


def wait_for_pvc_files(
    namespace: str,
    pvc_name: str,
    *,
    mount_path: str,
    min_count: int,
    filename_prefix: str = "",
    timeout_seconds: int = 300,
) -> list[dict[str, int | str]]:
    last_entries: list[dict[str, int | str]] = []

    def enough_files() -> bool:
        nonlocal last_entries
        last_entries = list_files_in_pvc(
            namespace,
            pvc_name,
            mount_path=mount_path,
            filename_prefix=filename_prefix,
        )
        return len(last_entries) >= min_count

    wait_for_condition(
        f"{min_count} files in pvc {pvc_name}",
        enough_files,
        timeout_seconds=timeout_seconds,
        poll_seconds=5,
    )
    return last_entries


def wait_for_pod_ready_by_selector(
    namespace: str,
    label_selector: str,
    *,
    timeout_seconds: int = 120,
    poll_seconds: int = 3,
) -> str:
    def pod_ready() -> bool:
        result = kubectl(["get", "pods", "-l", label_selector, "-o", "json"], namespace=namespace)
        pod_list = json.loads(result.stdout)
        pods = pod_list.get("items", [])
        if not pods:
            return False
        for pod in pods:
            phase = pod["status"].get("phase")
            if phase != "Running":
                return False
            conditions = pod["status"].get("conditions", [])
            ready_conditions = [cond for cond in conditions if cond.get("type") == "Ready"]
            if not ready_conditions or ready_conditions[0].get("status") != "True":
                return False
        return True

    wait_for_condition(
        f"pod ready for selector {label_selector}",
        pod_ready,
        timeout_seconds=timeout_seconds,
        poll_seconds=poll_seconds,
    )
    return get_first_pod_by_selector(namespace, label_selector)


def reset_namespace(namespace: str) -> None:
    kubectl(["delete", "namespace", namespace, "--ignore-not-found"], namespace=None)
    kubectl(["wait", "--for=delete", f"namespace/{namespace}", "--timeout=300s"], namespace=None, check=False)
    kubectl(["create", "namespace", namespace], namespace=None, check=False)


def apply_restricted_pod_security(namespace: str) -> None:
    kubectl(
        [
            "label",
            "namespace",
            namespace,
            "pod-security.kubernetes.io/enforce=restricted",
            "pod-security.kubernetes.io/enforce-version=latest",
            "pod-security.kubernetes.io/warn=restricted",
            "pod-security.kubernetes.io/warn-version=latest",
            "pod-security.kubernetes.io/audit=restricted",
            "pod-security.kubernetes.io/audit-version=latest",
            "--overwrite",
        ],
        namespace=None,
    )


def ensure_tls_secret(namespace: str, *, secret_name: str = "kasm-deployment-tls", common_name: str = "kasm.local") -> None:
    result = kubectl(["get", "secret", secret_name], namespace=namespace, check=False)
    if result.returncode == 0:
        return

    certificate_pem, private_key_pem = generate_self_signed_certificate(common_name=common_name)
    secret_manifest = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": secret_name},
        "type": "kubernetes.io/tls",
        "data": {
            "tls.crt": base64.b64encode(certificate_pem.encode()).decode(),
            "tls.key": base64.b64encode(private_key_pem.encode()).decode(),
        },
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as temp_file:
        yaml.safe_dump(secret_manifest, temp_file)
        manifest_path = temp_file.name

    kubectl(["apply", "-f", manifest_path], namespace=namespace)


def ensure_cluster_dns(namespace: str, *, retries: int = 5, backoff_seconds: int = 10) -> None:
    image = get_api_image()
    for attempt in range(1, retries + 1):
        try:
            manifest = f"""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dns-check
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dns-check
  template:
    metadata:
      labels:
        app: dns-check
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      containers:
      - name: dns-check
        image: "{image}"
        imagePullPolicy: Never
        command: ["/bin/sh", "-c", "sleep 3600"]
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          runAsNonRoot: true
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
          seccompProfile:
            type: RuntimeDefault
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 100m
            memory: 128Mi
        volumeMounts:
          - name: tmp-data
            mountPath: /tmp
      volumes:
        - name: tmp-data
          emptyDir: {{}}
---
apiVersion: v1
kind: Service
metadata:
  name: dns-check
spec:
  selector:
    app: dns-check
  ports:
    - name: http
      port: 80
      targetPort: 8080
"""
            with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as temp_file:
                temp_file.write(manifest)
                manifest_path = temp_file.name

            kubectl(["apply", "-f", manifest_path], namespace=namespace)
            kubectl(
                ["wait", "--for=condition=Available", "deploy/dns-check", "--timeout=120s"],
                namespace=namespace,
                check=False,
            )
            pod_name = wait_for_pod_ready_by_selector(namespace, "app=dns-check", timeout_seconds=180)
            exec_in_pod(namespace, pod_name, ["python3", "-c", "import socket; socket.getaddrinfo('dns-check', 80)"])
            return
        except Exception as exc:
            LOGGER.warning("[dns] attempt %s/%s failed: %s", attempt, retries, exc)
            dump_namespace_diagnostics(namespace, label_selector="app=dns-check")
            if attempt == retries:
                raise
            time.sleep(backoff_seconds)
        finally:
            kubectl(["delete", "deployment", "dns-check", "--ignore-not-found"], namespace=namespace, check=False)
            kubectl(["delete", "service", "dns-check", "--ignore-not-found"], namespace=namespace, check=False)


def install_and_wait_with_retry(
    *,
    helm_install_fn,
    e2e_config,
    namespace: str,
    values_file: str | None = None,
    set_args: list[str] | None = None,
    setup_namespace_fn=None,
    retries: int = 3,
    backoff_seconds: int = 20,
) -> None:
    for attempt in range(1, retries + 1):
        try:
            ensure_cluster_dns(
                namespace,
                retries=int(os.environ.get("E2E_DNS_RETRIES", "5")),
                backoff_seconds=int(os.environ.get("E2E_DNS_BACKOFF_SECONDS", "10")),
            )
            helm_install_fn(
                e2e_config=e2e_config,
                namespace=namespace,
                values_file=values_file,
                set_args=set_args,
            )
            wait_for_job_succeeded(namespace, job_name=f"{e2e_config.release_name}-db-init", timeout_seconds=360)
            wait_for_rollouts_complete(namespace, timeout_seconds=1200)
            wait_for_pods_ready(namespace, timeout_seconds=1200, progress=True)
            return
        except Exception as exc:
            if attempt == retries:
                raise
            LOGGER.warning("[retry] db init failed (attempt %s/%s): %s", attempt, retries, exc)
            dump_namespace_diagnostics(namespace)
            reset_namespace(namespace)
            ensure_tls_secret(namespace)
            if setup_namespace_fn:
                setup_namespace_fn()
            time.sleep(backoff_seconds)


def dump_namespace_diagnostics(
    namespace: str,
    *,
    reason: str = "",
    label_selector: str | None = None,
) -> None:
    """Emit a verbose snapshot of namespace state.

    - Skips Succeeded pods entirely.
    - For each remaining pod: dumps init/main container ready/restart/state.
    - For not-ready pods: dumps the last 80 log lines, but only for
      containers that have actually started (running or terminated).  Pods
      stuck in init dump the init container's logs (main containers won't
      have logs yet).
    - Dumps Job statuses and the last 40 namespace events.
    - When ``label_selector`` is given, additionally describes the matching
      pod (used by the dns-check retry path).

    Safe to call repeatedly on each progress tick.  Best-effort: individual
    kubectl failures are logged and skipped.
    """
    header = f"[diag] snapshot of {namespace}"
    if reason:
        header += f" ({reason})"
    LOGGER.info("=" * 72)
    LOGGER.info(header)
    LOGGER.info("=" * 72)

    pods_to_dump: list[tuple[str, list[dict], list[dict]]] = []
    db_readiness_hung = False
    try:
        result = kubectl(["get", "pods", "-o", "json"], namespace=namespace)
        for pod in json.loads(result.stdout).get("items", []):
            phase = pod.get("status", {}).get("phase", "Unknown")
            if phase == "Succeeded":
                continue
            name = pod["metadata"].get("name", "<unknown>")
            init_statuses = pod.get("status", {}).get("initContainerStatuses", []) or []
            container_statuses = pod.get("status", {}).get("containerStatuses", []) or []
            for cs in init_statuses:
                if cs.get("name") in ("db-is-ready", "kasm-api-is-ready") and not cs.get("ready"):
                    db_readiness_hung = True
            LOGGER.info("[diag] pod %s phase=%s", name, phase)
            for cs in init_statuses:
                LOGGER.info(
                    "[diag]   initContainer %s ready=%s restarts=%s state=%s",
                    cs.get("name"),
                    cs.get("ready"),
                    cs.get("restartCount"),
                    _container_state_summary(cs.get("state", {})),
                )
            for cs in container_statuses:
                LOGGER.info(
                    "[diag]   container %s ready=%s restarts=%s state=%s",
                    cs.get("name"),
                    cs.get("ready"),
                    cs.get("restartCount"),
                    _container_state_summary(cs.get("state", {})),
                )
            # Dump logs for any non-Succeeded pod that's either not ready
            # OR has any container with restarts > 0.  A Job pod whose main
            # container is crash-looping will show ready=True between
            # restarts (it just restarted) — restart count is the only
            # signal that catches it.
            has_restarts = any(
                int(cs.get("restartCount", 0) or 0) > 0
                for cs in (init_statuses + container_statuses)
            )
            if (not _pod_is_ready(pod)) or has_restarts:
                pods_to_dump.append((name, init_statuses, container_statuses))
    except Exception as exc:  # noqa: BLE001
        LOGGER.warning("[diag] failed to list pods: %s", exc)

    for pod_name, init_statuses, container_statuses in pods_to_dump:
        all_init_ready = all(s.get("ready") for s in init_statuses) if init_statuses else True
        targets: list[dict] = []
        for cs in init_statuses:
            restarts = int(cs.get("restartCount", 0) or 0)
            if (not cs.get("ready") and _container_has_started(cs)) or restarts > 0:
                targets.append(cs)
        if all_init_ready:
            for cs in container_statuses:
                restarts = int(cs.get("restartCount", 0) or 0)
                if (not cs.get("ready") and _container_has_started(cs)) or restarts > 0:
                    targets.append(cs)

        for cs in targets:
            container = cs.get("name")
            if not container:
                continue
            restarts = int(cs.get("restartCount", 0) or 0)
            # Current instance logs (always useful, last 80 lines).
            try:
                log_result = kubectl(
                    ["logs", pod_name, "-c", container, "--tail=80"],
                    namespace=namespace,
                    check=False,
                )
                body = (log_result.stdout or log_result.stderr or "").strip()
                if body:
                    LOGGER.info("[diag] --- logs %s/%s (last 80 lines) ---", pod_name, container)
                    for line in body.splitlines():
                        LOGGER.info("[diag]   %s", line)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[diag] failed to dump logs for %s/%s: %s", pod_name, container, exc)
            # Previous instance logs (only meaningful after a restart) —
            # this is what tells us why the container crashed, since the
            # current instance may have only just started.
            if restarts > 0:
                try:
                    prev_result = kubectl(
                        ["logs", pod_name, "-c", container, "--previous", "--tail=120"],
                        namespace=namespace,
                        check=False,
                    )
                    prev_body = (prev_result.stdout or prev_result.stderr or "").strip()
                    if prev_body:
                        LOGGER.info(
                            "[diag] --- previous logs %s/%s (last 120 lines, restartCount=%d) ---",
                            pod_name,
                            container,
                            restarts,
                        )
                        for line in prev_body.splitlines():
                            LOGGER.info("[diag]   %s", line)
                except Exception as exc:  # noqa: BLE001
                    LOGGER.warning(
                        "[diag] failed to dump previous logs for %s/%s: %s",
                        pod_name,
                        container,
                        exc,
                    )

    try:
        jobs_result = kubectl(["get", "jobs", "-o", "json"], namespace=namespace, check=False)
        if jobs_result.returncode == 0:
            for job in json.loads(jobs_result.stdout).get("items", []):
                name = job["metadata"].get("name", "<unknown>")
                status = job.get("status", {})
                LOGGER.info(
                    "[diag] job %s active=%s succeeded=%s failed=%s",
                    name,
                    status.get("active", 0),
                    status.get("succeeded", 0),
                    status.get("failed", 0),
                )
    except Exception as exc:  # noqa: BLE001
        LOGGER.warning("[diag] failed to list jobs: %s", exc)

    try:
        events_result = kubectl(
            ["get", "events", "--sort-by=.lastTimestamp"], namespace=namespace, check=False
        )
        body = (events_result.stdout or "").strip()
        if body:
            tail = body.splitlines()[-40:]
            LOGGER.info("[diag] --- recent events (last %d) ---", len(tail))
            for line in tail:
                LOGGER.info("[diag]   %s", line)
    except Exception as exc:  # noqa: BLE001
        LOGGER.warning("[diag] failed to list events: %s", exc)

    if label_selector:
        try:
            pod_name = get_first_pod_by_selector(namespace, label_selector)
            describe = kubectl(["describe", "pod", pod_name], namespace=namespace, check=False)
            LOGGER.info("[diag] describe pod/%s:\n%s", pod_name, describe.stdout)
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[diag] failed to describe pod for selector %s: %s", label_selector, exc)

    if db_readiness_hung:
        _dump_db_state(namespace)
        _dump_db_init_job_logs(namespace)

    LOGGER.info("=" * 72)


def _dump_db_state(namespace: str) -> None:
    """Probe the chart-bundled DB pod for table row counts.

    Triggered when an api/sidecar pod's ``db-is-ready`` or
    ``kasm-api-is-ready`` init container is stuck.  The chart's check
    swallows psql stderr (``2>/dev/null``), so the pod logs only repeat
    "Waiting for DB to initialize..." regardless of the actual failure
    mode (DB unreachable, auth rejected, schema missing, zones empty).
    Querying the DB pod directly via the unix socket (which pg_hba trusts
    locally) sidesteps that and surfaces what the api can't see.
    """
    try:
        pods_result = kubectl(
            ["get", "pods", "-l", "app.kubernetes.io/component=db", "-o", "json"],
            namespace=namespace,
            check=False,
        )
        if pods_result.returncode != 0:
            return
        items = json.loads(pods_result.stdout).get("items", [])
        if not items:
            LOGGER.info("[diag] no DB pod found (component=db) — skipping DB state probe")
            return
        pod = items[0]
        pod_name = pod["metadata"]["name"]
        if not _pod_is_ready(pod):
            LOGGER.info("[diag] DB pod %s not ready — skipping DB state probe", pod_name)
            return
        containers = pod.get("spec", {}).get("containers", []) or []
        if not containers:
            return
        container_name = containers[0].get("name")

        sql = (
            "SELECT 'zones' AS t, COUNT(*) FROM zones "
            "UNION ALL SELECT 'users', COUNT(*) FROM users "
            "UNION ALL SELECT 'settings', COUNT(*) FROM settings;"
        )
        bash_cmd = (
            'psql -h /var/run/postgresql '
            '-U "${POSTGRES_USER}" -d "${POSTGRES_DB}" '
            f'-c "{sql}" 2>&1'
        )
        exec_result = kubectl(
            ["exec", pod_name, "-c", container_name, "--", "/bin/bash", "-c", bash_cmd],
            namespace=namespace,
            check=False,
        )
        body = (exec_result.stdout or exec_result.stderr or "").strip()
        LOGGER.info("[diag] --- DB state on %s/%s (rc=%d) ---", pod_name, container_name, exec_result.returncode)
        if body:
            for line in body.splitlines():
                LOGGER.info("[diag]   %s", line)
        else:
            LOGGER.info("[diag]   (no output)")
    except Exception as exc:  # noqa: BLE001
        LOGGER.warning("[diag] DB state probe failed: %s", exc)


def _dump_db_init_job_logs(namespace: str) -> None:
    """Dump main-container logs from db-init-job pods (even if Succeeded).

    The init job runs ``startup.sh`` which seeds the schema and zones rows.
    Its pods normally land in Succeeded phase and are filtered out of the
    main snapshot, so when the api init container hangs we never see what
    the bootstrap actually did. These logs reveal whether seeding ran,
    skipped (DB-already-initialised branch), or partially succeeded.
    """
    try:
        result = kubectl(
            ["get", "pods", "-l", "app.kubernetes.io/component=db-init", "-o", "json"],
            namespace=namespace,
            check=False,
        )
        if result.returncode != 0:
            return
        pods = json.loads(result.stdout).get("items", [])
        if not pods:
            LOGGER.info("[diag] no db-init-job pod found — skipping init-job log dump")
            return
        for pod in pods:
            pod_name = pod["metadata"].get("name", "<unknown>")
            phase = pod.get("status", {}).get("phase", "Unknown")
            containers = pod.get("spec", {}).get("containers", []) or []
            for container in containers:
                container_name = container.get("name")
                if not container_name:
                    continue
                log_result = kubectl(
                    ["logs", pod_name, "-c", container_name, "--tail=200"],
                    namespace=namespace,
                    check=False,
                )
                body = (log_result.stdout or log_result.stderr or "").strip()
                LOGGER.info(
                    "[diag] --- db-init logs %s/%s phase=%s (last 200) ---",
                    pod_name,
                    container_name,
                    phase,
                )
                if body:
                    for line in body.splitlines():
                        LOGGER.info("[diag]   %s", line)
                else:
                    LOGGER.info("[diag]   (no output)")
    except Exception as exc:  # noqa: BLE001
        LOGGER.warning("[diag] db-init log dump failed: %s", exc)


def get_first_pod_by_selector(namespace: str, label_selector: str) -> str:
    result = kubectl(
        ["get", "pods", "-l", label_selector, "-o", "jsonpath={.items[0].metadata.name}"],
        namespace=namespace,
    )
    pod_name = result.stdout.strip()
    if not pod_name:
        raise AssertionError(f"No pod found for selector: {label_selector}")
    return pod_name


def get_jobs_owned_by_cronjob(
    namespace: str,
    cronjob_name: str,
    *,
    created_after: Optional[datetime] = None,
) -> list[dict]:
    result = kubectl(["get", "jobs", "-o", "json"], namespace=namespace)
    job_list = json.loads(result.stdout)
    jobs = []

    for job in job_list.get("items", []):
        owner_refs = job.get("metadata", {}).get("ownerReferences", []) or []
        if not any(ref.get("kind") == "CronJob" and ref.get("name") == cronjob_name for ref in owner_refs):
            continue

        if created_after:
            created_at_text = job.get("metadata", {}).get("creationTimestamp")
            if created_at_text:
                created_at = datetime.fromisoformat(created_at_text.replace("Z", "+00:00"))
                if created_at < created_after:
                    continue
        jobs.append(job)

    jobs.sort(key=lambda job: job.get("metadata", {}).get("creationTimestamp", ""))
    return jobs


def wait_for_cronjob_jobs_succeeded(
    namespace: str,
    cronjob_name: str,
    *,
    min_successes: int,
    created_after: Optional[datetime] = None,
    timeout_seconds: int = 300,
) -> list[dict]:
    LOGGER.info(
        "[cronjob] waiting for %s/%s to produce %s successful job(s)",
        namespace,
        cronjob_name,
        min_successes,
    )
    deadline = time.time() + timeout_seconds
    next_log = 0.0
    last_jobs: list[dict] = []

    while time.time() < deadline:
        last_jobs = get_jobs_owned_by_cronjob(namespace, cronjob_name, created_after=created_after)
        succeeded_jobs = [
            job for job in last_jobs if int(job.get("status", {}).get("succeeded", 0)) >= 1
        ]
        if len(succeeded_jobs) >= min_successes:
            return succeeded_jobs

        if time.time() >= next_log:
            job_names = ", ".join(job.get("metadata", {}).get("name", "<unknown>") for job in last_jobs) or "none"
            LOGGER.info(
                "[cronjob] %s/%s succeeded=%s/%s jobs=%s",
                namespace,
                cronjob_name,
                len(succeeded_jobs),
                min_successes,
                job_names,
            )
            next_log = time.time() + 30
        time.sleep(5)

    raise AssertionError(
        f"Timed out waiting for {min_successes} successful jobs from CronJob {cronjob_name}. "
        f"Observed {len(last_jobs)} job(s)."
    )


def exec_in_pod(
    namespace: str,
    pod_name: str,
    exec_args: list[str],
    *,
    container: Optional[str] = None,
) -> CommandResult:
    cmd = ["exec", pod_name]
    if container:
        cmd.extend(["-c", container])
    cmd.append("--")
    return kubectl(cmd + exec_args, namespace=namespace)


def curl_from_pod(
    namespace: str,
    pod_name: str,
    url: str,
    *,
    host_header: Optional[str] = None,
    insecure: bool = False,
    timeout_seconds: int = 30,
) -> tuple[int, str]:
    curl_args = [
        "curl",
        "-sS",
        "-L",
        "--max-time",
        str(timeout_seconds),
        "-o",
        "-",
        "-w",
        "\n%{http_code}",
    ]
    if insecure:
        curl_args.append("-k")
    if host_header:
        curl_args.extend(["-H", f"Host: {host_header}"])
    curl_args.append(url)

    try:
        result = exec_in_pod(namespace, pod_name, curl_args)
    except CommandError as exc:
        stderr = exc.result.stderr.strip()
        stdout = exc.result.stdout.strip()
        if stdout:
            body_hint = stdout.splitlines()[0][:1000]
            LOGGER.error("[curl] output head: %s", body_hint)
        LOGGER.error(
            "[curl] failed in pod %s/%s: %s",
            namespace,
            pod_name,
            stderr or stdout,
        )
        raise
    if not result.stdout:
        raise AssertionError("curl returned empty output")

    body, status_code_text = result.stdout.rsplit("\n", 1)
    return int(status_code_text.strip()), body


def assert_login_page(body: str) -> None:
    # Intentionally tolerant: Kasm versions/themes vary.
    # We want to know: did we reach an HTML login page with a password field?
    normalized = body.lower()
    if "<html" not in normalized:
        raise AssertionError("Response does not look like HTML")
    if "password" not in normalized:
        # Some builds serve a minimal SPA shell; accept common SPA markers.
        spa_markers = [
            'id="root"',
            "index.bundle.js",
            "manifest.webmanifest",
            "serviceworker.js",
        ]
        if not any(marker in normalized for marker in spa_markers):
            raise AssertionError("Login page missing 'password' field indicator")
    # Bonus signal: common patterns
    if not re.search(r'type\s*=\s*["\']password["\']', normalized):
        # still allow if page is JS-built and contains the word password somewhere
        return

def _deployment_ready(deploy: dict) -> bool:
    spec = deploy.get("spec", {})
    status = deploy.get("status", {})
    replicas = int(spec.get("replicas", 1))
    updated = int(status.get("updatedReplicas", 0))
    ready = int(status.get("readyReplicas", 0))
    observed = int(status.get("observedGeneration", 0))
    generation = int(deploy.get("metadata", {}).get("generation", 0))
    return observed >= generation and updated >= replicas and ready >= replicas


def _summarize_deployments(namespace: str) -> str:
    result = kubectl(["get", "deploy", "-o", "json"], namespace=namespace)
    deployment_list = json.loads(result.stdout)
    items = deployment_list.get("items", [])
    if not items:
        return "no deployments found"
    summaries: list[str] = []
    for deploy in items:
        name = deploy["metadata"].get("name", "<unknown>")
        status = deploy.get("status", {})
        spec = deploy.get("spec", {})
        replicas = int(spec.get("replicas", 1))
        ready = int(status.get("readyReplicas", 0))
        updated = int(status.get("updatedReplicas", 0))
        summaries.append(f"{name}: ready={ready}/{replicas} updated={updated}/{replicas}")
    return "; ".join(summaries)


def wait_for_deployments_rolled_out(namespace: str, *, timeout_seconds: int = 900) -> None:
    LOGGER.info("[rollout] waiting for deployments in %s", namespace)
    deadline = time.time() + timeout_seconds
    next_log = 0.0
    while time.time() < deadline:
        result = kubectl(["get", "deploy", "-o", "json"], namespace=namespace)
        deployment_list = json.loads(result.stdout)
        items = deployment_list.get("items", [])
        if items and all(_deployment_ready(d) for d in items):
            return
        if time.time() >= next_log:
            LOGGER.info("[rollout] deployments: %s", _summarize_deployments(namespace))
            dump_namespace_diagnostics(namespace, reason="wait_for_deployments_rolled_out tick")
            next_log = time.time() + 60
        time.sleep(5)
    dump_namespace_diagnostics(namespace, reason="wait_for_deployments_rolled_out timed out")
    raise AssertionError(f"Timed out waiting for deployments to roll out in namespace {namespace}")


def _statefulset_ready(sts: dict) -> bool:
    spec = sts.get("spec", {})
    status = sts.get("status", {})
    replicas = int(spec.get("replicas", 1))
    ready = int(status.get("readyReplicas", 0))
    updated = int(status.get("updatedReplicas", 0))
    observed = int(status.get("observedGeneration", 0))
    generation = int(sts.get("metadata", {}).get("generation", 0))
    return observed >= generation and updated >= replicas and ready >= replicas


def _summarize_statefulsets(namespace: str) -> str:
    result = kubectl(["get", "sts", "-o", "json"], namespace=namespace)
    sts_list = json.loads(result.stdout)
    items = sts_list.get("items", [])
    if not items:
        return "no statefulsets found"
    summaries: list[str] = []
    for sts in items:
        name = sts["metadata"].get("name", "<unknown>")
        status = sts.get("status", {})
        spec = sts.get("spec", {})
        replicas = int(spec.get("replicas", 1))
        ready = int(status.get("readyReplicas", 0))
        updated = int(status.get("updatedReplicas", 0))
        summaries.append(f"{name}: ready={ready}/{replicas} updated={updated}/{replicas}")
    return "; ".join(summaries)


def wait_for_statefulsets_rolled_out(namespace: str, *, timeout_seconds: int = 1200) -> None:
    LOGGER.info("[rollout] waiting for statefulsets in %s", namespace)
    deadline = time.time() + timeout_seconds
    next_log = 0.0
    while time.time() < deadline:
        result = kubectl(["get", "sts", "-o", "json"], namespace=namespace)
        sts_list = json.loads(result.stdout)
        items = sts_list.get("items", [])
        if not items:
            return
        if all(_statefulset_ready(s) for s in items):
            return
        if time.time() >= next_log:
            LOGGER.info("[rollout] statefulsets: %s", _summarize_statefulsets(namespace))
            dump_namespace_diagnostics(namespace, reason="wait_for_statefulsets_rolled_out tick")
            next_log = time.time() + 60
        time.sleep(5)
    dump_namespace_diagnostics(namespace, reason="wait_for_statefulsets_rolled_out timed out")
    raise AssertionError(f"Timed out waiting for statefulsets to roll out in namespace {namespace}")


def wait_for_ingress_address(
    namespace: str,
    ingress_name: str,
    *,
    timeout_seconds: int = 600,
    progress: bool = True,
    progress_seconds: int = 30,
) -> str:
    deadline = time.time() + timeout_seconds
    next_log = 0.0
    last_address: Optional[str] = None

    while time.time() < deadline:
        result = kubectl(["get", "ingress", ingress_name, "-o", "json"], namespace=namespace)
        ingress_obj = json.loads(result.stdout)
        lb_status = ingress_obj.get("status", {}).get("loadBalancer", {}).get("ingress", [])
        if lb_status:
            entry = lb_status[0]
            address = entry.get("ip") or entry.get("hostname")
            if address:
                return address
            last_address = str(entry)

        if progress and time.time() >= next_log:
            LOGGER.info(
                "[ingress] waiting for address %s/%s (last=%s)",
                namespace,
                ingress_name,
                last_address or "none",
            )
            next_log = time.time() + progress_seconds
        time.sleep(5)

    raise AssertionError(f"Timed out waiting for ingress address for {namespace}/{ingress_name}")


def wait_for_rollouts_complete(namespace: str, *, timeout_seconds: int = 1200) -> None:
    # Split budgets: statefulsets can be slower (PVC attach, init ordering, etc.)
    wait_for_deployments_rolled_out(namespace, timeout_seconds=min(timeout_seconds, 900))
    wait_for_statefulsets_rolled_out(namespace, timeout_seconds=timeout_seconds)


def generate_self_signed_certificate(common_name: str) -> tuple[str, str]:
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )

    subject = x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        ]
    )

    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(timezone.utc) - timedelta(days=1))
        .not_valid_after(datetime.now(timezone.utc) + timedelta(days=365))
        .add_extension(
            x509.SubjectAlternativeName(
                [
                    x509.DNSName(common_name),
                ]
            ),
            critical=False,
        )
        .sign(private_key, hashes.SHA256())
    )

    private_key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")

    certificate_pem = certificate.public_bytes(
        serialization.Encoding.PEM
    ).decode("utf-8")

    return certificate_pem, private_key_pem
