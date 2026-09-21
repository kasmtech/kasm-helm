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

**`agent.standby`** removes the wait. It runs a Deployment of low-priority pause-container
placeholders on the workspace nodes (same `workspacesNodeSelector`/`workspacesTolerations`), each
requesting what a session does. A real session outranks them, so the scheduler evicts a placeholder
and the session starts at once; the evicted placeholder then goes unschedulable, which is what makes
the autoscaler add a node - so the headroom comes back with nobody waiting on it. It requires a
`priorityClassName` naming a PriorityClass with a **negative** value; rendering fails if
`standby.enabled` is set without one. By default the chart only *references* that PriorityClass, so a
cluster admin creates it out-of-band (the common case, since a PriorityClass is cluster-scoped and
often shared); set `standby.priorityClass.create: true` to have the chart create it instead, with
`standby.priorityClass.value` (which must be negative).
`replicas` is how much headroom to hold - fixed, or `externallyScaled` to let a KEDA `ScaledObject` or
an HPA drive it from real demand. Each placeholder defaults to the largest request in the agent's
catalog (`status.workspaces.largestRequest`), so one placeholder's room fits any image; set
`standby.resources` to pin a size instead.

Used together, standby serves the room instantly and autoscaling refills it in the background. Standby
placeholders are counted as free room, not used, so they do not themselves make the pool look full.

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
- [ ] If using `agent.standby`: a negative-value PriorityClass in `standby.priorityClassName` (admin-managed, or `standby.priorityClass.create: true` to let the chart make it), and the headroom (`replicas`, or the KEDA/HPA path) decided.
- [ ] If the pool is tainted: session scheduling onto it verified.
- [ ] A load test scheduled to validate all of the above before go-live.

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
