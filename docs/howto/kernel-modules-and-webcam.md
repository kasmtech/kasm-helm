# Kernel modules and webcam passthrough

> **Applies to:** feature-matrix rows **9** (webcam / v4l2loopback) and **16** (kernel module management / WireGuard) — the "Outside the charts" cells covering loadable modules, kernel headers, the KMM operator and a reachable registry · **Charts/values:** `nodePrep.modules.v4l2loopback.enabled`, `nodePrep.modules.v4l2loopback.method`, `nodePrep.modules.v4l2loopback.videoDevices`, `nodePrep.modules.v4l2loopback.kmm.image.registry`, `nodePrep.modules.v4l2loopback.kmm.imageRepoSecret`, `nodePrep.modules.v4l2loopback.kmm.build.enabled`, `nodePrep.modules.wireguard.enabled`, `videoDevicePlugin.enabled`

## Why this is needed

Webcam passthrough is two halves and needs both:

1. **The module.** `v4l2loopback` creates the virtual `/dev/video*` devices `kasm_webcam_server` writes frames into. Kubernetes cannot load a kernel module; `kasm-node-prep` does, from a privileged DaemonSet that re-checks `/proc/modules` every `nodePrep.reconcileIntervalSeconds` (300s default) and so **self-heals across node reboots**.
2. **The resource.** Kubernetes schedules on resources, not device files. `kasm-video-device-plugin` advertises each `/dev/video*` as one unit of `kasm.com/video`, and kubelet assigns exactly one per pod. Without it the module is loaded and nothing can ask for it.

Enable one without the other and the feature fails quietly.

`modules.wireguard` is the same machinery for a different module, and matters **only on kernels older than 5.6** — WireGuard has been in-tree since. The reconcile script detects `wg_` symbols in `/proc/kallsyms` and exits early, so leaving it enabled across a mixed fleet is safe.

## Before you start

- **A kernel that ships the V4L2 core (`CONFIG_MEDIA_SUPPORT` / `CONFIG_VIDEO_DEV`).** This is the hard gate. Ubuntu's `-generic` flavor has it; the `-kvm` cloud flavor does **not**, and `v4l2loopback` can never link there. Check before you install anything:

  ```console
  uname -r                      # ...-generic  OK   |  ...-kvm  will never work
  modinfo videodev >/dev/null && echo "V4L2 core present"
  ```

  On Ubuntu generic, also install `linux-modules-extra-$(uname -r)`.
- **Loadable modules permitted.** A node with `kernel.modules_disabled=1` or an immutable/hardened image cannot be prepared this way.
- **The namespace must permit the `privileged` PSS** — do [privileged workloads and cluster policy](privileged-workloads-and-policies.md) first.
- **Pick a mode:**

  | | `method: build` (default) | `method: kmm` |
  | --- | --- | --- |
  | Compiles | on every node, every time the module is missing | once per kernel release, into an image |
  | Node needs | `linux-headers-$(uname -r)` resolvable + a toolchain (or a pre-baked builder image) | nothing but an image pull |
  | Also needs | — | the KMM operator, cluster-wide, and a container **registry** |
  | Failures show up in | the node-prep pod log, with a diagnosis | the `Module` status and KMM build pod logs |

  Full comparison: [kasm-node-prep § Which one to choose](../../charts/kasm-node-prep/README.md#which-one-to-choose).
- Distro variants: **k3s / kubeadm / managed (EKS, AKS, GKE)** behave identically for this chart — what differs is the node image (headers availability, kernel flavor), not the distribution. **OpenShift**: RHCOS ships no `apt`, so `method: build` needs a pre-baked builder image or `method: kmm`; KMM is also the RHEL-native answer there.

## Steps

### A. Build mode (default)

1. Confirm the headers package resolves on a node:

   ```console
   apt-get -s install "linux-headers-$(uname -r)" >/dev/null && echo "headers available"
   ```

   If it does not, either pre-install headers in the node image or use the airgap builder-image path in [kasm-node-prep § Airgapped / offline nodes](../../charts/kasm-node-prep/README.md#airgapped--offline-nodes) with `nodePrep.modules.v4l2loopback.sourcePath`.

2. Enable both halves and install:

   ```console
   helm upgrade --install kasm-agent charts/kasm-agent \
     --namespace kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.modules.v4l2loopback.enabled=true \
     --set nodePrep.modules.v4l2loopback.videoDevices=4 \
     --set videoDevicePlugin.enabled=true
   ```

3. Watch the first pass. A cold node compiles the module; expect a minute or two under the default `nodePrep.resources.limits.cpu` of `1000m`:

   ```console
   kubectl -n kasm-agent logs -l app.kubernetes.io/component=node-prep -f
   ```

4. Pin both DaemonSets to the same nodes so `kasm.com/video` is never advertised where the module is not loaded — `nodePrep.nodeSelector` and `videoDevicePlugin.nodeSelector` must match.

### B. KMM mode

1. **Install the KMM operator once per cluster.** It publishes no Helm chart; this repo pins `v2.7.0`:

   ```console
   make kmm-install                                              # connected clusters
   make kmm-install-mirrored KMM_IMAGE_REGISTRY=registry.example.internal   # airgap
   ```

   `make images-agent` prints the five KMM images to mirror under its `# KMM mode` section. KMM reuses cert-manager if it is already installed. `make kmm-uninstall` removes the operator — delete the `Module` first if you want the modules unloaded, because KMM unloads on delete.

2. **Create the registry secret** (needed to pull the kmod image, and to *push* when in-cluster builds are on):

   ```console
   kubectl create secret docker-registry kasm-registry \
     --namespace kasm-agent \
     --docker-server=registry.example.internal \
     --docker-username=... --docker-password=...
   ```

3. **Install with the module delegated.** Leave `nodePrep.modules.v4l2loopback.kmm.image.tag` empty so the rendered `containerImage` ends in the literal `${KERNEL_FULL_VERSION}` and one entry covers a multi-kernel fleet:

   ```console
   helm upgrade --install kasm-agent charts/kasm-agent \
     --namespace kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.modules.v4l2loopback.enabled=true \
     --set nodePrep.modules.v4l2loopback.method=kmm \
     --set nodePrep.modules.v4l2loopback.kmm.image.registry=registry.example.internal \
     --set nodePrep.modules.v4l2loopback.kmm.image.repository=kasm/v4l2loopback \
     --set nodePrep.modules.v4l2loopback.kmm.imageRepoSecret=kasm-registry \
     --set videoDevicePlugin.enabled=true
   ```

4. **If in-cluster builds are on** (`nodePrep.modules.v4l2loopback.kmm.build.enabled`, the default), the kaniko build pod runs on the **pod network** — not the host network. On clusters where the registry hostname only resolves through the *node's* resolver (tailnet/MagicDNS names, split-horizon internal DNS), pods cannot push. Add a CoreDNS forward. On k3s that is a `coredns-custom` ConfigMap with a `<zone>.server` stanza:

   ```console
   kubectl -n kube-system create configmap coredns-custom \
     --from-literal=example-ts-net.server='example.ts.net:53 {
       errors
       forward . 100.100.100.100
     }'
   kubectl -n kube-system rollout restart deployment coredns
   ```

   Confirm from a pod before rebuilding: `kubectl run dns-probe --rm -it --image=busybox --restart=Never -- nslookup registry.example.internal`.

5. **Airgap (Mode A):** set `nodePrep.modules.v4l2loopback.kmm.build.enabled=false` and pre-build one `<registry>/<repository>:<kernel release>` image per fleet kernel on a connected machine. Runbook: [kasm-node-prep § Airgapped KMM (prebuilt modules)](../../charts/kasm-node-prep/README.md#airgapped-kmm-prebuilt-modules).

### C. WireGuard (kernels < 5.6 only)

```console
helm upgrade --install kasm-agent charts/kasm-agent -n kasm-agent \
  --set nodePrep.enabled=true --set nodePrep.modules.wireguard.enabled=true
```

`nodePrep.modules.wireguard.method` accepts only `build`; `kmm` fails the render by design.

## Verify

The result is identical in both modes.

1. Devices exist on the node — `videoDevices` of them, `video0` .. `videoN-1`:

   ```console
   ls /dev/video*
   lsmod | grep v4l2loopback
   ```

   Expected: `/dev/video0 /dev/video1 /dev/video2 /dev/video3` for the default `videoDevices: 4`.

2. The extended resource is allocatable — the number must equal `videoDevices`:

   ```console
   kubectl get node <node> -o jsonpath='{.status.allocatable.kasm\.com/video}{"\n"}'
   ```

   Expected output: `4`. Fleet-wide:

   ```console
   kubectl get nodes -o custom-columns='NODE:.metadata.name,VIDEO:.status.allocatable.kasm\.com/video'
   ```

3. Build mode, in the pod log:

   ```console
   kubectl -n kasm-agent logs -l app.kubernetes.io/component=node-prep | grep v4l2loopback
   ```

   Expected: `v4l2loopback loaded; /dev/video* devices are present on the node`, and on subsequent passes `v4l2loopback is already loaded`.

4. KMM mode — this chart's log says nothing about v4l2loopback at all; look at the `Module`:

   ```console
   kubectl get modules.kmm.sigs.x-k8s.io
   kubectl describe module kasm-agent-kasm-node-prep-v4l2loopback
   kubectl get pods -l kmm.node.kubernetes.io/module.name=kasm-agent-kasm-node-prep-v4l2loopback
   ```

5. WireGuard on a modern kernel — the expected outcome is a skip, not a build:

   ```text
   WireGuard is built into kernel 6.8.0-40-generic (wg_ symbols found in /proc/kallsyms); nothing to build
   ```

## Chart values

Umbrella (`kasm-agent`) form:

```yaml
nodePrep:
  enabled: true
  modules:
    v4l2loopback:
      enabled: true
      videoDevices: 4
      # method: kmm            # delegate to the KMM operator instead of compiling on nodes
      # kmm:
      #   image:
      #     registry: registry.example.internal
      #     repository: kasm/v4l2loopback
      #   imageRepoSecret: kasm-registry
      #   build:
      #     enabled: false     # airgap Mode A: KMM only pulls prebuilt per-kernel images
    wireguard:
      enabled: false           # only on kernels older than 5.6
  nodeSelector:
    kasm.com/workspaces: "true"

videoDevicePlugin:
  enabled: true
  nodeSelector:
    kasm.com/workspaces: "true"   # must match nodePrep.nodeSelector
```

Under [kasm-platform](../../charts/kasm-platform/README.md) the same block nests one level down, under `kasm-agent:` (`kasm-agent.nodePrep.modules.v4l2loopback.method`). Installing `charts/kasm-node-prep` standalone drops the alias: the keys are `modules.v4l2loopback.*` at the top level.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Pod log: `Kernel <rel> has no V4L2 core (videodev): CONFIG_MEDIA_SUPPORT/CONFIG_VIDEO_DEV are not enabled in this kernel flavor` and no build is attempted | Minimal kernel flavor — Ubuntu `-kvm`, some cloud kernels. `v4l2loopback` can **never** link here | Move the node to the `-generic` flavor with `linux-modules-extra-$(uname -r)`, or rebuild the node image. No chart value works around it |
| Build mode: pass fails and the log names `linux-headers-$(uname -r)` | The exact headers package is not published by the distro repos (common on cloud-vendor kernels) | Pre-install headers in the node image, or switch to a pre-baked builder image with `nodePrep.modules.v4l2loopback.sourcePath`, or use `method: kmm` |
| `kubectl get node ... allocatable.kasm\.com/video` returns `0` or nothing, while `nodePrep` looks healthy | The device plugin runs on a node where the module was never loaded — mismatched `nodeSelector`s | Give `videoDevicePlugin.nodeSelector` and `nodePrep.nodeSelector` the same value; check the node-prep log on that specific node |
| `helm install` fails to render: `sourcePath` combined with `method: kmm` | `sourcePath` names a directory inside *this chart's* builder image, which a KMM build pod never runs. Rejected deliberately | Drop `sourcePath`, or go back to `method: build` |
| `helm install` fails to render with an empty KMM registry/repository | Both are required whenever `method: kmm` — KMM loads the module from an image | Set `nodePrep.modules.v4l2loopback.kmm.image.registry` and `nodePrep.modules.v4l2loopback.kmm.image.repository` |
| KMM in-cluster build pod cannot push; DNS lookup of the registry hostname fails from the pod | The kaniko pod runs on the **pod network**; the registry hostname resolves only via the node's resolver (tailnet/MagicDNS, split-horizon DNS) | Add a CoreDNS forward for that zone (k3s: a `coredns-custom` ConfigMap `<zone>.server` stanza) and restart CoreDNS |
| `Module` exists but a node's kernel is never prepared, in airgap Mode A | No `<registry>/<repository>:<kernel release>` image was built for that kernel; KMM cannot pull what does not exist | Build and push that kernel's image before the node joins. `kubectl describe module ...` names the unmatched kernel |
| Install fails: the `Module` CRD does not exist | `method: kmm` without the KMM operator installed | `make kmm-install` (or `make kmm-install-mirrored KMM_IMAGE_REGISTRY=<mirror>`) |
| Airgapped build mode still hits `apt-get` | The pre-baked builder image is missing a prerequisite, so the presence check fell through | Look for `build prerequisites already present; skipping package installation` in the pod log; if absent, add `build-essential kmod openssl libelf1` to the image |
| Build is OOMKilled and retried every `reconcileIntervalSeconds` without finishing | `nodePrep.resources.limits.memory` too low to hold headers + sources + gcc | Raise it above the `1Gi` default |

## Checklist

- [ ] Node kernel ships the V4L2 core (`modinfo videodev` succeeds); not a `-kvm`/minimal cloud flavor.
- [ ] Namespace labelled `pod-security.kubernetes.io/enforce=privileged`.
- [ ] Mode chosen: `build` (headers + toolchain per node) or `kmm` (operator + registry).
- [ ] KMM mode only: `make kmm-install` / `make kmm-install-mirrored` run; `kubernetes.io/dockerconfigjson` secret created and named in `nodePrep.modules.v4l2loopback.kmm.imageRepoSecret`.
- [ ] KMM in-cluster builds only: the registry hostname resolves **from a pod** (CoreDNS forward added if it does not).
- [ ] `nodePrep.enabled=true` **and** `videoDevicePlugin.enabled=true`.
- [ ] `nodePrep.nodeSelector` and `videoDevicePlugin.nodeSelector` match.
- [ ] `/dev/video0..N` present on the node and `lsmod | grep v4l2loopback` non-empty.
- [ ] `kubectl get node <node> -o jsonpath='{.status.allocatable.kasm\.com/video}'` equals `videoDevices`.
- [ ] `nodePrep.modules.wireguard.enabled` left `false` unless the fleet runs kernels older than 5.6.
