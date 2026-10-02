from __future__ import annotations

import json
import logging
import tempfile
import time
from pathlib import Path
from typing import Iterator

import yaml

from .conftest import ensure_namespace, helm_install
from .helpers import (
    get_api_image,
    helm,
    install_and_wait_with_retry,
    kubectl,
    wait_for_pods_ready,
    wait_for_rollouts_complete,
)

LOGGER = logging.getLogger("e2e")

PROBE_LABEL = "np-probe"

LOW_RESOURCES = {"requests": {"cpu": "50m", "memory": "256Mi"}}
LOW_RESOURCES_PROXY = {"requests": {"cpu": "50m", "memory": "128Mi"}}
LOW_RESOURCES_GW = {"requests": {"cpu": "25m", "memory": "128Mi"}}

# Run from inside a probe pod: print OPEN when the TCP connect succeeds, TIMEOUT when the
# SYN is dropped (what a NetworkPolicy deny looks like), REFUSED for an RST, ERR otherwise.
_PROBE_SCRIPT = """
import socket, sys
try:
    socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=4).close()
    print("OPEN")
except socket.timeout:
    print("TIMEOUT")
except ConnectionRefusedError:
    print("REFUSED")
except Exception as exc:
    print("ERR " + repr(exc))
"""


def netpol_values(*, zones: list[dict] | None = None, extra: dict | None = None) -> dict:
    """Release values shared by every NetworkPolicy scenario.

    externalEgress is disabled so only the chart's explicit in-cluster rules (internal,
    database and DNS egress) carry traffic: a missing rule fails the install instead of
    being hidden by the open 0.0.0.0/0 default.
    """
    values: dict = {
        "deploymentSize": "small",
        "publicAddr": "kasm.example.test",
        "certificate": {"secretName": "kasm-deployment-tls"},
        "components": {
            "api": {"resources": LOW_RESOURCES},
            "manager": {"resources": LOW_RESOURCES},
            "proxy": {"resources": LOW_RESOURCES_PROXY},
            "guac": {"resources": LOW_RESOURCES},
            "rdpGateway": {"resources": LOW_RESOURCES_GW},
            "rdpHttpsGateway": {"resources": LOW_RESOURCES_GW},
        },
        "dbManagement": {"initialize": True},
        "networkPolicies": {
            "enabled": True,
            "externalEgress": {"enabled": False},
        },
    }
    if zones:
        values["kasmZones"] = zones
    for key, value in (extra or {}).items():
        if isinstance(value, dict) and isinstance(values.get(key), dict):
            values[key] = {**values[key], **value}
        else:
            values[key] = value
    return values


def write_values(workdir: Path, name: str, values: dict) -> str:
    path = workdir / name
    path.write_text(yaml.safe_dump(values, sort_keys=False))
    return str(path)


def pod_ip(namespace: str, release: str, component: str, *, zone: str | None = None) -> str:
    selector = f"app.kubernetes.io/instance={release},app.kubernetes.io/component={component}"
    result = kubectl(
        ["get", "pods", "-l", selector, "-o", "jsonpath={.items[*].metadata.name}"],
        namespace=namespace,
    )
    names = result.stdout.split()
    if zone:
        names = [n for n in names if f"-{zone}" in n]
    assert names, f"no {component} pod found (zone={zone})"
    return kubectl(["get", "pod", names[0], "-o", "jsonpath={.status.podIP}"], namespace=namespace).stdout.strip()


def create_probe(namespace: str, name: str = "np-probe") -> str:
    """Pod with no kasm labels, so no chart policy selects it. Uses the api image (python3),
    already loaded into kind, same as the DNS pre-check."""
    ensure_namespace(namespace)
    manifest = {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {"name": name, "labels": {"app": PROBE_LABEL}},
        "spec": {
            "securityContext": {"runAsUser": 1000, "runAsGroup": 1000},
            "containers": [
                {
                    "name": "probe",
                    "image": get_api_image(),
                    "imagePullPolicy": "Never",
                    "command": ["/bin/sh", "-c", "sleep 7200"],
                    "resources": {"requests": {"cpu": "10m", "memory": "32Mi"}},
                }
            ],
        },
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as handle:
        handle.write(yaml.safe_dump(manifest))
    kubectl(["apply", "-f", handle.name], namespace=namespace)
    kubectl(["wait", "--for=condition=Ready", f"pod/{name}", "--timeout=180s"], namespace=namespace)
    return name


def delete_probe(namespace: str, name: str = "np-probe") -> None:
    kubectl(["delete", "pod", name, "--ignore-not-found", "--wait=false"], namespace=namespace, check=False)


def probe(namespace: str, pod: str, ip: str, port: int, *, via: str = "python") -> str:
    """OPEN / TIMEOUT / REFUSED / ERR for a TCP connect from `pod`. via="curl" is for pods
    without python (the proxy); both methods classify a dropped SYN as TIMEOUT."""
    if via == "curl":
        result = kubectl(
            ["exec", pod, "--", "curl", "-sS", "-o", "/dev/null", "--connect-timeout", "4",
             "--max-time", "5", "-w", "%{time_connect}", f"telnet://{ip}:{port}"],
            namespace=namespace,
            check=False,
        )
        connected = result.stdout.strip()
        if connected and float(connected) > 0:
            return "OPEN"
        if "Connection timed out" in result.stderr:
            return "TIMEOUT"
        if "Connection refused" in result.stderr:
            return "REFUSED"
        return f"ERR {result.stderr[:200]}"
    result = kubectl(
        ["exec", pod, "--", "python3", "-c", _PROBE_SCRIPT, ip, str(port)],
        namespace=namespace,
        check=False,
    )
    return result.stdout.strip().splitlines()[-1] if result.stdout.strip() else f"ERR {result.stderr[:200]}"


def _wait_probe(namespace: str, pod: str, ip: str, port: int, want: tuple[str, ...], timeout_seconds: int, via: str) -> str:
    # Policy changes reach the CNI asynchronously, so poll for the expected state.
    deadline = time.time() + timeout_seconds
    state = probe(namespace, pod, ip, port, via=via)
    while state not in want and time.time() < deadline:
        time.sleep(3)
        state = probe(namespace, pod, ip, port, via=via)
    return state


def assert_reachable(namespace: str, pod: str, ip: str, port: int, what: str, *, timeout_seconds: int = 60, via: str = "python") -> None:
    state = _wait_probe(namespace, pod, ip, port, ("OPEN",), timeout_seconds, via)
    assert state == "OPEN", f"{what}: expected reachable, probe said {state}"


def assert_not_dropped(namespace: str, pod: str, ip: str, port: int, what: str, *, timeout_seconds: int = 60, via: str = "python") -> None:
    """For a port nothing may listen on: OPEN or REFUSED both prove the SYN reached the pod
    (a policy deny is a silent drop, i.e. TIMEOUT)."""
    state = _wait_probe(namespace, pod, ip, port, ("OPEN", "REFUSED"), timeout_seconds, via)
    assert state in ("OPEN", "REFUSED"), f"{what}: expected the connect to reach the pod, probe said {state}"


def assert_blocked(namespace: str, pod: str, ip: str, port: int, what: str, *, timeout_seconds: int = 60, via: str = "python", holds: int = 3) -> None:
    # Only a dropped connect (TIMEOUT) counts: REFUSED/ERR mean the probe or the target
    # misbehaved, not that a policy denied it. Once the first TIMEOUT shows the policy has
    # landed, it must hold for `holds` more probes: a flapping or half-programmed rule fails.
    state = _wait_probe(namespace, pod, ip, port, ("TIMEOUT",), timeout_seconds, via)
    assert state == "TIMEOUT", f"{what}: expected blocked (connect timeout), probe said {state}"
    for attempt in range(holds):
        state = probe(namespace, pod, ip, port, via=via)
        assert state == "TIMEOUT", f"{what}: block did not hold, probe {attempt + 1}/{holds} said {state}"
        time.sleep(3)


def install_netpol_release(e2e_config, namespace: str, values_file: str) -> None:
    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=values_file,
    )


def upgrade_release(e2e_config, namespace: str, values_file: str, *, wait: bool = True) -> None:
    helm_install(e2e_config=e2e_config, namespace=namespace, values_file=values_file)
    if wait:
        wait_for_rollouts_complete(namespace, timeout_seconds=1200)
        wait_for_pods_ready(namespace, timeout_seconds=1200, progress=True)


def uninstall_release(e2e_config, namespace: str) -> None:
    helm(["uninstall", e2e_config.release_name, "-n", namespace], check=False)
    kubectl(
        [
            "wait", "--for=delete", "pods", "-l",
            f"app.kubernetes.io/instance={e2e_config.release_name}", "--timeout=300s",
        ],
        namespace=namespace,
        check=False,
    )


def policy_names(namespace: str, release: str) -> list[str]:
    result = kubectl(["get", "networkpolicy", "-o", "json"], namespace=namespace)
    items = json.loads(result.stdout).get("items", [])
    return [i["metadata"]["name"] for i in items if i["metadata"]["name"].startswith(release)]


def iter_zone_pods(namespace: str, release: str, component: str) -> Iterator[str]:
    result = kubectl(
        [
            "get", "pods", "-l",
            f"app.kubernetes.io/instance={release},app.kubernetes.io/component={component}",
            "-o", "jsonpath={.items[*].status.podIP}",
        ],
        namespace=namespace,
    )
    yield from result.stdout.split()


def front_door_ingress_address(namespace: str, release: str) -> str:
    from .helpers import wait_for_ingress_address

    names = kubectl(
        ["get", "ingress", "-l", f"app.kubernetes.io/instance={release}", "-o", "jsonpath={.items[*].metadata.name}"],
        namespace=namespace,
    ).stdout.split()
    assert names, "no Ingress rendered for the release"
    return wait_for_ingress_address(namespace, names[0])


def login_page_via_ingress(address: str, host: str, *, timeout_seconds: int = 120) -> None:
    """Curl the controller's address from the pytest container (outside the cluster), retrying
    while the controller programs its routes."""
    from .helpers import assert_login_page, curl_from_host

    deadline = time.time() + timeout_seconds
    last = "no attempt"
    while time.time() < deadline:
        try:
            status, body = curl_from_host(f"http://{address}/", host_header=host, timeout_seconds=10)
            if status == 200:
                assert_login_page(body)
                return
            last = f"HTTP {status}"
        except Exception as exc:  # curl exit != 0 on timeout/refused
            last = repr(exc)[:200]
        time.sleep(5)
    raise AssertionError(f"login page via ingress {address} host={host} not served: {last}")


def ingress_blocked(address: str, host: str, *, timeout_seconds: int = 60, holds: int = 3) -> None:
    """Counterpart of login_page_via_ingress: the controller must NOT get a 200. Only a
    gateway-error status (the controller could not reach the proxy) or a curl failure counts,
    and it must hold for `holds` consecutive requests. Call login_page_via_ingress after
    re-opening proxy.from to show the block was the policy."""
    from .helpers import curl_from_host

    def served() -> str:
        try:
            status, _ = curl_from_host(f"http://{address}/", host_header=host, timeout_seconds=8)
            return f"HTTP {status}"
        except Exception as exc:  # curl exit != 0: timeout / reset
            return f"EXC {exc!r}"[:200]

    def blocked(result: str) -> bool:
        return result in ("HTTP 502", "HTTP 503", "HTTP 504") or result.startswith("EXC")

    deadline = time.time() + timeout_seconds
    last = served()
    while not blocked(last) and time.time() < deadline:
        time.sleep(5)
        last = served()
    assert blocked(last), f"ingress {address} host={host} still served ({last}) despite proxy.from"
    for attempt in range(holds):
        time.sleep(3)
        last = served()
        assert blocked(last), f"ingress block did not hold, request {attempt + 1}/{holds} said {last}"
