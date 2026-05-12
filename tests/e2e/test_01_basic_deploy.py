from __future__ import annotations

import pytest

from .helpers import (
    assert_login_page,
    curl_from_pod,
    get_first_pod_by_selector,
    install_and_wait_with_retry,
)
from .conftest import helm_install


@pytest.mark.e2e
def test_basic_deployment_pods_ready_and_login_page(installer) -> None:
    e2e_config = installer["config"]
    namespace = installer["namespace"]

    # Minimal-ish install: rely on defaults as much as possible
    install_and_wait_with_retry(
        helm_install_fn=helm_install,
        e2e_config=e2e_config,
        namespace=namespace,
        set_args=[
            "deploymentSize=small",
            "publicAddr=kasm.example.com",
            "certificate.secretName=kasm-deployment-tls",
        ],
    )

    proxy_pod = get_first_pod_by_selector(namespace, "app.kubernetes.io/component=proxy")
    status_code, body = curl_from_pod(namespace, proxy_pod, "https://localhost:8443/", insecure=True)

    assert status_code == 200
    assert_login_page(body)
