# kasm-agent

![Version: 1.1200.0-develop](https://img.shields.io/badge/Version-1.1200.0--develop-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Umbrella chart for the Kasm Workspaces Kubernetes agent: operator, telemetry collector, agent instance, and optional per-feature cluster infrastructure

**Homepage:** <https://kasm.com>

A Kasm *agent* is the half of a Kasm Workspaces deployment that runs user sessions. It registers
with a Kasm *manager* (installed separately by the `kasm-helm` chart, or already running elsewhere,
including a Kasm-hosted one), and from then on the manager schedules workspaces into this cluster.
This umbrella chart installs everything an agent needs on the Kubernetes side, plus the optional
cluster infrastructure that individual Kasm features depend on.

This page is the chart reference: what it installs, what the cluster has to supply, the values that
interact, and the generated values table. Procedures live in the
[documentation index](../../docs/README.md); [Get started](../../docs/tutorials/get-started.md) is
the shortest path from nothing to one running session.

## What this chart installs

Each dependency is aliased, so every value below is set as `<alias>.<subchart value>`.

| Alias | Chart | Default | What it is |
| ----- | ----- | ------- | ---------- |
| `operator` | `kasm-agent-operator` | enabled | The three CRDs (`Agent`, `KasmWorkspace`, `KasmImagePuller`), the cluster RBAC, and the controller-manager that reconciles them. |
| `otelCollector` | `kasm-otel-collector` | enabled | An OpenTelemetry collector that receives traces, metrics, and logs from the operator, the agent, and workspace pods on ports 4317/4318, and forwards them to your telemetry backends. |
| `agent` | `kasm-agent-instance` | enabled | The `Agent` resource that registers this cluster as a Kasm deployment zone, plus the session proxy users' browsers connect to. |
| `nodePrep` | `kasm-node-prep` | disabled | A privileged DaemonSet that builds and loads host kernel modules (`v4l2loopback`, `wireguard`). |
| `videoDevicePlugin` | `kasm-video-device-plugin` | disabled | A device plugin that advertises `/dev/video*` as a scheduleable resource. |
| `egressInstaller` | `kasm-egress-installer` | disabled | A privileged DaemonSet (`hostPID` + `hostNetwork`) that installs a `kasm-egress-cni` shim into the node's CNI plugin directory, chains it into every active `.conflist`, and brings up per-session OpenVPN, WireGuard, or Ziti egress tunnels on request. |
| `csiRclone` | `csi-driver-rclone` | disabled | Third-party. The Veloxpack rclone CSI driver backing Kasm cloud storage mappings. |
| `gpuOperator` | `gpu-operator` | disabled | Third-party. The NVIDIA GPU Operator: drivers, container toolkit, device plugin. |
| `nfs-server-provisioner` | `nfs-server-provisioner` | disabled | Third-party. An in-cluster NFS server providing a ReadWriteMany StorageClass for persistent profiles. Un-aliased: the upstream chart has no nameOverride support. |

On top of the subcharts, the umbrella itself owns only two things: an optional set of baseline
namespace NetworkPolicies (`networkPolicies.*`) and an `extraObjects` escape hatch.

The operator's three CustomResourceDefinitions arrive from its `crds/` directory: Helm creates them
on install and never upgrades them. To put them under Helm's control instead, install
[`kasm-agent-crds`](../kasm-agent-crds/README.md) as its own release before this one and upgrade it
first thereafter; otherwise apply schema changes out of band with
`kubectl apply --server-side -f charts/kasm-agent-operator/crds/`. Both paths are described in
[CustomResourceDefinition lifecycle](../kasm-agent-operator/README.md#customresourcedefinition-lifecycle)
and [Install the CRDs](../../docs/how-to/install/crds.md).

## Scope

A few boundaries worth knowing before you plan an install.

* **Single namespace.** One release installs one agent into one namespace. Everything the chart
  creates is namespaced, apart from the operator's cluster-scoped RBAC and CRDs and whatever the
  third-party dependencies create.
* **The operator is a cluster singleton.** It owns cluster-scoped CRDs and fixed-name ClusterRoles,
  so only one release per cluster may set `operator.enabled=true`. To run a second agent in another
  namespace of the same cluster, install it with `operator.enabled=false` and let it share the
  operator that is already there.
* **The GPU Operator and the rclone CSI driver are cluster-scoped too.** Enable each of them in at
  most one release per cluster, and leave them disabled if they are already installed by something
  else.
* **Telemetry backends are external.** The collector *exports* to an LGTM stack (Loki, Grafana,
  Tempo, Mimir), a ClickHouse instance, or any OTLP endpoint — this chart never installs any of
  them. By default both of those exporters are disabled and the collector just logs telemetry to
  its own stdout, so a default install never silently ships data to a backend that does not exist.
  Point `otelCollector.exporters.otlp.endpoint` (and enable it) and/or
  `otelCollector.exporters.clickhouse.*` at backends you already run to ship telemetry out.
* **The Kasm manager is external to this chart.** Install it with the `kasm-helm` chart, or point
  `agent.manager.hostname` at an existing deployment.
* **Uninstall in two steps.** `helm uninstall` deletes the `Agent` resource and the operator that
  processes its finalizer at the same time; if the operator dies first, the CR's deletion hangs (or,
  worse, a later operator install processes the stale deletion and tears the agent down). Delete the
  agent first and let the operator clean it up, then uninstall the release:

  ```console
  # End any live sessions first — KasmWorkspace resources carry an operator-cleared finalizer too.
  kubectl delete kasmworkspaces.agent.kasm.com --all -n <namespace> --wait
  kubectl delete agents.agent.kasm.com --all -n <namespace> --wait
  helm uninstall <release> -n <namespace>
  ```

## Prerequisites

| Requirement | Why |
| ----------- | --- |
| Kubernetes 1.26+ (or OpenShift 4.10+) | The shared floor for the whole agent family (this umbrella and its six Kasm subcharts), set by the Gateway API v1 route types and the operator's CRDs. The control-plane `kasm-helm` chart, installed separately, has a lower floor of Kubernetes 1.24+. |
| Helm 3.18 or newer | The charts are published to an OCI registry and use current chart features. |
| A default StorageClass with dynamic provisioning | Workspace volumes and persistent profiles. |
| Working in-pod DNS resolution (CoreDNS) | The agent, the session proxy and workspaces resolve Services by name. |
| A reachable Kasm manager, and a registration token issued by it | What the agent registers with. See [Required values](#required-values). |
| The `privileged` Pod Security Standard on the namespace | Only when `nodePrep`, `videoDevicePlugin` or `egressInstaller` is enabled. See [Cluster preparation checklist](#cluster-preparation-checklist). |
| One way to publish the session proxy | Only for direct connections. On the relayed default the control plane reaches the proxy inside the cluster. See [External access](#external-access). |

## Required values

Three values have no default and cannot be guessed:

| Value | What it is |
| ----- | ---------- |
| `agent.manager.hostname` | The Kasm manager, or the proxy in front of it, this agent registers with: the control plane's `publicAddr`. Leave `agent.manager.pathPrefix` at `/manager_api`, the path the control plane's proxy routes to the manager. |
| `agent.manager.existingTokenSecret` (with `agent.manager.tokenSecretKey`), or `agent.manager.token` | The registration token. The control plane generates it as the `manager-token` key of Secret `<release>-secrets`. Prefer the Secret: an inline token lands in the release history in plain text. |
| `agent.publicHostname` | The hostname browsers reach this agent's session proxy on. Direct connections need a real external hostname under the same parent domain as the control plane's; on the relayed default it is the in-cluster session-proxy Service. |

`agent.inClusterControlPlane: true` derives all three from a `kasm-helm` release of the same name in
the same namespace, which is what `kasm-platform` does.

Everything else has a default. `agent.zone` is `default`, the zone a fresh `kasm-helm` install seeds.
The session proxy's TLS Secret (`agent.sessionProxy.certSecretName`, `kasm-session-proxy-tls`) is
generated self-signed unless a Secret of that name already exists, in which case it is used as-is:
pre-create it before the first install to bring your own certificate, or let cert-manager issue it
with `agent.sessionProxy.certificate`. Browsers only see that certificate on direct connections.

```yaml
agent:
  manager:
    hostname: kasm.example.com
    existingTokenSecret: kasm-manager-token   # key "token"
  publicHostname: sessions.example.com
```

```console
helm install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
  --version 1.1200.0-develop --namespace kasm-agent --create-namespace --values values.yaml
kubectl get agents.agent.kasm.com -n kasm-agent   # PHASE reaches Ready once the manager accepts it
```

New agents register **disabled**. In the admin UI: **Infrastructure** → the agent → **Enable**,
then **Workspaces** → the image → assign it to a group. The manager setting `auto_agent`
("Automatically Enable Agents") skips the first click; see
[Enable agents automatically](../../docs/how-to/enable-agents-automatically.md).
`helm get notes kasm-agent -n kasm-agent` reprints the post-install notes, including any
cross-feature warnings, at any time.

## Installing

See [Get started](../../docs/tutorials/get-started.md),
[Install on one cluster](../../docs/how-to/install/one-cluster.md),
[Install in two namespaces](../../docs/how-to/install/two-namespaces.md) and
[Add an agent cluster to an existing control plane](../../docs/how-to/install/agent-only.md).

### From Rancher

The chart carries what Rancher's Apps catalog reads: `catalog.cattle.io/*` annotations,
`app-readme.md` and a `questions.yaml` form for the registration values and the cluster features.
From a repository that lists both charts Rancher installs `kasm-agent-crds` first on its own
(`catalog.cattle.io/auto-install`); from a one-chart OCI entry such as
`oci://registry-1.docker.io/kasmweb/kasm-agent`, install the CRD chart first from its own entry.
A system default registry configured on the cluster is honoured for the six Kasm subcharts'
images (`global.cattle.systemDefaultRegistry`; the three third-party dependencies keep their own
image values). Procedure: [Install from the Rancher catalog](../../docs/how-to/install/rancher.md).

## Running alongside the kasm-helm control plane

See [Install in two namespaces](../../docs/how-to/install/two-namespaces.md) for the procedure,
[Topologies](../../docs/explanation/topologies.md) for the relayed default against direct
connections, and [Switch to direct connections](../../docs/how-to/networking/direct-connect.md) for
the zone and auth-domain settings that switch needs.

## External access

The session proxy can be published five ways (`agent.ingress`, `agent.httpRoute`, `agent.route`,
`agent.tlsRoute`, `agent.gatewayRoute`), or as a Service through `agent.sessionProxy.service`. At
most one of the five may be enabled; the chart refuses to render more. See
[External access](../kasm-agent-instance/README.md#external-access) in the `kasm-agent-instance`
README, which also states the websocket timeouts every HTTP path needs.

## Cluster preparation checklist

Most Kasm features need something from the cluster before they will work. Here is the short list —
the features people turn on most often, and the values that turn them on.
[**What works on Kubernetes**](../../docs/reference/feature-matrix.md) is the full one: every feature, its
status, what the cluster has to supply first, and the limits worth knowing.

| Kasm feature | Value that turns it on |
| ------------ | ---------------------- |
| Persistent profiles | `nfs-server-provisioner.enabled=true` with `nfs-server-provisioner.persistence.enabled=true`, or point Kasm at an RWX StorageClass the cluster already has |
| Cloud storage mappings | `csiRclone.enabled=true` **and** `agent.storageMappings.enabled=true` |
| GPU workspaces | `gpuOperator.enabled=true` **and** `agent.gpu.enabled=true` |
| Webcam passthrough | `nodePrep.enabled=true` with `nodePrep.modules.v4l2loopback.enabled=true`, **and** `videoDevicePlugin.enabled=true`. [KMM mode](../kasm-node-prep/README.md#kmm-mode) builds the module once per kernel instead of on every node |
| Per-session VPN egress | `egressInstaller.enabled=true` with `egressInstaller.distro` ([kasm-egress-installer](../kasm-egress-installer/README.md)) |
| Workspace network isolation | Nothing — the operator stamps a policy per session. `networkPolicies.enabled=true` adds the namespace baseline |
| External access to sessions | Only for direct connections. Exactly one of `agent.gatewayRoute.enabled=true` (preferred), `agent.tlsRoute.enabled=true`, `agent.httpRoute.enabled=true`, `agent.ingress.enabled=true`, `agent.route.enabled=true` (OpenShift), or none of them plus `agent.sessionProxy.service.type`; the chart refuses to render more than one of the five |
| Image pre-pulling | `agent.imagePuller.enabled=true` with `agent.imagePuller.images` |
| Private workspace registries | Registry credentials on the image in the manager (a per-registry Secret on each session pod); `agent.imagePuller.images[].imagePullSecrets` for pre-staged images |
| Telemetry | `otelCollector.exporters.otlp.*` and/or `otelCollector.exporters.clickhouse.*` |

Two patterns are worth carrying away. Several features need **two** values — the cluster-side
driver and the agent-side flag that makes Kasm ask for it — and setting one alone fails quietly.
And every feature that touches a node (webcam, WireGuard, Secure Boot, per-session egress) needs a
namespace that permits the `privileged` Pod Security Standard:

```console
kubectl label namespace kasm-agent pod-security.kubernetes.io/enforce=privileged
```

`egressInstaller` needs that same label and one thing more: its DaemonSet runs with `hostPID: true`
and `hostNetwork: true`, so any admission policy that blanket-disallows host namespaces (a Kyverno
`disallow-host-namespaces` rule, for instance) rejects it even in a `privileged` namespace, and has
to be scoped or excepted deliberately.

## Workspace node best practices

See [Node tuning and swap](../../docs/how-to/nodes/tuning-and-swap.md).

## Pulling from a private registry

Every image in the Kasm charts is split into `registry` / `repository` / `tag`, so pointing the
whole release at a mirror is one override block:

```yaml
operator:
  image:
    registry: registry.example.internal
    repository: kasmweb/agent-operator

otelCollector:
  image:
    registry: registry.example.internal
    repository: otel/opentelemetry-collector-contrib

agent:
  image:
    registry: registry.example.internal
    repository: kasmweb/agent-api
  sessionProxy:
    image:
      registry: registry.example.internal
      repository: kasmweb/nginx
      tag: "1.25.3"
    sidecarImage:
      registry: registry.example.internal
      repository: kasmweb/nginx-sidecar

videoDevicePlugin:
  image:
    registry: registry.example.internal
    repository: kasmweb/video-device-plugin

nodePrep:
  image:
    registry: registry.example.internal
    repository: kasm/node-prep-builder
    tag: "22.04-v0.15.4"
```

Two image sets are not covered by that block: workspace images come from the Kasm manager's
workspace registry and are re-pointed there, and every entry in `agent.imagePuller.images` is a full
reference used verbatim. The third-party subcharts (`csiRclone`, `nfs-server-provisioner`,
`gpuOperator`) take their own image values. `make images-agent` writes every image the rendered
manifests reference to `dist/kasm-agent-images.txt`, and `make images-check` fails when that list
misses one. The full procedure, including the node-prep builder image and the GPU Operator, is
[Registries and airgap](../../docs/how-to/registries-and-airgap.md).

## Baseline network policies

`networkPolicies.enabled=true` renders a default-deny policy for the release namespace plus narrow
allowances for DNS, intra-namespace traffic, the Kubernetes API server, the Kasm manager, inbound
session proxy traffic, and the telemetry backends. The `*.cidr` values all default to `0.0.0.0/0`
on specific ports, because those destinations vary per cluster; tighten them once you know the real
addresses. Add anything else through `networkPolicies.extraPolicies`, whose entries are rendered
with `tpl`.

These objects do nothing whatsoever unless the CNI enforces NetworkPolicy. Verify enforcement
before treating a default-deny policy as isolation.

## Publishing

See [Publish the charts](../../docs/how-to/publish-charts.md).

## Requirements

Kubernetes: `>= 1.26.0-0`

| Repository | Name | Version |
|------------|------|---------|
| file://../kasm-agent-instance | agent(kasm-agent-instance) | 1.1200.0-develop |
| file://../kasm-agent-operator | operator(kasm-agent-operator) | 1.1200.0-develop |
| file://../kasm-egress-installer | egressInstaller(kasm-egress-installer) | 1.1200.0-develop |
| file://../kasm-node-prep | nodePrep(kasm-node-prep) | 1.1200.0-develop |
| file://../kasm-otel-collector | otelCollector(kasm-otel-collector) | 1.1200.0-develop |
| file://../kasm-video-device-plugin | videoDevicePlugin(kasm-video-device-plugin) | 1.1200.0-develop |
| file://../kasm-video-device-plugin | driDevicePlugin(kasm-video-device-plugin) | 1.1200.0-develop |
| https://helm.ngc.nvidia.com/nvidia | gpuOperator(gpu-operator) | v26.7.0 |
| https://kubernetes-sigs.github.io/nfs-ganesha-server-and-external-provisioner/ | nfs-server-provisioner | 1.8.0 |
| oci://ghcr.io/veloxpack/charts | csiRclone(csi-driver-rclone) | 0.5.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent | object | `{"enabled":true,"nameOverride":"kasm-agent-instance","operatorRBAC":{"serviceAccount":{"namespace":""}}}` | The Kasm agent instance (`kasm-agent-instance` subchart, alias `agent`). Creates the Agent custom resource that registers this cluster as a Kasm deployment zone, plus the session proxy that terminates workspace connections.  This is the only subchart with required values. At a minimum set `agent.manager.hostname`, a manager token (`agent.manager.token` or `agent.manager.existingTokenSecret`), and `agent.publicHostname`, and either supply a session proxy TLS Secret through `agent.sessionProxy.certSecretName` or let cert-manager issue one with `agent.sessionProxy.certificate.enabled`.  See the `kasm-agent-instance` chart for its values (`name`, `image.*`, `manager.*`, `publicHostname`, `publicPort`, `zone`, `sessionProxy.*`, `otel.*`, `gpu.enabled`, `storageMappings.*`, `imagePuller.*`, `workspaceSecurity.*`, `httpRoute.*`, `env`, ...).  On OpenShift, `agent.openshift.scc.enabled` ships the SecurityContextConstraints the sessions need (shaped by `agent.workspaceSecurity.rootMode`) and grants them to the workspace ServiceAccount the operator creates; see the `kasm-agent-instance` chart.  |
| agent.enabled | bool | `true` | Install the Kasm agent instance with this release. Disable it to install only the operator and cluster infrastructure, and create Agent resources separately.  |
| agent.nameOverride | string | `"kasm-agent-instance"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, so without this the agent's satellite objects would be named after `agent` rather than after `kasm-agent-instance`.  |
| agent.operatorRBAC.serviceAccount.namespace | string | `""` | Namespace of the operator's ServiceAccount for the Secret-access Role the agent subchart stamps in this namespace. Leave empty here when `operator.enabled=true` (same namespace); set it to the operator's namespace when this release adds a second agent with `operator.enabled=false`.  |
| csiRclone | object | `{"enabled":false}` | The Veloxpack rclone CSI driver (`csi-driver-rclone`, pulled from `oci://ghcr.io/veloxpack/charts`, alias `csiRclone`). Third-party chart, not maintained by Kasm.  The driver provisions StorageClasses for the CSI driver `rclone.csi.veloxpack.io`, which mounts object storage and other rclone remotes (S3, GCS, Azure Blob, WebDAV, SFTP, ...) into workspace pods. It is what backs Kasm cloud storage mappings, so enable it alongside `agent.storageMappings.enabled` — the StorageClass names created here are the ones referenced by the storage mappings configured in the Kasm manager UI.  Nodes must have the FUSE kernel module available for rclone mounts to work.  Everything nested under `csiRclone` other than `enabled` is passed straight through to the upstream chart; run `helm show values oci://ghcr.io/veloxpack/charts/csi-driver-rclone --version 0.5.0` for the full reference.  |
| csiRclone.enabled | bool | `false` | Install the rclone CSI driver with this release. Leave disabled when the driver is already installed in the cluster, or when cloud storage mappings are not used.  |
| driDevicePlugin | object | `{"allocateEnvVar":"DRINODE","deviceKind":"dri","devicePrefix":"renderD","deviceShares":8,"driDrivers":"i915,xe,amdgpu","enabled":false,"nameOverride":"kasm-dri-device-plugin","resourceName":"kasm.com/dri"}` | The DRI device plugin: `kasm-video-device-plugin` a second time (alias `driDevicePlugin`), advertising each node's GPU render nodes (`/dev/dri/renderD*`) as `kasm.com/dri`. Kubernetes lets an unprivileged container open only the devices a device plugin handed it, so this is what gives an ordinary session hardware-accelerated rendering (EGL/VirtualGL through Mesa). A session allocated one gets the render node, its card node and `DRINODE`. Set `agent.workspaceSecurity.driResource: kasm.com/dri` as well, or the agent never requests it; the session still needs the node's `render` gid (`agent.workspaceSecurity. supplementalGroups`) to open the device. Any other subchart value is passed through. See docs/how-to/nodes/gpu.md.  |
| driDevicePlugin.allocateEnvVar | string | `"DRINODE"` | Set to the allocated render node; Kasm images read `DRINODE`.  |
| driDevicePlugin.deviceKind | string | `"dri"` | Switches the plugin to GPU render nodes. Leave as `dri`.  |
| driDevicePlugin.devicePrefix | string | `"renderD"` | Render nodes under `/dev/dri`. Leave as `renderD`.  |
| driDevicePlugin.deviceShares | int | `8` | Sessions per GPU. Every session on a GPU shares its video memory and time, so size this to the GPU's memory over what a session needs.  |
| driDevicePlugin.driDrivers | string | `"i915,xe,amdgpu"` | Kernel drivers whose GPUs to advertise. The default is the GPUs Mesa drives (Intel, AMD). An NVIDIA GPU needs NVIDIA's own userspace libraries in the container, which Mesa images lack, so it is left to the `nvidia.com/gpu` path (`gpuOperator`, `agent.gpu.enabled`). Empty advertises every render node.  |
| driDevicePlugin.enabled | bool | `false` | Install the DRI device plugin DaemonSet with this release.  |
| driDevicePlugin.nameOverride | string | `"kasm-dri-device-plugin"` | Pins the subchart's resource names, as for `videoDevicePlugin`, and keeps them apart from the webcam plugin's.  |
| driDevicePlugin.resourceName | string | `"kasm.com/dri"` | The resource sessions request; `agent.workspaceSecurity.driResource` must name the same one.  |
| egressInstaller | object | `{"enabled":false,"nameOverride":"kasm-egress-installer"}` | The Kasm egress installer (`kasm-egress-installer` subchart, alias `egressInstaller`). A privileged DaemonSet that chains a CNI shim into every node's CNI conflist and, on request, brings up an OpenVPN/WireGuard/Ziti tunnel inside a session's network namespace.  Requires hostNetwork, hostPID, and a privileged container -- see the subchart's README for why each is load-bearing. This trips the `kasm-disallow-host-namespaces` Kyverno policy by design, the same way `nodePrep` trips the PSS baseline: both are rendered via the `infra` test scenario, which is excluded from the Kyverno gate rather than exempted through it (this repo has no PolicyException mechanism). See docs/egress-installer-port-notes.md in kasm-monorepo for the reviewed risk profile.  Lifecycle: a graceful shutdown -- disabling this in a `helm upgrade`, or `helm uninstall` -- restores every patched conflist from its backup and removes the shim, leaving the node's CNI chain as it was found. A hard crash leaves the chain patched; the replacement pod re-installs and re-verifies it on start. The residual risk is the window with no daemon running: the chained shim fails CNI ADD on that node until the DaemonSet restarts it, so a sustained crash-loop still blocks new pod scheduling there.  See the `kasm-egress-installer` chart for its values (`distro`, `cniBinDir`, `cniConfDirs`, `socketDir`, ...).  |
| egressInstaller.enabled | bool | `false` | Install the egress installer DaemonSet with this release.  |
| egressInstaller.nameOverride | string | `"kasm-egress-installer"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and `egressInstaller` is not a valid RFC 1123 name, so without this the chart would render resource names Kubernetes rejects.  |
| extraObjects | list | `[]` | Deploy additional Kubernetes manifests alongside this release. This field is expected to be either a list of strings or a list of objects. Each entry is rendered through `tpl`, so Helm templating may be used inside it.  |
| global | object | `{"cattle":{"systemDefaultRegistry":""}}` | Values Helm shares with every chart in a release, this chart's six Kasm subcharts included. Rancher fills in `global.cattle.*` on every install from its catalog; nothing here needs to be set by hand. |
| global.cattle.systemDefaultRegistry | string | `""` | The registry Rancher configured as the cluster's system default registry (air-gapped and mirrored clusters). When set, it replaces the registry part of every image the six Kasm subcharts render and their per-image `registry` values are ignored, following Rancher's convention. The three third-party dependencies (`csiRclone`, `gpuOperator`, `nfs-server-provisioner`) do not read it; point their own image values at the mirror. Rancher sets it on install from its catalog; leave it empty everywhere else. |
| gpuOperator | object | `{"enabled":false}` | The NVIDIA GPU Operator (`gpu-operator`, alias `gpuOperator`). Third-party chart, not maintained by Kasm.  Installs the NVIDIA drivers, the container toolkit, and the device plugin so that GPU nodes advertise `nvidia.com/gpu` and CUDA workloads run inside workspace pods.  Installing the operator alone does not make Kasm request GPUs. Also set `agent.gpu.enabled=true`, which adds `KASM_GPU_OPERATOR_ENABLED` to the agent so it schedules GPU workspaces against the advertised resource.  Everything nested under `gpuOperator` other than `enabled` is passed straight through to the upstream chart; run `helm show values nvidia/gpu-operator --version v26.7.0` for the full reference. Note that the operator is cluster-scoped, so install it once per cluster.  |
| gpuOperator.enabled | bool | `false` | Install the NVIDIA GPU Operator with this release. Leave disabled when the operator is already installed in the cluster, or when the nodes' GPU drivers are managed outside Kubernetes.  |
| networkPolicies | object | `{"apiServer":{"cidr":"0.0.0.0/0","ports":[6443,443]},"cilium":{"enabled":false},"enabled":false,"extraPolicies":[],"manager":{"cidr":"0.0.0.0/0","inCluster":{"namespace":"","podSelector":{"app.kubernetes.io/component":"proxy"}},"ports":[443,80,8080]},"otelBackend":{"cidr":"0.0.0.0/0","ports":[4317,4318,9000]},"sessionProxy":{"from":[],"ports":[4444,4445]}}` | Baseline namespace-scoped NetworkPolicies for the release namespace.  These are a starting point for isolating the Kasm namespace: a default deny, then narrow allowances for DNS, intra-namespace traffic, the Kubernetes API server, the Kasm manager, inbound session proxy traffic, and the OpenTelemetry backend. The operator additionally stamps its own per-workspace NetworkPolicies at runtime for workspace network isolation; those are unaffected by anything here.  NetworkPolicy objects are inert unless the cluster CNI enforces them (Calico, Cilium, Antrea, Weave, and the managed equivalents do; the default kubenet and some managed CNIs do not).  |
| networkPolicies.apiServer | object | `{"cidr":"0.0.0.0/0","ports":[6443,443]}` | Egress to the Kubernetes API server, which the operator, the agent, and the device plugins all need.  |
| networkPolicies.apiServer.cidr | string | `"0.0.0.0/0"` | The CIDR the API server endpoint falls in. The default allows any destination on the ports below, because the API server address varies by cluster and is often outside the cluster network. Tighten it to the API server endpoint (or the control plane subnet) once known — `kubectl get endpoints kubernetes -n default` shows it.  |
| networkPolicies.apiServer.ports | list | `[6443,443]` | The TCP ports the API server is reachable on.  |
| networkPolicies.cilium | object | `{"enabled":false}` | Cilium companion to the baseline. A Kubernetes NetworkPolicy ipBlock cannot reach the API server on Cilium when it runs on the nodes: Cilium matches nodes and the kube-apiserver entity by identity, never by CIDR, unless the cluster runs `policyCIDRMatchMode: nodes`. Without one of the two the operator loses the API server the moment the baseline lands and crash-loops on leader election.  |
| networkPolicies.cilium.enabled | bool | `false` | Render a CiliumNetworkPolicy allowing egress to the `kube-apiserver` entity on `networkPolicies.apiServer.ports`. Needs the cilium.io/v2 CRDs.  |
| networkPolicies.enabled | bool | `false` | Render the baseline NetworkPolicies. Off by default because a default-deny policy in a namespace whose CNI does not enforce NetworkPolicy is misleading, and in a namespace whose CNI does enforce it can cut off traffic this chart cannot anticipate.  |
| networkPolicies.extraPolicies | list | `[]` | Additional NetworkPolicy manifests to render alongside the baseline set. Each entry is a complete manifest, either as a string or as an object, and is rendered through `tpl` so Helm templating may be used inside it.  Example:   extraPolicies:     - |       apiVersion: networking.k8s.io/v1       kind: NetworkPolicy       metadata:         name: {{ .Release.Name }}-allow-registry-egress       spec:         podSelector: {}         policyTypes:           - Egress         egress:           - to:               - ipBlock:                   cidr: 10.20.0.0/16             ports:               - protocol: TCP                 port: 443  |
| networkPolicies.manager | object | `{"cidr":"0.0.0.0/0","inCluster":{"namespace":"","podSelector":{"app.kubernetes.io/component":"proxy"}},"ports":[443,80,8080]}` | Egress to the Kasm manager this agent registers with. Covers the agent's registration and heartbeat traffic, and workspace uploads back to the manager.  |
| networkPolicies.manager.cidr | string | `"0.0.0.0/0"` | The CIDR the Kasm manager falls in. The default allows any destination on the ports below; tighten it to the manager's address or its load balancer subnet when that is a stable value.  |
| networkPolicies.manager.inCluster | object | `{"namespace":"","podSelector":{"app.kubernetes.io/component":"proxy"}}` | When the control plane runs in this cluster, name its namespace here to add a selector-based egress peer to its proxy pods next to the ipBlock rule. Cilium never matches a pod through an ipBlock, so without this the agent's heartbeats to an in-cluster manager are dropped there; on every CNI it is also the narrower rule. Leave the namespace empty when the manager is outside the cluster.  |
| networkPolicies.manager.inCluster.podSelector | object | `{"app.kubernetes.io/component":"proxy"}` | Labels that select the control-plane proxy pods in that namespace; the kasm-helm chart's proxy carries this one.  |
| networkPolicies.manager.ports | list | `[443,80,8080]` | The TCP ports the Kasm manager is reachable on. Policy evaluation happens AFTER destination NAT: when the manager is reached through its public hostname and that resolves to a node running hostPort/ServiceLB-style ingress (k3s + Traefik), the connection's effective destination is the ingress controller's backend pod port — add it here (Traefik's websecure is 8443) or agent heartbeats fail with "connection refused" and the manager reports no agent slots.  |
| networkPolicies.otelBackend | object | `{"cidr":"0.0.0.0/0","ports":[4317,4318,9000]}` | Egress to the telemetry backends the OpenTelemetry collector exports to. Those backends are external to this chart.  |
| networkPolicies.otelBackend.cidr | string | `"0.0.0.0/0"` | The CIDR the telemetry backends fall in. Leave as the default when the backend is outside the cluster and its address is not fixed; set it to the backend namespace's pod CIDR, or drop the ports you do not use, to tighten it.  |
| networkPolicies.otelBackend.ports | list | `[4317,4318,9000]` | The TCP ports the telemetry backends listen on. The defaults are OTLP gRPC (4317), OTLP HTTP (4318), and the ClickHouse native protocol (9000).  |
| networkPolicies.sessionProxy | object | `{"from":[],"ports":[4444,4445]}` | Inbound traffic to the session proxy, which is what users' browsers connect to for a workspace session.  |
| networkPolicies.sessionProxy.from | list | `[]` | The peers allowed to reach the session proxy, as a list of raw NetworkPolicy peer objects (`ipBlock`, `namespaceSelector`, `podSelector`). Empty means from anywhere, which is usually what is wanted when an ingress controller or a cloud load balancer fronts the proxy and its source addresses are not predictable.  Example:   from:     - namespaceSelector:         matchLabels:           kubernetes.io/metadata.name: ingress-nginx  |
| networkPolicies.sessionProxy.ports | list | `[4444,4445]` | The TCP ports the session proxy accepts connections on. Must match the session proxy's listeners; change both together.  |
| nfs-server-provisioner | object | `{"enabled":false}` | The in-cluster NFS server provisioner (`nfs-server-provisioner`, un-aliased: the upstream chart names its resources after the chart name and has no nameOverride support, so a camelCase alias would render invalid object names). Third-party chart, not maintained by Kasm.  Provides a ReadWriteMany StorageClass backed by a single in-cluster NFS server, for clusters that have no RWX-capable CSI driver of their own. Persistent user profiles need RWX, so this is a convenient starting point — but it is a single point of failure and is not a substitute for a managed RWX filesystem (EFS, Azure Files, CephFS, a real NFS appliance) in production.  Everything nested under `nfs-server-provisioner` other than `enabled` is passed straight through to the upstream chart; run `helm show values nfs-ganesha/nfs-server-provisioner --version 1.8.0` for the full reference.  |
| nfs-server-provisioner.enabled | bool | `false` | Install the in-cluster NFS server provisioner with this release.  |
| nodePrep | object | `{"enabled":false,"nameOverride":"kasm-node-prep"}` | Node preparation (`kasm-node-prep` subchart, alias `nodePrep`). Runs a privileged DaemonSet that builds and loads host kernel modules: `v4l2loopback` for webcam passthrough and `wireguard` for VPN egress on kernels older than 5.6.  The same DaemonSet also carries the optional node tuning under `nodePrep.tuning.*` — a disk swapfile (`tuning.swap`) and kernel tunables (`tuning.sysctls`) — which are off by default and are a reason to enable this subchart even on nodes whose image already ships every kernel module. See "Workspace node best practices" in this chart's README; `tuning.swap` additionally requires the node's kubelet to be configured for swap first.  This subchart needs privileged pods with host access, so the namespace must permit the `privileged` Pod Security Standard. Leave it disabled unless webcam, WireGuard egress or node tuning is used.  See the `kasm-node-prep` chart for its values (`modules.v4l2loopback.enabled`, `modules.v4l2loopback.videoDevices`, `modules.v4l2loopback.exclusiveCaps`, `modules.wireguard.enabled`, `tuning.swap.enabled`, `tuning.sysctls.enabled`, `secureBoot.existingMokSecret`, `nodeSelector`, ...). On OpenShift, `nodePrep.openshift.scc.enabled` grants its ServiceAccount the `privileged` SCC.  |
| nodePrep.enabled | bool | `false` | Install the privileged node preparation DaemonSet with this release.  |
| nodePrep.nameOverride | string | `"kasm-node-prep"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and `nodePrep` is not a valid RFC 1123 name, so without this the chart would render resource names Kubernetes rejects.  |
| operator | object | `{"enabled":true,"nameOverride":"kasm-agent-operator"}` | The Kasm agent operator (`kasm-agent-operator` subchart, alias `operator`). Installs the Kasm CustomResourceDefinitions, the cluster RBAC, and the controller-manager that reconciles Agent, KasmWorkspace, and KasmImagePuller resources.  The operator is a cluster singleton: it owns fixed-name ClusterRoles and cluster-scoped CRDs, so only one release per cluster may enable it. Disable it here when the operator is already installed by another release and this release only adds an agent instance.  The CRDs themselves come from the operator chart's `crds/` directory, a Helm `crds/` special directory: Helm installs them on first install and never upgrades or removes them again, and there is no values toggle for this. To have Helm own CRD upgrades instead, install the `kasm-agent-crds` chart as its own release before this one, and upgrade it before this one thereafter -- see `charts/kasm-agent-crds/README.md`.  See the `kasm-agent-operator` chart for its values (`serviceAccount.name`, `rbac.aggregateRoles`, `leaderElect`, `otel.enabled`, `otel.endpoint`, `image.*`, `resources`, ...).  |
| operator.enabled | bool | `true` | Install the Kasm agent operator with this release.  |
| operator.nameOverride | string | `"kasm-agent-operator"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, so without this the operator's resources would be named after `operator` rather than after `kasm-agent-operator`. Leave it alone unless you know why you are changing it.  |
| otelCollector | object | `{"enabled":true,"nameOverride":"kasm-otel-collector"}` | The Kasm OpenTelemetry collector (`kasm-otel-collector` subchart, alias `otelCollector`). Receives OTLP traces, metrics, and logs from the operator, the agent, and workspace pods on ports 4317 (gRPC) and 4318 (HTTP), optionally watches Kubernetes events, and forwards everything to the telemetry backends you point it at.  The backends themselves (an LGTM stack, ClickHouse, a vendor OTLP endpoint) are external to this chart — the collector's exporters reference them, this chart never installs them. By default no backend is configured: `exporters.otlp` and `exporters.clickhouse` are disabled and `exporters.debug` is enabled, so a fresh install logs telemetry to the collector's own stdout instead of guessing at a backend that may not exist. Set `otelCollector.exporters.otlp.endpoint` (and enable it) and/or `otelCollector.exporters.clickhouse.*` to ship telemetry somewhere real.  See the `kasm-otel-collector` chart for its values (`receivers.k8sEvents.enabled`, `exporters.otlp.*`, `exporters.clickhouse.*`, `exporters.debug.enabled`, `configOverride`, `image.*`, `resources`, ...).  |
| otelCollector.enabled | bool | `true` | Install the Kasm OpenTelemetry collector with this release. Disable it when workspace telemetry is not wanted, or when the agent and operator should point at a collector that already exists in the cluster.  |
| otelCollector.nameOverride | string | `"kasm-otel-collector"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and both the operator and the agent default their OTLP endpoint to `http://<release>-kasm-otel-collector:4318` — so without this the collector Service would be named after `otelCollector` and nothing would find it.  |
| videoDevicePlugin | object | `{"enabled":false,"nameOverride":"kasm-video-device-plugin"}` | The Kasm video device plugin (`kasm-video-device-plugin` subchart, alias `videoDevicePlugin`). Advertises the `/dev/video*` devices on each node as a scheduleable extended resource (`kasm.com/video` by default) so workspace pods can request a webcam.  The plugin only advertises devices that already exist. Pair it with `nodePrep.enabled` and `nodePrep.modules.v4l2loopback.enabled` unless the nodes provide real capture devices.  See the `kasm-video-device-plugin` chart for its values (`devicePrefix`, `maxDevices`, `resourceName`, `nodeSelector`, ...). On OpenShift, `videoDevicePlugin.openshift.scc.enabled` grants its ServiceAccount the `privileged` SCC.  |
| videoDevicePlugin.enabled | bool | `false` | Install the video device plugin DaemonSet with this release.  |
| videoDevicePlugin.nameOverride | string | `"kasm-video-device-plugin"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and `videoDevicePlugin` is not a valid RFC 1123 name, so without this the chart would render resource names Kubernetes rejects.  |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |
