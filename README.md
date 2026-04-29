# Kasm on Kubernetes (Helm Chart)

![Version: 1.1181.0](https://img.shields.io/badge/Version-1.1181.0-informational?style=flat-square) ![AppVersion: 1.18.1](https://img.shields.io/badge/AppVersion-1.18.1-informational?style=flat-square)

> ⚠️ **This Helm chart is currently under technical Preview. Potential users should be advised that it is suitable for demo and evaluation purposes.**  
> For advanced configurations, see the [Chart README](./charts/kasm/README.md).

## Overview

This Helm chart enables you to deploy [Kasm Workspaces](https://kasm.com/) in Kubernetes with minimal friction.
For more detailed information or procedures for upgrading your Kasm Kubernetes deployment, refer to our **[additional documentation](./docs)**.

> Important: The [Kasm agent](https://docs.kasm.com/docs/install/multi_server_install#install-agent-server-roles) is not included in this Helm chart. It must be installed separately on a VM or bare-metal server. A Kasm session cannot be started without a running agent.

## Quickstart

### Option 1: Using OCI Registry (Recommended for Production)

> **Note:** OCI charts are published on GitHub releases. This method provides better security with signed artifacts.

```bash
helm install kasm oci://ghcr.io/kasmtech/kasm \
  --namespace {namespace} --create-namespace \
  --set publicAddr="kasm.contoso.com" \
  --set certificate.secretName="<some-cert-secret>"
```

### Option 2: Using Helm Repository

> **Note:** Requires GitHub Pages enabled on `gh-pages` branch. See [Setup Instructions](#github-pages-setup) below.

```bash
helm repo add kasm https://kasmtech.github.io/kasm-helm
helm repo update
helm install kasm kasm/kasm \
  --namespace {namespace} --create-namespace \
  --set publicAddr="kasm.contoso.com" \
  --set certificate.secretName="<some-cert-secret>"
```

### Option 3: Cloning the Repository

1. **Clone the Helm Chart Repository:**
    ```bash
    git clone https://github.com/kasmtech/kasm-helm.git
    cd kasm-helm
    ```

2. **Select the Kasm Workspaces Release (Optional):**  
   (Skip if you want the latest release build)
    ```bash
    git checkout develop
    ```

3. **Prepare TLS Certificate Secret:**  
   - Create a Kubernetes secret containing your TLS cert.  
   - For cert-manager, see [cert-manager integration](./docs/upload-certs-to-k8s.md).
   - For manual upload, see [Uploading Certs to K8s](./docs/upload-certs-to-k8s.md).

4. **Install the Chart:**  
   *(Replace variables in brackets with your own values.)*
    ```bash
    helm install kasm ./charts/kasm \
      --namespace {namespace} \
      --set publicAddr="kasm.contoso.com" \
      --set certificate.secretName="<some-cert-secret>"
    ```

> **Note:**  
> It may take several minutes for all Kasm services to be ready.  
> For custom configuration, edit `values.yaml` as described in the [Chart README](./charts/kasm/README.md).

---

## Post-Install: Access & Credentials

After deployment, get your connection details and credentials:

- **Kasm URL:**  
  `https://kasm.contoso.com` (use port 8443 if using the quick deploy with no ingress or cloud load balancer)

- **Admin Login:**  
  - Username: `admin@kasm.local`
  - Retrieve password:
    ```bash
    kubectl get secret --namespace {namespace} {secret-name} \
      -o jsonpath="{.data.admin-password}" | base64 -d
    ```

    Replace `{namespace}` the namespace where the Kasm is running, `{secret-name}` with your actual kasm secret name.
    You can retrieve secret name by running:
    ```bash
    kubectl -n {namespace} get secrets | grep secrets
    ```

- **User Login:**  
  - Username: `user@kasm.local`
  - Retrieve password:
    ```bash
    kubectl get secret --namespace {namespace} {secret-name} \
      -o jsonpath="{.data.user-password}" | base64 -d
    ```


### Other Secrets

| Secret Description          | Command                                                                                                       |
|-----------------------------|---------------------------------------------------------------------------------------------------------------|
| Database Password           | `kubectl get secret --namespace {namespace} {secret-name} -o jsonpath="{.data.db-password}" \| base64 -d`     |
| Manager Token               | `kubectl get secret --namespace {namespace} {secret-name} -o jsonpath="{.data.manager-token}" \| base64 -d`   |
| Service Registration Token  | `kubectl get secret --namespace {namespace} {secret-name} -o jsonpath="{.data.service-token}" \| base64 -d`   |

> **Tip:**  
> Store these secrets in a secure vault. They will be reused for chart upgrades.

---

## Upgrades & Versioning

- **Branching:**  
  This repo maintains a release branch matching each Kasm Workspaces version (e.g., `release/1.18.1`).  
  Use the matching branch for your Kasm deployment version.
- **Development:**  
  Use the default `develop` branch for developer previews.

---

## Next Steps & Customization

- For detailed chart values and configuration, see the [Chart README](./charts/kasm/README.md).
- For backup, restore, or upgrade procedures, see this [additional documentation](./docs)

---

## GitHub Pages Setup

To enable the Helm repository (Option 2), GitHub Pages must be configured:

1. Go to **Settings** → **Pages**
2. Set **Source** to `gh-pages` branch
3. Set **Folder** to `/ (root)`
4. Click **Save**

The `gh-pages` branch is automatically created and maintained by the CI workflow when charts are released.

---

## Troubleshooting

- It may take several minutes for pods to be ready after install.
- If you have issues with ingress or service access consult your cloud provider's troubleshooting documentation.

---


