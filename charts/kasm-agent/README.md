# kasm-agent

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Umbrella chart for the Kasm Workspaces Kubernetes agent: operator, telemetry collector, agent instance, and optional per-feature cluster infrastructure

**Homepage:** <https://kasm.com>

A Kasm *agent* is the half of a Kasm Workspaces deployment that actually runs user sessions. It
registers with a Kasm *manager* (installed separately by the `kasm-helm` chart, or already running
elsewhere — including a Kasm-hosted one), and from then on the manager schedules workspaces into
this cluster. This umbrella chart installs everything an agent needs on the Kubernetes side, plus
the optional cluster infrastructure that individual Kasm features depend on.

> New to this? The [repository README](../../README.md#quickstart) has the shortest path from
> nothing to one running session. This page is the full reference for everything below that.

## What this chart installs

Each dependency is aliased, so every value below is set as `<alias>.<subchart value>`.

| Alias | Chart | Default | What it is |
| ----- | ----- | ------- | ---------- |
| `operator` | `kasm-agent-operator` | enabled | The CRDs, cluster RBAC, and controller-manager that reconcile `Agent`, `KasmWorkspace`, `KasmImagePuller`, `WarmPool`, and `WarmPoolInstance` resources. |
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
  them. Point `otelCollector.exporters.otlp.endpoint` and/or `otelCollector.exporters.clickhouse.*`
  at backends you already run.
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

Required for every install, regardless of which features you turn on:

* Kubernetes 1.26+ (or OpenShift 4.10+) — the shared floor for the whole agent family (this umbrella and its six Kasm subcharts: operator, agent instance, telemetry collector, node prep, video device plugin, egress installer), set by the Gateway API v1 route types and the operator's CRDs
* Helm 3
* A default StorageClass with dynamic provisioning
* Working in-pod DNS resolution (CoreDNS)
* A reachable Kasm manager, and a registration token issued by it

The control-plane `kasm-helm` chart, installed separately, has a lower floor of Kubernetes 1.24+.

## Quickstart

The chart needs five things it cannot guess: which manager to register with, a token to register
with, the hostname users will reach this agent's sessions on, a TLS certificate for the session
proxy, and one way to publish that proxy to the internet.

Create the namespace, the manager token (as a Secret, rather than a value that lands in the release
history), and the session proxy's certificate:

```console
kubectl create namespace kasm-agent

kubectl create secret generic kasm-manager-token \
  --namespace kasm-agent \
  --from-literal=token='<registration token from the Kasm manager>'

kubectl create secret tls kasm-agent-tls \
  --namespace kasm-agent \
  --cert=tls.crt --key=tls.key
```

Then a minimal `values.yaml`:

```yaml
agent:
  manager:
    # The Kasm manager this agent registers with.
    hostname: kasm.example.com
    existingTokenSecret: kasm-manager-token
  # The hostname users' browsers reach this agent's session proxy on. It must differ from the
  # manager's hostname and share a parent domain with it.
  publicHostname: sessions.example.com
  sessionProxy:
    # A kubernetes.io/tls Secret that already exists in the release namespace.
    certSecretName: kasm-agent-tls
  # Publish the session proxy. Enable exactly ONE of ingress / httpRoute / gatewayRoute /
  # tlsRoute / route — see "External access" below.
  ingress:
    enabled: true
    className: nginx
    annotations:
      # The one tuning value that is not optional: ingress-nginx cuts an idle websocket at 60s,
      # so without these every session dies about a minute in.
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    tls:
      - secretName: kasm-agent-tls
        hosts:
          - sessions.example.com
```

Nothing else has to be set. `agent.zone` defaults to `default`, the zone a fresh `kasm-helm`
install seeds — name yours only if it differs. `agent.manager.tokenSecretKey` defaults to `token`,
the key the `kubectl create secret` above writes.

Install from a checkout of this repository. The six Kasm subcharts are `file://` dependencies, so
they have to be staged into `charts/` first:

```console
helm dependency build charts/kasm-agent

helm install kasm-agent charts/kasm-agent \
  --namespace kasm-agent \
  --values values.yaml
```

This chart is also published as an OCI artifact with every dependency embedded, which removes the
checkout and the dependency build. Publishing a developer preview is a manual decision (see
[Publishing](#publishing)), so check that the version you want is there before relying on it:

```console
helm install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
  --version 0.1.0 \
  --namespace kasm-agent \
  --values values.yaml
```

Confirm the agent registered — `PHASE` reaches `Ready` once the manager has acknowledged it:

```console
kubectl get agents.agent.kasm.com -n kasm-agent
```

Then, in the Kasm admin UI, **Infrastructure** → the new agent → **Enable**; agents register
disabled. Post-install notes, including any cross-feature warnings, are available at any time with
`helm get notes kasm-agent -n kasm-agent`.

Either command installs the operator's five CustomResourceDefinitions from its `crds/` directory,
which Helm creates on install and then never upgrades — so a later `helm upgrade` of this release
does not pick up a CRD schema change. If you would rather Helm owned that lifecycle, install the
[`kasm-agent-crds`](../kasm-agent-crds) chart as its own release **before** this one, and upgrade it
before this one thereafter; otherwise apply schema changes out of band with
`kubectl apply --server-side -f charts/kasm-agent-operator/crds/`. Both paths, and the procedure for
adopting CRDs a previous install already created, are covered in
[`charts/kasm-agent-operator/README.md`](../kasm-agent-operator/README.md#customresourcedefinition-lifecycle).

Instead of supplying `agent.sessionProxy.certSecretName` yourself, you can have cert-manager issue
and renew the certificate:

```yaml
agent:
  sessionProxy:
    certificate:
      enabled: true
      issuerRef:
        kind: ClusterIssuer
        name: letsencrypt-prod
      dnsNames:
        - sessions.example.com
```

Users' browsers connect to the session proxy directly, so its certificate has to be trusted by the
client — a cluster-internal CA is not enough.

`agent.manager.token` accepts the token inline if you would rather not pre-create a Secret, but the
value then lives in your release history in plain text.

A fuller, copy-paste-ready values file for a lab cluster — with commented variants — is checked in
as [`dev-cluster-values.yaml`](../../examples/kasm-agent/dev-cluster-values.yaml).

## Running alongside the kasm-helm control plane

The control plane (the `kasm-helm` chart) and this chart can share one cluster. The control plane
creates no cluster-scoped objects at all — no CRDs, no ClusterRoles, no ClusterRoleBindings — so
nothing it installs can collide with the `agent.kasm.com` / `pools.kasm.ai` CRDs and the cluster RBAC
this chart's operator owns. Two namespaces (one per release) is the recommended layout, but even a
**single shared namespace** works — the two charts' resource names and label selectors are fully
disjoint, and it lets the agent reference the control plane's token Secret directly
(`agent.manager.existingTokenSecret: <release>-secrets`, `tokenSecretKey: manager-token`) instead of
copying it. Two caveats in shared-namespace mode: the `privileged` Pod Security Standard that
`nodePrep`/`videoDevicePlugin`/`egressInstaller` require then also covers the control-plane pods —
and `egressInstaller` additionally runs in the host PID and network namespaces, so those have to be
permitted there too; and leave the umbrella's `networkPolicies` **disabled** (its baseline models
only the agent stack's flows and would cut the control plane off). No namespace label is needed even
here — see the optional `kasm.com/role=manager` label below.

Four things have to line up between the two releases.

**The zone.** `agent.zone` must name a zone that already exists on the control plane. A fresh
`kasm-helm` install seeds exactly one, named `default`; the control plane's `kasmZones` creates
others. An agent pointed at a zone the manager does not know will not register.

**The registration token.** The control plane generates it as the `manager-token` key of its
`<release>-secrets` Secret. Secrets do not cross namespaces, so copy the value into the agent's
namespace:

```console
kubectl create secret generic kasm-manager-token \
  --namespace kasm-agent \
  --from-literal=token="$(kubectl get secret -n kasm kasm-secrets \
    -o jsonpath='{.data.manager-token}' | base64 -d)"
```

The control plane's `kasmSecrets.passwords.manager-token` pins it to a known value at install time
instead, if you would rather not read it back afterwards.

**The manager address.** Point `agent.manager.hostname` at the control plane's `publicAddr` and
leave `agent.manager.pathPrefix` at its `/manager_api` default — that is the path the control
plane's proxy routes to the manager. Only when addressing the manager Service directly should
`pathPrefix` be emptied.

**Distinct hostnames.** The control plane's `publicAddr` and this chart's `agent.publicHostname`
front different services and must be different names. Both usually terminate on the same ingress
controller or Gateway, so give each its own hostname and certificate rather than sharing a listener;
where a Gateway restricts `allowedRoutes` by namespace, admit both namespaces.

**The `kasm.com/role=manager` label is optional.** The operator's default per-workspace
NetworkPolicy admits ingress from the session proxy **by podSelector** (verified against the
stamped policy on a live deployment), and all session and manager traffic flows through the
session proxy — so sessions work with no namespace labels in every topology, including a
manager in another cluster (where a namespaceSelector could never match anyway). Label the
manager's namespace `kasm.com/role=manager` only if something there genuinely needs *direct*
ingress to workspace pods; the same selector also appears as a workspace egress allow, but
cross-cluster manager egress is covered by the policy's internet catch-all.

Two worked examples ship for this pairing. The recommended **two-namespace** layout is the pair
[`single-cluster-control-plane-values.yaml`](../../examples/kasm-agent/single-cluster-control-plane-values.yaml)
(the `kasm-helm` half) and
[`single-cluster-agent-values.yaml`](../../examples/kasm-agent/single-cluster-agent-values.yaml)
(this chart, with the umbrella's NetworkPolicies enforced). The **single-namespace** layout is the
`kasm-platform` chart driven by
[`platform-values.yaml`](../../examples/kasm-agent/platform-values.yaml). The
[demo runbook](../../examples/kasm-agent/demo-runbook.md) walks the single-command install end to
end.

**The zone must use direct connections, and the auth cookie must reach the agent's hostname.**
Two control-plane defaults break Kubernetes-agent sessions and both must change:

* *Proxy Connections* (zone setting, seeded enabled) routes browser session traffic through the
  control-plane proxy to the agent's address while preserving the original `Host` header — behind
  host-routing ingress (Traefik, most Gateway/Ingress setups) that request matches no route and
  dies as a 404. The Kubernetes agent's session proxy is built to be reached directly (that is
  what `agent.httpRoute` / `agent.ingress` / `agent.route` / `agent.gatewayRoute` / `agent.tlsRoute`
  expose, and what
  `agent.sessionProxy.service` publishes without an ingress layer at all), so disable it, and set the
  zone's *Upstream Auth Address* to the control plane's `publicAddr` (not the `$request_host$`
  default, which would point the session proxy's auth subrequests at the agent's own hostname).
* *Kasm Auth Domain* (global setting, defaults `$request_host$`) scopes the session cookie to the
  control plane's own hostname, so the browser never sends it to `agent.publicHostname` and every
  direct session connection fails with a 401. Set it to a parent domain that covers **both**
  hostnames — pick the two hostnames as siblings under one parent from the start.

On a **fresh** control-plane install both halves are plain `kasm-helm` values — the zone preseed
merges by name and every field passes through, and `kasmConfig.authDomain` writes the auth domain
into the seed (verified live; see
`examples/kasm-agent/single-cluster-control-plane-values.yaml`):

```yaml
kasmZones:
  - name: default
    proxyAddress: kasm.example.com
    proxy_connections: false
    upstream_auth_address: kasm.example.com
kasmConfig:
  generatePreseed: true
  # The parent domain of publicAddr and agent.publicHostname. Applied last against the finished
  # seed file, and independent of generatePreseed.
  authDomain: example.com
```

Reach for `kasmConfig.authDomain` rather than a `kasmConfig.config.settings` entry. Routing
`kasm_auth_domain` through `config.settings` used to be the broken path: the settings preseed
concatenated the two lists instead of upserting, so any setting that already exists in Kasm's
default seed ended up with a duplicate row and every `/api/authenticate` call 500'd with
`MultipleResultsFound`. That merge now upserts on `name` + `category`, so `config.settings` is safe
for seed-existing settings too — but `authDomain` is the supported route for this one, because it
is applied last and therefore wins over both the merge and `existingDefaultPropertiesSecret`.

On an **existing** control plane the preseed does not run at all — it only applies at database
initialization. Change *Kasm Auth Domain* and the two zone settings in the admin UI (Settings →
Auth; Infrastructure → Zones) or via the admin API, where `update_setting` takes top-level
`setting_id` (from `get_settings`) and `value`.

Finally, expose the control plane with its `ingress.enabled` and leave its `proxyService.type` as
`ClusterIP`. A `LoadBalancer` there claims port 443 on the node, which the ingress controller
fronting this chart's session proxy normally already holds — the control plane chart rejects that
combination outright whenever an ingress or route is configured.

## Cluster preparation checklist

Most Kasm features need something from the cluster before they will work. Here is the short list —
the features people turn on most often, and the values that turn them on.
[**What works on Kubernetes**](../../docs/feature-matrix.md) is the full one: every feature, its
status, what the cluster has to supply first, and the limits worth knowing.

| Kasm feature | Value that turns it on |
| ------------ | ---------------------- |
| Persistent profiles | `nfs-server-provisioner.enabled=true` with `nfs-server-provisioner.persistence.enabled=true`, or point Kasm at an RWX StorageClass the cluster already has |
| Cloud storage mappings | `csiRclone.enabled=true` **and** `agent.storageMappings.enabled=true` |
| GPU workspaces | `gpuOperator.enabled=true` **and** `agent.gpu.enabled=true` |
| Webcam passthrough | `nodePrep.enabled=true` with `nodePrep.modules.v4l2loopback.enabled=true`, **and** `videoDevicePlugin.enabled=true`. [KMM mode](../kasm-node-prep/README.md#kmm-mode) builds the module once per kernel instead of on every node |
| Per-session VPN egress | `egressInstaller.enabled=true` with `egressInstaller.distro` ([kasm-egress-installer](../kasm-egress-installer/README.md)) |
| Workspace network isolation | Nothing — the operator stamps a policy per session. `networkPolicies.enabled=true` adds the namespace baseline |
| External access to sessions | Exactly one of `agent.gatewayRoute.enabled=true` (preferred), `agent.tlsRoute.enabled=true`, `agent.httpRoute.enabled=true`, `agent.ingress.enabled=true`, `agent.route.enabled=true` (OpenShift), or `agent.sessionProxy.service.type` |
| Image pre-pulling | `agent.imagePuller.enabled=true` with `agent.imagePuller.images` |
| Private workspace registries | `agent.workspaceImagePullSecrets` |
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

Kasm's own Docker agent installer tunes the host it runs on. A Kubernetes node never runs that
installer, so the tuning has to come from somewhere else — partly from this chart, partly from the
node's kubelet, which no chart can configure. This section is what that adds up to.

| Concern | What Kasm does or recommends | On Kubernetes |
| ------- | ---------------------------- | ------------- |
| **Swap** | The installer creates `/mnt/Kasm.swap` (`fallocate` + `mkswap` + `swapon`) on every agent host, offering a 4/8/12/16 GB menu — `--swap-size 8192` in the docs. "It is imperative to a have a swap file for Kasm to be stable." | `nodePrep.tuning.swap.enabled=true` — **after** the node's kubelet is configured for swap. See below. |
| **Kernel tunables** | Nothing: the installer sets no sysctls. | `nodePrep.tuning.sysctls.enabled=true` raises the inotify limits, which desktop sessions consume heavily. Our judgement, not upstream's. |
| **Image GC** | The agent guards image pulls with `disk_usage_limit: 0.90`. | kubelet `imageGCHighThresholdPercent: 90` / `imageGCLowThresholdPercent: 80`. **Node setting.** |
| **Container logs** | — | kubelet `containerLogMaxSize: 10Mi`, `containerLogMaxFiles: 5`. **Node setting.** |
| **PID exhaustion** | — | kubelet `podPidsLimit` raised (e.g. `8192`). **Node setting.** |
| **Node disk** | `80GB + (Users × space_per_user)`. | Same formula, applied to the volume holding the container runtime's image store. |
| **`/dev/shm`** | Kasm's Docker agent gives each session `512m`. | The operator mounts a memory-backed `emptyDir` at `/dev/shm` per session — 2Gi by default, per-workspace via the `KasmWorkspace` `shmSize` field. Kubernetes' own default would be **64Mi**, which browsers do not survive. |
| **CPU** | CPU Shares by default: a session is "only throttled if there is CPU contention". Cores Override pins a count. | No CPU *limit* on workspace pods — that is the same behaviour. CPU *requests* are the analogue of Cores Override. |

Sources: [System requirements (swap section)](https://docs.kasm.com/docs/explanations/system-requirements/index.html),
[Docker Agent management](https://docs.kasm.com/docs/how-to/infra-autoscale/docker-agent/index.html),
[Sizing and operations](https://docs.kasm.com/docs/explanations/sizing-operations/index.html).

### Swap, and the kubelet setting that must come first

Kasm wants swap so the kernel can park the memory of idle and stopped sessions instead of the OOM
killer destroying a live one: "Not having a swap file can result in user desktops being destroyed
when RAM is over subscribed."

Kubernetes will not use node swap until the **node's kubelet** is configured for it — cgroup v2,
`failSwapOn: false`, and `memorySwap.swapBehavior: LimitedSwap`. The order is not negotiable: a
kubelet still carrying the default `failSwapOn: true` **refuses to start** while the node has swap
active, so enabling swap first quietly arms an outage for the next kubelet restart or node reboot.
`nodePrep` therefore refuses to create swap until it can read that setting out of the node's kubelet
configuration, and says so in its log. Apply
[`examples/kasm-agent/k3s-node-swap-config.yaml`](../../examples/kasm-agent/k3s-node-swap-config.yaml)
on each node first, restart k3s, then set `nodePrep.tuning.swap.enabled=true`.

Two caveats about what a session actually gets:

* `LimitedSwap` gives each **Burstable** pod a share proportional to its memory request:
  `(pod memory request / node MemTotal) × total node swap`. A default workspace (2768Mi) on a 16 GiB
  node with an 8 GiB swapfile gets `2768 / 16384 × 8192 MiB ≈ 1384 MiB`.
* **Workspace sessions get zero swap as the operator configures them today.** The kubelet's
  `LimitedSwap` grants a container swap only when its **memory request is strictly less than its
  memory limit** (a container with request = limit gets none, whatever its QoS class or CPU
  allocation method; Guaranteed and BestEffort pods get none either way). Kasm derives a workspace's
  memory request *and* limit from the same `memory_bytes`, so every session container has request =
  limit and therefore no swap — verified on k3s 1.36 and kubeadm 1.34. The node's swapfile still
  benefits other Burstable pods with memory headroom (the agent, sidecars, system pods). Two further
  gotchas: the kubelet only sees swap it was (re)started *after* the swapfile exists — enabling
  `nodePrep.tuning.swap` on an already-running kubelet needs one more kubelet restart before any pod
  gets a share — and `swapBehavior: LimitedSwap` must be set or every pod's share is zero.

Sizing, the `force` escape hatch, the zram question, and the full rationale are in
[**Node tuning**](../kasm-node-prep/README.md#node-tuning) in the `kasm-node-prep` README.

### Settings this chart cannot make for you

The four kubelet settings marked **Node setting** above are worth changing on any node that hosts
workspaces, and none of them is reachable from Helm — the kubelet is what runs the chart's pods.
They are all in the same example file:

* **`imageGCHighThresholdPercent: 90` / `imageGCLowThresholdPercent: 80`.** The stock 85/80 starts
  garbage-collecting images while the node is still healthy, and a workspace image is multi-GB — every
  eviction is repaid as a slow re-pull at the next session launch. 90 also matches the agent's own
  `disk_usage_limit: 0.90`, so the two stop disagreeing about when the disk is full.
* **`containerLogMaxSize: 10Mi` / `containerLogMaxFiles: 5`.** These are the kubelet's defaults; pin
  them so a chatty session (Xorg, the desktop, the browser) cannot fill the same disk the images live
  on if a distribution has changed them.
* **`podPidsLimit`.** The kubelet default is unlimited-per-pod. One desktop plus one browser is
  already dozens of processes and hundreds of threads, so a runaway session can exhaust the node's
  PIDs; a generous explicit cap (`8192`) contains that without affecting normal use.

### Node sizing

Apply Kasm's disk formula — `80GB + (Users × space_per_user)` — to the volume backing the container
runtime's image store, not to the root filesystem in general. That is where workspace images land, and
image GC (above) is what happens when the estimate is wrong.

For memory, size against concurrent sessions at their memory *limit*, not their request, and leave the
node headroom for the per-session `/dev/shm` `emptyDir`: it is memory-backed, so it counts against the
pod's memory limit **and** toward node memory pressure and eviction. This is the one place where the
Kubernetes default is actively dangerous rather than merely different — 64Mi against Kasm's 512m —
which is why the operator sets 2Gi instead of leaving it alone.

For CPU, leave workspace pods without a CPU limit. That reproduces Kasm's default CPU Shares behaviour
("only throttled if there is CPU contention") rather than throttling an idle-but-bursty desktop; CPU
requests are what actually reserve capacity, and are the analogue of Kasm's Cores Override. On
virtualized nodes, plan for roughly 25% CPU overcommit.

## Airgapped installation

The chart installs with no internet access at all. Four things have to cross the airgap: the chart
archive, the container images, the node-prep build inputs, and — if you enable it — whatever the
GPU Operator needs. Do the first three from a machine that *does* have network access.

### 1. Build the transferable chart artifact

A git clone is **not** enough: three of the nine dependencies (`csi-driver-rclone`, `gpu-operator`,
`nfs-server-provisioner`) are remote, their `.tgz` files are gitignored, and installing from a
checkout still runs `helm dependency build`. A packaged umbrella chart, on the other hand, embeds
every dependency under its own `charts/` directory and is completely self-contained:

```console
make package-agent
# -> dist/kasm-agent-0.1.0.tgz
```

Equivalently, without the Makefile:

```console
helm dependency build charts/kasm-agent
helm package charts/kasm-agent -d dist/
```

Copy that single `.tgz` across, and install from it directly — no repositories are contacted:

```console
helm install kasm-agent ./kasm-agent-0.1.0.tgz \
  --namespace kasm-agent \
  --values values.yaml
```

### 2. Mirror the images

Get the list from the rendered manifests of every test scenario, deduped:

```console
make images-agent
# prints the list and writes dist/kasm-agent-images.txt
```

Then mirror each one (`skopeo copy`, `crane copy`, `docker pull`/`tag`/`push`, or your registry's
own replication) into the internal registry.

Every image in the Kasm charts is split into `registry` / `repository` / `tag`, so pointing the
whole release at a mirror is one override block:

```yaml
operator:
  image:
    registry: registry.example.internal
    repository: kasmweb/kasm-agent-operator

otelCollector:
  image:
    registry: registry.example.internal
    repository: otel/opentelemetry-collector-contrib

agent:
  image:
    registry: registry.example.internal
    repository: kasmweb/kasm-agent-api
  sessionProxy:
    image:
      registry: registry.example.internal
      repository: kasmweb/nginx
      tag: "1.25.3"
    sidecarImage:
      registry: registry.example.internal
      repository: kasmweb/kasm-nginx-sidecar

videoDevicePlugin:
  image:
    registry: registry.example.internal
    repository: kasmweb/kasm-video-device-plugin

nodePrep:
  image:
    registry: registry.example.internal
    repository: kasm/node-prep-builder
    tag: "22.04-v0.13.2"
```

Two image sets are **not** covered by that block and have to be pointed at the internal registry
separately:

* **Workspace images.** These come from the Kasm manager's workspace registry, not from this chart.
  Re-point each workspace's image in the manager UI (or in its workspace registry) at the mirror.
* **`agent.imagePuller.images`.** Every entry's `image` field is a full reference used verbatim, so
  each must already name the internal registry, with `imagePullSecrets` per entry where the mirror
  needs credentials:

  ```yaml
  agent:
    imagePuller:
      enabled: true
      images:
        - image: registry.example.internal/kasmweb/chrome:1.18.0
          registry: https://registry.example.internal
          imagePullSecrets:
            - name: internal-registry
  ```

  The image-puller mechanism itself pulls through the node's container runtime, so it works against
  a mirror configured either here in values or at the runtime level (containerd
  `registry.mirrors`/`hosts.toml`, CRI-O `registries.conf`) — in the latter case the references may
  keep their original names and the runtime rewrites them.

### 3. Node prep: use a pre-baked builder image

`nodePrep` is the one component that fetches at *runtime*: `apt-get` for the toolchain and headers,
`git clone` for the module sources. Both go away with a builder image that already carries them,
plus `nodePrep.modules.*.sourcePath` pointing at the vendored sources inside it. The reconcile
script detects the pre-baked case, logs `build prerequisites already present; skipping package
installation`, and performs no network operation.

See **Airgapped / offline nodes** in the [`kasm-node-prep` README](../kasm-node-prep/README.md) for
the Dockerfile pattern and the values, including the caveat that the kernel build tree has to come
from the node image (`/lib/modules` and `/usr/src` are host mounts and shadow the builder image).

If instead you delegate `v4l2loopback` to the Kernel Module Management operator
(`nodePrep.modules.v4l2loopback.method=kmm`), the airgap path is different — KMM only *pulls* prebuilt
per-kernel module images, and the operator's own images are mirrored with `make kmm-install-mirrored
KMM_IMAGE_REGISTRY=<mirror>` — and is covered end to end by
**[Airgapped KMM (prebuilt modules)](../kasm-node-prep/README.md#airgapped-kmm-prebuilt-modules)** in the
`kasm-node-prep` README.

### 4. Third-party subcharts

* **`csi-driver-rclone`** — four images, each overridable on its own value path:
  `csiRclone.image.rclone.repository` (plus `.tag`), `csiRclone.image.csiProvisioner.repository`,
  `csiRclone.image.livenessProbe.repository`, `csiRclone.image.nodeDriverRegistrar.repository`.
  Note these are `repository`-only (the registry is part of the repository string) and take an
  optional sibling `tag`. Add pull secrets with `csiRclone.imagePullSecrets`.
* **`nfs-server-provisioner`** — one image: `nfs-server-provisioner.image.repository` and
  `nfs-server-provisioner.image.tag` (again, registry included in the repository string).
* **`gpu-operator`** — do **not** try to do this from the image list above. The operator pulls a
  much larger set of operand images (driver, container toolkit, DCGM, MIG manager, device plugin,
  …) at runtime, and NVIDIA publishes a dedicated procedure covering the local registry, the driver
  images per kernel, and the required values:
  [Install the GPU Operator in an air-gapped environment](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-air-gapped.html).
  Everything nested under `gpuOperator` is passed straight to that chart, so its air-gap values
  apply as-is with the `gpuOperator.` prefix.

Run `helm show values` against a staged dependency for the full third-party reference, for example
`helm show values charts/kasm-agent/charts/csi-driver-rclone-0.5.0.tgz`.

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

Releases go to `oci://registry-1.docker.io/kasmweb/`, the same registry and namespace the
`kasm-helm` control plane chart is published to. Four of the ten charts in this repo are published
as standalone releases — built by the `helm-build-agent` GitLab job on `develop` and `release/*`,
then pushed by the manual `helm-deploy-agent-docker-hub` job:

* **`kasm-agent`** — this chart, with all nine dependencies embedded.
* **`kasm-platform`** — the control plane and this chart composed into one release.
* **`kasm-agent-crds`** — the five CRDs as ordinary templates, for fleets that upgrade CRD schemas
  through Helm rather than the `kubectl` side channel.
* **`kasm-egress-installer`** — the CNI shim, which a platform team may want to roll out on a
  cluster running nothing else from Kasm.

The other five charts are only ever consumed as subcharts of this one and travel inside its
archive, so publishing them separately would offer a release nobody should install on its own.

**`make deps-agent` has to run before any packaging, and it builds inside-out.** `helm package`
does not resolve dependencies — it archives whatever the chart's `charts/` directory already
holds. `deps-agent` stages `charts/kasm-agent` first and only then `charts/kasm-platform`, which
archives `kasm-agent` off disk and would otherwise embed a copy missing all nine of its own
dependencies:

```console
make deps-agent package-agent-all
# -> dist/kasm-agent-0.1.0.tgz + the other three
```

**Every `file://` version pin is maintained by hand, and a stale one is only half-loud.** This
chart pins its six local subcharts at an exact version, and `kasm-platform` pins `kasm-helm` and
`kasm-agent` the same way. Bump a subchart without bumping the pin that names it and `helm
dependency build` refuses it — but `helm package` against an already-staged `charts/` directory
exits 0 and embeds the *old* archive, so the published umbrella ships the subchart the release was
meant to replace. `make version-check-agent` is the guard; it runs inside `make test` and again at
the top of the CI package job. The fix moves the chart and every pin naming it in one step:

```console
python3 scripts/agent_versions.py --bump kasm-agent-instance 0.2.0            # dry run
python3 scripts/agent_versions.py --bump kasm-agent-instance 0.2.0 --write
helm dependency update charts/kasm-agent charts/kasm-platform                 # refresh Chart.lock
```

At `0.1.0` / appVersion `develop` these are previews rather than a moving release line, so
every build produces the same version. The publish job therefore refuses to overwrite a version
already present in the registry; re-pushing one takes `FORCE_REPUBLISH=true` on the pipeline, which
makes replacing a published preview a deliberate act.

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://../kasm-agent-instance | agent(kasm-agent-instance) | 0.1.0 |
| file://../kasm-agent-operator | operator(kasm-agent-operator) | 0.1.0 |
| file://../kasm-egress-installer | egressInstaller(kasm-egress-installer) | 0.1.0 |
| file://../kasm-node-prep | nodePrep(kasm-node-prep) | 0.1.0 |
| file://../kasm-otel-collector | otelCollector(kasm-otel-collector) | 0.1.0 |
| file://../kasm-video-device-plugin | videoDevicePlugin(kasm-video-device-plugin) | 0.1.0 |
| https://helm.ngc.nvidia.com/nvidia | gpuOperator(gpu-operator) | v26.7.0 |
| https://kubernetes-sigs.github.io/nfs-ganesha-server-and-external-provisioner/ | nfs-server-provisioner | 1.8.0 |
| oci://ghcr.io/veloxpack/charts | csiRclone(csi-driver-rclone) | 0.5.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent | object | `{"enabled":true,"nameOverride":"kasm-agent-instance"}` | The Kasm agent instance (`kasm-agent-instance` subchart, alias `agent`). Creates the Agent custom resource that registers this cluster as a Kasm deployment zone, plus the session proxy that terminates workspace connections.  This is the only subchart with required values. At a minimum set `agent.manager.hostname`, a manager token (`agent.manager.token` or `agent.manager.existingTokenSecret`), and `agent.publicHostname`, and either supply a session proxy TLS Secret through `agent.sessionProxy.certSecretName` or let cert-manager issue one with `agent.sessionProxy.certificate.enabled`.  See the `kasm-agent-instance` chart for its values (`name`, `image.*`, `manager.*`, `publicHostname`, `publicPort`, `zone`, `sessionProxy.*`, `otel.*`, `gpu.enabled`, `storageMappings.*`, `imagePuller.*`, `httpRoute.*`, `env`, ...).  |
| agent.enabled | bool | `true` | Install the Kasm agent instance with this release. Disable it to install only the operator and cluster infrastructure, and create Agent resources separately.  |
| agent.nameOverride | string | `"kasm-agent-instance"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, so without this the agent's satellite objects would be named after `agent` rather than after `kasm-agent-instance`.  |
| csiRclone | object | `{"enabled":false}` | The Veloxpack rclone CSI driver (`csi-driver-rclone`, pulled from `oci://ghcr.io/veloxpack/charts`, alias `csiRclone`). Third-party chart, not maintained by Kasm.  The driver provisions StorageClasses for the CSI driver `rclone.csi.veloxpack.io`, which mounts object storage and other rclone remotes (S3, GCS, Azure Blob, WebDAV, SFTP, ...) into workspace pods. It is what backs Kasm cloud storage mappings, so enable it alongside `agent.storageMappings.enabled` — the StorageClass names created here are the ones referenced by the storage mappings configured in the Kasm manager UI.  Nodes must have the FUSE kernel module available for rclone mounts to work.  Everything nested under `csiRclone` other than `enabled` is passed straight through to the upstream chart; run `helm show values oci://ghcr.io/veloxpack/charts/csi-driver-rclone --version 0.5.0` for the full reference.  |
| csiRclone.enabled | bool | `false` | Install the rclone CSI driver with this release. Leave disabled when the driver is already installed in the cluster, or when cloud storage mappings are not used.  |
| egressInstaller | object | `{"enabled":false,"nameOverride":"kasm-egress-installer"}` | The Kasm egress installer (`kasm-egress-installer` subchart, alias `egressInstaller`). A privileged DaemonSet that chains a CNI shim into every node's CNI conflist and, on request, brings up an OpenVPN/WireGuard/Ziti tunnel inside a session's network namespace.  Requires hostNetwork, hostPID, and a privileged container -- see the subchart's README for why each is load-bearing. This trips the `kasm-disallow-host-namespaces` Kyverno policy by design, the same way `nodePrep` trips the PSS baseline: both are rendered via the `infra` test scenario, which is excluded from the Kyverno gate rather than exempted through it (this repo has no PolicyException mechanism). See docs/egress-installer-port-notes.md in kasm-monorepo for the reviewed risk profile.  Lifecycle (verified live on k3s): a graceful shutdown -- disabling this in a `helm upgrade`, or `helm uninstall` -- restores every patched conflist from its backup and removes the shim, leaving the node's CNI chain as it was found. A hard crash leaves the chain patched; the replacement pod re-installs and re-verifies it on start. The residual risk is the window with no daemon running: the chained shim fails CNI ADD on that node until the DaemonSet restarts it, so a sustained crash-loop still blocks new pod scheduling there.  See the `kasm-egress-installer` chart for its values (`distro`, `cniBinDir`, `cniConfDirs`, `socketDir`, ...).  |
| egressInstaller.enabled | bool | `false` | Install the egress installer DaemonSet with this release.  |
| egressInstaller.nameOverride | string | `"kasm-egress-installer"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and `egressInstaller` is not a valid RFC 1123 name, so without this the chart would render resource names Kubernetes rejects.  |
| extraObjects | list | `[]` | Deploy additional Kubernetes manifests alongside this release. This field is expected to be either a list of strings or a list of objects. Each entry is rendered through `tpl`, so Helm templating may be used inside it.  |
| gpuOperator | object | `{"enabled":false}` | The NVIDIA GPU Operator (`gpu-operator`, alias `gpuOperator`). Third-party chart, not maintained by Kasm.  Installs the NVIDIA drivers, the container toolkit, and the device plugin so that GPU nodes advertise `nvidia.com/gpu` and CUDA workloads run inside workspace pods.  Installing the operator alone does not make Kasm request GPUs. Also set `agent.gpu.enabled=true`, which adds `KASM_GPU_OPERATOR_ENABLED` to the agent so it schedules GPU workspaces against the advertised resource.  Everything nested under `gpuOperator` other than `enabled` is passed straight through to the upstream chart; run `helm show values nvidia/gpu-operator --version v26.7.0` for the full reference. Note that the operator is cluster-scoped, so install it once per cluster.  |
| gpuOperator.enabled | bool | `false` | Install the NVIDIA GPU Operator with this release. Leave disabled when the operator is already installed in the cluster, or when the nodes' GPU drivers are managed outside Kubernetes.  |
| networkPolicies | object | `{"apiServer":{"cidr":"0.0.0.0/0","ports":[6443,443]},"enabled":false,"extraPolicies":[],"manager":{"cidr":"0.0.0.0/0","ports":[443,80]},"otelBackend":{"cidr":"0.0.0.0/0","ports":[4317,4318,9000]},"sessionProxy":{"from":[],"ports":[4444,4445]}}` | Baseline namespace-scoped NetworkPolicies for the release namespace.  These are a starting point for isolating the Kasm namespace: a default deny, then narrow allowances for DNS, intra-namespace traffic, the Kubernetes API server, the Kasm manager, inbound session proxy traffic, and the OpenTelemetry backend. The operator additionally stamps its own per-workspace NetworkPolicies at runtime for workspace network isolation; those are unaffected by anything here.  NetworkPolicy objects are inert unless the cluster CNI enforces them (Calico, Cilium, Antrea, Weave, and the managed equivalents do; the default kubenet and some managed CNIs do not).  |
| networkPolicies.apiServer | object | `{"cidr":"0.0.0.0/0","ports":[6443,443]}` | Egress to the Kubernetes API server, which the operator, the agent, and the device plugins all need.  |
| networkPolicies.apiServer.cidr | string | `"0.0.0.0/0"` | The CIDR the API server endpoint falls in. The default allows any destination on the ports below, because the API server address varies by cluster and is often outside the cluster network. Tighten it to the API server endpoint (or the control plane subnet) once known — `kubectl get endpoints kubernetes -n default` shows it.  |
| networkPolicies.apiServer.ports | list | `[6443,443]` | The TCP ports the API server is reachable on.  |
| networkPolicies.enabled | bool | `false` | Render the baseline NetworkPolicies. Off by default because a default-deny policy in a namespace whose CNI does not enforce NetworkPolicy is misleading, and in a namespace whose CNI does enforce it can cut off traffic this chart cannot anticipate.  |
| networkPolicies.extraPolicies | list | `[]` | Additional NetworkPolicy manifests to render alongside the baseline set. Each entry is a complete manifest, either as a string or as an object, and is rendered through `tpl` so Helm templating may be used inside it.  Example:   extraPolicies:     - |       apiVersion: networking.k8s.io/v1       kind: NetworkPolicy       metadata:         name: {{ .Release.Name }}-allow-registry-egress       spec:         podSelector: {}         policyTypes:           - Egress         egress:           - to:               - ipBlock:                   cidr: 10.20.0.0/16             ports:               - protocol: TCP                 port: 443  |
| networkPolicies.manager | object | `{"cidr":"0.0.0.0/0","ports":[443,80]}` | Egress to the Kasm manager this agent registers with. Covers the agent's registration and heartbeat traffic, and workspace uploads back to the manager.  |
| networkPolicies.manager.cidr | string | `"0.0.0.0/0"` | The CIDR the Kasm manager falls in. The default allows any destination on the ports below; tighten it to the manager's address or its load balancer subnet when that is a stable value.  |
| networkPolicies.manager.ports | list | `[443,80]` | The TCP ports the Kasm manager is reachable on. Policy evaluation happens AFTER destination NAT: when the manager is reached through its public hostname and that resolves to a node running hostPort/ServiceLB-style ingress (k3s + Traefik), the connection's effective destination is the ingress controller's backend pod port — add it here (Traefik's websecure is 8443) or agent heartbeats fail with "connection refused" and the manager reports no agent slots. Verified live.  |
| networkPolicies.otelBackend | object | `{"cidr":"0.0.0.0/0","ports":[4317,4318,9000]}` | Egress to the telemetry backends the OpenTelemetry collector exports to. Those backends are external to this chart.  |
| networkPolicies.otelBackend.cidr | string | `"0.0.0.0/0"` | The CIDR the telemetry backends fall in. Leave as the default when the backend is outside the cluster and its address is not fixed; set it to the backend namespace's pod CIDR, or drop the ports you do not use, to tighten it.  |
| networkPolicies.otelBackend.ports | list | `[4317,4318,9000]` | The TCP ports the telemetry backends listen on. The defaults are OTLP gRPC (4317), OTLP HTTP (4318), and the ClickHouse native protocol (9000).  |
| networkPolicies.sessionProxy | object | `{"from":[],"ports":[4444,4445]}` | Inbound traffic to the session proxy, which is what users' browsers connect to for a workspace session.  |
| networkPolicies.sessionProxy.from | list | `[]` | The peers allowed to reach the session proxy, as a list of raw NetworkPolicy peer objects (`ipBlock`, `namespaceSelector`, `podSelector`). Empty means from anywhere, which is usually what is wanted when an ingress controller or a cloud load balancer fronts the proxy and its source addresses are not predictable.  Example:   from:     - namespaceSelector:         matchLabels:           kubernetes.io/metadata.name: ingress-nginx  |
| networkPolicies.sessionProxy.ports | list | `[4444,4445]` | The TCP ports the session proxy accepts connections on. Must match the session proxy's listeners; change both together.  |
| nfs-server-provisioner | object | `{"enabled":false}` | The in-cluster NFS server provisioner (`nfs-server-provisioner`, un-aliased: the upstream chart names its resources after the chart name and has no nameOverride support, so a camelCase alias would render invalid object names). Third-party chart, not maintained by Kasm.  Provides a ReadWriteMany StorageClass backed by a single in-cluster NFS server, for clusters that have no RWX-capable CSI driver of their own. Persistent user profiles need RWX, so this is a convenient starting point — but it is a single point of failure and is not a substitute for a managed RWX filesystem (EFS, Azure Files, CephFS, a real NFS appliance) in production.  Everything nested under `nfs-server-provisioner` other than `enabled` is passed straight through to the upstream chart; run `helm show values nfs-ganesha/nfs-server-provisioner --version 1.8.0` for the full reference.  |
| nfs-server-provisioner.enabled | bool | `false` | Install the in-cluster NFS server provisioner with this release.  |
| nodePrep | object | `{"enabled":false,"nameOverride":"kasm-node-prep"}` | Node preparation (`kasm-node-prep` subchart, alias `nodePrep`). Runs a privileged DaemonSet that builds and loads host kernel modules: `v4l2loopback` for webcam passthrough and `wireguard` for VPN egress on kernels older than 5.6.  The same DaemonSet also carries the optional node tuning under `nodePrep.tuning.*` — a disk swapfile (`tuning.swap`) and kernel tunables (`tuning.sysctls`) — which are off by default and are a reason to enable this subchart even on nodes whose image already ships every kernel module. See "Workspace node best practices" in this chart's README; `tuning.swap` additionally requires the node's kubelet to be configured for swap first.  This subchart needs privileged pods with host access, so the namespace must permit the `privileged` Pod Security Standard. Leave it disabled unless webcam, WireGuard egress or node tuning is used.  See the `kasm-node-prep` chart for its values (`modules.v4l2loopback.enabled`, `modules.v4l2loopback.videoDevices`, `modules.v4l2loopback.exclusiveCaps`, `modules.wireguard.enabled`, `tuning.swap.enabled`, `tuning.sysctls.enabled`, `secureBoot.existingMokSecret`, `nodeSelector`, ...).  |
| nodePrep.enabled | bool | `false` | Install the privileged node preparation DaemonSet with this release.  |
| nodePrep.nameOverride | string | `"kasm-node-prep"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and `nodePrep` is not a valid RFC 1123 name, so without this the chart would render resource names Kubernetes rejects.  |
| operator | object | `{"enabled":true,"nameOverride":"kasm-agent-operator"}` | The Kasm agent operator (`kasm-agent-operator` subchart, alias `operator`). Installs the Kasm CustomResourceDefinitions, the cluster RBAC, and the controller-manager that reconciles Agent, KasmWorkspace, KasmImagePuller, WarmPool, and WarmPoolInstance resources.  The operator is a cluster singleton: it owns fixed-name ClusterRoles and cluster-scoped CRDs, so only one release per cluster may enable it. Disable it here when the operator is already installed by another release and this release only adds an agent instance.  See the `kasm-agent-operator` chart for its values (`crds.install`, `crds.keep`, `serviceAccount.name`, `rbac.aggregateRoles`, `leaderElect`, `otel.enabled`, `otel.endpoint`, `image.*`, `resources`, ...).  |
| operator.enabled | bool | `true` | Install the Kasm agent operator with this release.  |
| operator.nameOverride | string | `"kasm-agent-operator"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, so without this the operator's resources would be named after `operator` rather than after `kasm-agent-operator`. Leave it alone unless you know why you are changing it.  |
| otelCollector | object | `{"enabled":true,"nameOverride":"kasm-otel-collector"}` | The Kasm OpenTelemetry collector (`kasm-otel-collector` subchart, alias `otelCollector`). Receives OTLP traces, metrics, and logs from the operator, the agent, and workspace pods on ports 4317 (gRPC) and 4318 (HTTP), optionally watches Kubernetes events, and forwards everything to the telemetry backends you point it at.  The backends themselves (an LGTM stack, ClickHouse, a vendor OTLP endpoint) are external to this chart — the collector's exporters reference them, this chart never installs them.  See the `kasm-otel-collector` chart for its values (`receivers.k8sEvents.enabled`, `exporters.otlp.*`, `exporters.clickhouse.*`, `exporters.debug.enabled`, `configOverride`, `image.*`, `resources`, ...).  |
| otelCollector.enabled | bool | `true` | Install the Kasm OpenTelemetry collector with this release. Disable it when workspace telemetry is not wanted, or when the agent and operator should point at a collector that already exists in the cluster.  |
| otelCollector.nameOverride | string | `"kasm-otel-collector"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and both the operator and the agent default their OTLP endpoint to `http://<release>-kasm-otel-collector:4318` — so without this the collector Service would be named after `otelCollector` and nothing would find it.  |
| videoDevicePlugin | object | `{"enabled":false,"nameOverride":"kasm-video-device-plugin"}` | The Kasm video device plugin (`kasm-video-device-plugin` subchart, alias `videoDevicePlugin`). Advertises the `/dev/video*` devices on each node as a scheduleable extended resource (`kasm.com/video` by default) so workspace pods can request a webcam.  The plugin only advertises devices that already exist. Pair it with `nodePrep.enabled` and `nodePrep.modules.v4l2loopback.enabled` unless the nodes provide real capture devices.  See the `kasm-video-device-plugin` chart for its values (`devicePrefix`, `maxDevices`, `resourceName`, `nodeSelector`, ...).  |
| videoDevicePlugin.enabled | bool | `false` | Install the video device plugin DaemonSet with this release.  |
| videoDevicePlugin.nameOverride | string | `"kasm-video-device-plugin"` | Pins the subchart's resource names to its own chart name. Helm sets `.Chart.Name` inside an aliased dependency to the *alias*, and `videoDevicePlugin` is not a valid RFC 1123 name, so without this the chart would render resource names Kubernetes rejects.  |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |
