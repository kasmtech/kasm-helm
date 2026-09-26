# GPU nodes (CUDA, EGL and DRI)

> **Applies to:** agent · **Charts/values:** `gpuOperator.enabled`, `agent.gpu.enabled`, `gpuOperator.driver.enabled`, `gpuOperator.toolkit.enabled`, `gpuOperator.devicePlugin.enabled`, `gpuOperator.nfd.enabled`, `gpuOperator.devicePlugin.config`, `driDevicePlugin.*`, `driDevicePlugin.driCapabilities`, `agent.workspaceSecurity.driResource`, `agent.workspaceSecurity.deviceAllowlist`, `agent.workspaceSecurity.supplementalGroups`, `agent.workspacesNodeSelector`, `agent.nodeSelector`

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
for GPUs, and report the GPUs to the Kasm manager at all. Enable only the operator and you have GPUs
nobody requests. Enable only the agent flag and
you request a resource no node advertises, so sessions stay `Pending`. EGL on NVIDIA needs nothing
further: the NVIDIA runtime adds the GPU's DRI nodes itself.

**Intel and AMD** also need two values. `driDevicePlugin.enabled=true` installs the DRI device
plugin, which advertises each Intel or AMD GPU's render node as `kasm.com/dri`, shared by up to
`driDevicePlugin.deviceShares` sessions, and labels each node with what its GPUs can do;
`agent.workspaceSecurity.driResource=kasm.com/dri` makes the agent report those GPUs to the Kasm
manager and request one for any image whose graphics or video preference needs it. Without the
second, the manager never hears of the GPUs, and a pre-1.19 image's `/dev/dri` device falls back to a
`hostPath` mount the session cannot open.

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
* **NVIDIA on k3s:** point the operator's toolkit at k3s's containerd. On RKE2 the config is
  `/var/lib/rancher/rke2/agent/etc/containerd/config.toml` and the socket the same as k3s's.

  ```yaml
  gpuOperator:
    toolkit:
      env:
        - name: CONTAINERD_CONFIG
          value: /var/lib/rancher/k3s/agent/etc/containerd/config.toml
        - name: CONTAINERD_SOCKET
          value: /run/k3s/containerd/containerd.sock
  ```

  Leave the toolkit's containerd drop-in where it is (a `99-nvidia.toml` in the host's
  `/etc/containerd/conf.d`, which k3s does not read): its `version = 4` drop-in in k3s's own
  `config-v3.toml.d` stops k3s's containerd from starting.

* **Intel and AMD:** the kernel driver (`i915`, `xe` or `amdgpu`) loaded on the node, so that
  `/dev/dri/renderD*` exists. No chart installs it; every mainstream node image has it for
  integrated and discrete GPUs alike.
* **Workspace images:** the image carries the userspace drivers for its GPU - Mesa for Intel and AMD
  (the Kasm images do). An NVIDIA session gets NVIDIA's libraries from the runtime instead.

Distro / cloud variants:

| Platform | Notes |
| -------- | ----- |
| k3s / RKE2 | Point the toolkit at the distribution's own containerd (below): by default it configures and restarts `/run/containerd`, which on k3s is not the cluster's runtime - and on a node that also runs Docker is Docker's. k3s restarts once and picks up the NVIDIA runtime by itself. |
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

4. **Choose each GPU image's methods in Kasm.** In the image's settings, set the **graphics acceleration**
   preference (`DRI3`, `EGL`, `VULKAN`, or `MESA` for software) and the **video encoding** preference
   (`VAAPI`, `NVENC`, or `SW`), in order of preference, and a **GPU count** for CUDA work. The agent
   reports every GPU in the cluster to the manager with what it can do, the manager only places the
   image on an agent offering a listed method, and the agent then requests the matching device:

   | Method | Needs | The session gets |
   | ------ | ----- | ---------------- |
   | `DRI3` | an Intel or AMD GPU (`kasm.com/dri`) | KasmVNC's own hardware 3D on the render node |
   | `EGL` | an NVIDIA GPU or an Intel/AMD one | its desktop started under VirtualGL on the GPU |
   | `VULKAN` | an NVIDIA GPU or an Intel/AMD one | its desktop's OpenGL through Zink on Vulkan |
   | `VAAPI` | an Intel or AMD GPU | hardware video encoding on the render node |
   | `NVENC` | an NVIDIA GPU | hardware video encoding on the NVIDIA GPU |

   A method is tried only on nodes whose GPU can do it (the DRI plugin labels each node
   `kasm.com/dri.<method>`), and one device covering both the graphics and the video method is
   preferred. When nothing in the list is available and it has no `MESA`/`SW`, the launch fails with
   `Image required GPU, failed to obtain gpu on host`. GPUs an admin excludes on the agent in Kasm
   (graphics, video or CUDA) are honoured per node: a node is avoided once all of its GPUs are
   excluded for that role.

   The agent adds the GPU's `render` and `video` groups to the session itself, from the gids the DRI
   plugin reads on each node, so uid-1000 sessions can open the devices.

   The DRI plugin decides what an Intel or AMD GPU can do by its kernel driver (`i915`, `xe`,
   `amdgpu`: all four methods). If a GPU lacks one - an Intel GPU without a video encoder, say - set
   `driDevicePlugin.driCapabilities` (e.g. `dri3,egl,vulkan`).

5. **Images configured the pre-1.19 way** pass a render node through in the run config and set
   `HW3D`:

   ```json
   { "devices": ["/dev/dri/renderD128:/dev/dri/renderD128:rwm"],
     "environment": { "HW3D": "true" } }
   ```

   These keep working: with `driResource` set, the agent turns any allowed `/dev/dri` entry into one
   `kasm.com/dri`, and the plugin picks the node and sets `DRINODE`, so the path in the run config
   does not have to match; the render and card groups are added as for step 4. Which host devices
   a run config may pass through at all is `agent.workspaceSecurity.deviceAllowlist` (default: the
   DRI card and render nodes; `["none"]` passes none).

6. **Root and user-namespaced sessions.** An image that runs as root gets the same devices; the
   startup script keeps the GPU groups when it drops to `kasm-user`. A session in a pod user
   namespace (`workspaceSecurity.rootMode: userns`, or `userNamespaces: always`) sees the node's DRI
   device nodes owned by an unmapped user and cannot open them, so the agent never gives it DRI3,
   VA-API or EGL: it moves on down the image's preferences to what does work there - Vulkan, NVENC
   and CUDA on an NVIDIA GPU, whose device files are open to all - and fails the launch at once
   when nothing is left and software is not allowed. A pre-1.19 image's `/dev/dri` device in such a
   session fails the launch with a message saying so.

7. **Airgapped?** Do **not** mirror the GPU Operator from `make images-agent`; it pulls a much larger
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

When every share is taken, a GPU launch fails at once with the scheduler's reason
(`Insufficient kasm.com/dri`) rather than waiting, and the agent stops offering the manager the
images that need that GPU until a share frees up. The manager does not count graphics or video
GPUs itself, so a burst of launches can reach a full GPU before the agent's next report.

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
* Changing an existing sharing config (replicas, or time-slicing to MPS) takes effect once the
  device plugin and GPU Feature Discovery pods restart; enabling one for the first time needs no
  restart:

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

KasmVNC encodes its stream with VA-API only, so on an Intel or AMD GPU with `VAAPI` chosen it
finds a hardware H.264 encoder on the session's render node. On an NVIDIA GPU, `NVENC` gives
applications in the session the hardware encoder; KasmVNC's own stream is encoded on the CPU.

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
| The render node opens with `Permission denied` for `kasm-user` | The DRI device plugin has not published the node's devices (no `kasm.com/dri-devices` annotation on the Node), so the agent does not know their groups | Check the plugin pod's log and its permission to patch Nodes; `agent.workspaceSecurity.supplementalGroups` adds gids by hand |
| An Intel or AMD session renders in software though the node has the GPU | `agent.workspaceSecurity.driResource` unset (the release notes warn), or the image's graphics preference is `MESA` | Set `driResource`; set the image's graphics acceleration (step 4) |
| The manager never places a GPU image on the agent | No node offers a listed method: no GPU resource advertised, the method's `kasm.com/dri.<method>` label missing, or every GPU excluded | `kubectl get nodes --show-labels`; check the plugin pods and the agent's GPU exclusions in Kasm |
| `kasm.com/dri` is 0 on a node with an NVIDIA GPU only | NVIDIA GPUs are left to `nvidia.com/gpu` by default | Use the NVIDIA path; `driDevicePlugin.driDrivers` lists the drivers advertised |
| containerd fails to start after the GPU Operator installs, `drop-in config version 4 higher than root config version 2` | The toolkit's containerd drop-in is newer than the node's root config | On the node: `containerd config migrate > /tmp/config.toml`, review it, replace `/etc/containerd/config.toml`, restart containerd |
| A changed time-slicing or MPS config does not show in allocatable | The device plugin and GPU Feature Discovery read the config at start | Restart both (see [time-slicing](#nvidia-time-slicing)) |
| On k3s, NVIDIA operand pods fail with `unable to get OCI runtime for sandbox`, or the host's own containerd restarted | The toolkit configured `/run/containerd`, not k3s's containerd | Set the toolkit's `CONTAINERD_CONFIG` and `CONTAINERD_SOCKET` to k3s's (see Before you start) |
| k3s does not come back up, its containerd log says `drop-in config version 4 higher than root config version 3` | An NVIDIA drop-in in `/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d` | Remove it, restart k3s, and leave the toolkit's drop-in path at its default |
| Driver pods `CrashLoopBackOff` on a cloud GPU image | `gpuOperator.driver.enabled=true` on a node that already has a host driver | Set `gpuOperator.driver.enabled=false` |
| Duplicate NFD, node labels flapping | NFD already ran in the cluster | `gpuOperator.nfd.enabled=false` |
| Sessions land on non-GPU nodes | No node targeting | `agent.workspacesNodeSelector` (and tolerate the GPU taint) |
| A GPU image in a user-namespaced session gets software rendering, or fails with `Image required GPU` | DRI devices cannot be opened in a pod user namespace (`rootMode: userns`, `userNamespaces: always`), so DRI3, VA-API and EGL are out there (step 6) | Prefer Vulkan/NVENC on NVIDIA for such images, run them at uid 1000, or `agent.workspaceSecurity.rootMode: host` (the default) |
| Airgapped install of `gpuOperator` fails pulling operands | The operand set is not in `dist/kasm-agent-images.txt` | Follow NVIDIA's air-gapped procedure, values passed through as `gpuOperator.*` |

## Decisions

- [ ] GPU nodes labelled (and taints planned for)
- [ ] Which path: NVIDIA (`gpuOperator` + `agent.gpu.enabled`), Intel/AMD (`driDevicePlugin` + `agent.workspaceSecurity.driResource`), or both
- [ ] NVIDIA: driver strategy decided - operator-managed vs pre-installed (`gpuOperator.driver.enabled`)
- [ ] NVIDIA: `gpuOperator.enabled=true` in exactly one release per cluster (or skipped if a device plugin already exists)
- [ ] NVIDIA on containerd 2.x: root containerd config at the current version
- [ ] NVIDIA on k3s/RKE2: toolkit pointed at the distribution's containerd
- [ ] `agent.workspacesNodeSelector` targets the GPU nodes
- [ ] Sharing decided: sessions per GPU (`replicas` or `deviceShares`) sized to the GPU's memory
- [ ] `kubectl get nodes` shows non-empty allocatable for the chosen resource
- [ ] Workspace images set graphics acceleration and video encoding preferences (and a GPU count for CUDA)
- [ ] A Kasm GPU workspace launches and renders on the GPU
