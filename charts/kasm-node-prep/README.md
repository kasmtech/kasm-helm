# Kasm Node Prep

![Version: 1.1200.0-develop](https://img.shields.io/badge/Version-1.1200.0--develop-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Privileged DaemonSet that builds and loads the kernel modules Kasm Workspaces sessions depend on (v4l2loopback for webcam passthrough, WireGuard for VPN sidecars on kernels older than 5.6) on every matching node, re-applying them after node reboots.

**Homepage:** <https://kasm.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## What this chart does

Kasm Workspaces features that need a kernel module on the node cannot get one from Kubernetes alone. This
chart fills that gap with a privileged DaemonSet that runs a reconcile loop on every matching node:

* **v4l2loopback** creates the virtual `/dev/video*` devices behind Kasm webcam support. The browser captures
  the user's webcam, streams it to `kasm_webcam_server` inside the workspace, and that binary writes frames
  into a loopback device. Pair this chart with `kasm-video-device-plugin`, which advertises those devices to
  kubelet as the extended resource `kasm.com/video` so workspace pods can request `kasm.com/video: 1`.
  When the running kernel ships a `v4l2loopback` of its own (Ubuntu 24.04 and later carry one in-tree, signed
  with the distribution's kernel key) the script loads that one and builds nothing, which also passes Secure
  Boot without a MOK; the source build is the fallback (`modules.v4l2loopback.preferShippedModule`). A missing
  V4L2 core (`videodev`) is installed from the builder image on Debian/Ubuntu nodes
  (`modules.v4l2loopback.installVideodevPackage`). The loopback devices are made `0666` on every pass
  (`modules.v4l2loopback.deviceMode`): a session pod gets the node's device node as udev made it, and the
  image's webcam server runs as `kasm-user`, whose `video` gid is the image's, not the node's.
* **WireGuard** backs workspace VPN sidecars on nodes running a kernel older than 5.6. Kernels 5.6 and newer
  ship WireGuard in-tree, so the reconcile script detects the built-in module (`wg_` symbols in
  `/proc/kallsyms`) and skips the build even when the module is enabled. Most managed Kubernetes node images
  need nothing here.

`modules.v4l2loopback` can also be delegated instead of built here: `modules.v4l2loopback.method: kmm` hands
the module to the [Kernel Module Management](https://kmm.sigs.k8s.io/) operator, which builds it into a
container image and loads it with its own worker pods, and removes it from the DaemonSet's script entirely.
See [KMM mode](#kmm-mode). Everything below describes the default, `method: build`.

Each pass checks whether the requested modules are loaded (`lsmod`), and builds and inserts the ones that are
not. A pass where everything is already loaded does nothing but sleep for
`reconcileIntervalSeconds`. Because the check is against the running kernel, **node reboots self-heal**: after
a reboot the module is gone, the next pass rebuilds and reloads it, and no operator action is needed.

A module that cannot be built (missing kernel headers, no repository access) is logged as a clear error and
retried on the next pass. It never crash-loops the DaemonSet, so one unprepared node cannot take the rollout
down.

The same loop optionally applies **node tuning** — a disk swapfile and a set of kernel tunables — under
`tuning.*`. Both are off by default and both are re-asserted every pass, which is what makes them survive a
reboot without anything being written to `/etc/sysctl.d` or `/etc/fstab`. See
[Node tuning](#node-tuning). A tuning-only install (every module disabled) is valid: the DaemonSet renders
with none of the module build machinery and none of its host mounts.

This page is the chart reference. The procedures (the webcam module through KMM, Secure Boot, node
tuning and swap, the airgap builder image) are in the [documentation index](../../docs/README.md).

## Security posture

Read this before installing. **This chart is privileged by necessity** — inserting a kernel module, writing
the node's `/proc/sys` and calling `swapon` cannot be done from an unprivileged container.

* The DaemonSet container runs with `securityContext.privileged: true`. It holds `CAP_SYS_MODULE` and full
  access to the node kernel; anything it builds and inserts runs in ring 0 on that node.
* Every host path is mounted **only when the feature that needs it is enabled**, so an install renders the
  smallest set its values call for:
  * Kernel modules (`modules.*.enabled`):
    * `/lib/modules` **read-write** — so `modules_install` and `depmod` can place the built module in the
      node's module tree.
    * `/usr/src` **read-write** — so the kernel headers installed at runtime persist on the node and the
      `sign-file` helper can be found there.
    * `/dev` **read-write** — to observe the `/dev/video*` devices v4l2loopback creates.
  * Swap (`tuning.swap.enabled`):
    * `tuning.swap.hostPath` (default `/var/lib/kasm-node-prep`) **read-write** — the directory the
      swapfile is created in, mounted at its own host path.
    * `/etc/rancher/k3s` and `/var/lib/kubelet` **read-only** — read solely by the kubelet swap-support
      check. Both use `DirectoryOrCreate`, so whichever one your distribution does not use is created
      empty on the node rather than wedging the pod in `ContainerCreating`.
  * `tuning.sysctls` needs no host mount at all: the privileged container already writes the node's
    `/proc/sys`.
* It does **not** use `hostNetwork`, `hostPID`, `hostIPC`, or a host service account, and it mounts no other
  host path.
* `modules.v4l2loopback.method: kmm` does not remove the privilege, it **moves** it: KMM's own worker pods
  insert the module and are privileged in the same way. What changes is that this chart stops compiling
  arbitrary source on the node, and — with `kmm.sign` — that only a signed module ever reaches one. Read
  [KMM mode](#kmm-mode) before treating it as a hardening measure.
* With `tuning.*` enabled the DaemonSet changes **node-wide** kernel state — sysctl values and an active
  swapfile — that outlives the pod. Deleting the release stops the reconciliation but does not undo the
  state; a node reboot does (nothing is persisted to `/etc/sysctl.d` or `/etc/fstab`).
* The namespace it is installed into must allow privileged pods. With
  [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) that means
  labelling the namespace `pod-security.kubernetes.io/enforce: privileged`. The pods cannot satisfy the
  `baseline` or `restricted` standards and will be rejected outright by an enforcing namespace.
* By default the reconcile script installs packages from the builder image's distribution repositories and
  clones module sources over the network at runtime. Pin `modules.*.sourceRef` and point `modules.*.sourceRepo` at an internal
  mirror if you need builds to be reproducible and supply-chain reviewed (a mirror that needs a login takes its credentials from a Secret named in `modules.*.sourceRepoSecret`; a `user:password@` in the URL itself is rejected at render time) — or remove the runtime fetches
  altogether with a pre-baked builder image (see [Airgapped / offline nodes](#airgapped-and-offline-nodes)),
  which is the only configuration where what gets inserted into the node kernel is fixed at image build time.

Treat installing this chart as granting node-root to whoever controls its values.

## Node prerequisites

* **Loadable kernel modules.** The node kernel must permit module insertion (`/sys/module` accessible, module
  loading not locked down). Nodes with `kernel.modules_disabled=1` or a hardened, immutable OS image cannot be
  prepared this way.
* **A kernel flavor that ships the V4L2 core (for `v4l2loopback`).** The module links against the kernel's
  `videodev` module. Minimal VM kernel flavors — Ubuntu's `-kvm` flavor, some cloud kernels — are built with
  `CONFIG_MEDIA_SUPPORT` unset and can **never** load v4l2loopback. Elsewhere `videodev` is usually a
  separately packaged module: on Ubuntu it is in `linux-modules-extra-$(uname -r)` (the `-generic`, `-aws`,
  `-gke` and `-azure` flavors all have one in the 22.04 and 24.04 archives); on RHEL 8/9, Rocky and Alma in
  `kernel-modules`, which the `kernel` metapackage installs by default; on Amazon Linux 2023 in
  `kernel-modules-extra`; on Oracle Linux UEK in `kernel-uek-modules` (UEK R7) or `kernel-uek-modules-desktop` (UEK
  R8), both pulled in by the `kernel-uek` metapackage. Confirm with `modinfo videodev` on the node.
  The script detects a missing core and reports it in the pod log, naming the package for the builder image's
  family, instead of retrying a build that cannot succeed.
* **Kernel headers.** The container installs the kernel headers package for `$(uname -r)` at runtime, from
  the **builder image's** package repositories: `linux-headers-$(uname -r)` on Debian and Ubuntu,
  `kernel-devel` and its variants on the RPM families, `kernel-<flavor>-devel` on openSUSE and SLES — the
  exact package per family is in [Builder image per node image](#builder-image-per-node-image). `uname -r`
  inside the container reports the *node* kernel, because containers share the host kernel; they do not share
  its package repositories, which is why the builder image has to match the node (below). If the headers for
  the node kernel are not published at all (some cloud-vendor kernels; RHEL, whose UBI repositories carry no
  `kernel-devel`), pre-install them in the node image: `/usr/src` is bind-mounted, so the container then
  finds them. Without them the module cannot be compiled, and the pass is skipped with an error in the pod log.
  When the kernel was built with a newer gcc than the builder image's default, the script installs that one
  too, taken from the kernel's `CONFIG_CC_VERSION_TEXT`: `gcc-<N>` on Ubuntu (the 22.04 HWE kernels pin
  `gcc-12`) and `gcc-toolset-<N>` on RHEL 9, its rebuilds and Oracle Linux 9 (UEK R8 is built with gcc 14).
* **Package repository and source access.** Each node needs to reach the builder image's distribution package
  repositories and the git repositories in `modules.*.sourceRepo`, either directly or through a proxy or
  internal mirror — unless you use a pre-baked builder image, which removes both fetches. See
  [Airgapped / offline nodes](#airgapped-and-offline-nodes).
* **A builder image of the node's distribution family and release**, *when packages have to be installed at
  runtime.* The container shares the node's kernel but not its userland, and the headers above come from the
  builder image's repositories, never the node's. So `image.registry`/`image.repository`/`image.tag` must be
  the same distribution family **and** release as the node: the default `docker.io/library/ubuntu:22.04`
  matches Ubuntu 22.04 nodes, and a GKE Ubuntu 24.04 node — whose 6.8 `-gke` kernel has no headers in the
  22.04 archive — needs `ubuntu:24.04`. The reconcile script detects the package manager the image carries
  and branches on it: `apt-get` (Debian, Ubuntu); `dnf`, `yum` or `microdnf` (RHEL 8/9, Rocky, Alma, Oracle,
  CentOS Stream, Fedora, Amazon Linux 2023); `tdnf` (Azure Linux 3); `zypper` (openSUSE Leap, SLES). An
  image with none of the six logs an error naming all six. A pre-baked builder image that already carries
  everything is never asked for a package and so may be built on any OS family. One DaemonSet has one builder
  image, so a fleet mixing node families under one release is out of scope: install one release per family,
  each with a `nodeSelector` for its nodes. Which image to use per node image is the table in
  [Builder image per node image](#builder-image-per-node-image).
* **Secure Boot: MOK enrollment.** On a node with UEFI Secure Boot enabled the kernel refuses unsigned
  modules. Generate a Machine Owner Key pair, enroll the public key in each node's MOK database with `mokutil
  --import` (a one-time manual step per node, or bake it into the node image), and store the pair in a Secret:

  ```bash
  kubectl create secret generic kasm-mok-keys \
    --from-file=mokPrivateKey=MOK.priv \
    --from-file=mokPublicKey=MOK.der
  ```

  Then set `secureBoot.existingMokSecret: kasm-mok-keys`. The Secret is mounted read-only at `/etc/kasm-mok`
  and every built `.ko` is signed with the kernel's `sign-file` helper before insertion. Most managed
  Kubernetes node images (EKS, GKE, AKS) leave Secure Boot off, so this is mainly a bare-metal and private
  cloud concern. See [Secure Boot](../../docs/how-to/nodes/secure-boot.md).

### Builder image per node image

What the reconcile script installs, by the package manager it finds in the builder image:

| Builder family | Package manager | Kernel headers it installs | Toolchain it installs |
| --- | --- | --- | --- |
| Debian, Ubuntu | `apt-get` | `linux-headers-$(uname -r)` | `build-essential git kmod ca-certificates libelf1` |
| RHEL 8/9, Rocky, Alma, Oracle, CentOS Stream, Fedora, Amazon Linux 2023 | `dnf` (also `yum`, `microdnf`) | by path, `/usr/src/kernels/$(uname -r)`, which resolves to `kernel-devel`, `kernel6.12-devel` (Amazon Linux 2023's second kernel line) or `kernel-uek-devel` (Oracle UEK) | `gcc make kmod git ca-certificates elfutils-libelf-devel` (the headers package pulls most of this itself) |
| Azure Linux 3 | `tdnf` | `kernel-devel-$(uname -r)` | `gcc make binutils kmod git ca-certificates elfutils-libelf-devel` |
| openSUSE Leap, SLES | `zypper` | `kernel-<flavor>-devel = <version>`, derived from `uname -r` (for example `6.4.0-150600.23.17-default`) | `gcc make kmod git ca-certificates libelf-devel` |

Plus `openssl` on every family when Secure Boot signing is configured (`secureBoot.existingMokSecret`). A
pre-baked image that already carries everything skips package installation entirely, on any family.

Which builder image to point `image.*` at, per node image:

| Node image | Builder image (`image.*`) | Build mode? | Notes |
| --- | --- | --- | --- |
| Ubuntu 22.04 / 24.04 (self-managed, EKS Ubuntu AMI, GKE Ubuntu, AKS Ubuntu) | `docker.io/library/ubuntu:22.04` / `:24.04`, matching the node release | yes | `-aws`, `-gke`, `-azure` and `-generic` headers and modules-extra all exist. Not the `-kvm` flavor. |
| Debian 12 | `docker.io/library/debian:12` | yes | |
| Amazon Linux 2023 (EKS default) | `public.ecr.aws/amazonlinux/amazonlinux:2023` (or `docker.io/library/amazonlinux:2023`) | yes | V4L2 core is in `kernel-modules-extra`; confirm with `modinfo videodev` on a node. Both AL2023 kernel lines (6.1 and 6.12) resolve. |
| Rocky / Alma / CentOS Stream 9 (and 8) | `docker.io/library/rockylinux:9`, `almalinux:9` (or `:8`), matching the major | yes | V4L2 core in `kernel-modules`, present by default. |
| RHEL (subscription) | `registry.access.redhat.com/ubi9/ubi` (or Rocky/Alma of the same major) | partial | UBI repositories carry the toolchain but **not** `kernel-devel`: pre-install `kernel-devel-$(uname -r)` in the node image; `/usr/src` is bind-mounted, so the container then finds it. |
| Oracle Linux 9 | `docker.io/library/oraclelinux:9` as is, RHCK or UEK nodes. The stock image ships its UEK repositories disabled; under a UEK kernel (release ending in `.el9uek.x86_64`) the script and the KMM Dockerfile enable the matching one (`ol9_UEKR8` for 6.12 kernels, `ol9_UEKR7` for 5.15) for the headers install, so the headers-by-path lookup resolves `kernel-uek-devel`. UEK R8 is built with gcc 14 from `gcc-toolset-14`, which the headers pull in and the script switches to on its own. | yes | |
| Azure Linux 3 (AKS) | `mcr.microsoft.com/azurelinux/base/core:3.0` | yes, the `tdnf` path | |
| openSUSE Leap / SLES | `registry.opensuse.org/opensuse/leap:15.6`, or the SLES BCI matching the release | expected | |
| EKS Bottlerocket | none | no | No shell, no headers, immutable. `method: kmm` with `kmm.build.enabled: false` and per-kernel images built out of band (Bottlerocket publishes a kmod-kit for that). Module loading policy is Bottlerocket's own. |
| GKE Container-Optimized OS | none | no | Unchanged: use the Ubuntu node image for the workspace pool, or prebuilt KMM images. |
| OpenShift RHCOS | none | no | Unchanged: KMM. |

## KMM mode

`modules.v4l2loopback.method: kmm` swaps *who builds and loads the module*. Instead of compiling it on every
node inside this chart's privileged DaemonSet, the chart renders a `kmm.sigs.x-k8s.io/v1beta1` **`Module`**
custom resource and lets the [Kernel Module Management](https://kmm.sigs.k8s.io/) operator do the rest: KMM
watches which kernel releases are actually present on the selected nodes, builds (or pulls) one kmod image
per kernel, and runs its own worker pods to `modprobe` the module.

When the method is `kmm`, v4l2loopback disappears from the reconcile script. If it was the only reason the
DaemonSet existed — no `wireguard`, no `tuning.*` — no DaemonSet and no script ConfigMap are rendered at all.
The `Module` is the whole release. Node tuning and any module still on `method: build` keep their DaemonSet
exactly as before, alongside the `Module`.

### Which one to choose

| | `build` (default) | `kmm` |
| --- | --- | --- |
| **Prerequisites** | Just this chart | The KMM operator, installed cluster-wide out of band |
| **Where compilation happens** | On every node, every time the module is missing | Once per kernel release, in a build pod, into an image |
| **Fleet with several kernels** | Each node builds its own | One `Module`; KMM resolves each kernel to its own image tag |
| **Node needs a toolchain and headers** | Yes, at runtime, through the builder image's package manager (`apt-get`, `dnf`, `tdnf` or `zypper`), unless pre-baked | No — nodes only pull an image |
| **Container registry** | Not needed | **Required** |
| **Secure Boot** | Sign on the node with a mounted MOK key (`secureBoot.existingMokSecret`) | Sign in-cluster before the image is pushed (`modules.v4l2loopback.kmm.sign`) |
| **Where failures show up** | The node-prep pod log, with a diagnosis | The `Module` status and the KMM build pod logs |

Choose `kmm` when the fleet is large enough that N nodes compiling the same module N times is waste, when
Secure Boot means an unsigned `.ko` must never touch a node, or when the node image deliberately ships no
compiler and no kernel headers. Choose `build` when you want the chart to be self-contained — no operator, no
registry, no CRD — and when you value the reconcile script's diagnostics: it explains a missing V4L2 core, an
unavailable headers package, or a kubelet that will not tolerate swap, in the pod log, on the node it happened
on.

### Prerequisite: the KMM operator

KMM publishes no official Helm chart. Install it once per cluster from its pinned kustomize overlay:

```console
make kmm-install
```

which is `kubectl apply -k "https://github.com/kubernetes-sigs/kernel-module-management/config/default?ref=<KMM_VERSION>"`
with `KMM_VERSION` pinned in the repository `Makefile` (the version the `Module` schema this chart renders
was written against), followed by pinning the operator's five images to the matching release tag — the
overlay itself references `:latest`, a rolling CI build. **cert-manager must already be installed**: the
overlay creates an `Issuer` and a `Certificate` for KMM's admission webhook, and without them the apply fails
on those two kinds and the webhook never comes up. `make kmm-uninstall` removes it again; note that it removes the
*operator*, not the modules KMM already loaded — delete the `Module` custom resource first if you want those
unloaded, because KMM unloads on delete.

Without the operator the `Module` this chart creates is inert: the CRD does not exist, so the install fails
outright, and if the CRD is present but the controller is not, nothing ever reconciles it.

### The registry is not optional

KMM loads the module from a container image, so `modules.v4l2loopback.kmm.image.registry` and
`.repository` are both **required** — an empty one fails the render with an explanatory message. With
in-cluster builds enabled the same registry is also the *push* target, so the credentials in
`modules.v4l2loopback.kmm.imageRepoSecret` need write access to it:

```console
kubectl create secret docker-registry kasm-registry \
  --docker-server=registry.example.internal \
  --docker-username=... --docker-password=...
```

Leave `modules.v4l2loopback.kmm.image.tag` empty and the rendered `containerImage` ends in the literal
`${KERNEL_FULL_VERSION}`, which **KMM** substitutes with each node's kernel release. That single line covers a
fleet running several kernels. Set an explicit tag only when every matching node runs one kernel.

```yaml
modules:
  v4l2loopback:
    enabled: true
    method: kmm
    kmm:
      image:
        registry: registry.example.internal
        repository: kasm/v4l2loopback
      imageRepoSecret: kasm-registry
```

### In-cluster builds

`modules.v4l2loopback.kmm.build.enabled: true` (the default) renders a ConfigMap holding a two-stage
Dockerfile, and points the `Module`'s `build.dockerfileConfigMap` at it. KMM runs a kaniko build pod per
kernel release from it. That build pod — not the node — needs:

* the distribution's kernel headers package for `${KERNEL_FULL_VERSION}`, from the package repositories of
  the base image (`image.registry`/`image.repository`/`image.tag`, the same builder image values the
  DaemonSet uses, so the same family-and-release rule applies): `linux-headers-${KERNEL_FULL_VERSION}` on
  Debian and Ubuntu, `/usr/src/kernels/${KERNEL_FULL_VERSION}` (`kernel-devel`, `kernel6.12-devel` or
  `kernel-uek-devel`) on the dnf families, `kernel-devel-${KERNEL_FULL_VERSION}` on Azure Linux 3,
  `kernel-<flavor>-devel` on openSUSE and SLES — the table in
  [Builder image per node image](#builder-image-per-node-image);
* `modules.v4l2loopback.sourceRepo` at `modules.v4l2loopback.sourceRef`, cloned over HTTPS;
* push access to the registry above.

The Dockerfile detects the package manager the same way the reconcile script does. On the RPM families it
passes `KERNEL_DIR=/usr/src/kernels/${KERNEL_FULL_VERSION}` to the module's `make`, because a build
container that has only the headers package has no `/lib/modules/<kernel>/build` symlink to find them by.

The second stage keeps only the compiled `.ko`, placed where a KMM worker expects it —
`/opt/lib/modules/${KERNEL_FULL_VERSION}/extra/`, indexed with `depmod -b /opt` — so the image that reaches
the node carries no toolchain.

`modules.v4l2loopback.sourcePath` is a `method: build` value only and **fails the render** when combined with
`method: kmm`: it names a directory inside *this chart's* builder image, which a KMM build pod never runs.

### Airgapped KMM (prebuilt modules)

With `modules.v4l2loopback.kmm.build.enabled: false` the chart renders no Dockerfile ConfigMap and
no `build` block on the `Module`, and KMM only ever *pulls*: one `<registry>/<repository>:<kernel
release>` image per fleet kernel. A kernel with no matching tag is left unprepared, and the `Module`
status says so. Building those images and mirroring the KMM operator's own five (`make images-agent`
lists them; `make kmm-install-mirrored KMM_IMAGE_REGISTRY=<mirror>` installs against them) is
[Webcam kernel modules](../../docs/how-to/nodes/webcam-kernel-modules.md).

### Secure Boot

`modules.v4l2loopback.kmm.sign` (with `keySecret` and `certSecret`, both required when it is
enabled) is the KMM-mode counterpart of `secureBoot.existingMokSecret`: KMM signs the built module
in-cluster, between the build and the push, so an unsigned `.ko` never reaches a node. The two are
independent, and `secureBoot.existingMokSecret` applies only to modules this chart's DaemonSet
builds. MOK enrollment stays a per-node step. See [Secure Boot](../../docs/how-to/nodes/secure-boot.md).

### Diagnosing it

This is the real day-two difference. In `build` mode a failure is a line in the node-prep pod log, on the node
it happened on. In `kmm` mode this chart's log has nothing to say about v4l2loopback at all — look at the
`Module` and at KMM instead:

```console
kubectl get modules.kmm.sigs.x-k8s.io
kubectl describe module <release>-v4l2
kubectl get pods -l kmm.node.kubernetes.io/module.name=<release>-v4l2
kubectl logs -n kmm-operator-system deploy/kmm-operator-controller
```

A build that cannot find its kernel headers, a push the registry secret is not allowed to make, and a kernel
release no mapping matches all surface there, not here.

The `Module` is named `<release>-v4l2`, much shorter than this chart's other resources on purpose: KMM's
admission webhook refuses a `Module` whose name and namespace together exceed 41 characters, which even
`<release>-v4l2loopback` breaks for ordinary pairs such as `kasm-agent-prod` in `kasm-agent-prod`. The chart
applies the same rule at render time so the limit surfaces from Helm rather than from the webhook. A
`fullnameOverride`, when set, replaces the release name in it.

## Node tuning

Two optional pieces of host tuning, applied by the same reconcile loop, both **off by default**. Nothing is
persisted to the node's configuration files: the loop re-asserts the state every pass, which is what makes it
survive a reboot, and what makes backing it out a values change rather than a node edit.

### Swap (`tuning.swap`)

A disk swapfile, the counterpart of the `/mnt/Kasm.swap` that Kasm's Docker agent installer creates on every
agent host. Kubernetes hands pods node swap only when the **node's kubelet** is configured for it (cgroup v2,
`failSwapOn: false`, `memorySwap.swapBehavior: LimitedSwap`), and a kubelet still carrying the default
`failSwapOn: true` refuses to start while the node has swap active. Configure the kubelet first:
[Node tuning and swap](../../docs/how-to/nodes/tuning-and-swap.md).

#### The safety check

The reconcile loop refuses to create swap until it can confirm the kubelet tolerates it. Before the first
`swapon` it greps, best effort, the kubelet configuration mounted read-only into the pod:

* `/etc/rancher/k3s/config.yaml` and `/etc/rancher/k3s/config.yaml.d/*.yaml` for `fail-swap-on=false`
  (k3s, RKE2)
* `/var/lib/kubelet/config.yaml` for `failSwapOn: false` (kubeadm and most other distributions)

If neither confirms it the pass logs an error naming both paths and skips swap; the node is left exactly as it
was, and fixing the kubelet is picked up on the next pass. A kubelet configured somewhere the script cannot
read (a systemd drop-in, `--kubelet-arg` on a command line, a cloud-init unit) never confirms.
`tuning.swap.force: true` skips the check entirely and removes it from the rendered script; verify
`failSwapOn: false` is in effect via `kubectl get --raw "/api/v1/nodes/<node>/proxy/configz"` before using it.

#### Sizing

`tuning.swap.sizeMib: 0`, the default, means half of the node's `MemTotal` clamped to `[4096, 16384]` MiB.
Upstream Kasm publishes no RAM-ratio formula; **the half-of-RAM rule is this chart's**, anchored on the
installer's documented `8192` example being exactly half of a 16 GiB node, and the clamp is the range of the
installer's own menu. Set an explicit `sizeMib` whenever you have a better number for your workload.

The file is `<tuning.swap.hostPath>/kasm.swap`, mode `0600`, created with `fallocate` (`dd` fallback) and
activated with `swapon`. Point `hostPath` at a real node disk with room for it: ext4 and xfs work, btrfs
needs a `nodatacow` file, and overlayfs and tmpfs never will. Changing `sizeMib` later is picked up on the
next pass — a swapfile of the wrong size that is not currently active is replaced.

#### How much of it a workspace pod actually gets — today, none

`LimitedSwap` gives a container swap **only when its memory request is strictly below its memory limit**.
A container with request equal to limit gets exactly zero, whatever its QoS class or CPU allocation
method; *BestEffort* and fully *Guaranteed* pods get zero too. This is the important part: the Kasm
operator derives a workspace's memory request **and** limit from the same `memory_bytes`, so every
session container runs with request = limit and therefore **gets no swap**. The swapfile this chart creates is still worth having: the agent, the session-proxy
sidecar, CSI plugins and system pods are Burstable with memory headroom and do draw on it, which is what
keeps the node itself off the OOM edge. But do not size a node expecting *sessions* to spill into swap,
and do not read the formula below as a per-session allowance — it is the allowance for a Burstable pod
whose request is below its limit, which a workspace is not:

```text
container swap limit = (container memory request / node MemTotal) × total node swap   # request < limit only
```

If a future operator release stamps a memory limit above the request, sessions would pick up swap by this
formula automatically; until then the knob tunes everything on the node *except* the sessions.

#### Why not zram

zram is deliberately not offered as a default. Compressed swap lives in RAM, so it cannot do the one job
Kasm wants swap for — getting an idle session's pages *off* the node's memory — and every MiB of it inflates
`total node swap` in the formula above, handing every Burstable pod a larger `LimitedSwap` allowance backed
by the very memory that was under pressure. Configure zram by hand at a *lower priority* than the disk
swapfile if you want it as a fast first tier; do not use it instead of one.

### Sysctls (`tuning.sysctls`)

`tuning.sysctls.values` is a map written straight to the node's `/proc/sys` once per pass (no `sysctl`
binary is needed in the builder image) — silent when the value is already correct, logged when it changes. **Kasm's installer sets no sysctls at all**; these are this chart's
engineering judgement, not an upstream recommendation. The defaults raise the inotify limits, which desktop
sessions consume disproportionately:

| Tunable | Default here | Kernel default | Why |
| ------- | ------------ | -------------- | --- |
| `fs.inotify.max_user_instances` | `1024` | `128` | Every session runs a desktop environment, a file manager and a browser, each of which takes inotify instances. The limit is per *UID*, and workspace sessions on a node share one, so it is effectively a per-node budget that a handful of concurrent sessions exhausts. |
| `fs.inotify.max_user_watches` | `524288` | `8192`, raised by some distributions | The same per-UID accounting applied to watched paths. The symptom of running out is applications silently losing file-change notifications rather than failing outright, which makes it an unpleasant one to diagnose. |

The map **merges** with these defaults, the way Helm merges any map, so adding an entry keeps them. Set a key
to `null` to drop one:

```yaml
tuning:
  sysctls:
    enabled: true
    values:
      fs.inotify.max_user_instances: null   # drop the default
      vm.max_map_count: 262144
```

Values are only ever written to `/proc/sys`, never to `/etc/sysctl.d`, so a node reboot resets them and the
next pass reapplies them — and uninstalling the chart leaves nothing behind on the node.

## Airgapped and offline nodes

Out of the box this chart reaches the network twice per build: the builder image's package manager
(`apt-get`, `dnf`, `tdnf` or `zypper`) for the toolchain and the kernel headers, and `git clone` for the
module sources. Both are avoidable. With a **pre-baked builder image** the
reconcile loop performs no network operation at all, which is what makes the chart installable in an
airgapped environment.

Two things make that work:

1. **The presence check.** Before any package installation the script checks whether what this pass needs is
   already there — `gcc`, `make`, `insmod` (from `kmod`), `openssl` when Secure Boot signing is configured,
   `git` only when a clone is still needed, and the kernel build tree at `/lib/modules/$(uname -r)/build`. If
   everything is present it logs `build prerequisites already present; skipping package installation` and
   goes straight to the build. This check runs before any distro-specific logic, so a pre-baked image does
   not have to belong to any of the supported package-manager families, and an image with none of
   `apt-get`, `dnf`, `microdnf`, `yum`, `tdnf` or `zypper` is only an error (one naming all six) for an
   image that is *not* pre-baked.
2. **`modules.*.sourcePath`.** Set it to a directory inside the builder image holding an already-vendored
   module source tree. The script copies that tree into its work directory and builds from it instead of
   cloning. When every enabled module has a `sourcePath`, `git` disappears from the rendered script entirely.

### The kernel build tree comes from the node, not the image

`/lib/modules` and `/usr/src` are host paths bind-mounted into the container, so they **shadow** whatever the
builder image has at those paths. Baking the headers package into the image does not help: at runtime the
container sees the node's copies. Pre-install the matching headers in the **node image** (they are what
`/lib/modules/$(uname -r)/build` resolves to), or leave the runtime package-installation path in place on
nodes that can still reach the builder image's distribution repositories.

### Build and push the builder image

See [Registries and airgap](../../docs/how-to/registries-and-airgap.md) for the Dockerfile and the push.

### Point the chart at it

```yaml
image:
  registry: registry.example.internal
  repository: kasm/node-prep-builder
  tag: "22.04-v0.15.4"

modules:
  v4l2loopback:
    enabled: true
    sourcePath: /opt/kasm-modules/v4l2loopback
  wireguard:
    # Only on kernels older than 5.6.
    enabled: false
    sourcePath: /opt/kasm-modules/wireguard-linux-compat
```

`modules.*.sourceRepo` and `modules.*.sourceRef` are ignored while `sourcePath` is set; keep them pointed at
the upstream you vendored from, as a record of what the image contains. The pod log confirms the offline path
with `build prerequisites already present; skipping package installation`. If that line never appears the
script has fallen back to the builder image's package manager, which is exactly what fails on an airgapped
node.

## Usage

Installing with every module *and* every `tuning.*` feature disabled is a mistake, and the chart fails the
render with an explanatory error rather than installing a DaemonSet that does nothing. A module delegated to
KMM counts as enabled: that install renders a `Module` and, if nothing else needs the reconcile loop, no
DaemonSet at all.

Restrict the DaemonSet to the nodes that actually host workspace sessions, and give
`kasm-video-device-plugin` the same selector so `kasm.com/video` is only advertised where the module is
loaded:

```yaml
nodeSelector:
  kasm.com/workspaces: "true"
tolerations:
  - key: kasm.com/workspaces
    operator: Exists
    effect: NoSchedule
```

Watch a rollout with `kubectl logs -l app.kubernetes.io/component=node-prep -f`, and confirm the result on a
node with `lsmod | grep v4l2loopback` and `ls /dev/video*`.

## Chart value settings in `values.yaml`

## Values

<table>
	<thead>
		<th>Key</th>
		<th>Type</th>
		<th>Default</th>
		<th>Description</th>
	</thead>
	<tbody>
		<tr>
			<td id="fullnameOverride"><a href="./values.yaml#L9">fullnameOverride</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Override the fully qualified name of every resource this chart creates. Leave empty to use the standard `<release name>-<chart name>` naming. </td>
		</tr>
		<tr>
			<td id="global"><a href="./values.yaml#L13">global</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
cattle:
    systemDefaultRegistry: ""
</pre>
</div>
			</td>
			<td>Values Helm shares with every chart in a release. Rancher fills in `global.cattle.*` on every install from its catalog; nothing here needs to be set by hand.</td>
		</tr>
		<tr>
			<td id="global--cattle--systemDefaultRegistry"><a href="./values.yaml#L19">global.cattle.systemDefaultRegistry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The registry Rancher configured as the cluster's system default registry (air-gapped and mirrored clusters). When set, it replaces the registry part of every image this chart renders and `image.registry` is ignored, following Rancher's convention. Rancher sets it on install from its catalog; leave it empty everywhere else.</td>
		</tr>
		<tr>
			<td id="image--registry"><a href="./values.yaml#L40">image.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
docker.io
</pre>
</div>
			</td>
			<td>Container registry that hosts the builder image. Point this at a private registry or a pull-through mirror for air-gapped clusters. </td>
		</tr>
		<tr>
			<td id="image--repository"><a href="./values.yaml#L43">image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
library/ubuntu
</pre>
</div>
			</td>
			<td>Repository of the builder image within `image.registry`. </td>
		</tr>
		<tr>
			<td id="image--tag"><a href="./values.yaml#L47">image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
"22.04"
</pre>
</div>
			</td>
			<td>Tag of the builder image. May carry a digest suffix (for example `22.04@sha256:<digest>`) to pin the image immutably. </td>
		</tr>
		<tr>
			<td id="imagePullSecrets"><a href="./values.yaml#L54">imagePullSecrets</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Names of image pull Secrets in the release namespace, for pulling the builder image from a private registry (the air-gapped path described under `image.*`). Applies to the DaemonSet; a KMM in-cluster build pulls the builder for its own build pod and pushes the module image with `modules.v4l2loopback.kmm.imageRepoSecret`. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--deviceMode"><a href="./values.yaml#L97">modules.v4l2loopback.deviceMode</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
"0666"
</pre>
</div>
			</td>
			<td>Permission bits applied to the loopback device nodes (the `/dev/video*` this module creates, never a physical camera) after every pass. A session pod receives the node's device node as it is, `root:video 0660` by udev's default, while the workspace image runs its webcam server as `kasm-user`, whose `video` group is the image's own gid (39 on RHEL-family images), not the node's (44 on Ubuntu). The server then fails with "Could not access /dev/videoN due to missing permissions" and the browser reports "unable to connect to the webcam stream". `0666` lets any user in a pod that was allocated the device open it; the device plugin still hands each device to one pod at a time. Empty leaves udev's mode alone. **Applies to `method: build` only**; under KMM set the same mode with a udev rule on the node. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--enabled"><a href="./values.yaml#L67">modules.v4l2loopback.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Build and load the v4l2loopback kernel module on every matching node. Required for webcam passthrough (`KASM_SVC_WEBCAM=1`) into workspace sessions. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--exclusiveCaps"><a href="./values.yaml#L87">modules.v4l2loopback.exclusiveCaps</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Announce the video capture capability only once a producer has opened the device (`exclusive_caps=1`). Required by Chrome/Chromium based applications inside the workspace, which ignore loopback devices that advertise capture with no stream attached. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--installVideodevPackage"><a href="./values.yaml#L112">modules.v4l2loopback.installVideodevPackage</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>When the kernel has its V4L2 core (`videodev`) as a separate module that is not installed on the node, install the package carrying it from the builder image's repositories into the node's `/lib/modules`, the same way the kernel headers are installed into `/usr/src`. Debian/Ubuntu families only (`linux-modules-extra-<release>`); on the RPM families the core is part of the kernel's own module package and the script names it instead. **Applies to `method: build` only.** </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--build--enabled"><a href="./values.yaml#L200">modules.v4l2loopback.kmm.build.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Let KMM build the kmod image in the cluster. The build pod needs to reach the distribution's kernel headers package for that kernel (the builder image's family decides which one — `image.*` must match the node family and release, exactly as for the DaemonSet), the module source in `modules.v4l2loopback.sourceRepo`, and the registry above (to push). Set to `false` for the airgapped path: no Dockerfile ConfigMap is rendered and no `build` block appears on the `Module`, so KMM only ever *pulls* images you built in connected CI and mirrored, one `<registry>/<repository>:<kernel release>` tag per kernel in the fleet. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--image--registry"><a href="./values.yaml#L168">modules.v4l2loopback.kmm.image.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Registry hosting the kmod image. **Required when `modules.v4l2loopback.method` is `kmm`.** With in-cluster builds this is also the registry the kaniko build pod pushes to, so the credentials in `modules.v4l2loopback.kmm.imageRepoSecret` need write access to it. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--image--repository"><a href="./values.yaml#L173">modules.v4l2loopback.kmm.image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Repository of the kmod image within `modules.v4l2loopback.kmm.image.registry` (for example `kasm/v4l2loopback`). **Required when `modules.v4l2loopback.method` is `kmm`.** </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--image--tag"><a href="./values.yaml#L181">modules.v4l2loopback.kmm.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag of the kmod image. Leave empty (the default) to tag per kernel: the rendered `containerImage` then ends in the literal `${KERNEL_FULL_VERSION}`, which KMM substitutes with each node's kernel release, so one entry covers a fleet running several kernels. Set it to pin a single image for every matching kernel instead — sensible only when the fleet is on one kernel. May carry a digest suffix (`1.0@sha256:<digest>`) to pin immutably. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--imageRepoSecret"><a href="./values.yaml#L187">modules.v4l2loopback.kmm.imageRepoSecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of an existing `kubernetes.io/dockerconfigjson` Secret in the release namespace, used both to pull the kmod image onto the nodes and to push the result of an in-cluster build (`spec.imageRepoSecret` on the `Module`). Leave empty for a registry that needs no credentials. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--kernelRegexp"><a href="./values.yaml#L156">modules.v4l2loopback.kmm.kernelRegexp</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
^.*$
</pre>
</div>
			</td>
			<td>Regular expression matched against each node's kernel release, deciding which nodes this mapping applies to (`spec.moduleLoader.container.kernelMappings[].regexp` on the `Module`). The default matches every kernel, which is what a single-image fleet wants. Narrow it (for example `^6\.8\..*$`) when different kernel families need different images. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--sign--certSecret"><a href="./values.yaml#L220">modules.v4l2loopback.kmm.sign.certSecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of the Secret holding the **public** certificate (DER). **Required when `modules.v4l2loopback.kmm.sign.enabled` is set.** KMM expects the certificate under the Secret key `cert`. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--sign--enabled"><a href="./values.yaml#L210">modules.v4l2loopback.kmm.sign.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Have KMM sign the built module for Secure Boot nodes (`spec.moduleLoader.container.kernelMappings[].sign` on the `Module`). This is the KMM-mode counterpart of `secureBoot.existingMokSecret`, which only signs modules the DaemonSet builds. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--kmm--sign--keySecret"><a href="./values.yaml#L215">modules.v4l2loopback.kmm.sign.keySecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of the Secret holding the **private** signing key. **Required when `modules.v4l2loopback.kmm.sign.enabled` is set.** KMM expects the key under the Secret key `key`. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--method"><a href="./values.yaml#L77">modules.v4l2loopback.method</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
build
</pre>
</div>
			</td>
			<td>How the module reaches the node. `build` (the default) compiles it from source on every node inside this chart's privileged DaemonSet. `kmm` instead delegates the whole lifecycle to the [Kernel Module Management](https://kmm.sigs.k8s.io/) operator: this chart renders a KMM `Module` custom resource (and, unless `modules.v4l2loopback.kmm.build.enabled` is false, the Dockerfile ConfigMap it builds from) and drops v4l2loopback out of the DaemonSet's reconcile script entirely. **`kmm` requires the KMM operator to already be installed in the cluster** — it ships no official Helm chart, so install it with `make kmm-install` (or the pinned `kubectl apply -k` URL that target runs). See "KMM mode" in this chart's README. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--preferShippedModule"><a href="./values.yaml#L104">modules.v4l2loopback.preferShippedModule</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Load the v4l2loopback the running kernel ships, when there is one, instead of building from source. Ubuntu carries it in-tree from 24.04, signed with the distribution's kernel key, so it loads on a Secure Boot node with no MOK enrolment and needs neither a toolchain nor kernel headers. The source build is the fallback whenever the kernel ships none or the shipped one fails to load. Set to false to always build `sourceRef`. **Applies to `method: build` only.** </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--sourcePath"><a href="./values.yaml#L143">modules.v4l2loopback.sourcePath</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Absolute path *inside the builder image* holding an already-vendored v4l2loopback source tree (for example `/opt/kasm-modules/v4l2loopback`). When set, the reconcile script copies that tree into its work directory and builds from it instead of running `git clone`, so the node needs no network access at all. This is the airgapped/offline path: bake the sources into a custom builder image, push it to your internal registry, and point `image.*` at it. Leave empty to clone from `modules.v4l2loopback.sourceRepo`. **Applies to `method: build` only** — a KMM in-cluster build always clones from `modules.v4l2loopback.sourceRepo`, and the airgapped KMM path is prebuilt per-kernel images (`modules.v4l2loopback.kmm.build.enabled: false`) instead. Setting it together with `method: kmm` fails the render. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--sourceRef"><a href="./values.yaml#L124">modules.v4l2loopback.sourceRef</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
v0.15.4
</pre>
</div>
			</td>
			<td>Git tag, branch, or commit to build. Pinning a released tag keeps builds reproducible across nodes. Do not pin below v0.15: RHEL 9.8's 5.14.0-687 kernel dropped the `from_timer` helper that v0.13's timer-API probe relies on, so v0.13.2 fails there with `implicit declaration of function 'setup_timer'`; v0.15.4 compiles against every kernel this chart was tested on (Ubuntu 22.04 5.15 and 6.8, RHEL 9.8 5.14, Amazon Linux 2023 6.12, openSUSE Leap 15.6 6.4, Azure Linux 3 6.6). </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--sourceRepo"><a href="./values.yaml#L116">modules.v4l2loopback.sourceRepo</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
https://github.com/umlaeute/v4l2loopback.git
</pre>
</div>
			</td>
			<td>Git repository the module sources are cloned from. Point this at an internal mirror when nodes cannot reach GitHub. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--sourceRepoSecret"><a href="./values.yaml#L132">modules.v4l2loopback.sourceRepoSecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of an existing Secret in the release namespace holding the HTTPS login for `modules.v4l2loopback.sourceRepo`, with keys `username` and `password` (a read-only deploy token works). The reconcile script hands them to git through a credential helper, so they never appear in the clone URL, the ConfigMap or the pod log. Credentials embedded in `sourceRepo` itself are rejected at render time for exactly that reason. **Applies to `method: build` only** — a KMM in-cluster build clones inside its Dockerfile and cannot use it; use a mirror that needs no login there. </td>
		</tr>
		<tr>
			<td id="modules--v4l2loopback--videoDevices"><a href="./values.yaml#L82">modules.v4l2loopback.videoDevices</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
4
</pre>
</div>
			</td>
			<td>Number of virtual video devices to create per node (`devices=` module parameter). This is the upper bound on concurrent webcam-enabled sessions on that node, so size it against the node's workspace capacity. </td>
		</tr>
		<tr>
			<td id="modules--wireguard--enabled"><a href="./values.yaml#L229">modules.wireguard.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Build and load the out-of-tree WireGuard module on every matching node. Leave disabled unless nodes run a kernel older than 5.6; the reconcile script detects an in-tree WireGuard (`wg_` symbols in `/proc/kallsyms`) and skips the build even when this is enabled. </td>
		</tr>
		<tr>
			<td id="modules--wireguard--method"><a href="./values.yaml#L235">modules.wireguard.method</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
build
</pre>
</div>
			</td>
			<td>How the module reaches the node. Only `build` is supported here: this key exists so the two modules read the same way, not because there is a choice to make. `kmm` fails the render, because the only nodes that need an out-of-tree WireGuard are those on kernels older than 5.6 — precisely the fleet where delegating to an operator buys nothing. </td>
		</tr>
		<tr>
			<td id="modules--wireguard--sourcePath"><a href="./values.yaml#L250">modules.wireguard.sourcePath</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Absolute path *inside the builder image* holding an already-vendored `wireguard-linux-compat` source tree (for example `/opt/kasm-modules/wireguard-linux-compat`). When set, the reconcile script copies that tree into its work directory and builds from it instead of running `git clone`, so the node needs no network access at all. This is the airgapped/offline path; see `modules.v4l2loopback.sourcePath`. Leave empty to clone from `modules.wireguard.sourceRepo`. </td>
		</tr>
		<tr>
			<td id="modules--wireguard--sourceRepo"><a href="./values.yaml#L239">modules.wireguard.sourceRepo</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
https://git.zx2c4.com/wireguard-linux-compat
</pre>
</div>
			</td>
			<td>Git repository the WireGuard compatibility module is cloned from. Point this at an internal mirror when nodes cannot reach the upstream host. </td>
		</tr>
		<tr>
			<td id="modules--wireguard--sourceRepoSecret"><a href="./values.yaml#L243">modules.wireguard.sourceRepoSecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of an existing Secret (keys `username` and `password`) holding the HTTPS login for `modules.wireguard.sourceRepo`; see `modules.v4l2loopback.sourceRepoSecret`. </td>
		</tr>
		<tr>
			<td id="nameOverride"><a href="./values.yaml#L4">nameOverride</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Override the chart name used when building resource names and the `app.kubernetes.io/name` label. Leave empty to use the chart name (`kasm-node-prep`). </td>
		</tr>
		<tr>
			<td id="nodeSelector"><a href="./values.yaml#L347">nodeSelector</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Node labels that select which nodes get prepared. Leave empty to run on every node, or restrict it to the nodes that host Kasm workspace sessions. Pair it with the matching `kasm-video-device-plugin` selector so the device plugin only advertises `kasm.com/video` where the module is actually loaded. </td>
		</tr>
		<tr>
			<td id="podAnnotations"><a href="./values.yaml#L392">podAnnotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Extra annotations to add to the DaemonSet pods, merged with the reconcile script checksum annotation this chart always sets. </td>
		</tr>
		<tr>
			<td id="podLabels"><a href="./values.yaml#L396">podLabels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Extra labels to add to the DaemonSet pods, merged with the chart's standard selector labels. </td>
		</tr>
		<tr>
			<td id="reconcileIntervalSeconds"><a href="./values.yaml#L328">reconcileIntervalSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
300
</pre>
</div>
			</td>
			<td>Seconds to sleep between reconcile passes. Every pass re-checks whether each enabled module is loaded and rebuilds it if it is not, and re-asserts any enabled `tuning.*` state, which is what makes both survive node reboots: after a reboot the check fails and the state is applied again. </td>
		</tr>
		<tr>
			<td id="resources"><a href="./values.yaml#L363">resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
limits:
    cpu: 1000m
    memory: 1Gi
requests:
    cpu: 100m
    memory: 256Mi
</pre>
</div>
			</td>
			<td>CPU and memory requests and limits for the node prep container. Module builds are bursty: compiling against the node's kernel headers is short but CPU hungry, while the idle reconcile loop uses almost nothing. Both requests and limits are always set. </td>
		</tr>
		<tr>
			<td id="resources--limits--cpu"><a href="./values.yaml#L381">resources.limits.cpu</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1000m
</pre>
</div>
			</td>
			<td>CPU limit for the node prep container, and the knob that decides how long a module build takes: the compile is bounded by this limit, so 1000m is roughly one core's worth of `make`. Raise it to shorten the window in which a freshly booted node has no `/dev/video*` yet; lower it to keep builds from competing with the workspace sessions sharing the node. </td>
		</tr>
		<tr>
			<td id="resources--limits--memory"><a href="./values.yaml#L387">resources.limits.memory</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1Gi
</pre>
</div>
			</td>
			<td>Memory limit for the node prep container. It has to cover an out-of-tree kernel module compile — the unpacked kernel headers, the module source tree, and gcc — not just the idle loop. Set it too low and the build is OOMKilled part way through, which the reconcile loop then retries every `reconcileIntervalSeconds` without ever finishing. </td>
		</tr>
		<tr>
			<td id="resources--requests--cpu"><a href="./values.yaml#L369">resources.requests.cpu</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
100m
</pre>
</div>
			</td>
			<td>CPU request for the node prep container. Between builds the reconcile loop only sleeps and re-checks, so the request is sized for that idle steady state rather than for a compile; what a build actually gets to use is `resources.limits.cpu`. </td>
		</tr>
		<tr>
			<td id="resources--requests--memory"><a href="./values.yaml#L374">resources.requests.memory</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
256Mi
</pre>
</div>
			</td>
			<td>Memory request for the node prep container. This is the idle floor, the reconcile loop itself; the real consumer is a kernel-module compile, which is what `resources.limits.memory` has to cover. </td>
		</tr>
		<tr>
			<td id="secureBoot--existingMokSecret"><a href="./values.yaml#L340">secureBoot.existingMokSecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of an existing Secret holding the MOK signing key pair, with keys `mokPrivateKey` (PEM private key) and `mokPublicKey` (DER certificate). When set, the Secret is mounted read-only at `/etc/kasm-mok` and every built module is signed with the kernel's `sign-file` helper before it is inserted. Leave empty on nodes that do not enforce Secure Boot. </td>
		</tr>
		<tr>
			<td id="tolerations"><a href="./values.yaml#L352">tolerations</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Tolerations for the DaemonSet pods, so nodes carrying taints (for example dedicated workspace nodes) still get their kernel modules prepared. </td>
		</tr>
		<tr>
			<td id="tuning--swap--enabled"><a href="./values.yaml#L299">tuning.swap.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Create and activate a swapfile on every matching node. The reconcile loop refuses to do so until it can confirm the node's kubelet tolerates swap (see `tuning.swap.force`). </td>
		</tr>
		<tr>
			<td id="tuning--swap--force"><a href="./values.yaml#L322">tuning.swap.force</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Skip the kubelet swap-support check and activate swap unconditionally. Only set this when the kubelet is configured somewhere the reconcile script cannot read (a systemd drop-in, a cloud-init unit, a distribution-specific config path) **and** you have verified `failSwapOn: false` is in effect. Enabling swap under a kubelet that still defaults to `failSwapOn: true` takes the node out at its next kubelet restart or reboot. </td>
		</tr>
		<tr>
			<td id="tuning--swap--hostPath"><a href="./values.yaml#L309">tuning.swap.hostPath</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
/var/lib/kasm-node-prep
</pre>
</div>
			</td>
			<td>Host directory the swapfile lives in; the file itself is `<hostPath>/kasm.swap`. Mounted into the DaemonSet at the same path so `/proc/swaps` reads identically inside and outside the container. Point this at a directory on a disk with room for `tuning.swap.sizeMib`. </td>
		</tr>
		<tr>
			<td id="tuning--swap--sizeMib"><a href="./values.yaml#L304">tuning.swap.sizeMib</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Size of the swapfile in MiB. `0` means auto: half of the node's `MemTotal`, clamped to `[4096, 16384]` — the range of the menu Kasm's own agent installer offers, whose documented example (`--swap-size 8192`) is half of a 16 GiB node. </td>
		</tr>
		<tr>
			<td id="tuning--swap--swappiness"><a href="./values.yaml#L315">tuning.swap.swappiness</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
80
</pre>
</div>
			</td>
			<td>`vm.swappiness` to set alongside the swapfile, re-applied every pass. Kasm's rationale for swap is parking the memory of *stopped and idle* Workspaces rather than absorbing peak load, so this defaults high (the kernel default is 60): idle desktop pages should move to disk readily and leave RAM for sessions that are actually being used. </td>
		</tr>
		<tr>
			<td id="tuning--sysctls--enabled"><a href="./values.yaml#L264">tuning.sysctls.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Apply `tuning.sysctls.values` on every matching node. The DaemonSet is already privileged, so it can write the node's `/proc/sys`; no extra host mount is needed. </td>
		</tr>
		<tr>
			<td id="tuning--sysctls--values"><a href="./values.yaml#L275">tuning.sysctls.values</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
fs.inotify.max_user_instances: 1024
fs.inotify.max_user_watches: 524288
</pre>
</div>
			</td>
			<td>Kernel tunables to set, as `key: value` pairs, written straight to the node's `/proc/sys` once per reconcile pass (no `sysctl` binary is needed in the builder image). Setting an already-correct value is a no-op, and because nothing is persisted to `/etc/sysctl.d` the loop is also what re-applies them after a node reboot. The defaults raise the inotify limits for desktop-session density: every session runs a desktop environment, a file manager and a browser, each of which consumes inotify instances and watches. The kernel's limit of 128 instances is per *UID*, and workspace sessions on a node share one, so it is effectively a per-node budget that a handful of concurrent sessions exhausts. This is Kasm-independent engineering judgement — Kasm's own installer sets no sysctls at all. </td>
		</tr>
		<tr>
			<td id="updateStrategy"><a href="./values.yaml#L357">updateStrategy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
RollingUpdate
</pre>
</div>
			</td>
			<td>DaemonSet update strategy type. `RollingUpdate` restarts the reconcile pods gradually; `OnDelete` leaves running pods untouched until they are deleted manually. </td>
		</tr>
	</tbody>
</table>

