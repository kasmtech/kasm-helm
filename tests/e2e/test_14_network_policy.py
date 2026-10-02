from __future__ import annotations

import json
from pathlib import Path

import pytest

from .conftest import E2EConfig
from .helpers import (
    assert_login_page,
    curl_from_pod,
    exec_in_pod,
    get_first_pod_by_selector,
    kubectl,
    wait_for_job_succeeded,
    wait_for_pods_ready,
)
from .netpol_flow import (
    assert_blocked,
    assert_not_dropped,
    assert_reachable,
    create_probe,
    delete_probe,
    install_netpol_release,
    netpol_values,
    pod_ip,
    policy_names,
    upgrade_release,
    uninstall_release,
    write_values,
)
PROXY_TLS = 8443
API_PORT = 8080
MANAGER_PORT = 8181
DB_PORT = 5432


@pytest.fixture(scope="module")
def np_release(e2e_config: E2EConfig, namespace: str, deployment_tls_secret, tmp_path_factory):
    """One policy-enabled release shared by the ordered tests below (installing is the slow part).

    Tests run in file order: the customization and upgrade tests change the release and
    leave it in a state the earlier tests do not need.
    """
    workdir = tmp_path_factory.mktemp("np")
    backup_pvc = f"{e2e_config.release_name}-db-backup-np"
    state = {
        "config": e2e_config,
        "namespace": namespace,
        "probe_namespace": f"{namespace}-probe",
        "workdir": workdir,
        "backup_pvc": backup_pvc,
    }

    def values(**overrides) -> dict:
        base = netpol_values(
            extra={
                "proxyService": {"type": "ClusterIP"},
                "dbManagement": {
                    "initialize": overrides.pop("initialize", False),
                    "upgrade": overrides.pop("upgrade", {"enable": False}),
                    "backupCron": {
                        "enabled": True,
                        "schedule": "0 3 * * *",
                        "timeZone": "Etc/UTC",
                        "pvcName": backup_pvc,
                        "pvcSize": 1,
                    },
                },
            }
        )
        np = base["networkPolicies"]
        for key, value in overrides.items():
            np[key] = value
        return base

    state["values"] = values
    install_netpol_release(
        e2e_config, namespace, write_values(workdir, "install.yaml", values(initialize=True))
    )
    yield state
    delete_probe(namespace)
    delete_probe(state["probe_namespace"])
    uninstall_release(e2e_config, namespace)
    kubectl(["delete", "namespace", state["probe_namespace"], "--ignore-not-found", "--wait=false"], check=False)


def _login_settings(namespace: str, proxy_pod: str) -> str:
    result = exec_in_pod(
        namespace,
        proxy_pod,
        [
            "curl", "-sSk", "--max-time", "30", "-X", "POST",
            "-H", "Content-Type: application/json", "-d", "{}",
            "-w", "\n%{http_code}", "https://localhost:8443/api/login_settings",
        ],
    )
    body, code = result.stdout.rsplit("\n", 1)
    assert code.strip() == "200", f"login_settings returned {code}: {body[:300]}"
    return body


@pytest.mark.e2e
def test_01_install_works_under_policy(np_release) -> None:
    e2e_config = np_release["config"]
    namespace = np_release["namespace"]
    release = e2e_config.release_name

    assert any(n.endswith("-network-policy-default-deny") for n in policy_names(namespace, release))

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)

    # proxy -> api -> db, all crossing policy boundaries.
    settings = json.loads(_login_settings(namespace, proxy_pod))
    assert isinstance(settings, dict) and settings

    # guac / rdp-gateway / rdp-https-gateway are part of "all pods ready" (install waited on it);
    # name them so a component silently disabled in the values is caught.
    for component in ("guac", "rdp-gateway", "rdp-https-gateway", "api", "manager", "db"):
        pod_ip(namespace, release, component)

    job_name = f"{release}-db-backup-np-manual"
    kubectl(["delete", "job", job_name, "--ignore-not-found"], namespace=namespace, check=False)
    kubectl(["create", "job", f"--from=cronjob/{release}-db-backup", job_name], namespace=namespace)
    wait_for_job_succeeded(namespace, job_name=job_name, timeout_seconds=900)


@pytest.mark.e2e
def test_02_policies_block_unlabeled_pod(np_release) -> None:
    namespace = np_release["namespace"]
    release = np_release["config"].release_name
    probe = create_probe(namespace)

    proxy_ip = pod_ip(namespace, release, "proxy")
    api_ip = pod_ip(namespace, release, "api")
    manager_ip = pod_ip(namespace, release, "manager")
    db_ip = pod_ip(namespace, release, "db")

    # Control: the probe method reaches the one thing the policy leaves open.
    assert_reachable(namespace, probe, proxy_ip, PROXY_TLS, "probe -> proxy 8443 (open to any source)")

    assert_blocked(namespace, probe, db_ip, DB_PORT, "probe -> db 5432")
    assert_blocked(namespace, probe, api_ip, API_PORT, "probe -> api 8080")
    assert_blocked(namespace, probe, manager_ip, MANAGER_PORT, "probe -> manager 8181")

    # The proxy is not a database client. Its own policy must keep it away from the db even
    # though both are in the release. The proxy image has curl but no python, so use curl's raw
    # TCP mode (probe via="curl"): TIMEOUT is a dropped connect, OPEN a completed one.
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")

    assert_reachable(namespace, proxy_pod, api_ip, API_PORT, "control: proxy -> api 8080", via="curl")
    assert_blocked(namespace, proxy_pod, db_ip, DB_PORT, "proxy -> db 5432", via="curl")


@pytest.mark.e2e
def test_03_customization(np_release) -> None:
    e2e_config = np_release["config"]
    namespace = np_release["namespace"]
    probe_ns = np_release["probe_namespace"]
    release = e2e_config.release_name
    workdir: Path = np_release["workdir"]
    values = np_release["values"]

    probe = create_probe(namespace)
    other_probe = create_probe(probe_ns)
    proxy_ip = pod_ip(namespace, release, "proxy")
    db_ip = pod_ip(namespace, release, "db")

    # proxy.from restricted to one namespace.
    assert_reachable(namespace, probe, proxy_ip, PROXY_TLS, "before: release-ns probe -> proxy")
    upgrade_release(
        e2e_config,
        namespace,
        write_values(
            workdir,
            "proxy-from.yaml",
            values(proxy={"from": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": probe_ns}}}]}),
        ),
    )
    proxy_ip = pod_ip(namespace, release, "proxy")
    assert_reachable(probe_ns, other_probe, proxy_ip, PROXY_TLS, "proxy.from namespace probe -> proxy")
    assert_blocked(namespace, probe, proxy_ip, PROXY_TLS, "release-ns probe -> proxy with proxy.from set")
    # in-chart callers (guac/rdp*) are covered by their own rule: pods stayed Ready in upgrade_release.

    # db.extraIngress opens the db to the probe.
    assert_blocked(namespace, probe, db_ip, DB_PORT, "before: probe -> db")
    extra_ingress = [
        {
            "from": [{"podSelector": {"matchLabels": {"app": "np-probe"}}}],
            "ports": [{"protocol": "TCP", "port": DB_PORT}],
        }
    ]
    db_cfg = {"db": {"enabled": True, "extraIngress": extra_ingress}}
    upgrade_release(
        e2e_config, namespace, write_values(workdir, "db-extra.yaml", values(components=db_cfg))
    )
    assert_reachable(namespace, probe, db_ip, DB_PORT, "db.extraIngress: probe -> db")

    # db.enabled=false swaps the chart's restrictive db ingress policy for an allow-all one: the
    # probe now reaches the db, and chart clients keep working (upgrade_release waits for every
    # rollout and pod to be Ready, and the login settings call crosses proxy -> api -> db).
    upgrade_release(
        e2e_config,
        namespace,
        write_values(workdir, "db-off.yaml", values(components={"db": {"enabled": False}})),
    )
    names = policy_names(namespace, release)
    assert not any(n.endswith("-network-policy-db-ingress") for n in names)
    assert any(n.endswith("-network-policy-db-ingress-allow-all") for n in names)
    assert_reachable(namespace, probe, db_ip, DB_PORT, "db.enabled=false: probe -> db (allow-all ingress)")
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    assert isinstance(json.loads(_login_settings(namespace, proxy_pod)), dict)

    # Restore the chart's own policies and make sure the release recovers.
    upgrade_release(e2e_config, namespace, write_values(workdir, "restore.yaml", values()))
    assert_blocked(namespace, probe, db_ip, DB_PORT, "restored: probe -> db")


@pytest.mark.e2e
def test_04_proxy_reaches_gateway_ports(np_release) -> None:
    namespace = np_release["namespace"]
    release = np_release["config"].release_name
    probe = create_probe(namespace)
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")

    # (component, port) edges the proxy needs: /desktop/ proxy_pass to the nginx sidecars.
    for component, port in (("guac", 9000), ("rdp-gateway", 5555), ("rdp-gateway", 9001), ("rdp-https-gateway", 9002)):
        ip = pod_ip(namespace, release, component)
        what = f"{component} {port}"
        # Same method (curl telnet) from the allowed source and from the unlabeled pod.
        assert_reachable(namespace, proxy_pod, ip, port, f"proxy -> {what}", via="curl")
        assert_blocked(namespace, probe, ip, port, f"unlabeled probe -> {what}", via="curl")


@pytest.mark.e2e
def test_05_external_rdp_port(np_release) -> None:
    e2e_config = np_release["config"]
    namespace = np_release["namespace"]
    probe_ns = np_release["probe_namespace"]
    release = e2e_config.release_name
    workdir: Path = np_release["workdir"]
    values = np_release["values"]

    def rdp_values(**rdp_gateway) -> dict:
        base = values()
        base["directRdpService"] = {"enabled": True, "type": "NodePort", "rdpAccessURL": "rdp.example.test"}
        if rdp_gateway:
            base["networkPolicies"]["rdpGateway"] = rdp_gateway
        return base

    probe = create_probe(namespace)
    other_probe = create_probe(probe_ns)

    # rdpGateway.from empty: any source. Nothing necessarily listens on 3389 in kind, so a
    # connect that is accepted OR refused proves the SYN was not policy-dropped (a deny is TIMEOUT).
    upgrade_release(e2e_config, namespace, write_values(workdir, "rdp-open.yaml", rdp_values()))
    gw_ip = pod_ip(namespace, release, "rdp-gateway")
    assert_not_dropped(namespace, probe, gw_ip, 3389, "rdpGateway.from empty: probe -> rdp-gateway 3389")
    assert_not_dropped(probe_ns, other_probe, gw_ip, 3389, "rdpGateway.from empty: other-ns probe -> rdp-gateway 3389")

    # rdpGateway.from restricted to one namespace.
    upgrade_release(
        e2e_config,
        namespace,
        write_values(
            workdir,
            "rdp-from.yaml",
            rdp_values(**{"from": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": probe_ns}}}]}),
        ),
    )
    gw_ip = pod_ip(namespace, release, "rdp-gateway")
    assert_not_dropped(probe_ns, other_probe, gw_ip, 3389, "rdpGateway.from namespace: probe -> rdp-gateway 3389")
    assert_blocked(namespace, probe, gw_ip, 3389, "rdpGateway.from namespace: release-ns probe -> rdp-gateway 3389")

    # Back to the baseline for the hooks test.
    upgrade_release(e2e_config, namespace, write_values(workdir, "rdp-restore.yaml", values()))


@pytest.mark.e2e
def test_06_upgrade_hooks_under_policy(np_release) -> None:
    e2e_config = np_release["config"]
    namespace = np_release["namespace"]
    release = e2e_config.release_name
    workdir: Path = np_release["workdir"]

    db_svc = kubectl(
        ["get", "svc", "-l", f"app.kubernetes.io/instance={release},app.kubernetes.io/component=db",
         "-o", "jsonpath={.items[0].metadata.name}"],
        namespace=namespace,
    ).stdout.strip()
    upgrade_job = f"{release}-db-upgrade"
    backup_job = f"{release}-pre-upgrade-backup"
    kubectl(["delete", "job", upgrade_job, "--ignore-not-found"], namespace=namespace, check=False)

    upgrade_values = np_release["values"](
        upgrade={"enable": True, "oldDbHostname": db_svc, "oldDbBackupFileName": "kasm_dump.tar"}
    )
    upgrade_release(e2e_config, namespace, write_values(workdir, "upgrade.yaml", upgrade_values), wait=False)

    wait_for_job_succeeded(namespace, job_name=backup_job, timeout_seconds=900)
    wait_for_job_succeeded(namespace, job_name=upgrade_job, timeout_seconds=900)
    wait_for_pods_ready(namespace, timeout_seconds=1200, progress=True)
    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)
    assert status_code == 200
    assert_login_page(body)
