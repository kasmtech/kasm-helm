# GPU nodes (CUDA and EGL/DRI)

> **Applies to:** [GPU workspaces (CUDA) and GPU graphics acceleration (EGL/DRI)](../../reference/feature-matrix.md#devices-gpu-webcam-audio), and [node targeting](../../reference/feature-matrix.md#observability-and-operations) · **Charts/values:** `gpuOperator.enabled`, `agent.gpu.enabled`, `gpuOperator.driver.enabled`, `gpuOperator.toolkit.enabled`, `gpuOperator.devicePlugin.enabled`, `gpuOperator.nfd.enabled`, `agent.workspacesNodeSelector`, `agent.nodeSelector`

> **Honest scope note.** This repository's lab clusters have **no GPU nodes**. The chart path below
> is render-validated (it is exercised by the `infra` test scenario) but has not been run against
> real NVIDIA hardware here. Treat the NVIDIA-side steps as pointers to NVIDIA's own procedure, not
> as live-verified output.

## Why this is needed

Two values, always. `gpuOperator.enabled=true` installs the NVIDIA GPU Operator so nodes advertise
`nvidia.com/gpu`; `agent.gpu.enabled=true` sets `KASM_GPU_OPERATOR_ENABLED` on the agent, which is
what makes it put `nvidia.com/gpu: N` into a workspace pod's resource limits. Enable only the
operator and you have GPUs nobody requests. Enable only the agent flag and you request a resource no
node advertises, so sessions stay `Pending`.

`agent.gpu.enabled` also gates the **DRI device mounts** the operator adds for EGL graphics
acceleration, so it is required on the EGL path too — even when no CUDA device plugin is involved.

## Before you start

* NVIDIA GPU nodes, labelled (and usually tainted) for GPU workloads.
* A **driver strategy**, decided up front:
  * *Operator-managed driver container* — `gpuOperator.driver.enabled=true` (the operator builds and
    loads the driver on the node).
  * *Pre-installed host drivers* — most cloud GPU images already have them; set
    `gpuOperator.driver.enabled=false` or the operator will fight the host driver.
* The GPU Operator is **cluster-scoped**: install it once per cluster, from at most one release
  ([Scope](../../../charts/kasm-agent/README.md#scope)). If NVIDIA's device plugin is already running,
  leave `gpuOperator.enabled=false` and set only `agent.gpu.enabled=true`.
* Node Feature Discovery does the GPU labelling. Set `gpuOperator.nfd.enabled=false` if NFD already
  runs in the cluster.

Distro / cloud variants:

| Platform | Notes |
| -------- | ----- |
| k3s / RKE2 | Works, but the operator must find the containerd config; follow NVIDIA's k3s notes. |
| kubeadm / vanilla | The reference path. Operator-managed driver is fine. |
| EKS | GPU AMIs ship drivers and the toolkit — `gpuOperator.driver.enabled=false`. |
| AKS | The AKS GPU image ships drivers — `gpuOperator.driver.enabled=false`; or use a plain image with the operator driver. |
| GKE | GKE installs drivers via its own DaemonSet. Prefer that plus `agent.gpu.enabled=true` and `gpuOperator.enabled=false`. |
| OpenShift | Use the Red Hat certified NVIDIA GPU Operator from OperatorHub, not this subchart. |

EGL/DRI graphics acceleration is a **node-image** concern: drivers pre-installed, with
`/dev/dri/card0` and `/dev/dri/renderD128` present. No chart prepares the node image.

## Steps

1. **Label the GPU nodes** so sessions can be targeted at them.

   ```console
   kubectl label node <gpu-node> kasm-gpu=true
   ```

2. **Enable both halves.**

   ```yaml
   gpuOperator:
     enabled: true
     driver:
       enabled: false      # true only when the host has no NVIDIA driver
     toolkit:
       enabled: true
     devicePlugin:
       enabled: true
     nfd:
       enabled: true       # false if NFD already runs in this cluster
   agent:
     gpu:
       enabled: true
     workspacesNodeSelector:
       kasm-gpu: "true"
   ```

3. **Upgrade the release**, allowing time for the operator's operands to roll out.

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
     -n kasm-agent -f values.yaml --timeout 20m
   ```

4. **For EGL/DRI**, additionally confirm the node image exposes the DRI devices and that the
   workspace image carries the `com.kasmweb.gpu_acceleration_egl=nvidia` label. The operator adds the
   `hostPath` `CharDevice` mounts itself when GPU support is on — there is nothing else to set.

5. **Airgapped?** Do **not** mirror the GPU Operator from `make images-agent`; it pulls a much larger
   operand set at runtime. Follow NVIDIA's air-gapped procedure and pass its values through with the
   `gpuOperator.` prefix — see
   [Airgapped installation → Third-party subcharts](../../../charts/kasm-agent/README.md#4-third-party-subcharts).

## Verify

```console
kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

Expected indicator: a non-empty integer (`1`, `4`, …) for each GPU node — not `<none>`.

Then a direct device test:

```console
kubectl run cuda-probe --rm -it --restart=Never \
  --image=nvidia/cuda:12.4.1-base-ubuntu22.04 \
  --overrides='{"spec":{"nodeSelector":{"kasm-gpu":"true"},"containers":[{"name":"cuda-probe","image":"nvidia/cuda:12.4.1-base-ubuntu22.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":1}}}]}}'
```

Expected indicator: `nvidia-smi` prints the driver/CUDA version table and lists the GPU. A pod stuck
`Pending` with `Insufficient nvidia.com/gpu` means the device plugin has not advertised yet.

For EGL/DRI, inside a running session:

```console
ls -l /dev/dri
```

Expected indicator: `card0` and `renderD128` present.

Finally, launch a Kasm GPU workspace and confirm the pod carries the limit:

```console
kubectl get pod -n kasm-agent <session-pod> \
  -o jsonpath='{.spec.containers[0].resources.limits}{"\n"}'
```

## Chart values

Under the `kasm-platform` umbrella:

```yaml
kasm-agent:
  gpuOperator:
    enabled: true
    driver:
      enabled: false
  agent:
    gpu:
      enabled: true
    workspacesNodeSelector:
      kasm-gpu: "true"
```

Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `gpuOperator:` / `agent:`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Nodes advertise `nvidia.com/gpu` but Kasm sessions never request it | `agent.gpu.enabled` left `false` | Set it — both values are required |
| GPU session stays `Pending` with `Insufficient nvidia.com/gpu` | The operator is not installed, or the device plugin has not rolled out on that node | `gpuOperator.enabled=true`; check the operand pods in the operator's namespace |
| Driver pods `CrashLoopBackOff` on a cloud GPU image | `gpuOperator.driver.enabled=true` on a node that already has a host driver | Set `gpuOperator.driver.enabled=false` |
| Duplicate NFD, node labels flapping | NFD already ran in the cluster | `gpuOperator.nfd.enabled=false` |
| Sessions land on non-GPU nodes | No node targeting | `agent.workspacesNodeSelector` (and tolerate the GPU taint) |
| EGL session falls back to software rendering | `/dev/dri` missing on the node image, or the workspace image lacks the EGL label | Prepare the node image; use a workspace image with `com.kasmweb.gpu_acceleration_egl=nvidia` |
| Airgapped install of `gpuOperator` fails pulling operands | The operand set is not in `dist/kasm-agent-images.txt` | Follow NVIDIA's air-gapped procedure, values passed through as `gpuOperator.*` |

## Checklist

- [ ] GPU nodes labelled (and taints planned for)
- [ ] Driver strategy decided — operator-managed vs pre-installed (`gpuOperator.driver.enabled`)
- [ ] `gpuOperator.enabled=true` in exactly one release per cluster (or skipped if a device plugin already exists)
- [ ] `agent.gpu.enabled=true`
- [ ] `agent.workspacesNodeSelector` targets the GPU nodes
- [ ] `kubectl get nodes` shows non-empty `nvidia.com/gpu` allocatable
- [ ] `nvidia-smi` succeeds in a pod requesting `nvidia.com/gpu: 1`
- [ ] EGL only: `/dev/dri/card0` and `/dev/dri/renderD128` present on the node image
- [ ] A Kasm GPU workspace launches and shows the GPU
