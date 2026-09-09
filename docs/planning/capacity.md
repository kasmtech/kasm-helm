> **Applies to:** node sizing for the agent half; the control plane sizes with `kasm-helm.deploymentSize` · **Charts/values:** `agent.workspacesNodeSelector`, `nodePrep.tuning.*`, `kasm-helm.deploymentSize`

# Capacity

Everything below is a **planning estimate to validate with a load test**, not a guarantee. The
per-session numbers are defaults observed on lab control planes; yours come from your own workspace
images. Measure before you commit hardware.

## What one session costs

A workspace pod's resources come from the workspace image's `cores` and `memory_bytes` in the Kasm
manager — not from any chart value.

| Dimension | How it is set | Observed defaults |
| --------- | ------------- | ----------------- |
| **CPU** | A **request only** under `cpu_allocation_method` *Shares* or *Inherit* — burstable, no ceiling. A request *and* an equal limit under *Quotas*. | `requests.cpu: 2` on a develop control plane; `cpu: 1` for a 1-core image on 1.19 |
| **Memory** | Always request **=** limit, from `memory_bytes` — a hard reservation, and a hard OOM ceiling. | `2768Mi` on develop; `1536Mi` for a 1.5Gi image on 1.19 |
| **`/dev/shm`** | A **memory-backed** `emptyDir` the operator mounts per session, `2Gi` by default (`KasmWorkspace.spec.shmSize`). Counts against the pod's memory limit **and** node RAM — it is not disk, and it is not additive to the limit. | `2Gi` |
| **Recording buffer** | Only when recording is on: `KasmWorkspace.spec.recordingBufferSize`, default `3Gi`, on the pod's **ephemeral storage**. The operator seeds the container's ephemeral-storage request/limit to cover it (observed: a `1Gi` buffer produced a `2Gi` ephemeral floor). | `3Gi` |
| **Image layers** | Node disk in the container runtime's image store, shared between every session on that node using the same image. | measure — see [3.5](#measure-do-not-guess) |

> **The `/dev/shm` trap.** The 2Gi shm lives *inside* the pod's memory limit. A 2768Mi workspace
> that fills its shm has ~720Mi left for the desktop, the browser and Xorg; a 1536Mi workspace
> cannot even hold the default shm. Either raise `memory_bytes` on the image or lower the
> workspace's `shmSize`. Kubernetes' own 64Mi default is what the operator is protecting you from —
> 2Gi is not a number to leave unexamined at the small end.

## What the node and cluster cost before any session

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

## The four ceilings

A node runs out of one of these first. Find which.

| Ceiling | The number | Notes |
| ------- | ---------- | ----- |
| **Memory** | node allocatable RAM − fixed overhead | Memory request = limit, so the request is a hard reservation. Size against the **limit**, not a guess at the working set. |
| **CPU requests** | node allocatable CPU − fixed overhead | Under *Shares*/*Inherit* there is no CPU limit, so this bounds **scheduling**, not throughput. Frequently the binding ceiling — see [3.4](#worked-example). |
| **`maxPods`** | kubelet default **110 per node** | Includes the DaemonSets, the agent, the session proxy, CSI plugins and every system pod — not just sessions. A hidden ceiling on small, dense sessions. |
| **Disk** | `80GB + (users × space_per_user)` on the volume holding the image store | Kasm's own formula. Image GC runs at 90/80% — see [Settings this chart cannot make for you](../../charts/kasm-agent/README.md#settings-this-chart-cannot-make-for-you). |

Swap is a fifth, softer one — and for **workspace sessions it currently does nothing**.
`LimitedSwap` grants a container swap only when its **memory request is strictly less than its
memory limit**; a container with request = limit gets none, whatever its QoS class or CPU
allocation method (this was verified on k3s 1.36 and kubeadm 1.34, not just derived from the QoS
class). Kasm sets a workspace's memory request *and* limit from the same `memory_bytes`, so every
session container has request = limit and no swap. The node's swapfile still helps other Burstable
pods with headroom — the agent, the sidecars, system pods — so it is not wasted, but do not size a
node expecting sessions to spill into it. The worked example and the full rationale are in
[kasm-agent → Swap, and the kubelet setting that must come first](../../charts/kasm-agent/README.md#swap-and-the-kubelet-setting-that-must-come-first);
the node-side procedure, including the kubelet setting that must land first, is
[Node tuning and swap](nodes/tuning-and-swap.md).

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

**CPU requests bind, at 3 sessions per node** — three times tighter than RAM, on a node that is
nowhere near CPU-saturated, because under *Shares* that 2-core request is a scheduling reservation
with no ceiling behind it. The levers, in order of preference: lower `cores` on the workspace image
(the request is what the scheduler counts), pick a CPU-denser node shape, or move the image to
*Quotas* only if you actually want a throughput ceiling.

Same node, a 1-core / 1536Mi image: 6500m ÷ 1000m = **6** sessions on CPU, 18 on RAM. CPU still
binds — and the default 2Gi `/dev/shm` no longer fits inside a 1536Mi limit at all.

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
targeting needs no chart value — the manager's `include_labels` become `spec.nodeSelector` on the
`KasmWorkspace` ([node targeting](../reference/feature-matrix.md#observability-and-operations)).

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

## The control-plane half

The control plane is not sized with this model. One value covers it:

| `kasm-helm.deploymentSize` | Sized for |
| -------------------------- | --------- |
| `small` (the default) | up to 10–15 concurrent sessions |
| `medium` | up to 25–30 |
| `large` | 50+ |

It sets requests, limits and the Guacamole cluster size across every control-plane component at
once. Override an individual component under `kasm-helm.components.<name>.resources` when a real
measurement disagrees with the preset. The database is sized separately — see
[Database](database.md).
