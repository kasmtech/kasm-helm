# Kasm Workspaces on Kubernetes

![Version: 1.1190.4](https://img.shields.io/badge/Version-1.1190.4-informational?style=flat-square) ![AppVersion: 1.19.0](https://img.shields.io/badge/AppVersion-1.19.0-informational?style=flat-square) ![Type: Application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Kasm Workspaces core services can be deployed to Kubernetes using the [open-source Kasm Helm chart](https://github.com/kasmtech/kasm-helm), which will be Generally Available as of Kasm version 1.19.0 (the developer preview is available using chart version 1.1200.0-develop).

## Live Demo

Try Kasm Workspaces in your browser: [kasm.com](https://kasm.com/solutions/platform)

## Get Started

[Kasm Workspaces Community Edition](https://kasm.com/community-edition) is free for personal and small-team use. The chart works with both Community and commercial editions.

## About This Chart

Kasm Workspaces is a container streaming platform that delivers browsers, desktops, and applications as disposable, isolated sessions in any modern browser. This chart deploys the Kasm **core control-plane services** — `api`, `manager`, `guac`, `rdp-gateway`, and `rdp-https-gateway` — into a Kubernetes cluster, along with an optional bundled PostgreSQL database.

A few things to know up front:

- **Sessions do not run in the cluster.** Containerized desktop, browser, and app sessions are hosted on external Docker Agent servers that you provision separately (statically or via auto scaling).
- **RDP target hosts are external.** RDP sessions are routed by the in-cluster gateways to Windows or Linux hosts running outside the cluster.
- **Ingress fronts the deployment.** Browser and HTTPS-based client traffic enters through your Ingress controller, typically backed by a cloud load balancer.

## Prerequisites

- **Kubernetes 1.24+**
- **Helm 3.18.x+** ([install Helm](https://helm.sh/docs/intro/install/))
- `kubectl` configured against your target cluster
- A **default StorageClass** (or explicit `storageClassName` in your values) for the built-in PostgreSQL PVC — not required if you point the chart at an external database
- A **domain name** you control, used as the `publicAddr` for Kasm
- A **TLS certificate** (or cert-manager installed in the cluster)

## Quick Start

Create a minimal `my-values.yaml`:

```yaml
publicAddr: kasm.example.com
certificate:
  secretName: my-tls-secret
```

Install from the OCI registry (recommended):

```bash
helm install kasm oci://registry-1.docker.io/kasmweb/kasm-helm \
  --version 1.1190.4 \
  --namespace kasm --create-namespace \
  -f my-values.yaml
```

Or from the classic Helm repository:

```bash
helm repo add kasmweb https://helm.kasm.com
helm repo update
helm install kasm kasmweb/kasm-helm \
  --version 1.1190.4 \
  --namespace kasm --create-namespace \
  -f my-values.yaml
```

After the pods are healthy, retrieve generated credentials and post-install notes:

```bash
helm get notes kasm -n kasm
```

For step-by-step instructions — including TLS, DNS, secret pre-seeding, and verification — see the Documentation section below.

## Configuration

The chart is configured through `values.yaml`. Two values are required to install — `publicAddr` (the public DNS name for the deployment) and `certificate.secretName` (the TLS secret to terminate ingress with) — both shown in the Quick Start above.

For the full values reference (cert-manager, external database, ingress, per-component overrides, multi-zone topology, and more), see the chart documentation in the [Helm chart repository](https://github.com/kasmtech/kasm-helm). The repo also includes example manifests for pre-seeding secrets and managing database backups.

### DB preseed

The chart can seed Kasm's database at initialization time — users, groups, images, autoscale providers, SSO connectors, and more — declared as Helm values rather than post-install API calls. See [charts/kasm-helm/docs/preseed.md](charts/kasm-helm/docs/preseed.md) for the full preseed reference, including:

- [Default user accounts and group permissions](charts/kasm-helm/docs/default-users.md) (`defaultUsers: true`)
- [Default API credentials and permissions](charts/kasm-helm/docs/default-api-users.md) (`defaultApiUsers: true`)

## Versioning

Chart versions track Kasm Workspaces versions. The middle component of the chart version corresponds to the Kasm release — for example, chart **1.1181.0** matches Kasm Workspaces **1.18.1**. This branch (`1.1190.4` / app `1.19.0`) is the stable release for Kasm Workspaces **1.19.0**.

| Branch | Purpose |
| --- | --- |
| `release/<version>` | Stable chart for a specific Kasm Workspaces release |
| `develop` | Developer previews — no guaranteed migration path; not for production |

Always use the chart version that matches the Kasm Workspaces version you are deploying.

## Resources

- [Kasm Workspaces website](https://kasm.com/)
- [Kasm documentation](https://docs.kasm.com/) — installation, upgrade, configuration, multi-region, VM-to-Kubernetes migration, and troubleshooting
- [Helm chart repository](https://github.com/kasmtech/kasm-helm) — chart source, values reference, and examples
- [Kasm on GitHub](https://github.com/kasmtech) — KasmVNC and the open-source workspace image library
- [Helm chart issues and discussion](https://github.com/kasmtech/kasm-helm/issues)

## License

This chart is published by Kasm Technologies. Kasm Workspaces itself is licensed separately — see [kasm.com](https://kasm.com/) for license terms.
