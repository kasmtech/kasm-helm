# Capacity

> **Applies to:** both halves · node sizing for the agent; the control plane sizes with `kasm-helm.deploymentSize` · **Charts/values:** `agent.workspacesNodeSelector`, `nodePrep.tuning.*`, `kasm-helm.deploymentSize`

Everything below is a **planning estimate to validate with a load test**, not a guarantee. The
per-session numbers are Kasm's defaults; yours come from your own workspace
images. Measure before you commit hardware.

## What one session costs

A workspace pod's resources come from the workspace image's `cores` and `memory_bytes` in the Kasm
manager - not from any chart value.

| Dimension | How it is set | Observed defaults |
| --------- | ------------- | ----------------- |
| **CPU** | A **request only** under `cpu_allocation_method` *Shares* or *Inherit* - burstable, no ceiling. A request *and* an equal limit under *Quotas*. | `requests.cpu: 2` on a develop control plane; `cpu: 1` for a 1-core image on 1.19 |
| **Memory** | Always request **=** limit, from `memory_bytes` - a hard reservation, and a hard OOM ceiling. | `2768Mi` on develop; `1536Mi` for a 1.5Gi image on 1.19 |
| **`/dev/shm`** | A **memory-backed** `emptyDir` the operator mounts per session, `2Gi` by default (`KasmWorkspace.spec.shmSize`). Counts against the pod's memory limit **and** node RAM - it is not disk, and it is not additive to the limit. | `2Gi` |
| **Recording buffer** | Only when recording is on: `KasmWorkspace.spec.recordingBufferSize`, default `3Gi`, on the pod's **ephemeral storage**. The operator seeds the container's ephemeral-storage request/limit to cover it (observed: a `1Gi` buffer produced a `2Gi` ephemeral floor). | `3Gi` |
| **Image layers** | Node disk in the container runtime's image store, shared between every session on that node using the same image. | measure - see [Measure, do not guess](#measure-do-not-guess) |

> **The `/dev/shm` trap.** The 2Gi shm lives *inside* the pod's memory limit. A 2768Mi workspace
> that fills its shm has ~720Mi left for the desktop, the browser and Xorg; a 1536Mi workspace
> cannot even hold the default shm. Either raise `memory_bytes` on the image or lower the
> workspace's `shmSize`. Kubernetes' own 64Mi default is what the operator is protecting you from  - 
> 2Gi is not a number to leave unexamined at the small end.

## What the node and cluster cost before any session

| Component | Scope | Requests (chart defaults) |
| --------- | ----- | ------------------------- |
| `kasm-agent-operator` | one pod per **cluster** | `100m` / `256Mi`, request = limit (Guaranteed) |
| `kasm-otel-collector` | one pod per **release** | `50m` / `128Mi` (limits `250m` / `512Mi`) |
| Agent + session proxy | one of each per **Agent CR** (`agent.sessionProxy.replicas` scales the proxy) | operator defaults - `agent.resources` is empty and the proxy has no chart value; measure |
| `kasm-node-prep` | DaemonSet, **per node** | `100m` / `256Mi` (limits `1000m` / `1Gi` for a module build) |
| `kasm-video-device-plugin` | DaemonSet, **per node** | `10m` / `32Mi` (limits `50m` / `64Mi`) |
| `kasm-egress-installer` | DaemonSet, **per node** | `50m` / `64Mi` (limits `500m` / `256Mi`) |
| Image puller | DaemonSet on the **session nodes** (on by default), one idle container per staged image | tiny idle footprint (`1m` / `8Mi` per container); `agent.imagePuller.resources` overrides |
| CSI node plugins, KMM workers, cluster system pods | **per node** | cluster-specific - measure |

## The four ceilings

A node runs out of one of these first. Find which.

| Ceiling | The number | Notes |
| ------- | ---------- | ----- |
| **Memory** | node allocatable RAM − fixed overhead | Memory request = limit, so the request is a hard reservation. Size against the **limit**, not a guess at the working set. |
| **CPU requests** | node allocatable CPU − fixed overhead | Under *Shares*/*Inherit* there is no CPU limit, so this bounds **scheduling**, not throughput. Frequently the binding ceiling - see [Worked example](#worked-example). |
| **`maxPods`** | kubelet default **110 per node** | Includes the DaemonSets, the agent, the session proxy, CSI plugins and every system pod, not only sessions. A hidden ceiling on small, dense sessions. |
| **Disk** | `80GB + (users × space_per_user)` on the volume holding the image store | Kasm's own formula. Image GC runs at 90/80% - the kubelet's image GC thresholds are node settings, see [Node tuning and swap](../how-to/nodes/tuning-and-swap.md). |

Swap is a fifth, softer one - and for **workspace sessions it currently does nothing**.
`LimitedSwap` grants a container swap only when its **memory request is strictly less than its
memory limit**; a container with request = limit gets none, whatever its QoS class or CPU
allocation method. Kasm sets a workspace's memory request *and* limit from the same `memory_bytes`, so every
session container has request = limit and no swap. The node's swapfile still helps other Burstable
pods with headroom - the agent, the sidecars, system pods - so it is not wasted, but do not size a
node expecting sessions to spill into it. The worked example, the rationale and the node-side procedure, including the kubelet
setting that must land first, are in [Node tuning and swap](../how-to/nodes/tuning-and-swap.md).

## Worked example

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

**CPU requests bind, at 3 sessions per node** - three times tighter than RAM, on a node that is
nowhere near CPU-saturated, because under *Shares* that 2-core request is a scheduling reservation
with no ceiling behind it. The levers, in order of preference: shrink the request with
`agent.workspaceCPURequestPercent` (below), lower `cores` on the workspace image (the request is
what the scheduler counts), pick a CPU-denser node shape, or move the image to *Quotas* only if you
actually want a throughput ceiling.

Same node, a 1-core / 1536Mi image: 6500m ÷ 1000m = **6** sessions on CPU, 18 on RAM. CPU still
binds - and the default 2Gi `/dev/shm` no longer fits inside a 1536Mi limit at all.

### Shrinking the CPU request without changing the image

`agent.workspaceCPURequestPercent` (1-100, default 100) is the share of an image's `cores` a session
pod reserves as its CPU **request**. The manager's `cores` are a soft hint the Docker agent only ever
applied as a scheduling weight; as a Kubernetes request they are a hard reservation, which is why the
worked example fills a node's CPU while it sits idle. Lowering the percent shrinks only the request,
so more sessions bin-pack per node; any CPU **limit** (on a *Quotas* image) is untouched, so a session
can still burst to its full `cores`.

In the worked example, `workspaceCPURequestPercent: 50` halves the 2-core request to 1000m, so CPU
requests fit **6** sessions per node instead of 3, still under the 9 that RAM allows. The agent scales
the capacity it reports to the manager by the same factor, so the manager's session accounting keeps
matching what the scheduler can actually place - set it too low and you oversubscribe CPU, so treat it
as trading idle-time burst headroom for density, and measure a real session's usage (below) before
going far below 50.

## Measure, do not guess

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

## Node pools and placement

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
targeting needs no chart value - the manager's `include_labels` become `spec.nodeSelector` on the
`KasmWorkspace` ([node targeting](../reference/feature-matrix.md#observability-and-operations)).

**Taints need care.** `nodePrep`, `videoDevicePlugin` and `egressInstaller` each expose a
`tolerations` value, and their READMEs document the matching pattern:

```yaml
tolerations:
  - key: kasm.com/workspaces
    operator: Exists
    effect: NoSchedule
```

Session pods have their own tolerations value, `agent.workspacesTolerations`, so a `NoSchedule` taint
on the pool no longer keeps sessions off it - set it to the pool's taint alongside the DaemonSets'.
`agent.workspacesNodeSelector` is label-based placement on top of that. The operator adds placement of
its own: after an eviction or OOM it excludes that node from the replacement pod's affinity until a
back-off passes and the node's pressure conditions clear. The full procedure is [Scope workspaces to
specific nodes](../how-to/nodes/scope-workspaces-to-nodes.md).

## Growing capacity: autoscaling and standby

Everything above sizes a **fixed** pool: when its binding ceiling is reached the manager stops routing
launches here, and a launch that races in fails. Two opt-in `Agent` features change that, and they
compose.

**`agent.workspacesAutoscaling`** makes a full pool one the autoscaler can grow. A cluster autoscaler
(Cluster Autoscaler, Karpenter, a cloud node pool) only adds a node for a pod it already sees
unschedulable - but by default the agent never lets one get that far: it reports only the room that
exists, so the manager refuses the launch before a pod is ever created. With autoscaling on, the agent
counts nodes the autoscaler could still add (up to `maxNodes`, or one past what is running when no cap
is set) as capacity, stops withholding an image that would fit a fresh node, and holds an
unschedulable session `Pending`/`WaitingForCapacity` for `schedulingTimeoutSeconds` (default 600, the
clock restarting once the pod is scheduled, since a fresh node has no pre-pulled images) rather than
failing it in seconds. It needs an autoscaler actually watching the workspace nodes; without one, a
session just waits out the timeout.

**`agent.workspacesAutoscaling.standby`** removes the wait. It runs a Deployment of low-priority pause-container
placeholders on the workspace nodes (same `workspacesNodeSelector`/`workspacesTolerations`), each
requesting what a session does. A real session outranks them, so the scheduler evicts a placeholder
and the session starts at once; the evicted placeholder then goes unschedulable, which is what makes
the autoscaler add a node - so the headroom comes back with nobody waiting on it. It runs the placeholders under a PriorityClass with a **negative** value, and works out of the box:
`workspacesAutoscaling.standby.enabled: true` is enough. By default the chart derives the class name from the agent
(`<name>-standby`) and **creates** it (at `workspacesAutoscaling.standby.priorityClass.value`, which must be negative). Point
`workspacesAutoscaling.standby.priorityClassName` at a specific name to override the derived one, and set
`workspacesAutoscaling.standby.priorityClass.create: false` to reference a class a cluster admin manages instead of creating
it. Since a PriorityClass is cluster-scoped, the derived per-agent name keeps two agent releases from
clashing; give them distinct names (or a shared admin-managed one) if you override it.
`replicas` is how much headroom to hold - fixed, or `externallyScaled` to let a KEDA `ScaledObject` or
an HPA drive it from real demand. Each placeholder defaults to the largest request in the agent's
catalog (`status.workspaces.largestRequest`), so one placeholder's room fits any image; set
`workspacesAutoscaling.standby.resources` to pin a size instead — a bare resource map like `{cpu: "2", memory: 2Gi}` (applied as
both request and limit), not a pod-style `{requests, limits}` block.

**You do not need both — they are independent, and each is turned on by its own `enabled`.** Enable
whichever fits:

- **`workspacesAutoscaling` on its own** lets a session *wait* for a node instead of the launch failing
  on a full pool. It is only useful with a real node autoscaler watching the workspace nodes — without
  one, the session just waits out `schedulingTimeoutSeconds` and then fails.
- **`workspacesAutoscaling.standby` on its own** starts sessions *instantly* from reserved room, and because an evicted
  placeholder goes unschedulable it is itself what prompts a node autoscaler to grow the pool. It still
  helps without an autoscaler (the instant start), it just won't refill the headroom on its own.
- **Both together** is the fullest setup: standby absorbs a burst instantly, while
  `workspacesAutoscaling` catches the case where even the placeholder-freed room isn't enough and holds
  that session `WaitingForCapacity` rather than failing it. Both ultimately depend on a node autoscaler
  to add real capacity.

Standby placeholders are counted as free room, not used, so they do not themselves make the pool look
full.

> **Caveat — this is chart-managed, not manager-managed.** Kubernetes cluster autoscaling here
> (`workspacesAutoscaling` and `workspacesAutoscaling.standby`) is configured and driven **entirely through this chart** — the
> `Agent`'s Helm values — and observed through Kubernetes (`kubectl get agent`, the placeholder
> Deployment, and your node autoscaler's own logs). The Kasm **manager, API and admin UI have no
> controls over it and no visibility into it**, with one exception: the capacity the agent reports each
> heartbeat (its cores, sessions and image availability) still shows up there. There is no autoscale
> config, schedule, or status for this in the Kasm admin panel the way there is for Kasm's own cloud-VM
> autoscaler; treat it as infrastructure you manage with Helm and `kubectl`, not from Kasm.

### Scaling standby headroom (KEDA or HPA)

`workspacesAutoscaling.standby.replicas` holds a **fixed** amount of headroom. To size it to load instead, set
`workspacesAutoscaling.standby.externallyScaled: true`: the operator then applies `replicas` only once, at creation, and
leaves the count to a horizontal autoscaler you run. This chart installs neither KEDA nor the autoscaler
object — you apply that yourself, against the placeholder Deployment, which is named
`<agent name>-workspace-standby` (for the default agent name, `k8s-agent-workspace-standby`).

A KEDA `ScaledObject` that keeps one placeholder per five running sessions:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: k8s-agent-workspace-standby
  namespace: kasm
spec:
  scaleTargetRef:
    name: k8s-agent-workspace-standby                     # the standby Deployment
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
    - type: kubernetes-workload
      metadata:
        podSelector: app.kubernetes.io/component=workspace # count running session pods
        value: "5"                                         # one placeholder per five sessions
```

Scale on the **running sessions**, as here (`component=workspace`), not on the agent's `launchable`
figures — those *fall* as more room is needed, the opposite of what a horizontal autoscaler expects.

A native `HorizontalPodAutoscaler` can drive the same Deployment, but note the catch: the placeholders
are idle pause pods, so a **resource** (CPU/memory) HPA is useless — utilisation is always ~0. You need a
metric for the *session* count, which a custom/external-metrics adapter (for example
[prometheus-adapter](https://github.com/kubernetes-sigs/prometheus-adapter)) must expose; KEDA above just
packages that plumbing for you. With such an adapter serving an external metric, the HPA is:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: k8s-agent-workspace-standby
  namespace: kasm
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: k8s-agent-workspace-standby            # the standby Deployment
  minReplicas: 1
  maxReplicas: 10
  metrics:
    - type: External
      external:
        metric:
          name: kasm_running_sessions            # your adapter's metric for component=workspace pods
        target:
          type: AverageValue
          averageValue: "5"                       # one placeholder per five sessions
```

Either way, leave `externallyScaled: false` (the default) to keep the fixed `replicas` with no external
autoscaler.

**Decisions**

- [ ] Per-session cost written down from **your** images' `cores` / `memory_bytes`, not from the defaults above.
- [ ] `shmSize` checked against each image's memory limit - the shm is inside the limit.
- [ ] Recording decided; if on, the Kasm licence confirmed to cover it, and the `recordingBufferSize` and the resulting ephemeral-storage floor budgeted.
- [ ] Fixed per-node overhead measured on a real node, not assumed.
- [ ] The binding ceiling identified (CPU requests / memory / `maxPods` / disk) and the arithmetic recorded.
- [ ] `maxPods` checked against the planned session density.
- [ ] Node disk sized with `80GB + (users × space_per_user)` on the **image-store** volume.
- [ ] Swap decision made - understanding sessions get **no** swap (memory request = limit); the swapfile helps only other Burstable pods.
- [ ] Node pool labelled; `agent.workspacesNodeSelector` and the DaemonSet `nodeSelector`s agree.
- [ ] If the pool is meant to grow: an autoscaler confirmed to watch the workspace nodes, `agent.workspacesAutoscaling` enabled, and `maxNodes` set to the pool's real limit.
- [ ] If using `agent.workspacesAutoscaling.standby`: the PriorityClass decided (the chart derives and creates `<name>-standby` by default; set `workspacesAutoscaling.standby.priorityClassName` and/or `workspacesAutoscaling.standby.priorityClass.create: false` to use an admin-managed one), and the headroom (`replicas`, or the KEDA/HPA path) decided.
- [ ] If the pool is tainted: session scheduling onto it verified.
- [ ] A load test scheduled to validate all of the above before go-live.

---

## Scaling the session proxy

The session proxy is not the workspace tier: it is the nginx pod every session's streams pass through on
the way to its workspace. One pod carries many sessions, but a pod **removed** takes with it every stream
it still holds, so the proxy is sized and scaled on its own terms, separate from the node capacity above.

Two things make it unlike an ordinary Deployment:

- **Its load is connections, not CPU.** A websocket relay spends almost no CPU, so a CPU-based autoscaler
  never fires before a pod's connections run out. Size and scale it by *session count*.
- **Scaling in is destructive.** A pod leaving the Service stops taking new connections at once, but the
  desktop streams already on it keep running until `sessionProxy.drainTimeoutSeconds` (default 300)
  elapses, then are cut. Session streams last hours, so set the drain to how long a rollout or a scale-in
  may take, and scale **in** slowly.

**One pod's capacity.** `sessionProxy.nginx` sets `workerProcesses` and `workerConnections`. A proxied
connection uses two of a worker's connections (client and upstream), and a session holds one per service
in its port map (vnc, audio, uploads, ...), so a pod carries about
`workerProcesses × workerConnections / (2 × services-per-session)` sessions. Set `sessionProxy.resources`
requests to match, so the scheduler and a node autoscaler account for the pod instead of packing it onto
a node they later remove.

**Operator-driven autoscaling.** `sessionProxy.autoscaling` has the operator set the replica count from
the live session count — `ceil(sessions / sessionsPerReplica)`, clamped to `minReplicas`..`maxReplicas`.
It grows at once and shrinks one pod at a time, and only once a lower count has been called for without
interruption for `scaleDownStabilizationSeconds` (default 1800); each removed pod then drains. While it is
on, `sessionProxy.replicas` is ignored, and `status.sessionProxy` reports `replicas`/`desiredReplicas`.

```yaml
sessionProxy:
  autoscaling:
    enabled: true
    sessionsPerReplica: 25      # from the nginx capacity above
    minReplicas: 2
    maxReplicas: 20
    scaleDownStabilizationSeconds: 1800
  nginx:
    workerConnections: 2048
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
```

**External autoscaling (KEDA or HPA).** `sessionProxy.externallyScaled: true` leaves the replica count to
a horizontal autoscaler you run, exactly as `workspacesAutoscaling.standby.externallyScaled` does (`sessionProxy.replicas`
applies only when the Deployment is first created). The two proxy paths are mutually exclusive — set
`autoscaling` *or* `externallyScaled`, not both. Scale on the **running sessions**
(`component=workspace`), the same trigger the standby example above uses; the proxy Deployment is named
`<agent name>-session-proxy` (`k8s-agent-session-proxy` for the default agent name):

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: k8s-agent-session-proxy
  namespace: kasm
spec:
  scaleTargetRef:
    name: k8s-agent-session-proxy                        # the session-proxy Deployment
  minReplicaCount: 2
  maxReplicaCount: 20
  triggers:
    - type: kubernetes-workload
      metadata:
        podSelector: app.kubernetes.io/component=workspace # count running session pods
        value: "25"                                        # one proxy pod per 25 sessions
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 1800                 # scale in slowly; pods still drain
```

**Placement.** A proxy pod on a node a cluster autoscaler later shrinks goes down with the node, dropping
its streams. Keep the proxy on stable nodes with `sessionProxy.nodeSelector` (unset, the pods follow the
agent's own `nodeSelector`), and give it `resources` requests so the autoscaler counts it.
`sessionProxy.podDisruptionBudget` (one of `minAvailable`/`maxUnavailable`) bounds how many pods a single
drain may take.

---

## The control-plane half

The control plane is not sized with this model. One value covers it:

| `kasm-helm.deploymentSize` | Sized for |
| -------------------------- | --------- |
| `small` (the default) | up to 10–15 concurrent sessions |
| `medium` | up to 25–30 |
| `large` | 50+ |

It sets requests, limits and the Guacamole cluster size across every control-plane component at
once. Override an individual component under `kasm-helm.components.<name>.resources` when a real
measurement disagrees with the preset. The database is sized separately - see
[Database](../how-to/database.md).
