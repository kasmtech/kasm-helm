# Kernel modules and webcam passthrough

> **Applies to:** agent · **Charts/values:** `nodePrep.modules.v4l2loopback.enabled`, `nodePrep.modules.v4l2loopback.method`, `nodePrep.image.registry`, `nodePrep.image.repository`, `nodePrep.image.tag`, `nodePrep.modules.v4l2loopback.videoDevices`, `nodePrep.modules.v4l2loopback.kmm.image.registry`, `nodePrep.modules.v4l2loopback.kmm.imageRepoSecret`, `nodePrep.modules.v4l2loopback.kmm.build.enabled`, `nodePrep.modules.wireguard.enabled`, `videoDevicePlugin.enabled`, `agent.workspaceSecurity.supplementalGroups`

## Why this is needed

Webcam passthrough is two halves and needs both:

1. **The module.** `v4l2loopback` creates the virtual `/dev/video*` devices `kasm_webcam_server` writes frames into. Kubernetes cannot load a kernel module; `kasm-node-prep` does, from a privileged DaemonSet that re-checks `/proc/modules` every `nodePrep.reconcileIntervalSeconds` (300s default) and so **self-heals across node reboots**.
2. **The resource.** Kubernetes schedules on resources, not device files. `kasm-video-device-plugin` advertises each `/dev/video*` as one unit of `kasm.com/video`, and kubelet assigns exactly one per pod. Without it the module is loaded and nothing can ask for it.

Enable one without the other and the feature fails quietly.

The session has to be able to open the device it is given, too. Sessions run as `kasm-user`
(uid 1000), and udev makes `/dev/video*` `root:video 0660` on the node. node-prep widens the mode to
`nodePrep.modules.v4l2loopback.deviceMode` (`0666` by default), which covers it; if you keep the
node's `0660` (or load the module with KMM, which leaves udev's mode), add the node's `video` gid
to the sessions instead, with `agent.workspaceSecurity.supplementalGroups` or the image's run config
`group_add`. A session that runs as root in a pod user namespace
(`agent.workspaceSecurity.rootMode: userns`) may not reach the device at all, because its host
owner and group are unmapped inside the namespace; keep webcam images at uid 1000, or keep the
default `rootMode: host`.

`modules.wireguard` is the same machinery for a different module, and matters **only on kernels older than 5.6** - WireGuard has been in-tree since. The reconcile script detects `wg_` symbols in `/proc/kallsyms` and exits early, so leaving it enabled across a mixed fleet is safe.

## Before you start

- **A kernel that ships the V4L2 core (`CONFIG_MEDIA_SUPPORT` / `CONFIG_VIDEO_DEV`).** This is the hard gate. Ubuntu's `-generic` flavor has it; the `-kvm` cloud flavor does **not**, and `v4l2loopback` can never link there. Check before you install anything:

  ```console
  uname -r                      # ...-generic  OK   |  ...-kvm  will never work
  modinfo videodev >/dev/null && echo "V4L2 core present"
  ```

  `videodev` is usually a separately packaged module - if `modinfo` fails, install the one for the node's family: Ubuntu `linux-modules-extra-$(uname -r)` (the `-generic`, `-aws`, `-gke` and `-azure` flavors all have one in the 22.04 and 24.04 archives); RHEL 8/9, Rocky and Alma `kernel-modules` (the `kernel` metapackage installs it by default); Amazon Linux 2023 `kernel-modules-extra`; Oracle Linux UEK `kernel-uek-modules` (UEK R7) or `kernel-uek-modules-desktop` (UEK R8). When the core is missing the node-prep log names the package for the builder image's family.
- **Loadable modules permitted.** A node with `kernel.modules_disabled=1` or an immutable/hardened image cannot be prepared this way.
- **The namespace must permit the `privileged` PSS** - do [privileged workloads and cluster policy](privileged-workloads.md) first.
- **Pick a mode:**

  | | `method: build` (default) | `method: kmm` |
  | --- | --- | --- |
  | Compiles | on every node, every time the module is missing | once per kernel release, into an image |
  | Node needs | the node kernel's headers package resolvable from a builder image of the node's own family and release (`nodePrep.image.*` - `linux-headers-$(uname -r)` on Ubuntu/Debian, `kernel-devel` and its variants on the RPM families) + a toolchain, or a pre-baked builder image | nothing but an image pull |
  | Also needs | - | the KMM operator, cluster-wide, and a container **registry** |
  | Failures show up in | the node-prep pod log, with a diagnosis | the `Module` status and KMM build pod logs |

  Full comparison: [kasm-node-prep § Which one to choose](../../../charts/kasm-node-prep/README.md#which-one-to-choose).
- Distro variants: **k3s / kubeadm / managed (EKS, AKS, GKE)** behave identically for this chart - what differs is the node image, not the distribution. The rule for build mode: **`nodePrep.image.*` must name a builder image of the node's own distribution family and release.** The container shares the node's kernel but not its userland, and the kernel headers are installed from the builder image's repositories, never the node's; the default `ubuntu:22.04` fits Ubuntu 22.04 nodes only. The reconcile script detects the image's package manager (`apt-get`, `dnf`/`yum`/`microdnf`, `tdnf`, `zypper`) and branches on it. One DaemonSet has one builder image, so a fleet mixing families needs one `kasm-node-prep` release per family, each with its own `nodeSelector`. The full table, with the packages each family installs, is [kasm-node-prep § Builder image per node image](../../../charts/kasm-node-prep/README.md#builder-image-per-node-image); the short version:

  | Node image | `nodePrep.image.*` | Build mode |
  | --- | --- | --- |
  | Ubuntu 22.04 / 24.04 (self-managed, EKS Ubuntu AMI, GKE Ubuntu, AKS Ubuntu) | `docker.io/library/ubuntu:22.04` / `:24.04`, matching the node release | yes - `-generic`, `-aws`, `-gke` and `-azure` all have headers and modules-extra; never `-kvm` |
  | Debian 12 | `docker.io/library/debian:12` | yes |
  | EKS Amazon Linux 2023 (the default AMI) | `public.ecr.aws/amazonlinux/amazonlinux:2023` | yes - both kernel lines (6.1, 6.12) resolve; V4L2 core in `kernel-modules-extra` |
  | Rocky / Alma / CentOS Stream 9 (or 8) | `docker.io/library/rockylinux:9` or `almalinux:9` (`:8`), matching the major | yes |
  | RHEL (subscription) | `registry.access.redhat.com/ubi9/ubi`, or Rocky/Alma of the same major | partial - UBI repositories have no `kernel-devel`; pre-install `kernel-devel-$(uname -r)` in the node image and the bind-mounted `/usr/src` lets the container find it |
  | Oracle Linux 9 | RHCK nodes: `docker.io/library/oraclelinux:9`. UEK nodes (the default): a builder with the UEK repository enabled, which the stock image ships disabled - `FROM oraclelinux:9` plus `RUN dnf config-manager --set-enabled ol9_UEKR8` (6.12) or `ol9_UEKR7` (5.15); UEK R8's gcc-toolset-14 is picked up automatically | yes - both UEK lines compiled in Docker, not on a live node |
  | AKS Azure Linux 3 | `mcr.microsoft.com/azurelinux/base/core:3.0` | yes, the `tdnf` path |
  | openSUSE Leap / SLES | `registry.opensuse.org/opensuse/leap:15.6`, or the SLES BCI of the release | expected |
  | EKS Bottlerocket | none | no - no shell, no headers, immutable. `method: kmm` with `kmm.build.enabled: false` and per-kernel images built out of band (Bottlerocket publishes a kmod-kit); module loading policy there is Bottlerocket's own |
  | GKE Container-Optimized OS | none | no - use the Ubuntu node image for the workspace pool, or prebuilt KMM images |
  | OpenShift RHCOS | none | no - `method: kmm`, the RHEL-native answer |

## Steps

### A. Build mode (default)

1. Confirm the node kernel's headers package resolves. Run on the node; it stands in for the builder image's repositories, so it only means something when `nodePrep.image.*` is the node's own family and release (table above):

   ```console
   # Ubuntu / Debian node
   apt-get -s install "linux-headers-$(uname -r)" >/dev/null && echo "headers available"
   # RHEL-family node (Rocky, Alma, CentOS Stream, Oracle, Amazon Linux 2023): the transaction summary must
   # name kernel-devel, kernel6.12-devel or kernel-uek-devel; "no match" means it does not resolve
   dnf install --assumeno "/usr/src/kernels/$(uname -r)"
   ```

   Or ask the builder image itself, with the node's kernel release substituted: `docker run --rm rockylinux:9 dnf repoquery --whatprovides /usr/src/kernels/<kernel release>` (on Debian/Ubuntu images, `apt-get update && apt-get -s install linux-headers-<kernel release>`). If it does not resolve, check the builder image release against the node first - a GKE Ubuntu 24.04 node runs a 6.8 `-gke` kernel whose headers are only in the 24.04 archive. If the headers genuinely are not published (RHEL, whose UBI repositories carry no `kernel-devel`; some cloud-vendor kernels), either pre-install them in the node image (`/usr/src` is bind-mounted, so the container then finds them) or use the airgap builder-image path in [kasm-node-prep § Airgapped / offline nodes](../../../charts/kasm-node-prep/README.md#airgapped-and-offline-nodes) with `nodePrep.modules.v4l2loopback.sourcePath`.

2. Enable both halves and install:

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
     --namespace kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.modules.v4l2loopback.enabled=true \
     --set nodePrep.modules.v4l2loopback.videoDevices=20 \
     --set videoDevicePlugin.enabled=true
   ```

   The default builder image is `ubuntu:22.04`, right for Ubuntu 22.04 nodes only. On any other node image add `nodePrep.image.registry`, `nodePrep.image.repository` and `nodePrep.image.tag` from the table in Before you start - for GKE Ubuntu 24.04 nodes `--set nodePrep.image.tag=24.04` is enough; for EKS Amazon Linux 2023, `--set nodePrep.image.registry=public.ecr.aws --set nodePrep.image.repository=amazonlinux/amazonlinux --set nodePrep.image.tag=2023`.

3. Watch the first pass. A cold node compiles the module; expect a minute or two under the default `nodePrep.resources.limits.cpu` of `1000m`:

   ```console
   kubectl -n kasm-agent logs -l app.kubernetes.io/component=node-prep -f
   ```

4. Pin both DaemonSets to the same nodes so `kasm.com/video` is never advertised where the module is not loaded - `nodePrep.nodeSelector` and `videoDevicePlugin.nodeSelector` must match.

### B. KMM mode

1. **Install the KMM operator once per cluster.** It publishes no Helm chart; this repo pins `v2.7.0`:

   ```console
   make kmm-install                                              # connected clusters
   make kmm-install-mirrored KMM_IMAGE_REGISTRY=registry.example.internal   # airgap
   ```

   `make images-agent` prints the five KMM images to mirror under its `# KMM mode` section. KMM's manifests need cert-manager already installed (they create an `Issuer` and a `Certificate` for the admission webhook); `make kmm-install` also pins the operator's images to the release tag, because the upstream overlay references rolling `:latest` builds. `make kmm-uninstall` removes the operator - delete the `Module` first if you want the modules unloaded, because KMM unloads on delete.

2. **Create the registry secret** (needed to pull the kmod image, and to *push* when in-cluster builds are on):

   ```console
   kubectl create secret docker-registry kasm-registry \
     --namespace kasm-agent \
     --docker-server=registry.example.internal \
     --docker-username=... --docker-password=...
   ```

3. **Install with the module delegated.** Leave `nodePrep.modules.v4l2loopback.kmm.image.tag` empty so the rendered `containerImage` ends in the literal `${KERNEL_FULL_VERSION}` and one entry covers a multi-kernel fleet:

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
     --namespace kasm-agent \
     --set nodePrep.enabled=true \
     --set nodePrep.modules.v4l2loopback.enabled=true \
     --set nodePrep.modules.v4l2loopback.method=kmm \
     --set nodePrep.modules.v4l2loopback.kmm.image.registry=registry.example.internal \
     --set nodePrep.modules.v4l2loopback.kmm.image.repository=kasm/v4l2loopback \
     --set nodePrep.modules.v4l2loopback.kmm.imageRepoSecret=kasm-registry \
     --set videoDevicePlugin.enabled=true
   ```

4. **If in-cluster builds are on** (`nodePrep.modules.v4l2loopback.kmm.build.enabled`, the default), the kaniko build pod runs on the **pod network** - not the host network. On clusters where the registry hostname only resolves through the *node's* resolver (tailnet/MagicDNS names, split-horizon internal DNS), pods cannot push. Add a CoreDNS forward. On k3s that is a `coredns-custom` ConfigMap with a `<zone>.server` stanza:

   ```console
   kubectl -n kube-system create configmap coredns-custom \
     --from-literal=example-ts-net.server='example.ts.net:53 {
       errors
       forward . 100.100.100.100
     }'
   kubectl -n kube-system rollout restart deployment coredns
   ```

   Confirm from a pod before rebuilding: `kubectl run dns-probe --rm -it --image=busybox --restart=Never -- nslookup registry.example.internal`.

5. **Airgap (Mode A):** set `nodePrep.modules.v4l2loopback.kmm.build.enabled=false` and pre-build one `<registry>/<repository>:<kernel release>` image per fleet kernel on a connected machine. Runbook: [kasm-node-prep § Airgapped KMM (prebuilt modules)](../../../charts/kasm-node-prep/README.md#airgapped-kmm-prebuilt-modules).

### C. WireGuard (kernels < 5.6 only)

```console
helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent \
  --set nodePrep.enabled=true --set nodePrep.modules.wireguard.enabled=true
```

`nodePrep.modules.wireguard.method` accepts only `build`; `kmm` fails the render by design.

## Verify

The result is identical in both modes.

1. Devices exist on the node - `videoDevices` of them, `video0` .. `videoN-1`:

   ```console
   ls /dev/video*
   lsmod | grep v4l2loopback
   ```

   Expected: `/dev/video0` .. `/dev/video19` for the default `videoDevices: 20`.

2. The extended resource is allocatable - the number must equal `videoDevices`:

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

4. KMM mode - this chart's log says nothing about v4l2loopback at all; look at the `Module`:

   ```console
   kubectl get modules.kmm.sigs.x-k8s.io
   kubectl describe module kasm-agent-v4l2
   kubectl get pods -l kmm.node.kubernetes.io/module.name=kasm-agent-v4l2
   ```

5. WireGuard on a modern kernel - the expected outcome is a skip, not a build:

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
      videoDevices: 20
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

Under [kasm-platform](../../../charts/kasm-platform/README.md) the same block nests one level down, under `kasm-agent:` (`kasm-agent.nodePrep.modules.v4l2loopback.method`). Installing `charts/kasm-node-prep` standalone drops the alias: the keys are `modules.v4l2loopback.*` at the top level.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Pod log: `Kernel <rel> has no V4L2 core (videodev): CONFIG_MEDIA_SUPPORT/CONFIG_VIDEO_DEV are not enabled in this kernel flavor` and no build is attempted | Either the V4L2 core is a package the node image left out, or the kernel flavor has no V4L2 at all (Ubuntu `-kvm`, some cloud kernels), where `v4l2loopback` can **never** link | Install the package the log names for the family - Ubuntu `linux-modules-extra-$(uname -r)`, RHEL/Rocky/Alma `kernel-modules`, Amazon Linux 2023 `kernel-modules-extra`, Oracle Linux UEK `kernel-uek-modules` (UEK R7) or `kernel-uek-modules-desktop` (UEK R8) - or, on `-kvm`, move the node to `-generic` or rebuild the node image. No chart value works around it |
| Build mode: pass fails and the log names the kernel headers package - `linux-headers-$(uname -r)`, `/usr/src/kernels/$(uname -r)`, `kernel-devel-$(uname -r)` or `kernel-<flavor>-devel` | The builder image's repositories do not carry headers for the node kernel. Almost always a builder image of the wrong family or release (`ubuntu:22.04` against Ubuntu 24.04 nodes, whose 6.8 `-gke`/`-aws` headers are only in the 24.04 archive); otherwise a cloud-vendor kernel the distro never published headers for, or RHEL, whose UBI repositories carry no `kernel-devel` | Set `nodePrep.image.*` to the node's own family and release (table in Before you start). If the headers genuinely are not published, pre-install them in the node image, or switch to a pre-baked builder image with `nodePrep.modules.v4l2loopback.sourcePath`, or use `method: kmm` |
| `kubectl get node ... allocatable.kasm\.com/video` returns `0` or nothing, while `nodePrep` looks healthy | The device plugin runs on a node where the module was never loaded - mismatched `nodeSelector`s | Give `videoDevicePlugin.nodeSelector` and `nodePrep.nodeSelector` the same value; check the node-prep log on that specific node |
| `helm install` fails to render: `sourcePath` combined with `method: kmm` | `sourcePath` names a directory inside *this chart's* builder image, which a KMM build pod never runs. Rejected deliberately | Drop `sourcePath`, or go back to `method: build` |
| `helm install` fails to render with an empty KMM registry/repository | Both are required whenever `method: kmm` - KMM loads the module from an image | Set `nodePrep.modules.v4l2loopback.kmm.image.registry` and `nodePrep.modules.v4l2loopback.kmm.image.repository` |
| KMM in-cluster build pod cannot push; DNS lookup of the registry hostname fails from the pod | The kaniko pod runs on the **pod network**; the registry hostname resolves only via the node's resolver (tailnet/MagicDNS, split-horizon DNS) | Add a CoreDNS forward for that zone (k3s: a `coredns-custom` ConfigMap `<zone>.server` stanza) and restart CoreDNS |
| `Module` exists but a node's kernel is never prepared, in airgap Mode A | No `<registry>/<repository>:<kernel release>` image was built for that kernel; KMM cannot pull what does not exist | Build and push that kernel's image before the node joins. `kubectl describe module ...` names the unmatched kernel |
| Install fails: the `Module` CRD does not exist | `method: kmm` without the KMM operator installed | `make kmm-install` (or `make kmm-install-mirrored KMM_IMAGE_REGISTRY=<mirror>`) |
| Airgapped build mode still runs the builder image's package manager (`apt-get`, `dnf`, `tdnf` or `zypper`) | The pre-baked builder image is missing a prerequisite, so the presence check fell through | Look for `build prerequisites already present; skipping package installation` in the pod log; if absent, add the missing piece to the image - the toolchain for its family (`build-essential kmod openssl libelf1` on Debian/Ubuntu, `gcc make kmod openssl elfutils-libelf-devel` on the RPM families) and the kernel build tree |
| Pod log: an error that the builder image has no supported package manager, listing `apt-get`, `dnf`, `microdnf`, `yum`, `tdnf` and `zypper` | `nodePrep.image.*` names an image that is neither pre-baked nor from a supported family (a distroless, Alpine or scratch-based image, for example), so nothing can install the toolchain | Use a builder image of the node's own family and release from the table in Before you start, or pre-bake everything so the presence check skips package installation |
| Pod log: `modprobe v4l2loopback failed: the kernel rejected the module's signature (... Key was rejected by service)` | UEFI Secure Boot is on and the freshly built module is unsigned | [Secure Boot](secure-boot.md); on Ubuntu 24.04+ the kernel's own signed `v4l2loopback` is loaded instead when `preferShippedModule` is on, so check that videodev is installed (next row) rather than signing |
| Pod log: `has its V4L2 core (videodev) as a separate module that is not installed on the node` | The kernel supports V4L2 but the package carrying `videodev.ko` is absent; cloud images often omit it | On Debian/Ubuntu the script installs `linux-modules-extra-<release>` itself from the builder image (`installVideodevPackage`); elsewhere install the package the message names on the node |
| Session never starts; agent log or the pod's `FailedScheduling` event: `Insufficient kasm.com/video` | The webcam is on for the image, so the pod requests `kasm.com/video`, and no node advertises it: `videoDevicePlugin` is off, its DaemonSet is not on the node, or `/dev/video*` does not exist there yet | Enable `videoDevicePlugin` next to `nodePrep` and pin both to the same nodes; or turn the webcam off on the image |
| Browser: "unable to connect to the webcam stream", the proxies log 502 on `.../webcam/stream`, and the session container's log says `Could not access /dev/videoN due to missing permissions` | The pod received the node's device node as udev made it (`root:video 0660`), and the image's webcam server runs as `kasm-user`, whose `video` gid is the image's, not the node's | `nodePrep.modules.v4l2loopback.deviceMode` (default `0666`) is applied by node-prep on every pass; a session started before the mode changed keeps the old node until it is relaunched. Under KMM, set the mode with a udev rule on the node, or add the node's `video` gid with `agent.workspaceSecurity.supplementalGroups`. A root session in a user namespace (`kubectl get pod -L kasm.com/run-mode` shows `userns-root`) may be refused even so: run the image at uid 1000, or `agent.workspaceSecurity.rootMode: host` (the default) |
| Build is OOMKilled and retried every `reconcileIntervalSeconds` without finishing | `nodePrep.resources.limits.memory` too low to hold headers + sources + gcc | Raise it above the `1Gi` default |

## Decisions

- [ ] Node kernel ships the V4L2 core (`modinfo videodev` succeeds); not a `-kvm`/minimal cloud flavor.
- [ ] Namespace labelled `pod-security.kubernetes.io/enforce=privileged`.
- [ ] Mode chosen: `build` (headers + toolchain per node) or `kmm` (operator + registry).
- [ ] Build mode only: `nodePrep.image.*` names a builder image of the node's own distribution family and release (the default `ubuntu:22.04` is for Ubuntu 22.04 nodes); one release per family in a mixed fleet.
- [ ] KMM mode only: `make kmm-install` / `make kmm-install-mirrored` run; `kubernetes.io/dockerconfigjson` secret created and named in `nodePrep.modules.v4l2loopback.kmm.imageRepoSecret`.
- [ ] KMM in-cluster builds only: the registry hostname resolves **from a pod** (CoreDNS forward added if it does not).
- [ ] `nodePrep.enabled=true` **and** `videoDevicePlugin.enabled=true`.
- [ ] `nodePrep.nodeSelector` and `videoDevicePlugin.nodeSelector` match.
- [ ] `/dev/video0..N` present on the node and `lsmod | grep v4l2loopback` non-empty.
- [ ] `kubectl get node <node> -o jsonpath='{.status.allocatable.kasm\.com/video}'` equals `videoDevices`.
- [ ] `nodePrep.modules.wireguard.enabled` left `false` unless the fleet runs kernels older than 5.6.
