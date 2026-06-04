from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from .helpers import (
    assert_login_page,
    curl_from_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
)
from .conftest import helm_install


@pytest.mark.e2e
def test_basic_deployment_pods_ready_and_login_page(installer, temp_workdir: Path) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    # Lower per-component resource requests so all pods (api, manager, proxy,
    # guac + nginx sidecar, rdpGateway + nginx sidecar, rdpHttpsGateway +
    # nginx sidecar, bundled db) fit on the single-node kind cluster in
    # gitlab runner.
    low_resources = {"requests": {"cpu": "50m", "memory": "256Mi"}}
    low_resources_proxy = {"requests": {"cpu": "50m", "memory": "128Mi"}}
    low_resources_gw = {"requests": {"cpu": "25m", "memory": "128Mi"}}
    values_obj = {
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
    values_path = temp_workdir / "values.yaml"
    values_path.write_text(yaml.safe_dump(values_obj, sort_keys=False))

    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        values_file=str(values_path),
    )

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)

    assert status_code == 200
    assert_login_page(body)
