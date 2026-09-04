# Planning a Kasm agent deployment

## 1. How to use this plan

1. **[Hosting and topology](#2-hosting-and-topology)** — pick one of the four layouts, and the provider if managed.
2. **[Capacity model](#3-capacity-model)** — cost a session, cost a node, find the ceiling that binds first.
3. **[Network plan](#4-network-plan)** — two hostnames, one auth domain, exactly one exposure method.
4. **[Storage plan](#5-storage-plan)** — profiles, storage mappings, recordings, the node image store.
5. **[Security decisions](#6-security-decisions)** — what the privileged charts cost you, and where.
6. **[Install order and verification](#7-install-order-and-verification)**, then **[day 2](#8-day-2-and-recovery)** and the **[master checklist](#9-master-checklist)**.

Each phase is a set of decisions, each ending in `- [ ]` items. It assembles the rest of this
repository's documentation rather than repeating it: [architecture](architecture.md) says which
chart, [what works on Kubernetes](feature-matrix.md) says which value, the
[how-tos](howto/README.md) say how. Follow the links for mechanics.

For whoever sizes the cluster, owns DNS and TLS, and signs off the security posture — before the
first `helm install`. Several decisions here (the two hostnames, the NetworkPolicy engine, the node
image) cannot be changed afterwards without a rebuild.

---

## 2. Hosting and topology

### 2.1 Pick a layout

Four layouts, described in full in [Architecture → Deployment topologies](architecture.md#deployment-topologies).

| Requirement | Layout | Install |
| ----------- | ------ | ------- |
| Simplest possible install; one team owns both halves | 1 — whole stack, single namespace | [kasm-platform](../charts/kasm-platform/README.md), both halves enabled |
| Control plane must stay out of a `privileged` namespace | 2 — two namespaces, one cluster *(recommended)* | [kasm-helm](../charts/kasm-helm/README.md) + [kasm-agent](../charts/kasm-agent/README.md) as separate releases |
| You want the agent's baseline NetworkPolicies enforced | 2 | `networkPolicies.enabled=true` is only safe in an agent-only namespace |
| A manager already exists — VM/Docker, another cluster, Kasm-hosted | 3 — agent only | `kasm-agent`, or `kasm-platform` with `kasm-helm.enabled=false` |
| Sessions run on VM agents, or agents come later | 4 — control plane only | `kasm-helm`, or `kasm-platform` with `kasm-agent.enabled=false` |
| Sessions in more than one region or cluster | 3, repeated — one agent release per zone | one `kasm-agent` per cluster, one `kasm-helm.kasmZones` entry per zone |
| A second agent in another namespace of the *same* cluster | 2, with `operator.enabled=false` on the second release | the operator is a [cluster singleton](architecture.md#cluster-singletons) |

The toggle matrix for driving all four from one chart is in
[kasm-platform → The toggle matrix](../charts/kasm-platform/README.md#the-toggle-matrix).

### 2.2 What the layout choice fixes

Picking a layout settles five things at once. None of them is a later tuning knob.

| Fixed by the layout | 1 — single namespace | 2 — two namespaces | 3 — agent only | 4 — control plane only |
| ------------------- | -------------------- | ------------------ | -------------- | ---------------------- |
| Scope of the `privileged` Pod Security Standard | covers control-plane pods too | agent namespace only | agent namespace only | not needed |
| Agent baseline NetworkPolicies (`networkPolicies.enabled`) | must stay `false` — the baseline models only the agent's flows | `true` supported | `true` supported | n/a |
| Where the manager lives | same release | same cluster, other namespace | outside this cluster | here; agents elsewhere |
| Manager token | reference the control plane's Secret in place (`agent.manager.existingTokenSecret`) | copy the Secret across namespaces | issued by the remote manager | n/a |
| Cross-cluster reachability | none needed | none needed | the agent must reach `agent.manager.hostname`, and the manager must reach the session proxy | n/a |

The four things the two halves must agree on — the zone, the token, the manager address, and the
hostname split — are spelled out in
[kasm-agent → Running alongside the kasm-helm control plane](../charts/kasm-agent/README.md#running-alongside-the-kasm-helm-control-plane).

### 2.3 If the cluster is managed

A managed service fixes the node OS, the load balancer, and the security baseline — and those
decide which optional charts are *possible*, not merely convenient. Start at the
[cross-provider matrix](howto/managed-kubernetes-providers.md#cross-provider-matrix), then work the
[Before you pick a provider](howto/managed-kubernetes-providers.md#before-you-pick-a-provider)
checklist, which collects the choices that cannot be changed after cluster creation.

Three that bite hardest:

* **Node image.** Bottlerocket and COS cannot build kernel modules at all; if webcam is in scope,
  either the image ships headers and a toolchain, or you commit to
  `nodePrep.modules.v4l2loopback.method=kmm` with prebuilt per-kernel images.
* **NetworkPolicy engine.** A creation-time choice on AKS, and a feature flag on EKS. A
  `NetworkPolicy` under a non-enforcing CNI succeeds silently and isolates nothing.
* **Serverless node pools.** Fargate, GKE Autopilot and AKS virtual nodes cannot run `nodePrep`,
  `videoDevicePlugin`, `egressInstaller`, the rclone CSI node plugin, or `agent.imagePuller`.

Minimum floor for the agent family, whatever the provider: **Kubernetes 1.26+** (or OpenShift
4.10+), Helm 3, a default StorageClass with dynamic provisioning, working in-pod DNS, and a
reachable manager with a registration token — see
[kasm-agent → Prerequisites](../charts/kasm-agent/README.md#prerequisites). The control plane's own
floor is lower, at 1.24+.

**Decisions**

- [ ] Layout chosen from the table in [2.1](#21-pick-a-layout), and the reason recorded.
- [ ] If managed: provider chosen, and [Before you pick a provider](howto/managed-kubernetes-providers.md#before-you-pick-a-provider) worked through.
- [ ] Node image confirmed able to do what the feature set needs (kernel modules, `/dev/fuse`, `/dev/dri`).
- [ ] NetworkPolicy engine selected — at cluster creation where the provider requires it.
- [ ] One cluster, one `operator.enabled=true`; likewise `gpuOperator.enabled` and `csiRclone.enabled`.
- [ ] Kubernetes ≥ 1.26 on every cluster that will run an agent.

---

## 3. Capacity model

Everything below is a **planning estimate to validate with a load test**, not a guarantee. The
per-session numbers are defaults observed on lab control planes; yours come from your own workspace
images. Measure before you commit hardware.

### 3.1 What one session costs

A workspace pod's resources come from the workspace image's `cores` and `memory_bytes` in the Kasm
manager — not from any chart value.

| Dimension | How it is set | Observed defaults |
| --------- | ------------- | ----------------- |
| **CPU** | A **request only** under `cpu_allocation_method` *Shares* or *Inherit* — burstable, no ceiling. A request *and* an equal limit under *Quotas*. | `requests.cpu: 2` on a develop control plane; `cpu: 1` for a 1-core image on 1.19 |
| **Memory** | Always request **=** limit, from `memory_bytes` — a hard reservation, and a hard OOM ceiling. | `2768Mi` on develop; `1536Mi` for a 1.5Gi image on 1.19 |
| **`/dev/shm`** | A **memory-backed** `emptyDir` the operator mounts per session, `2Gi` by default (`KasmWorkspace.spec.shmSize`). Counts against the pod's memory limit **and** node RAM — it is not disk, and it is not additive to the limit. | `2Gi` |
| **Recording buffer** | Only when recording is on: `KasmWorkspace.spec.recordingBufferSize`, default `3Gi`, on the pod's **ephemeral storage**. The operator seeds the container's ephemeral-storage request/limit to cover it (observed: a `1Gi` buffer produced a `2Gi` ephemeral floor). | `3Gi` |
| **Image layers** | Node disk in the container runtime's image store, shared between every session on that node using the same image. | measure — see [3.5](#35-measure-do-not-guess) |

> **The `/dev/shm` trap.** The 2Gi shm lives *inside* the pod's memory limit. A 2768Mi workspace
> that fills its shm has ~720Mi left for the desktop, the browser and Xorg; a 1536Mi workspace
> cannot even hold the default shm. Either raise `memory_bytes` on the image or lower the
> workspace's `shmSize`. Kubernetes' own 64Mi default is what the operator is protecting you from —
> 2Gi is not a number to leave unexamined at the small end.

### 3.2 What the node and cluster cost before any session

| Component | Scope | Requests (chart defaults) |
| --------- | ----- | ------------------------- |
| `kasm-agent-operator` | one pod per **cluster** | `100m` / `256Mi`, request = limit (Guaranteed) |
| `kasm-otel-collector` | one pod per **release** | `50m` / `128Mi` (limits `250m` / `512Mi`) |
| Agent + session proxy | one of each per **Agent CR** (`agent.sessionProxy.replicas` scales the proxy) | operator defaults — `agent.resources` is empty and the proxy has no chart value; measure |
| `kasm-node-prep` | DaemonSet, **per node** | `100m` / `256Mi` (limits `1000m` / `1Gi` for a module build) |
| `kasm-video-device-plugin` | DaemonSet, **per node** | `10m` / `32Mi` (limits `50m` / `64Mi`) |
| `kasm-egress-installer` | DaemonSet, **per node** | `50m` / `64Mi` (limits `500m` / `256Mi`) |
| Image puller | DaemonSet, **per node** | none by default (`agent.imagePuller.resources` is empty) |
| CSI node plugins, KMM workers, cluster system pods | **per node** | cluster-specific — measure |

### 3.3 The four ceilings

A node runs out of one of these first. Find which.

| Ceiling | The number | Notes |
| ------- | ---------- | ----- |
| **Memory** | node allocatable RAM − fixed overhead | Memory request = limit, so the request is a hard reservation. Size against the **limit**, not a guess at the working set. |
| **CPU requests** | node allocatable CPU − fixed overhead | Under *Shares*/*Inherit* there is no CPU limit, so this bounds **scheduling**, not throughput. Frequently the binding ceiling — see [3.4](#34-worked-example). |
| **`maxPods`** | kubelet default **110 per node** | Includes the DaemonSets, the agent, the session proxy, CSI plugins and every system pod — not just sessions. A hidden ceiling on small, dense sessions. |
| **Disk** | `80GB + (users × space_per_user)` on the volume holding the image store | Kasm's own formula. Image GC runs at 90/80% — see [Settings this chart cannot make for you](../charts/kasm-agent/README.md#settings-this-chart-cannot-make-for-you). |

Swap is a fifth, softer one — and for **workspace sessions it currently does nothing**.
`LimitedSwap` grants a container swap only when its **memory request is strictly less than its
memory limit**; a container with request = limit gets none, whatever its QoS class or CPU
allocation method (this was verified on k3s 1.36 and kubeadm 1.34, not just derived from the QoS
class). Kasm sets a workspace's memory request *and* limit from the same `memory_bytes`, so every
session container has request = limit and no swap. The node's swapfile still helps other Burstable
pods with headroom — the agent, the sidecars, system pods — so it is not wasted, but do not size a
node expecting sessions to spill into it. The worked example and the full rationale are in
[kasm-agent → Swap, and the kubelet setting that must come first](../charts/kasm-agent/README.md#swap-and-the-kubelet-setting-that-must-come-first);
the node-side procedure, including the kubelet setting that must land first, is
[Node tuning and swap](howto/node-tuning-and-swap.md).

### 3.4 Worked example

**Assumptions** (state yours the same way, then measure):

* Node: 8 vCPU / 32 GiB. Allocatable after kubelet and system reservations: **7.5 CPU / 29 GiB**.
* Reserved on each workspace node for the agent stack and cluster system pods: **1 CPU / 2 GiB**.
* Sessions: `requests.cpu: 2`, memory request = limit `2768Mi`, `shmSize: 2Gi` inside that limit.
* Recording off. `nodePrep` and `videoDevicePlugin` on, `egressInstaller` off.

**Available to sessions:** 7.5 − 1 = **6.5 CPU**; 29 − 2 = **27 GiB** = 27648 MiB.

| Ceiling | Arithmetic | Sessions per node |
| ------- | ---------- | ----------------- |
| CPU requests | 6500m ÷ 2000m | **3** |
| Memory | 27648Mi ÷ 2768Mi | 9 |
| `maxPods` | 110 − ~15 (system + DaemonSets + agent stack) | 95 |
| Disk | `80GB + (users × space_per_user)` | sized separately |

**CPU requests bind, at 3 sessions per node** — three times tighter than RAM, on a node that is
nowhere near CPU-saturated, because under *Shares* that 2-core request is a scheduling reservation
with no ceiling behind it. The levers, in order of preference: lower `cores` on the workspace image
(the request is what the scheduler counts), pick a CPU-denser node shape, or move the image to
*Quotas* only if you actually want a throughput ceiling.

Same node, a 1-core / 1536Mi image: 6500m ÷ 1000m = **6** sessions on CPU, 18 on RAM. CPU still
binds — and the default 2Gi `/dev/shm` no longer fits inside a 1536Mi limit at all.

### 3.5 Measure, do not guess

```console
# Real allocatable, and what is already requested on the node
kubectl describe node <node> | sed -n '/Allocatable/,/Allocated resources/p'
kubectl describe node <node> | sed -n '/Allocated resources/,$p'

# maxPods as the kubelet actually has it
kubectl get --raw "/api/v1/nodes/<node>/proxy/configz" | jq '.kubeletconfig.maxPods'

# What a live session really consumes, versus its request
kubectl top pod -n <namespace> --containers
kubectl get pod -n <namespace> <session-pod> -o jsonpath='{.spec.containers[0].resources}'

# Image sizes, from the registry rather than from memory
./bin/crane manifest <registry>/<workspace-image>:<tag> | jq '[.layers[].size] | add'
```

Do not carry image sizes or pull times from anywhere else; they are entirely a function of your
image catalogue.

### 3.6 Node pools and placement

Put sessions on their own node pool. Label it, then point the agent at the label:

```yaml
agent:
  workspacesNodeSelector:
    kasm.com/workspaces: "true"
nodePrep:
  nodeSelector:
    kasm.com/workspaces: "true"
videoDevicePlugin:
  nodeSelector:
    kasm.com/workspaces: "true"
```

`agent.workspacesNodeSelector` is the fleet-wide default for the pods the agent launches;
`agent.nodeSelector` places the agent's *own* pods, which is a different question. Per-workspace
targeting needs no chart value — the manager's `include_labels` become `spec.nodeSelector` on the
`KasmWorkspace` ([node targeting](feature-matrix.md#observability--operations)).

**Taints need care.** `nodePrep`, `videoDevicePlugin` and `egressInstaller` each expose a
`tolerations` value, and their READMEs document the matching pattern:

```yaml
tolerations:
  - key: kasm.com/workspaces
    operator: Exists
    effect: NoSchedule
```

There is **no equivalent chart value for the session pods** — `kasm-agent-instance` has no
tolerations key, and `agent.workspacesNodeSelector` is label-based placement only. If you taint the
workspace pool, prove a session still schedules onto it before relying on the taint to keep other
workloads off.

**Decisions**

- [ ] Per-session cost written down from **your** images' `cores` / `memory_bytes`, not from the defaults above.
- [ ] `shmSize` checked against each image's memory limit — the shm is inside the limit.
- [ ] Recording decided; if on, the Kasm licence confirmed to cover it, and the `recordingBufferSize` and the resulting ephemeral-storage floor budgeted.
- [ ] Fixed per-node overhead measured on a real node, not assumed.
- [ ] The binding ceiling identified (CPU requests / memory / `maxPods` / disk) and the arithmetic recorded.
- [ ] `maxPods` checked against the planned session density.
- [ ] Node disk sized with `80GB + (users × space_per_user)` on the **image-store** volume.
- [ ] Swap decision made — understanding sessions get **no** swap (memory request = limit); the swapfile helps only other Burstable pods.
- [ ] Node pool labelled; `agent.workspacesNodeSelector` and the DaemonSet `nodeSelector`s agree.
- [ ] If the pool is tainted: session scheduling onto it verified.
- [ ] A load test scheduled to validate all of the above before go-live.

---

## 4. Network plan

### 4.1 Worksheet

Fill this in before touching values. The hostname pair in particular cannot be changed later
without renaming one of them.

| Item | Decide | Value that carries it |
| ---- | ------ | --------------------- |
| Control-plane hostname | e.g. `kasm.example.com` | `kasm-helm.publicAddr` |
| Agent public hostname | must **differ** from the above; one per zone | `agent.publicHostname` |
| Session-proxy public port | 443 unless something in front says otherwise | `agent.publicPort` |
| **Authorization domain** | the shared **parent** of both hostnames | `kasm-helm.kasmConfig.authDomain` |
| Zone name | must already exist on the control plane | `agent.zone`, `kasm-helm.kasmZones` |
| Zone routing | `proxy_connections: false`; `upstream_auth_address` = the control-plane address | entries under `kasm-helm.kasmZones` |
| Control-plane certificate | own cert, or cert-manager (keep the wildcard) | `kasm-helm.certificate.secretName`, or `kasm-helm.certificate.certManager.enabled` + `issuerName` + `addWildCard` |
| Agent certificate | must cover the hostname **and** `*.<hostname>`, publicly trusted | `agent.sessionProxy.certSecretName`, or `agent.sessionProxy.certificate.enabled` + `dnsNames` |
| Exposure, control plane | ingress, Route, or the Service directly | `kasm-helm.ingress.enabled` / `kasm-helm.route.enabled` / `kasm-helm.proxyService.type` |
| Exposure, agent | **exactly one** of six | see [4.2](#42-exposure-decision-matrix) |
| Idle timeout | ≥ 3600s on whatever fronts the proxy | ingress annotations, or the LB's L4 idle timeout |
| Real client IPs | needed, or not | `agent.sessionProxy.service.externalTrafficPolicy`, **or** `agent.sessionProxy.proxyProtocol.enabled` + `trustedCIDRs` |
| Per-session egress / VPN | needed, or not | `egressInstaller.enabled`, `egressInstaller.distro` |
| Policy baseline | on only in an agent-only namespace | `networkPolicies.enabled`, `networkPolicies.manager.ports` |

Two hostnames, siblings under one parent, plus that parent as the authorization domain, is the
whole shape. Get it wrong and every session connect returns 401 (cookie out of scope) or 404 (zone
still relaying through the control-plane proxy).

### 4.2 Exposure decision matrix

Eight ways to publish the two halves. **Exactly one** of the agent rows may be enabled — all of
them point at the same session-proxy Service. Mechanics for every row:
[External access and TLS](howto/external-access-and-tls.md).

| Option | TLS terminates at | End-to-end TLS to the proxy | Client IP preserved by | WebSocket idle-timeout knob | Needs an ingress/gateway controller? | Cloud-LB native? | OpenShift native? | Verified in the lab? |
| ------ | ----------------- | --------------------------- | ---------------------- | --------------------------- | ------------------------------------ | ---------------- | ----------------- | -------------------- |
| `kasm-helm.ingress.enabled=true` *(control plane)* | the ingress controller | No | the controller's forwarded headers | controller annotation (`proxy-read-timeout`) | Yes | via the controller's LB | No — use the Route | **Yes** — Traefik on k3s |
| `kasm-helm.route.enabled=true` *(control plane)* | the OpenShift router — `edge` once `kasm-helm.route.tls` is set; with it empty the Route carries no TLS stanza at all | Only with `passthrough`/`reencrypt` | the router's forwarded headers | `haproxy.router.openshift.io/timeout` | Yes — the router | n/a | **Yes** | No — render-verified |
| `kasm-helm.proxyService.type=LoadBalancer` or `NodePort` *(control plane, no ingress)* | the Kasm proxy pod | Yes | `externalTrafficPolicy` on the Service | none — raise the LB's L4 idle timeout | No | Yes | works, not native | No — render-verified |
| `agent.httpRoute.enabled=true` | the Gateway (backend 4445) | No | the Gateway's forwarded headers | the Gateway data plane's own setting | Yes — Gateway API | via the Gateway's LB | No | **Yes** — Traefik Gateway, one and two namespaces |
| `agent.ingress.enabled=true` | the ingress controller (backend 4445; 4444 with `backend-protocol: HTTPS`) | No | the controller's forwarded headers | `nginx.ingress.kubernetes.io/proxy-read-timeout` | Yes | via the controller's LB | No | No — render-verified |
| `agent.route.enabled=true` | the session proxy (`passthrough` default; `agent.route.backendPort` follows the mode) | Yes | the router, or L4 | `haproxy.router.openshift.io/timeout` | Yes — the router | n/a | **Yes** | No — render-verified |
| `agent.gatewayRoute.enabled=true` *(operator-managed)* or `agent.tlsRoute.enabled=true` *(chart-managed)* | the session proxy — SNI passthrough, port 4444 | Yes | L4 through the Gateway | none — raise the L4 idle timeout | Yes — Gateway API 1.5+ CRDs (`TLSRoute` is standard-channel `v1`), `Passthrough` listener | via the Gateway's LB | No | **Yes** for `gatewayRoute` — Traefik 3.7 / Gateway API 1.5.1; `tlsRoute` render-verified |
| `agent.sessionProxy.service.type=NodePort` or `LoadBalancer` | the session proxy on 4444, or whatever fronts 4445 | Yes on 4444 | `externalTrafficPolicy: Local`, or `proxyProtocol` | none — raise the LB's L4 idle timeout | No | Yes | works, not native | **Yes** — NodePort, pinned ports, `externalTrafficPolicy: Local` |

"Verified in the lab" means run end-to-end on this repository's k3s clusters. Everything else is
render-verified only — the manifests are correct and the values exist; the path has not been driven
by a browser here.

### 4.3 Start from the requirement

| The requirement | Option | Values |
| --------------- | ------ | ------ |
| **No ingress controller and none coming** | Publish the Services directly | `agent.sessionProxy.service.type=LoadBalancer` (or `NodePort`); `kasm-helm.proxyService.type=LoadBalancer` |
| **Real client IPs are required** | Pick one mechanism, never both | `agent.sessionProxy.service.externalTrafficPolicy=Local` (L4; only routes via nodes running a proxy pod — pair with `agent.sessionProxy.replicas` or a health-checking LB) **or** `agent.sessionProxy.proxyProtocol.enabled=true` + `agent.sessionProxy.proxyProtocol.trustedCIDRs` (L7; the LB **must** send PROXY protocol, or every connection breaks) |
| **TLS must not terminate on shared cluster infrastructure** | SNI passthrough to the session proxy's own certificate | `agent.gatewayRoute.enabled=true` + `agent.gatewayRoute.parentRef` (preferred), or `agent.tlsRoute.enabled=true` + `agent.tlsRoute.parentRefs`, or `agent.route.enabled=true` on OpenShift |
| **A corporate F5 / HAProxy forwarding to node ports** | Pinned NodePorts | `agent.sessionProxy.service.type=NodePort`, `agent.sessionProxy.service.httpsNodePort`, `agent.sessionProxy.service.httpNodePort` (both inside 30000–32767), plus `externalTrafficPolicy=Local` or PROXY protocol |
| **A cloud NLB straight onto sessions** | LoadBalancer Service with cloud annotations | `agent.sessionProxy.service.type=LoadBalancer`, `agent.sessionProxy.service.annotations`; raise the NLB idle timeout above its 350s default |
| **SSL terminated outside the cluster** | Send plain HTTP to the proxy's 4445 listener | `agent.sessionProxy.service.type` = `NodePort`/`LoadBalancer` pointed at `agent.sessionProxy.service.httpNodePort`. The certificate no longer has to be publicly trusted — but `agent.sessionProxy.certSecretName` must still exist, because the proxy will not start without it |
| **OpenShift, both halves** | The native router path | `kasm-helm.route.enabled=true`; `agent.route.enabled=true` with `passthrough` |

Whatever you pick: the control plane stays on `kasm-helm.proxyService.type=ClusterIP` whenever an
ingress or Route fronts it — a `LoadBalancer` there claims the node's :443 that the controller
already holds, and the chart rejects the combination outright.

**Decisions**

- [ ] Two sibling hostnames chosen under one parent domain; DNS planned for both.
- [ ] `kasm-helm.kasmConfig.authDomain` set to that parent — at **install** time on a fresh database, or by hand in Settings → Auth on an existing one.
- [ ] Zone named, `proxy_connections: false` and `upstream_auth_address` set on it.
- [ ] Exactly one agent exposure method chosen from [4.2](#42-exposure-decision-matrix).
- [ ] Idle timeout ≥ 3600s confirmed on whatever fronts the session proxy (HTTP knob or L4).
- [ ] Session-proxy certificate covers `<hostname>` **and** `*.<hostname>`, publicly trusted.
- [ ] Control-plane certificate settled; `proxyService.type=ClusterIP` behind an ingress or Route.
- [ ] Client-IP mechanism chosen — one, not both — and the fronting LB configured to match.
- [ ] Per-session egress decided; if yes, [egress node prerequisites](howto/egress-installer-node-prerequisites.md) verified first.
- [ ] Gateway/ingress listener admits **every** namespace that needs it (both, in the two-namespace layout).

---

## 5. Storage plan

### 5.1 Persistent profiles

The profile is a PVC the operator attaches to every session a user launches. The access mode
decides the scheduling story.

| Choice | When | Values |
| ------ | ---- | ------ |
| An existing **RWX** class — EFS, Azure Files/ANF, Filestore, ODF/CephFS, NFS | Production. Shared profiles need `ReadWriteMany`. | none — point Kasm at the class name |
| **RWO** (EBS, PD, Azure Disk, local-path) | Single-node-affine profiles only | none — but the PVC pins every future session to that node |
| The bundled in-cluster NFS server | A cluster with no RWX driver; a starting point, not a plan | `nfs-server-provisioner.enabled=true` **and** `nfs-server-provisioner.persistence.enabled=true` — without the second, profiles are lost when the NFS pod restarts |

Pick the performance tier deliberately: a browser profile is a many-small-files workload, which is
NFS's worst case. Procedure: [RWX storage for profiles](howto/rwx-storage-for-profiles.md).

### 5.2 User storage mappings (rclone / S3 / Drive)

Two values, always — the driver alone mounts nothing and the agent flag alone points at a driver
that is not there:

```yaml
csiRclone:
  enabled: true
agent:
  storageMappings:
    enabled: true
    installationID: <scopes the derived StorageClass and Secret names>
```

The cluster must supply **FUSE on every session node** (`/dev/fuse` present, module loaded); no
chart builds or loads it. `csiRclone` is cluster-scoped — one release per cluster. Procedure:
[Cloud storage mappings (rclone CSI)](howto/cloud-storage-rclone-csi.md).

### 5.3 Recordings

Session recording is a **licensed** Kasm feature. Without the entitlement, sessions start with the
recorder disabled even when the upload location and the `record_sessions` group setting are both
configured; the API logs *"Session recording is configured but not licensed"*. Confirm the licence
before budgeting for any of the below.

Recording buffers on the **session pod's ephemeral storage** until it uploads —
`KasmWorkspace.spec.recordingBufferSize`, `3Gi` by default, with the operator seeding the
container's ephemeral-storage request/limit to cover it. It survives a container restart, not pod
loss: an evicted or OOM-killed pod loses an in-flight recording. Nothing mounts a PVC at
`/opt/kasm/recordings` automatically.

Plan for it: budget the ephemeral floor per concurrent recorded session into the node disk
([3.3](#33-the-four-ceilings)), configure the upload location and object-storage credentials on the
control plane, and make sure workspace pods can reach the Kasm API Service — and the bucket — if
`networkPolicies.enabled=true`.

### 5.4 The node image store

`80GB + (users × space_per_user)` on the volume backing the container runtime's image store, not on
the root filesystem in general. Image GC at `imageGCHighThresholdPercent: 90` /
`imageGCLowThresholdPercent: 80` — a kubelet setting no chart can make, and one worth aligning with
the agent's own `disk_usage_limit: 0.90`. See
[kasm-agent → Node sizing](../charts/kasm-agent/README.md#node-sizing).

Pre-pulling changes the launch experience, not the arithmetic. The operator creates a
`KasmImagePuller` from the manager's own image list without being asked; `agent.imagePuller.enabled`
and `agent.imagePuller.images` stage extra images regardless, and
`agent.imageAvailabilityPolicy` (`all` or `any`) decides when an image counts as available. It
needs the container runtime socket from a DaemonSet — impossible on serverless node pools.
Procedure: [Private registries and image pulling](howto/private-registries-and-image-pulling.md).

**Decisions**

- [ ] RWX class identified (or RWO accepted, with the node-pinning consequence understood).
- [ ] If using the bundled NFS server: `persistence.enabled=true`, and it is understood to be a single point of failure.
- [ ] Storage mappings decided; if yes, FUSE confirmed on every session node and `csiRclone` enabled in exactly one release.
- [ ] Recording decided; buffer size, ephemeral floor, upload target and egress path all planned.
- [ ] Image-store volume sized with Kasm's formula; kubelet image-GC thresholds set on the node.
- [ ] Pre-pull strategy chosen, and the runtime socket confirmed reachable from a DaemonSet.

---

## 6. Security decisions

Each of these is a decision with a blast radius, not a switch to flip late.

| Decision | What it costs | Where |
| -------- | ------------- | ----- |
| **`privileged` PSS scope** | `nodePrep`, `videoDevicePlugin` and `egressInstaller` cannot be made unprivileged. The namespace label covers **everything** in that namespace — including the control plane, in a shared-namespace layout. Keeping the two halves apart is the main argument for the two-namespace topology. | [Privileged workloads and policies](howto/privileged-workloads-and-policies.md) |
| **Host namespaces for the egress installer** | `egressInstaller` runs with `hostPID: true` *and* `hostNetwork: true` on top of a privileged container, so a blanket `disallow-host-namespaces` rule rejects it even in a `privileged` namespace. Its shim hard-fails CNI ADD when it cannot reach the daemon — which fails **every** pod sandbox on that node, not just Kasm's. Decide this deliberately or leave it off. | [Egress installer node prerequisites](howto/egress-installer-node-prerequisites.md) |
| **Operator RBAC** | The operator is a cluster singleton owning cluster-scoped CRDs and fixed-name ClusterRoles. The chart owns that RBAC, so a `helm upgrade` **re-applies** it — which is how a hand-edited role silently reverts, and also how a missing rule (for example the TLSRoute rule behind `GatewayRouteAccepted`) gets fixed. | [architecture → Cluster singletons](architecture.md#cluster-singletons) |
| **NetworkPolicy enforcement** | Objects are inert unless the CNI enforces them — the worst failure mode, because it looks like it worked. Verify enforcement before treating default-deny as isolation. In the two-namespace layout with an in-cluster manager reached through a hostPort ingress, `networkPolicies.manager.ports` must carry the ingress controller's **backend** port (Traefik: 8443) — the policy sees the post-DNAT port, not 443. | [NetworkPolicy enforcement](howto/network-policy-enforcement.md) |
| **Image provenance and airgap** | Every chart installs with no internet access, but three flows need separate handling: the chart archive (`make package-agent`), the component images (`make images-agent`, then a registry override block), and **workspace images**, which come from the manager's registry and must be re-pointed there. `nodePrep` in `method: build` fetches at runtime — use a pre-baked builder image or KMM with prebuilt per-kernel images. | [kasm-agent → Airgapped installation](../charts/kasm-agent/README.md#airgapped-installation) |
| **Secure Boot** | Only where it is on — mostly bare metal and private cloud. MOK enrolment is a **firmware** step per node; on a managed node image you generally cannot reach the firmware. KMM signing is the cleaner path where you have the choice. | [Secure Boot](howto/secure-boot.md) |
| **Private registries** | `agent.workspaceImagePullSecrets` (what the agent injects into session pods) and `agent.imagePullSecrets` (what pulls the agent's own images) are genuinely different settings. ECR tokens expire every 12h. | [Private registries and image pulling](howto/private-registries-and-image-pulling.md) |

Multi-tenancy sits on top of all of it and is `Partial` by design: the operator isolates each
session pod from its neighbours and denies sessions any API access, but a namespace per tenant needs
provisioning automation this repository does not ship — and the same namespace that permits
`privileged` weakens the story for everything else in it. See
[multi-tenancy](feature-matrix.md#security--isolation).

**Decisions**

- [ ] Namespace layout chosen with the `privileged` PSS blast radius in mind.
- [ ] `egressInstaller` explicitly in or out, with the no-daemon failure window accepted if in.
- [ ] Understood that `helm upgrade` re-applies the operator's cluster RBAC.
- [ ] CNI enforcement **proven**, not assumed, before `networkPolicies.enabled=true`.
- [ ] `networkPolicies.manager.ports` set to the post-DNAT backend port where an in-cluster ingress fronts the manager.
- [ ] Airgap decided; if yes, chart archive, component images, workspace images and node-prep inputs all planned.
- [ ] Secure Boot state of the node image known.
- [ ] Pull secrets planned for both flows, with a refresh story for expiring tokens.

---

## 7. Install order and verification

### 7.1 Order

1. **`kasm-agent-crds`, if you want Helm to own the CRD lifecycle.** Its own release, *before*
   anything else, and upgraded before the app releases thereafter. Skip it and the operator chart's
   `crds/` directory installs the same five schemas — but `helm upgrade` will never touch them.
   [Install order](../charts/kasm-agent-crds/README.md#install-order) ·
   [why the split exists](architecture.md#why-the-crds-are-split-from-the-operator).
2. **Stage dependencies, or install from OCI.** From a checkout the build is **inside-out** —
   `helm dependency build charts/kasm-agent` *then* `charts/kasm-platform`, which `make deps-agent`
   does in that order. Skipping the first silently renders a control-plane-only stack. The OCI
   artifact embeds every dependency and needs neither step.
3. **Label the namespace** if any privileged chart is on:
   `kubectl label namespace <ns> pod-security.kubernetes.io/enforce=privileged`. `egressInstaller`
   needs host namespaces permitted as well.
4. **Install.** One release (`kasm-platform`), or the control plane first and then the agent — the
   agent needs the zone to exist and the token to have been copied across.
5. **Two clicks in the UI, still manual.** Infrastructure → the registered agent → **Enable** (new
   agents register disabled). Workspaces → the image → assign a group (`group_images` has no
   preseed path).

The narrated version, with measured timings, is the
[demo runbook](../examples/kasm-agent/demo-runbook.md): ~3m30s for the single-command platform
install, ~3m41s for both installs in the two-namespace layout, ~11s to a running session on a warm
node.

### 7.2 What to watch

```console
# Both halves rolled out
kubectl get pods -n <ns>

# The agent registered; Phase and the operator's conditions
kubectl get agents.agent.kasm.com -n <ns>
kubectl get agents.agent.kasm.com -n <ns> -o jsonpath='{.items[*].status.conditions}' | jq

# Webcam path only: the extended resource is actually advertised
kubectl get node <node> -o jsonpath='{.status.allocatable}' | jq '."kasm.com/video"'

# The session proxy answers — 404 with no active session is correct
curl -k -sS -o /dev/null -w '%{http_code}\n' https://<agent hostname>/

# The session really is a pod
kubectl get kasmworkspaces -n <ns>
```

`Degraded=True` with `GatewayRouteAccepted=False` means the operator cannot manage TLSRoutes —
missing RBAC, or a `TLSRoute` CRD that is missing or older than Gateway API 1.5. Everything else keeps reconciling, so sessions
stay up; only `agent.gatewayRoute` is unfulfilled. The fix, and the rest of the failure catalogue,
is in [External access and TLS → Troubleshooting](howto/external-access-and-tls.md#troubleshooting).

Then the real test: log in at the control-plane hostname, launch a session, confirm the browser's
URL bar shows the **agent's** hostname, and confirm the session survives past 60 seconds (proof the
websocket timeout is raised).

**Decisions**

- [ ] CRD ownership chosen: `kasm-agent-crds` release, or the operator chart's `crds/` plus an out-of-band `kubectl apply --server-side` habit.
- [ ] Install source chosen: OCI artifact, or a checkout with the inside-out dependency build.
- [ ] Namespace labels applied ahead of the install where privileged charts are on.
- [ ] Install order agreed: CRDs → control plane → token copy → agent.
- [ ] Someone owns the two manual UI steps.
- [ ] Verification run: pods, `Agent` conditions, session proxy answering, one real session past 60s.

---

## 8. Day-2 and recovery

### 8.1 Upgrades

**Order: CRDs → operator → agent.** A new operator expects its new schema, so the app release that
carries it must land on a cluster whose CRDs already accept the fields it writes. The reverse order
leaves a window in which the operator writes fields the stored schema prunes.
[Upgrade discipline](../charts/kasm-agent-crds/README.md#upgrade-discipline). In the normal case
the last two steps are one release — the `kasm-agent` umbrella carries both — and separate only
where a second agent runs with `operator.enabled=false`, in which case the operator's release goes
first.

**Version lockstep.** `make version-check-agent` (backed by `scripts/agent_versions.py --check`)
fails when any `file://` dependency pin in `kasm-agent` or `kasm-platform` drifts from the subchart's
own `Chart.yaml`, and CI runs it on every pipeline; `scripts/agent_versions.py --bump` moves the whole
family together. The two rules it does *not* encode still have to be held by hand:

* `kasm-platform`'s `Chart.yaml` pins **both** dependency versions. Bump the `kasm-helm` dependency
  there whenever the control-plane chart's version moves, and re-run
  `helm dependency update charts/kasm-platform` — without both, `helm dependency build` cannot
  resolve the local dependency.
* The control plane's `manager/agent_version` setting gates which agent builds it accepts, so an
  agent image tag out of step with the control plane surfaces as a **registration failure**, not a
  runtime error.
* `python3 scripts/set_versions.py --check` keeps the root README's version references honest with
  `charts/kasm-helm/Chart.yaml`.

**CRD schema changes** land one of two ways, and it depends on the choice made in
[7.1](#71-order): `helm upgrade` of the `kasm-agent-crds` release, or
`kubectl apply --server-side -f charts/kasm-agent-operator/crds/` out of band. A `crds/`-installed
CRD is never touched by `helm upgrade`.

**Do not roll back the CRD release.** `helm rollback` will reinstate an older schema underneath
objects already stored in the newer one; the API server prunes the fields the restored schema does
not define, silently and irreversibly. Roll forward instead.

### 8.2 Uninstall

Always in this order — `helm uninstall` would otherwise delete the `Agent` and the operator that
clears its finalizer at the same time, hanging the deletion (or worse, letting a later operator
install process a stale deletion and tear down a live agent):

```console
kubectl delete kasmworkspaces.agent.kasm.com --all -n <ns> --wait   # end live sessions first
kubectl delete agents.agent.kasm.com --all -n <ns> --wait
helm uninstall <release> -n <ns>
```

CRDs survive by design, whichever path installed them — the `kasm-agent-crds` templates carry
`helm.sh/resource-policy: keep`, and Helm never removes a `crds/` CRD. So do the control plane's
PersistentVolumeClaims. Delete both deliberately, and know that deleting a CRD cascades to every
custom resource of that kind in every namespace.
[The `keep` annotation](../charts/kasm-agent-crds/README.md#the-keep-annotation) ·
[kasm-platform → Uninstall, in two steps](../charts/kasm-platform/README.md#uninstall-in-two-steps).

If a cluster already has these CRDs from a `crds/`-directory install and you now want the Helm-owned
release, they have to be adopted first — label and annotate, then install:
[Adopting CRDs that Helm did not install](../charts/kasm-agent-crds/README.md#adopting-crds-that-helm-did-not-install).

### 8.3 What is stateful, and what is not

| Stateless — rebuild freely | Stateful — plan for it |
| -------------------------- | ---------------------- |
| The agent Deployment and the session proxy (the operator recreates both from the `Agent` CR) | The control-plane database — the entire configuration: users, groups, images, zones, settings |
| The operator itself | Persistent profile PVCs — they survive `KasmWorkspace` deletion when `persistent: true` |
| The OTel collector (in-flight telemetry only) | **Recordings in flight** — buffered on the session pod's ephemeral storage; a lost pod loses them |
| The DaemonSets, apart from node-wide `tuning.*` state | Node-wide state `nodePrep.tuning.*` leaves behind: swap stays active and sysctls stay raised after `helm uninstall` |

Back up the control-plane database — `kasm-helm.dbManagement.backupCron.enabled` with a schedule and
a PVC, plus the manifests in `examples/db-backup.yaml` and `examples/db-restore.yaml`. Draining a
node for maintenance destroys the sessions on it; drain the sessions first if recordings matter.
Rolling back `nodePrep.tuning.swap` has its own reversed order —
[Node tuning and swap](howto/node-tuning-and-swap.md#steps), step 7.

**Decisions**

- [ ] Upgrade order documented for whoever runs it: CRDs → operator → agent.
- [ ] Version-lockstep rule owned, including the `kasm-platform` `Chart.yaml` pin and `manager/agent_version`.
- [ ] CRD upgrade path chosen and written down (Helm release, or `kubectl apply --server-side`).
- [ ] "Never `helm rollback` the CRD release" understood by everyone with upgrade rights.
- [ ] Uninstall runbook — custom resources first — stored somewhere findable.
- [ ] Control-plane database backups configured and a restore actually rehearsed.
- [ ] Node-drain procedure accounts for in-flight sessions and recordings.
- [ ] Node-wide `tuning.*` rollback order known before it is ever enabled.

---

## 9. Master checklist

### Hosting and topology

- [ ] Layout chosen from the table in [2.1](#21-pick-a-layout), and the reason recorded.
- [ ] If managed: provider chosen, and [Before you pick a provider](howto/managed-kubernetes-providers.md#before-you-pick-a-provider) worked through.
- [ ] Node image confirmed able to do what the feature set needs (kernel modules, `/dev/fuse`, `/dev/dri`).
- [ ] NetworkPolicy engine selected — at cluster creation where the provider requires it.
- [ ] One cluster, one `operator.enabled=true`; likewise `gpuOperator.enabled` and `csiRclone.enabled`.
- [ ] Kubernetes ≥ 1.26 on every cluster that will run an agent.

### Capacity

- [ ] Per-session cost written down from **your** images' `cores` / `memory_bytes`.
- [ ] `shmSize` checked against each image's memory limit — the shm is inside the limit.
- [ ] Recording decided; licence confirmed; `recordingBufferSize` and ephemeral-storage floor budgeted.
- [ ] Fixed per-node overhead measured on a real node.
- [ ] The binding ceiling identified and the arithmetic recorded.
- [ ] `maxPods` checked against the planned session density.
- [ ] Node disk sized with `80GB + (users × space_per_user)` on the image-store volume.
- [ ] Swap decision made — sessions get no swap (memory request = limit); the swapfile helps only other Burstable pods.
- [ ] Node pool labelled; `agent.workspacesNodeSelector` and the DaemonSet `nodeSelector`s agree.
- [ ] If the pool is tainted: session scheduling onto it verified.
- [ ] A load test scheduled before go-live.

### Network

- [ ] Two sibling hostnames under one parent domain; DNS planned for both.
- [ ] `kasm-helm.kasmConfig.authDomain` set to that parent.
- [ ] Zone named, `proxy_connections: false` and `upstream_auth_address` set on it.
- [ ] Exactly one agent exposure method chosen.
- [ ] Idle timeout ≥ 3600s confirmed on whatever fronts the session proxy.
- [ ] Session-proxy certificate covers `<hostname>` and `*.<hostname>`, publicly trusted.
- [ ] Control-plane certificate settled; `proxyService.type=ClusterIP` behind an ingress or Route.
- [ ] Client-IP mechanism chosen — one, not both — and the LB configured to match.
- [ ] Per-session egress decided; prerequisites verified first if yes.
- [ ] Gateway/ingress listener admits every namespace that needs it.

### Storage

- [ ] RWX class identified, or RWO accepted with its node-pinning consequence.
- [ ] Bundled NFS server, if used, has `persistence.enabled=true`.
- [ ] Storage mappings decided; FUSE confirmed; `csiRclone` in exactly one release.
- [ ] Recording buffer, ephemeral floor, upload target and egress path planned.
- [ ] Image-store volume sized; kubelet image-GC thresholds set.
- [ ] Pre-pull strategy chosen and the runtime socket confirmed reachable.

### Security

- [ ] Namespace layout chosen with the `privileged` PSS blast radius in mind.
- [ ] `egressInstaller` explicitly in or out.
- [ ] Understood that `helm upgrade` re-applies the operator's cluster RBAC.
- [ ] CNI enforcement proven before `networkPolicies.enabled=true`.
- [ ] `networkPolicies.manager.ports` set to the post-DNAT backend port where relevant.
- [ ] Airgap plan covers chart, component images, workspace images and node-prep inputs.
- [ ] Secure Boot state of the node image known.
- [ ] Pull secrets planned for both image flows, with a token-refresh story.

### Install

- [ ] CRD ownership chosen.
- [ ] Install source chosen: OCI, or a checkout with the inside-out dependency build.
- [ ] Namespace labels applied ahead of the install.
- [ ] Install order agreed: CRDs → control plane → token copy → agent.
- [ ] Someone owns the two manual UI steps.
- [ ] Verification run end to end, including one real session past 60 seconds.

### Day 2

- [ ] Upgrade order documented: CRDs → operator → agent.
- [ ] Version-lockstep rule owned.
- [ ] CRD upgrade path chosen and written down.
- [ ] "Never `helm rollback` the CRD release" understood.
- [ ] Uninstall runbook stored somewhere findable.
- [ ] Database backups configured and a restore rehearsed.
- [ ] Node-drain procedure accounts for in-flight sessions and recordings.
- [ ] Node-wide `tuning.*` rollback order known.

---

## Related reading

* [Architecture](architecture.md) — the ten charts, how they compose, and which one to install.
* [What works on Kubernetes](feature-matrix.md) — every Kasm feature, whether it works, and what it needs from the cluster.
* [Cluster configuration how-tos](howto/README.md) — the eleven per-topic procedures, each with its own verification commands.
* [Managed Kubernetes providers: what changes](howto/managed-kubernetes-providers.md) — EKS, AKS, GKE and OpenShift.
* [kasm-agent → Cluster preparation checklist](../charts/kasm-agent/README.md#cluster-preparation-checklist) — the short list: the features people turn on most often, and the values that turn them on.
* [Demo runbook](../examples/kasm-agent/demo-runbook.md) — the install, narrated, with measured timings.
