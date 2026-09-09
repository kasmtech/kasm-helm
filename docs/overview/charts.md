> **Applies to:** choosing which chart to install · **See also:** [Architecture](architecture.md) for how they compose

# The charts

Ten charts, all published under `oci://registry-1.docker.io/kasmweb/`. Most deployments
install one of the top three and configure the rest through its values.

## Which one do I install?

Just want the shortest working install? The [**Quickstart**](../../README.md#quickstart) walks two
paths — the whole stack on one cluster, or an agent added to a Kasm you already run — end to end.

- **kasm-platform** — the whole stack, or either half via its toggles, in one
  release. Start here for a single-cluster install.
- **kasm-helm** — the control plane on its own (GA). Sessions run on external
  agents (Kubernetes, VM/Docker, or hosted).
- **kasm-agent** — a Kubernetes agent on its own: operator, collector, and `Agent`
  instance, plus optional cluster infrastructure. Registers with any Kasm manager.
- **kasm-agent-operator, kasm-agent-instance, kasm-otel-collector, kasm-node-prep,
  kasm-video-device-plugin, kasm-egress-installer** — subcharts of kasm-agent. You
  rarely install these directly; configure them through the umbrella (`operator.*`,
  `agent.*`, `otelCollector.*`, `nodePrep.*`, `videoDevicePlugin.*`,
  `egressInstaller.*`). Install one alone only for advanced splits, such as a second
  agent that shares an existing operator.
- **kasm-agent-crds** — install as its own release, before kasm-agent or
  kasm-platform, only when you want Helm to own the CRD lifecycle.

Working from a feature rather than a chart? [**What works on Kubernetes**](../reference/feature-matrix.md) says
whether each Kasm feature works here, what it needs from the cluster, and the values that turn it
on.

Sizing a deployment before installing anything? [**Planning a Kasm agent deployment**](../planning/README.md)
is the decision sequence — topology, capacity, network, storage, security, install and day 2.

Ready to prepare the cluster? [**Cluster configuration how-tos**](../planning/README.md) are the
step-by-step procedures, with the commands that prove each one worked. On a managed service,
[**Managed Kubernetes providers: what changes**](../planning/managed-providers.md) is the
cross-provider view for EKS, AKS, GKE and OpenShift.

## Every chart

| Chart | Role | README |
| ----- | ---- | ------ |
| kasm-helm | Control plane (GA) | [charts/kasm-helm/README.md](../../charts/kasm-helm/README.md) |
| kasm-agent | Agent umbrella | [charts/kasm-agent/README.md](../../charts/kasm-agent/README.md) |
| kasm-agent-operator | CRDs + RBAC + controller (singleton) | [charts/kasm-agent-operator/README.md](../../charts/kasm-agent-operator/README.md) |
| kasm-agent-instance | `Agent` CR + session proxy | [charts/kasm-agent-instance/README.md](../../charts/kasm-agent-instance/README.md) |
| kasm-otel-collector | Telemetry collector | [charts/kasm-otel-collector/README.md](../../charts/kasm-otel-collector/README.md) |
| kasm-node-prep | Kernel modules + node tuning | [charts/kasm-node-prep/README.md](../../charts/kasm-node-prep/README.md) |
| kasm-video-device-plugin | Advertises `kasm.com/video` | [charts/kasm-video-device-plugin/README.md](../../charts/kasm-video-device-plugin/README.md) |
| kasm-egress-installer | Per-session VPN egress via a chained CNI shim (privileged, off by default) | [charts/kasm-egress-installer/README.md](../../charts/kasm-egress-installer/README.md) |
| kasm-agent-crds | CRDs as Helm templates (standalone) | [charts/kasm-agent-crds/README.md](../../charts/kasm-agent-crds/README.md) |
| kasm-platform | Top-level umbrella (whole stack) | [charts/kasm-platform/README.md](../../charts/kasm-platform/README.md) |
