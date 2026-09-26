# GPU nodes (CUDA, EGL and DRI)

> **Applies to:** agent · **Charts/values:** `gpuOperator.enabled`, `agent.gpu.enabled`, `gpuOperator.driver.enabled`, `gpuOperator.toolkit.enabled`, `gpuOperator.devicePlugin.enabled`, `gpuOperator.nfd.enabled`, `gpuOperator.devicePlugin.config`, `driDevicePlugin.*`, `agent.workspaceSecurity.driResource`, `agent.workspaceSecurity.deviceAllowlist`, `agent.workspaceSecurity.supplementalGroups`, `agent.workspacesNodeSelector`, `agent.nodeSelector`

> **Scope note.** The NVIDIA-side steps are pointers to NVIDIA's own procedure; follow NVIDIA's
> current documentation for the driver and device-plugin install.

## Why this is needed

Kubernetes lets an unprivileged container open a device only when the container runtime was told
to hand it over, which in practice means a **device plugin** allocated it. Mounting `/dev/dri` or
`/dev/nvidia0` into a session by `hostPath` is not enough: the device appears, but opening it fails
with `Operation not permitted`, whatever the session's user and groups. Every GPU session therefore
goes through a device plugin, and there are two, one per kind of GPU:

| GPU | Resource | What the session gets | Values |
| --- | -------- | --------------------- | ------ |
| NVIDIA | `nvidia.com/gpu` | The GPU, NVIDIA's driver libraries (CUDA, OpenGL/EGL, Vulkan, NVENC) and the GPU's own `/dev/dri` card and render nodes | `gpuOperator.enabled`, `agent.gpu.enabled` |
| Intel, AMD | `kasm.com/dri` | The GPU's `/dev/dri` render and card nodes, and `DRINODE` naming the render node; the image's own Mesa drivers do the rest | `driDevicePlugin.enabled`, `agent.workspaceSecurity.driResource` |

**NVIDIA** needs two values, always. `gpuOperator.enabled=true` installs the NVIDIA GPU Operator so
nodes advertise `nvidia.com/gpu`; `agent.gpu.enabled=true` sets `KASM_GPU_OPERATOR_ENABLED` on the
agent, which is what makes it put `nvidia.com/gpu: N` into the pod of a workspace whose image asks
for GPUs. Enable only the operator and you have GPUs nobody requests. Enable only the agent flag and
you request a resource no node advertises, so sessions stay `Pending`. EGL on NVIDIA needs nothing
further: the NVIDIA runtime adds the GPU's DRI nodes itself.

**Intel and AMD** also need two values. `driDevicePlugin.enabled=true` installs the DRI device
plugin, which advertises each Intel or AMD GPU's render node as `kasm.com/dri`, shared by up to
`driDevicePlugin.deviceShares` sessions; `agent.workspaceSecurity.driResource=kasm.com/dri` makes
the agent request it for any image whose run config passes a `/dev/dri` device through. Without the
second, the agent falls back to a `hostPath` mount the session cannot open, and it renders in
software.

## Before you start

* GPU nodes, labelled (and usually tainted) for GPU workloads.
* **NVIDIA:** a driver strategy, decided up front:
  * *Operator-managed driver container* - `gpuOperator.driver.enabled=true` (the operator builds and
    loads the driver on the node).
  * *Pre-installed host drivers* - most cloud GPU images already have them; set
    `gpuOperator.driver.enabled=false` or the operator will fight the host driver.
* **NVIDIA:** the GPU Operator is **cluster-scoped**: install it once per cluster, from at most one
  release ([Scope](../../../charts/kasm-agent/README.md#scope)). If NVIDIA's device plugin is already
  running, leave `gpuOperator.enabled=false` and set only `agent.gpu.enabled=true`. Node Feature
  Discovery does the GPU labelling; set `gpuOperator.nfd.enabled=false` if NFD already runs.
* **NVIDIA on containerd 2.x:** the operator's toolkit writes a `version = 4` containerd drop-in.
  containerd refuses to start when its root `/etc/containerd/config.toml` is an older version (see
  Troubleshooting); migrate the root config first on nodes that still carry a `version = 2` file.
* **Intel and AMD:** the kernel driver (`i915`, `xe` or `amdgpu`) loaded on the node, so that
  `/dev/dri/renderD*` exists. No chart installs it; every mainstream node image has it for
  integrated and discrete GPUs alike.
* **Workspace images:** the image carries the userspace drivers for its GPU - Mesa for Intel and AMD
  (the Kasm images do). An NVIDIA session gets NVIDIA's libraries from the runtime instead.

Distro / cloud variants:

| Platform | Notes |
| -------- | ----- |
| k3s / RKE2 | Works, but the operator must find the containerd config; follow NVIDIA's k3s notes. |
| kubeadm / vanilla | The reference path. Operator-managed driver is fine. |
| EKS | GPU AMIs ship drivers and the toolkit - `gpuOperator.driver.enabled=false`. |
| AKS | The AKS GPU image ships drivers - `gpuOperator.driver.enabled=false`; or use a plain image with the operator driver. |
| GKE | GKE installs drivers via its own DaemonSet. Prefer that plus `agent.gpu.enabled=true` and `gpuOperator.enabled=false`. |
| OpenShift | Use the Red Hat certified NVIDIA GPU Operator from OperatorHub, not this subchart. The DRI device plugin needs `driDevicePlugin.openshift.scc.enabled`. |

## Steps

1. **Label the GPU nodes** so sessions can be targeted at them.

   ```console
   kubectl label node <gpu-node> kasm-gpu=true
   ```

2. **Enable the path for your GPUs.** NVIDIA:

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

   Intel or AMD:

   ```yaml
   driDevicePlugin:
     enabled: true
     deviceShares: 8       # sessions per GPU
   agent:
     workspaceSecurity:
       driResource: kasm.com/dri
       supplementalGroups: [990, 44]   # the node's render and video gids - step 4
     workspacesNodeSelector:
       kasm-gpu: "true"
   ```

   A cluster with both kinds of GPU sets both. The DRI plugin leaves NVIDIA GPUs alone by default
   (`driDevicePlugin.driDrivers: i915,xe,amdgpu`): Mesa cannot drive them, and they get everything
   they need through `nvidia.com/gpu`.

3. **Upgrade the release**, allowing time for the operator's operands to roll out.

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
     -n kasm-agent -f values.yaml --timeout 20m
   ```

4. **Give sessions the node's render group.** Sessions run as uid 1000, and the device plugin hands
   a device over with its node permissions: `/dev/dri/renderD*` is usually mode `0660`, group
   `render`, and `card*` group `video`. A uid-1000 session opens them only as a member of those
   groups, by the node's numeric gids - which differ between distributions (Ubuntu's `render` is
   often 990 or 109, `video` 44).

   ```console
   # on a GPU node
   stat -c '%n %G %g' /dev/dri/renderD* /dev/dri/card*
   ```

   Put the gids `stat` printed in `agent.workspaceSecurity.supplementalGroups`, or in the image's
   run config `group_add`. The gids have to agree across the GPU nodes.

5. **Point the workspace images at the GPU.** In Kasm, set the image's resources and run config:
   * NVIDIA: the image's **GPU count** (`gpu_count`) is the number of `nvidia.com/gpu` it gets;
     one is normal. Set `HW3D=true` in its run config environment for hardware-accelerated
     rendering.
   * Intel or AMD: pass a render node through in the run config, as on a Docker agent, and set
     `HW3D=true`:

     ```json
     { "devices": ["/dev/dri/renderD128:/dev/dri/renderD128:rwm"],
       "environment": { "HW3D": "true" } }
     ```

     With `driResource` set, the agent turns any allowed `/dev/dri` entry into one `kasm.com/dri`,
     and the plugin picks the node: the session gets whichever render node it allocated and
     `DRINODE` set to it, so the path in the run config does not have to match the node. Which host
     devices a run config may pass through at all is `agent.workspaceSecurity.deviceAllowlist`
     (default: the DRI card and render nodes; `["none"]` passes none).

   Without `DRINODE`, a session uses the first render node it can see.

6. **Airgapped?** Do **not** mirror the GPU Operator from `make images-agent`; it pulls a much larger
   operand set at runtime. Follow NVIDIA's air-gapped procedure and pass its values through with the
   `gpuOperator.` prefix - see [Registries and airgap](../registries-and-airgap.md). The DRI device
   plugin is the same image as the video device plugin and is in the image list.

A GPU session is not isolated from the others on its node: see the next section before putting
several on one GPU.

## Sharing a GPU between sessions

### Intel and AMD

`driDevicePlugin.deviceShares` sets how many sessions share each GPU (8 by default). With more than
one GPU on a node, the plugin puts each new session on the GPU with the most shares free. Every
session on a GPU shares its memory and its time, so size the shares to the GPU's memory over what a
session needs.

### NVIDIA (time-slicing)

By default each `nvidia.com/gpu` is one physical GPU, and a session that asks for one holds it
alone. NVIDIA's device plugin can instead advertise each GPU as several time-sliced replicas, so
that many sessions share it. Nothing on the Kasm side changes: the agent requests `nvidia.com/gpu`
as before and counts the replicas when it reports capacity.

```yaml
gpuOperator:
  devicePlugin:
    config:
      create: true
      name: time-slicing-config
      default: any              # the entry below applies to every GPU node
      data:
        any: |-
          version: v1
          flags:
            migStrategy: none
          sharing:
            timeSlicing:
              renameByDefault: false          # keep the resource name nvidia.com/gpu
              failRequestsGreaterThanOne: true
              resources:
                - name: nvidia.com/gpu
                  replicas: 8                 # sessions per physical GPU
```

* Keep `renameByDefault: false`. With `true` the resource becomes `nvidia.com/gpu.shared`, which
  the agent never requests, so GPU sessions never schedule.
* Keep `failRequestsGreaterThanOne: true`. Two replicas of a time-sliced GPU are the same GPU, not
  twice as much; this makes such a request fail rather than silently get one GPU's worth.
* To use different replica counts per node pool, add more entries under `data` and label each node
  with `nvidia.com/device-plugin.config=<entry>`.
* Changing the sharing config of a running cluster takes effect once the device plugin and GPU
  Feature Discovery pods restart:

  ```console
  kubectl -n <gpu-operator-namespace> delete pod -l app=nvidia-device-plugin-daemonset
  kubectl -n <gpu-operator-namespace> delete pod -l app=gpu-feature-discovery
  ```

Time-slicing isolates nothing: every session on a GPU shares its video memory and its compute
time, so one heavy session slows its neighbours and one that exhausts video memory can crash them.
Size `replicas` so that the GPU's memory divided by the replicas covers a session (24GB across 8
sessions leaves 3GB each).

NVIDIA's MPS (`sharing.mps` in place of `sharing.timeSlicing`) also works with Kasm sessions,
including mixed uid-1000 and root sessions on one GPU. Its per-client memory and compute limits
apply to CUDA work only: rendering and video encoding use the GPU outside MPS, so for desktop
sessions it behaves like time-slicing. The MPS device plugin also mounts a `/dev/shm` shared by
every MPS client on the GPU; Kasm sessions always mount their own `/dev/shm` over it, which keeps
their shared memory private without affecting MPS.

On GeForce cards NVIDIA's driver limits how many video encode (NVENC) sessions run at once per
system; sessions beyond the limit encode on the CPU. Datacenter and workstation GPUs have no such
limit.

## Verify

```console
kubectl get nodes -o custom-columns='NODE:.metadata.name,NVIDIA:.status.allocatable.nvidia\.com/gpu,DRI:.status.allocatable.kasm\.com/dri'
```

Expected indicator: a non-empty integer for each GPU node, in the column of its path - GPUs times
replicas for `nvidia.com/gpu`, GPUs times `deviceShares` for `kasm.com/dri` - not `<none>`. A
time-sliced node also carries `nvidia.com/gpu.replicas` and `nvidia.com/gpu.sharing-strategy`
labels.

NVIDIA, a direct device test:

```console
kubectl run cuda-probe --rm -it --restart=Never \
  --image=nvidia/cuda:12.9.1-base-ubuntu24.04 \
  --overrides='{"spec":{"nodeSelector":{"kasm-gpu":"true"},"containers":[{"name":"cuda-probe","image":"nvidia/cuda:12.9.1-base-ubuntu24.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":1}}}]}}'
```

Expected indicator: `nvidia-smi` prints the driver/CUDA version table and lists the GPU. A pod stuck
`Pending` with `Insufficient nvidia.com/gpu` means the device plugin has not advertised yet.

Inside a running GPU session:

```console
echo $DRINODE; ls -l /dev/dri
```

Expected indicator: a render node (and its card node) present, owned by a group the session is in
(`id` lists it), and `DRINODE` naming it on the DRI path.

Finally, launch a Kasm GPU workspace and confirm the pod carries the resource:

```console
kubectl get pod -n kasm-agent <session-pod> \
  -o jsonpath='{.spec.containers[0].resources.limits}{"\n"}'
```

## Chart values

Under the `kasm-platform` umbrella:

```yaml
kasm-agent:
  gpuOperator:              # NVIDIA
    enabled: true
    driver:
      enabled: false
  driDevicePlugin:          # Intel, AMD
    enabled: true
  agent:
    gpu:
      enabled: true
    workspaceSecurity:
      driResource: kasm.com/dri
      supplementalGroups: [990, 44]
    workspacesNodeSelector:
      kasm-gpu: "true"
```

Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `gpuOperator:` / `agent:`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Nodes advertise `nvidia.com/gpu` but Kasm sessions never request it | `agent.gpu.enabled` left `false`, or the image has no GPU count | Set it - both values are required - and give the image a GPU count |
| GPU session stays `Pending` with `Insufficient nvidia.com/gpu` or `Insufficient kasm.com/dri` | The device plugin is not installed, has not rolled out on that node, or every share is taken | Check the plugin pods; raise the replicas or `deviceShares`, or add GPU nodes |
| `/dev/dri/renderD128` is in the session but opening it fails with `Operation not permitted` | It was mounted by `hostPath`, which only a privileged container can open | `driDevicePlugin.enabled` plus `agent.workspaceSecurity.driResource` (Intel, AMD), or `nvidia.com/gpu` (NVIDIA) |
| The render node opens with `Permission denied` for `kasm-user` | The session runs as uid 1000 without the device's `render`/`video` group | `agent.workspaceSecurity.supplementalGroups` with the node's gids, or `group_add` in the image's run config (step 4) |
| An Intel or AMD session renders in software though the node has the GPU | `agent.workspaceSecurity.driResource` unset (the release notes warn), the run config passes no `/dev/dri` device, or `HW3D` is not set | Set `driResource`; add the device and `HW3D` to the run config (step 5) |
| `kasm.com/dri` is 0 on a node with an NVIDIA GPU only | NVIDIA GPUs are left to `nvidia.com/gpu` by default | Use the NVIDIA path; `driDevicePlugin.driDrivers` lists the drivers advertised |
| containerd fails to start after the GPU Operator installs, `drop-in config version 4 higher than root config version 2` | The toolkit's containerd drop-in is newer than the node's root config | On the node: `containerd config migrate > /tmp/config.toml`, review it, replace `/etc/containerd/config.toml`, restart containerd |
| A new time-slicing or MPS config does not show in allocatable | The device plugin and GPU Feature Discovery read the config at start | Restart both (see [time-slicing](#nvidia-time-slicing)) |
| Driver pods `CrashLoopBackOff` on a cloud GPU image | `gpuOperator.driver.enabled=true` on a node that already has a host driver | Set `gpuOperator.driver.enabled=false` |
| Duplicate NFD, node labels flapping | NFD already ran in the cluster | `gpuOperator.nfd.enabled=false` |
| Sessions land on non-GPU nodes | No node targeting | `agent.workspacesNodeSelector` (and tolerate the GPU taint) |
| A root GPU image sees the devices but cannot open them, or its pod fails to start | It runs as root in a pod user namespace (`rootMode: userns`), where the host device ownership is unmapped | Run it at uid 1000 with the groups above, or `agent.workspaceSecurity.rootMode: host` (the default) |
| Airgapped install of `gpuOperator` fails pulling operands | The operand set is not in `dist/kasm-agent-images.txt` | Follow NVIDIA's air-gapped procedure, values passed through as `gpuOperator.*` |

## Decisions

- [ ] GPU nodes labelled (and taints planned for)
- [ ] Which path: NVIDIA (`gpuOperator` + `agent.gpu.enabled`), Intel/AMD (`driDevicePlugin` + `agent.workspaceSecurity.driResource`), or both
- [ ] NVIDIA: driver strategy decided - operator-managed vs pre-installed (`gpuOperator.driver.enabled`)
- [ ] NVIDIA: `gpuOperator.enabled=true` in exactly one release per cluster (or skipped if a device plugin already exists)
- [ ] NVIDIA on containerd 2.x: root containerd config at the current version
- [ ] `agent.workspacesNodeSelector` targets the GPU nodes
- [ ] The node's `render`/`video` gids in `agent.workspaceSecurity.supplementalGroups` (or the images' `group_add`)
- [ ] Sharing decided: sessions per GPU (`replicas` or `deviceShares`) sized to the GPU's memory
- [ ] `kubectl get nodes` shows non-empty allocatable for the chosen resource
- [ ] Workspace images carry a GPU count (NVIDIA) or a `/dev/dri` device (Intel, AMD), and `HW3D`
- [ ] A Kasm GPU workspace launches and renders on the GPU
