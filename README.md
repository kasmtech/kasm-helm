# Kasm Workspaces on Kubernetes

![Version: 1.1190.6](https://img.shields.io/badge/Version-1.1190.6-informational?style=flat-square) ![AppVersion: 1.19.0](https://img.shields.io/badge/AppVersion-1.19.0-informational?style=flat-square) ![Type: Application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

This repository packages Kasm Workspaces for Kubernetes as a family of Helm charts. It began as the single control-plane chart (`kasm-helm`, documented below) and now also ships the **Kubernetes agent** charts that run sessions in-cluster, plus two umbrella charts that compose them. For a map of all ten charts and how they fit together — the dependency tree, deployment topologies, and a "which chart do I use" guide — see **[docs/architecture.md](docs/architecture.md)**.

For a feature-by-feature map — every Kasm workspace capability, the chart and values that provide it on Kubernetes, and what the cluster has to supply first — see **[docs/feature-matrix.md](docs/feature-matrix.md)**.

For the cluster-side work behind that last part — RWX storage, NetworkPolicy enforcement, GPU nodes, external access and TLS, private registries, and the privileged node prerequisites — the step-by-step procedures live in **[docs/howto/README.md](docs/howto/README.md)**.

Kasm Workspaces core services can be deployed to Kubernetes using the [open-source Kasm Helm chart](https://github.com/kasmtech/kasm-helm), which will be Generally Available as of Kasm version 1.19.0 (the developer preview is available using chart version 1.1200.0-develop).

## Live Demo

Try Kasm Workspaces in your browser: [kasm.com](https://kasm.com/solutions/platform)

## Get Started

[Kasm Workspaces Community Edition](https://kasm.com/community-edition) is free for personal and small-team use. The chart works with both Community and commercial editions.

## The control plane (`kasm-helm`)

Kasm Workspaces is a container streaming platform that delivers browsers, desktops, and applications as disposable, isolated sessions in any modern browser. The `kasm-helm` chart deploys the Kasm **core control-plane services** — `api`, `manager`, `guac`, `rdp-gateway`, and `rdp-https-gateway` — into a Kubernetes cluster, along with an optional bundled PostgreSQL database. This is the half users log in to and the half agents register with; the rest of this README covers installing it. To run sessions inside the cluster as well, add the [agent charts](#charts-in-this-repository) or install the [whole stack](#deploy-the-whole-stack) at once.

A few things to know up front:

- **Sessions do not run in this chart.** Containerized desktop, browser, and app sessions run on Kasm agents you provision separately — external Docker Agent servers (statically or via auto scaling), or the **Kubernetes agent** in this same repository (the `kasm-agent` charts).
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
  --version 1.1190.6 \
  --namespace kasm --create-namespace \
  -f my-values.yaml
```

Or from the classic Helm repository:

```bash
helm repo add kasmweb https://helm.kasm.com
helm repo update
helm install kasm kasmweb/kasm-helm \
  --version 1.1190.6 \
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

## Charts in this repository

This repository contains ten Helm charts. `kasm-helm` (above) is the control plane; the agent-family charts run sessions in-cluster; and the umbrella charts compose them. Each chart keeps its own README; see [docs/architecture.md](docs/architecture.md) for how they relate.

### Control plane

| Chart | Purpose | README |
| ----- | ------- | ------ |
| `kasm-helm` | The GA control plane: web UI, manager/API, session proxy, Guacamole, RDP gateways, and a bundled PostgreSQL. Sessions do not run here. | [charts/kasm-helm/README.md](charts/kasm-helm/README.md) |

### Agent family

| Chart | Purpose | README |
| ----- | ------- | ------ |
| `kasm-agent` | Umbrella for the Kubernetes agent — composes the six subcharts below plus three optional third-party dependencies (rclone CSI driver, GPU Operator, NFS provisioner). | [charts/kasm-agent/README.md](charts/kasm-agent/README.md) |
| `kasm-agent-operator` | The CRDs, cluster RBAC, and controller-manager that reconcile `Agent`, `KasmWorkspace`, `KasmImagePuller`, `WarmPool`, and `WarmPoolInstance`. Cluster singleton. | [charts/kasm-agent-operator/README.md](charts/kasm-agent-operator/README.md) |
| `kasm-agent-instance` | The `Agent` custom resource and the session proxy users' browsers connect to, plus external-access options (HTTPRoute / Ingress / Route). | [charts/kasm-agent-instance/README.md](charts/kasm-agent-instance/README.md) |
| `kasm-otel-collector` | An OpenTelemetry collector that fans agent traces, metrics, and logs out to external observability backends. | [charts/kasm-otel-collector/README.md](charts/kasm-otel-collector/README.md) |
| `kasm-node-prep` | Privileged DaemonSet that builds and loads host kernel modules (`v4l2loopback`, WireGuard) and applies optional node tuning. | [charts/kasm-node-prep/README.md](charts/kasm-node-prep/README.md) |
| `kasm-video-device-plugin` | Device plugin that advertises `/dev/video*` as the schedulable resource `kasm.com/video` for webcam-enabled sessions. | [charts/kasm-video-device-plugin/README.md](charts/kasm-video-device-plugin/README.md) |
| `kasm-egress-installer` | Privileged DaemonSet that chains a CNI shim into every node's CNI config and brings up per-session OpenVPN, WireGuard, or Ziti egress tunnels. Off by default. | [charts/kasm-egress-installer/README.md](charts/kasm-egress-installer/README.md) |
| `kasm-agent-crds` | The same five CRDs as ordinary Helm templates, for fleets that want a Helm-native CRD lifecycle. Standalone — install before the umbrellas. | [charts/kasm-agent-crds/README.md](charts/kasm-agent-crds/README.md) |

### Umbrellas

| Chart | Purpose | README |
| ----- | ------- | ------ |
| `kasm-platform` | Top-level umbrella composing `kasm-helm` + `kasm-agent` into one release, each half independently switchable. The whole stack at once. | [charts/kasm-platform/README.md](charts/kasm-platform/README.md) |

## Deploy the whole stack

To install both halves — the control plane and the Kubernetes agent — as a single release, use the **[kasm-platform](charts/kasm-platform/README.md)** umbrella chart. Each half is independently switchable (`kasm-helm.enabled`, `kasm-agent.enabled`), so the same chart also installs the control plane alone or an agent alone.

Its OCI reference follows the same convention as the control-plane snippets above:

```text
oci://registry-1.docker.io/kasmweb/kasm-platform
```

For the worked single-namespace example, the install order, and the one setting the two halves must agree on (the Kasm Authorization Domain), see the [kasm-platform README](charts/kasm-platform/README.md). For the full picture of how all ten charts relate, see [docs/architecture.md](docs/architecture.md).

## Versioning

Chart versions track Kasm Workspaces versions. The middle component of the chart version corresponds to the Kasm release — for example, chart **1.1181.0** matches Kasm Workspaces **1.18.1**. This branch (`1.1190.6` / app `1.19.0`) is the stable release for Kasm Workspaces **1.19.0**.

| Branch | Purpose |
| --- | --- |
| `release/<version>` | Stable chart for a specific Kasm Workspaces release |
| `develop` | Developer previews — no guaranteed migration path; not for production |

Always use the chart version that matches the Kasm Workspaces version you are deploying.

The agent-family and umbrella charts are versioned on their own line, independent of the control plane, and are currently `0.1.0` (app `develop`) — a developer preview. For per-chart release history, see each chart's `CHANGELOG.md` (for example, [charts/kasm-helm/CHANGELOG.md](charts/kasm-helm/CHANGELOG.md)); there is no repository-wide changelog.

## Resources

- [Kasm Workspaces website](https://kasm.com/)
- [Kasm documentation](https://docs.kasm.com/) — installation, upgrade, configuration, multi-region, VM-to-Kubernetes migration, and troubleshooting
- [Helm chart repository](https://github.com/kasmtech/kasm-helm) — chart source, values reference, and examples
- [Kasm on GitHub](https://github.com/kasmtech) — KasmVNC and the open-source workspace image library
- [Helm chart issues and discussion](https://github.com/kasmtech/kasm-helm/issues)

## License

This chart is published by Kasm Technologies. Kasm Workspaces itself is licensed separately — see [kasm.com](https://kasm.com/) for license terms.
