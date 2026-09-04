# Managed Kubernetes providers: what changes

> **Applies to:** all eleven [cluster configuration how-tos](README.md) at once — this is the consolidated view of the *"Distro / cloud variants"* rows each of them carries, plus the parts that only make sense across pages · **Charts/values:** `nodePrep.modules.v4l2loopback.method`, `nodePrep.modules.v4l2loopback.kmm.build.enabled`, `nodePrep.tuning.swap.enabled`, `nodePrep.tuning.sysctls.enabled`, `videoDevicePlugin.enabled`, `gpuOperator.enabled`, `gpuOperator.driver.enabled`, `agent.gpu.enabled`, `agent.httpRoute.*`, `agent.ingress.*`, `agent.route.*`, `agent.gatewayRoute.*`, `agent.tlsRoute.*`, `agent.sessionProxy.service.*`, `agent.sessionProxy.proxyProtocol.*`, `networkPolicies.enabled`, `egressInstaller.distro`, `egressInstaller.cniBinDir`, `nfs-server-provisioner.enabled`, `csiRclone.enabled`

## Why this is needed

Every chart in this repository is provider-agnostic. Nothing in `values.yaml` asks which cloud you
are on, and the same values file installs on k3s, kubeadm, EKS, AKS, GKE or OpenShift.

What is *not* provider-agnostic is the cluster underneath. A managed Kubernetes service fixes three
things you would otherwise have chosen for yourself:

1. **The node OS.** Which image the kubelet runs on, whether it ships kernel headers and a
   compiler, whether its root filesystem is writable at all, and how often its kernel changes.
2. **The load balancer and ingress path.** What fronts the session proxy, what its idle timeout
   is, and whether the client's real IP survives the trip.
3. **The security baseline.** Whether Pod Security Admission enforces anything, whether a cloud
   policy add-on sits on top of it, and — on OpenShift — whether Pod Security Admission is even
   the mechanism.

Those three decide which of the optional charts are *possible*, not merely which are convenient.
`nodePrep`, `videoDevicePlugin` and `egressInstaller` are privileged, node-level DaemonSets; on a
read-only node image or a serverless node pool they do not degrade gracefully, they cannot run at
all. This page is where that gets said once, instead of eleven times.

**How this page was written — read this before you quote it.** The provider specifics below come
from each vendor's own documentation and from this repo's chart behaviour as **verified on k3s**.
They have **not** been run against EKS, AKS, GKE or OpenShift: this repository's lab clusters are
k3s, and there are no cloud clusters here to test on. Where a claim depends on a node-image
generation, a cluster-creation-time choice, a region, or a control-plane version, it is marked
**verify against current provider docs** — treat those as a pointer to the vendor's procedure, not
as a promise. The chart values are the half that *is* verified: every value in backticks below
exists in one of this repo's `values.yaml` files.

Values are written as they are set on the **`kasm-agent`** umbrella, the same convention
[What works on Kubernetes](../feature-matrix.md) uses: `agent.*` is the `kasm-agent-instance` subchart,
`nodePrep.*` is `kasm-node-prep`, `egressInstaller.*` is `kasm-egress-installer`, and so on. Under
[kasm-platform](../../charts/kasm-platform/README.md), prefix them with `kasm-agent.`.

## Cross-provider matrix

Rows are the eleven cluster-configuration topics. Each cell names the provider-native option and
says whether the chart's default path works there.

| Topic | Amazon EKS | Azure AKS | Google GKE | OpenShift (ROSA / ARO / self-managed) | Notes |
| ----- | ---------- | --------- | ---------- | ------------------------------------- | ----- |
| [RWX storage for profiles](rwx-storage-for-profiles.md) | EFS CSI (`efs.csi.aws.com`). EBS is RWO. | Azure Files (`azurefile-csi`), or Azure NetApp Files. Disk is RWO. | Filestore CSI (`filestore.csi.storage.gke.io`). PD is RWO. | ODF/CephFS, or an external NFS export. | Prefer the provider class. `nfs-server-provisioner.enabled=true` works anywhere but is a single point of failure — and needs an SCC on OpenShift. |
| [Cloud storage mappings (rclone CSI)](cloud-storage-rclone-csi.md) | AL2023 has FUSE. **Bottlerocket: verify.** | Ubuntu node images have `/dev/fuse`. | COS and Ubuntu have `/dev/fuse`. **Autopilot: no.** | RHCOS has `fuse`; the CSI node plugin needs a privileged SCC. | `csiRclone.enabled=true` + `agent.storageMappings.enabled=true`. The node plugin is a privileged DaemonSet — same gate as the rest. |
| [NetworkPolicy enforcement](network-policy-enforcement.md) | VPC CNI enforces **only** with its network-policy feature enabled; else Calico or Cilium. | Choose Azure NPM, Calico or Cilium **at cluster creation**. | Dataplane V2 (or the legacy network-policy add-on). | OVN-Kubernetes enforces. Works out of the box. | `networkPolicies.enabled=true` renders objects that are inert without an enforcing CNI — the worst failure mode, because it looks like it worked. |
| [Privileged workloads and policies](privileged-workloads-and-policies.md) | PSA available, `restricted` not enforced by default. Label the namespace. | Same, plus the Azure Policy add-on if enabled. | Same, plus Policy Controller. **Autopilot forbids privileged pods.** | **SCCs, not PSA.** Default `restricted-v2` blocks every privileged chart until a role binding grants `privileged`. | `pod-security.kubernetes.io/enforce=privileged` is necessary everywhere and *not sufficient* on OpenShift. |
| [GPU nodes (CUDA and EGL/DRI)](gpu-nodes.md) | Accelerated AMIs ship drivers → `gpuOperator.driver.enabled=false`. | GPU node pools ship drivers by default → `gpuOperator.driver.enabled=false`. | GKE installs drivers with its **own** DaemonSet → prefer `gpuOperator.enabled=false`. | Use Red Hat's certified NVIDIA GPU Operator from OperatorHub, not the `gpuOperator` subchart. | Never install drivers twice. `agent.gpu.enabled=true` is required on every path, including EGL/DRI. |
| [External access and TLS](external-access-and-tls.md) | AWS Load Balancer Controller: ALB → `agent.ingress`, NLB → `agent.sessionProxy.service.type=LoadBalancer`. | App Gateway for Containers, ingress-nginx, or Azure LB straight onto the Service. | GKE Gateway controller is Gateway API native → `agent.httpRoute`. | `agent.route.enabled=true`, `passthrough` termination. | Every path needs a **≥ 3600s** websocket/idle timeout, and every provider's default is far below it. |
| [Private registries and image pulling](private-registries-and-image-pulling.md) | ECR via the node role or IRSA; a static Secret expires every 12h. | ACR attached with `az aks update --attach-acr`. | Artifact Registry via Workload Identity or the node service account. | A `dockerconfigjson` Secret linked to the ServiceAccount. | `agent.imagePuller.enabled=true` needs the CRI socket from a DaemonSet — impossible on serverless node pools. |
| [Kernel modules and webcam](kernel-modules-and-webcam.md) | AL2023 needs the matching `kernel-devel`. **Bottlerocket cannot build.** | Ubuntu node images ship headers. **Azure Linux: verify.** | Ubuntu node images work. **COS cannot build**; auto-upgrade churns kernels. | RHCOS ships no `apt` and no toolchain — KMM is the native answer. | Where `method: build` cannot work, use `nodePrep.modules.v4l2loopback.method=kmm` with `nodePrep.modules.v4l2loopback.kmm.build.enabled=false` and prebuilt per-kernel images. |
| [Secure Boot](secure-boot.md) | Off on the default AMIs. | Off unless a Trusted Launch node pool enables it — **verify.** | Off unless Shielded VM Secure Boot is on — **verify.** | Bare-metal and private-cloud concern; KMM signing is the native path. | MOK enrolment is a **firmware** step. On a managed node image you generally cannot reach the firmware — bake a signed module into a custom image, or leave Secure Boot off. |
| [Node tuning and swap](node-tuning-and-swap.md) | kubelet config via the node-pool bootstrap / launch template — **verify** what is exposed. | `kubeletConfig` on the node pool exposes a subset — **verify.** | Node system config exposes a subset. **Autopilot: none.** | `KubeletConfig` MachineConfig; the node reboots to apply it. | `nodePrep.tuning.sysctls.enabled=true` is safe everywhere. Leave `nodePrep.tuning.swap.enabled=false` unless you can prove `failSwapOn: false` is live. |
| [Egress installer node prerequisites](egress-installer-node-prerequisites.md) | `distro: vanilla`. Chaining onto VPC CNI **unverified**; impossible on Fargate. | `distro: vanilla`. Chaining onto Azure CNI **unverified**. | `distro: vanilla`. Chaining onto Dataplane V2 **unverified**; impossible on Autopilot. | Multus/OVN-Kubernetes layout — set `egressInstaller.cniBinDir` explicitly. | The chained-CNI shim fails *every* pod sandbox on a node when it misbehaves. Prove it with the test pod in [Verify](egress-installer-node-prerequisites.md#verify) before relying on it anywhere. |

---

## Amazon EKS

### Node OS and kernel modules

EKS gives you three node-image families and they behave completely differently for
[kernel modules and webcam](kernel-modules-and-webcam.md):

* **Amazon Linux 2023.** Has a toolchain available, but `method: build` compiles against
  `linux-headers-$(uname -r)` from **Debian/Ubuntu** package names — AL2023 wants the matching
  `kernel-devel` package from `dnf` instead. The default `ubuntu:22.04` builder image will not
  install it. Either pre-install `kernel-devel` for the exact node kernel in a custom AMI, or use
  KMM. Amazon's kernel revisions move with the AMI, so pinning matters — **verify against current
  provider docs**.
* **Bottlerocket.** A minimal, **read-only** node OS with no package manager, no headers and no
  compiler. `nodePrep.modules.v4l2loopback.method=build` **cannot work there** — there is nothing
  on the node to build with. This is not a tuning problem.
* **Ubuntu-based EKS AMIs.** The friendliest case: `linux-headers-$(uname -r)` generally resolves,
  and the build path behaves as it does on any Ubuntu node. Check the kernel *flavor* first —
  a `-kvm` flavor has no V4L2 core and can never load `v4l2loopback`, whatever you do.

Where build mode cannot work, the answer is KMM with **prebuilt per-kernel images**:

```yaml
nodePrep:
  enabled: true
  modules:
    v4l2loopback:
      enabled: true
      method: kmm
      kmm:
        build:
          enabled: false          # airgap "Mode A": KMM only ever pulls
        image:
          registry: <account>.dkr.ecr.<region>.amazonaws.com
          repository: kasm/v4l2loopback
        imageRepoSecret: kasm-registry
videoDevicePlugin:
  enabled: true
```

One image tag per kernel release, built on a connected machine — the runbook is
[kasm-node-prep § Airgapped KMM (prebuilt modules)](../../charts/kasm-node-prep/README.md#airgapped-kmm-prebuilt-modules).
The alternative is a custom AMI with `v4l2loopback` already baked in, which takes `nodePrep` out of
the picture for that module entirely.

Two features ride on this: [webcam passthrough](../feature-matrix.md#devices-gpu-webcam-audio)
and [WireGuard](../feature-matrix.md#security--isolation) — the latter only on kernels older
than 5.6; from 5.6 it is in-tree and `nodePrep.modules.wireguard.enabled` should stay `false`.

### RWX storage for profiles

EBS is `ReadWriteOnce` only, so it cannot back a shared Kasm profile. The provider answer is
**Amazon EFS** through the EFS CSI driver (`efs.csi.aws.com`), installed as an EKS add-on or from
its own chart. EFS is NFS underneath: expect NFS latency on many-small-file workloads, which is
exactly what a browser profile directory is. EFS offers throughput and performance modes — pick
them deliberately for the profile workload rather than taking the default, and **verify against
current provider docs** for the current mode names and their limits.

The in-cluster alternative, `nfs-server-provisioner.enabled=true` with
`nfs-server-provisioner.persistence.enabled=true` and a name in
`nfs-server-provisioner.storageClass.name`, works on EKS and is a legitimate starting point — but
it is one pod, backed by one EBS volume, in front of every user's profile. See
[RWX storage for profiles](rwx-storage-for-profiles.md#before-you-start).

### GPU

EKS accelerated AMIs ship the NVIDIA driver and container toolkit already. Running the GPU
Operator's driver container on top of a host driver is the documented way to get
`CrashLoopBackOff`, so turn that component off:

```yaml
gpuOperator:
  enabled: true
  driver:
    enabled: false      # the accelerated AMI already has the driver
agent:
  gpu:
    enabled: true
  workspacesNodeSelector:
    kasm-gpu: "true"
```

On a *generic* AMI with no driver, the opposite holds: leave `gpuOperator.driver.enabled=true` and
let the operator build and load it. Either way `agent.gpu.enabled=true` is required — without it
the operator advertises GPUs that Kasm never requests, and sessions simply do not get one.

EGL/DRI graphics acceleration is a **node-image** property regardless of which path you take:
`/dev/dri/card0` and `/dev/dri/renderD128` have to exist on the node before anything can mount
them. No chart prepares the node image. Details in [GPU nodes](gpu-nodes.md#before-you-start).

### External access and client IP

The AWS Load Balancer Controller is the usual front door, in one of two shapes:

* **ALB, via Ingress** — `agent.ingress.enabled=true` with `agent.ingress.className` pointing at
  the ALB class, and the idle timeout raised on the load-balancer attributes annotation
  (`alb.ingress.kubernetes.io/load-balancer-attributes` with `idle_timeout.timeout_seconds`). The
  default is nowhere near the 3600s the session websocket needs.
* **NLB, via a Service** — `agent.sessionProxy.service.type=LoadBalancer` with the controller's
  annotations in `agent.sessionProxy.service.annotations`. This is the passthrough shape, and the
  one the chart itself documents by example.

Gateway API on EKS is provided by the ALB controller rather than by a separate implementation;
whether it covers the `TLSRoute` passthrough shape `agent.gatewayRoute` / `agent.tlsRoute` needs is
version-dependent — **verify against current provider docs** before designing around it. `TLSRoute`
is standard-channel `v1` since Gateway API 1.5, wherever you run it; older CRD bundles carry it only in
the experimental channel.

Client IP, pick exactly one:

```yaml
agent:
  sessionProxy:
    service:
      type: LoadBalancer
      externalTrafficPolicy: Local        # L4: no SNAT; only routes via nodes running a proxy pod
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: external
        service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
        service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
    proxyProtocol:
      enabled: true                       # required if, and only if, the NLB sends PROXY protocol
      trustedCIDRs:
        - 10.0.0.0/16
```

The `aws-load-balancer-proxy-protocol: "*"` annotation is what turns on `proxy_protocol_v2` on the
target group; `agent.sessionProxy.proxyProtocol.enabled=true` is what tells nginx to *expect* it.
Enable one without the other and every connection breaks — `proxyProtocol` is all-or-nothing, so
browsers, health checks and `curl` all fail the moment the two sides disagree. The NLB's own idle
timeout is a load-balancer attribute, historically fixed and now configurable; **verify against
current provider docs** and set it to at least 3600s, since a passthrough path has no HTTP knob to
fall back on.

### Security baseline

EKS ships Pod Security Admission but does not enforce `restricted` cluster-wide by default, so in a
default cluster the privileged DaemonSets are admitted. Organisation policy usually is the real
gate — an `AdmissionConfiguration` default, Kyverno, or Gatekeeper. Label the namespace regardless:

```console
kubectl label namespace kasm-agent pod-security.kubernetes.io/enforce=privileged
```

`egressInstaller` needs more than that label: `hostPID` **and** `hostNetwork`, which a blanket
`disallow-host-namespaces` rule rejects even in a `privileged` namespace. Settle it in
[privileged workloads and cluster policy](privileged-workloads-and-policies.md#steps) before
installing.

### Networking specifics

The Amazon VPC CNI enforces `NetworkPolicy` **only when its network-policy feature is enabled**;
without it, policy objects are accepted and ignored. The alternatives are Calico for policy on top
of VPC CNI, or replacing the CNI with Cilium. Whichever you choose, prove it with the default-deny
probe in [NetworkPolicy enforcement](network-policy-enforcement.md#before-you-start) before
`networkPolicies.enabled=true` means anything.

For [the egress installer](egress-installer-node-prerequisites.md), EKS is a `vanilla` distro —
`/opt/cni/bin`:

```yaml
egressInstaller:
  enabled: true
  distro: vanilla        # /opt/cni/bin
```

That is the *path*, not a guarantee. Whether the VPC CNI honours a chained plugin appended to its
`.conflist` is a per-cluster fact this repo has not tested. Confirm the bin dir from containerd's
own config, then run the test pod from
[Verify](egress-installer-node-prerequisites.md#verify) — a broken chain fails every pod on the
node, not just Kasm's. Treat this as verify-first.

### Serverless and restricted modes

**AWS Fargate** runs pods without nodes you own. No privileged containers, no `hostPath`, no
`hostPID`/`hostNetwork`, and no DaemonSets in the sense these charts need. On Fargate profiles,
`nodePrep`, `videoDevicePlugin`, `egressInstaller`, KMM and `gpuOperator` are **not possible** —
and neither is the rclone CSI node plugin or `agent.imagePuller`, both of which are privileged
DaemonSets that touch the node.

What still runs: the whole control plane, and the agent's core — `operator.enabled=true`,
`agent.enabled=true`, `otelCollector.enabled=true`, the session proxy, and sessions without webcam,
VPN egress or GPU. What drops out: egress gateways, GPU (both kinds), webcam passthrough, image
pre-pulling, WireGuard, host-path volume mappings, Secure Boot, cloud storage mappings, and node
tuning. Everything else — persistent profiles, file mappings, network isolation, recording,
printing, microphone, web filtering, SSH keys, node targeting, external access, TLS, private
registries, autoscaling and multi-tenancy — is unaffected. A common shape is a Fargate profile
for the control plane and real EC2 nodes for sessions.

---

## Azure AKS

### Node OS and kernel modules

AKS node pools are Ubuntu-based by default, which is the good case for
[kernel modules](kernel-modules-and-webcam.md): headers resolve, the toolchain installs, and
`nodePrep.modules.v4l2loopback.method` can stay at its default `build`. Confirm the kernel flavor
ships the V4L2 core before you commit — `modinfo videodev` on a node is the whole check.

Azure Linux (formerly CBL-Mariner) node pools are a different package ecosystem and the default
`apt`-based builder image does not apply; **verify against current provider docs** whether matching
kernel headers are published for the node kernel you are on, and fall back to KMM with prebuilt
images if they are not.

AKS node images and their kernels are replaced on the node-image upgrade cadence, so a prebuilt
per-kernel KMM image set is something you keep in step with upgrades, not something you build once.

### RWX storage for profiles

Azure Disk is `ReadWriteOnce`. The provider answer is **Azure Files** through
`file.csi.azure.com`, usually the built-in `azurefile-csi` StorageClass, or **Azure NetApp Files**
where the profile workload needs real IOPS. Azure Files' standard tier is fine for light profiles
and noticeably slow for a browser cache; the premium (SSD) tier is the usual fix, and ANF is the
step above that. Pick the tier deliberately — **verify against current provider docs** for the
current tier names and their limits. Background:
[RWX storage for profiles](rwx-storage-for-profiles.md#before-you-start).

### GPU

AKS GPU node pools include the NVIDIA driver by default, so the GPU Operator should not install one
on top:

```yaml
gpuOperator:
  enabled: true
  driver:
    enabled: false
agent:
  gpu:
    enabled: true
```

AKS also exposes a node-pool setting to *skip* its own driver installation, at which point the
operator's driver container becomes the right choice instead — the two are alternatives, never both.
Which flag name applies to your AKS version is worth checking: **verify against current provider
docs**. As everywhere, `agent.gpu.enabled=true` is the half that makes Kasm actually request the
GPU, and EGL/DRI still needs `/dev/dri` present on the node image.

### External access and client IP

Three shapes are common on AKS:

* **Application Gateway for Containers** — the managed Gateway API path. `agent.httpRoute.enabled=true`
  with `agent.httpRoute.parentRefs` pointing at its Gateway, and the request timeout raised for
  websockets.
* **ingress-nginx in-cluster** — `agent.ingress.enabled=true` with
  `nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"` and the matching send timeout in
  `agent.ingress.annotations`. This is the same shape as any other cluster.
* **Azure Load Balancer straight onto the Service** — `agent.sessionProxy.service.type=LoadBalancer`.

Client IP on the L4 path is `externalTrafficPolicy: Local`, which preserves the source address at
the cost of only routing through nodes that host a session-proxy pod:

```yaml
agent:
  sessionProxy:
    service:
      type: LoadBalancer
      externalTrafficPolicy: Local
      annotations:
        service.beta.kubernetes.io/azure-load-balancer-tcp-idle-timeout: "30"
```

**The idle timeout is the AKS-specific trap.** Azure Load Balancer's TCP idle timeout defaults to
around 4 minutes and is raised per-Service with the annotation above, expressed in **minutes**. Its
documented ceiling has historically been well under the 3600s (60 minute) floor these sessions want,
so an L4-only path leans on the session keeping the connection non-idle rather than on the timeout
itself. **Verify the current ceiling against provider docs**, and prefer terminating HTTP at an
ingress or Application Gateway where a true 3600s read timeout is settable. A session that dies at a
suspiciously round number of minutes is this, every time.

### Security baseline

AKS ships PSA and does not enforce `restricted` by default; the namespace label is still the step
that matters, and the **Azure Policy add-on** — if enabled on the cluster — enforces independently
of PSA. Satisfying one does not satisfy the other. Inventory both before installing `nodePrep`,
`videoDevicePlugin` or `egressInstaller`, and remember `egressInstaller` additionally needs host
namespaces. See [privileged workloads and cluster policy](privileged-workloads-and-policies.md#steps).

### Networking specifics

The network policy engine on AKS is a **cluster-creation-time** choice — Azure NPM, Calico or
Cilium — and it is not something you switch on afterwards on an existing cluster in the general
case. Decide it when the cluster is created if network isolation or multi-tenancy
matters to you; **verify against current provider docs** for what your AKS version allows changing
in place. Without an engine, `networkPolicies.enabled=true` renders objects nothing enforces.

For the egress installer, AKS is `distro: vanilla` (`/opt/cni/bin`). Whether Azure CNI — in any of
its overlay, node-subnet or Cilium-powered variants — honours a chained plugin appended to its
`.conflist` is unverified here. Confirm the bin dir from containerd's config on a node, then run the
test pod from [Verify](egress-installer-node-prerequisites.md#verify). On any Cilium-based dataplane,
the Cilium agent also rewrites its own conflist whenever `/etc/cni/net.d` changes and undoes the
shim within a second — it needs `cni.customConf=true` and `cni.exclusive=false`, plus an agent
restart, before chaining holds ([egress installer prerequisites](egress-installer-node-prerequisites.md#before-you-start)).

### Serverless and restricted modes

**AKS virtual nodes** (ACI-backed) are not real nodes: no privileged pods, no `hostPath`, no host
namespaces, no DaemonSets scheduled onto them. `nodePrep`, `videoDevicePlugin`, `egressInstaller`,
KMM, `gpuOperator`, the rclone CSI node plugin and `agent.imagePuller` are all **not possible**
there. The same features drop out as on Fargate: egress gateways, GPU, webcam passthrough, image
pre-pulling, WireGuard, host-path volume mappings, Secure Boot, node tuning and cloud storage
mappings. Keep sessions that need any of those on a real node pool and use
`agent.workspacesNodeSelector` to pin them.

---

## Google GKE

### Node OS and kernel modules

**Container-Optimized OS (COS)** is GKE's default, and it is the case that most often surprises
people. COS has **no kernel headers, no toolchain, and a read-only root filesystem** by design.
`nodePrep.modules.v4l2loopback.method=build` **cannot work there** — there is nothing to compile
with and nowhere to write. Ubuntu node images are the escape hatch and behave like any other Ubuntu
node.

Two workable paths on COS:

1. **KMM with prebuilt per-kernel images** — `nodePrep.modules.v4l2loopback.method=kmm` with
   `nodePrep.modules.v4l2loopback.kmm.build.enabled=false`, one image tag per kernel release in
   Artifact Registry, named in `nodePrep.modules.v4l2loopback.kmm.image.registry` and
   `.repository`. Runbook:
   [kasm-node-prep § Airgapped KMM (prebuilt modules)](../../charts/kasm-node-prep/README.md#airgapped-kmm-prebuilt-modules).
2. **A custom node image** with the module already baked in, which removes `nodePrep` from the
   picture for that module.

**GKE node auto-upgrade is the operational catch.** Kernels change when GKE upgrades the node
image, and a prebuilt per-kernel image set that does not track those upgrades leaves the new kernel
with no matching tag — KMM cannot pull what does not exist, and `kubectl describe module ...` names
the unmatched kernel. Either build ahead of the release channel you are on, or pin the node version
and take upgrades deliberately. **Verify against current provider docs** for what your channel
allows.

The choice between the two modes is laid out in
[kasm-node-prep § Which one to choose](../../charts/kasm-node-prep/README.md#which-one-to-choose);
the procedure for both is [Kernel modules and webcam](kernel-modules-and-webcam.md#b-kmm-mode).

### RWX storage for profiles

Persistent Disk is `ReadWriteOnce`. The provider answer is **Filestore** through
`filestore.csi.storage.gke.io`, enabled as a GKE add-on. Filestore's service tiers differ by an
order of magnitude in throughput and IOPS and by a large factor in minimum capacity — the basic
tier's minimum instance is far more storage than a profile share usually needs, which makes the
tier choice a cost decision as much as a performance one. **Verify against current provider docs**
for current tier names and minimums. The in-cluster
`nfs-server-provisioner.enabled=true` path also works, with the caveats in
[RWX storage for profiles](rwx-storage-for-profiles.md#before-you-start).

### GPU

GKE installs NVIDIA drivers itself, with **its own DaemonSet**, on GPU node pools. Running the GPU
Operator's driver component alongside it is a double install. The clean shape on GKE is to let GKE
do the driver and skip the operator entirely:

```yaml
gpuOperator:
  enabled: false        # GKE's own driver DaemonSet handles this
agent:
  gpu:
    enabled: true
  workspacesNodeSelector:
    kasm-gpu: "true"
```

`agent.gpu.enabled=true` is still required — it is what puts `nvidia.com/gpu` into the workspace
pod's limits and what gates the DRI device mounts for EGL. If you do run `gpuOperator.enabled=true`
on GKE for the toolkit or device plugin, `gpuOperator.driver.enabled=false` is mandatory, and
`gpuOperator.nfd.enabled=false` if Node Feature Discovery already runs. **Verify against current
provider docs** for which components GKE's own installation already covers on your node image.

### External access and client IP

GKE's **Gateway controller is Gateway API native**, which makes `agent.httpRoute` the natural fit:

```yaml
agent:
  httpRoute:
    enabled: true
    parentRefs:
      - name: kasm-gateway
        namespace: kasm-agent
    hostnames:
      - sessions.example.com
```

**The backend timeout is the GKE-specific trap.** The default backend service timeout is 30
seconds, which kills a session websocket almost immediately. Raise it — on the Ingress path with a
`BackendConfig` (`timeoutSec`), on the Gateway path with a `GCPBackendPolicy` — to at least 3600s.
Both are Google CRDs, not chart values; **verify against current provider docs** for the field names
your GKE version uses.

Client IP preservation on GKE depends on the load balancer type in front: an external passthrough
load balancer preserves the source address natively, while proxy-based load balancers present their
own address and pass the original in `X-Forwarded-For`. Where you are on the L4 path,
`agent.sessionProxy.service.externalTrafficPolicy=Local` is the chart-side lever, with
`agent.sessionProxy.service.annotations` carrying the GKE-specific load-balancer annotations.
`agent.sessionProxy.proxyProtocol.enabled` is only correct if the thing in front actually sends
PROXY protocol — do not turn it on speculatively.

### Security baseline

GKE Standard ships PSA and does not enforce `restricted` by default; **Policy Controller**, where
it is installed, enforces on top and independently. The namespace label is the same one line as
everywhere:

```console
kubectl label namespace kasm-agent pod-security.kubernetes.io/enforce=privileged
```

GKE **Autopilot** is a different story entirely — see below.

### Networking specifics

`NetworkPolicy` enforcement on GKE needs **Dataplane V2** (Cilium-based, and the default on newer
clusters) or the legacy network-policy add-on. Without one, `networkPolicies.enabled=true` is
inert. Prove it with the probe in
[NetworkPolicy enforcement](network-policy-enforcement.md#before-you-start).

For the egress installer, GKE Standard nodes are `distro: vanilla` (`/opt/cni/bin`). Whether
Dataplane V2 honours a chained plugin appended to its `.conflist` is unverified here and is exactly
the kind of thing a dataplane rewrite changes — confirm the bin dir from the node's containerd
config and run the test pod from
[Verify](egress-installer-node-prerequisites.md#verify) before relying on it. Verify-first, not a
promise.

### Serverless and restricted modes

**GKE Autopilot** does not give you the node. No privileged pods, no `hostPath`, no
`hostPID`/`hostNetwork`, and no DaemonSets of the kind these charts ship. `nodePrep`,
`videoDevicePlugin`, `egressInstaller`, KMM, `gpuOperator`, the rclone CSI node plugin and
`agent.imagePuller` are **not possible** on Autopilot. Autopilot does support GPU workloads through
its own mechanism — **verify against current provider docs** — but that is Google installing the
driver, not the `gpuOperator` subchart running.

What still runs: `operator.enabled=true`, `agent.enabled=true`, `otelCollector.enabled=true`, the
session proxy, ingress, NetworkPolicy (Dataplane V2 is standard on Autopilot), and sessions without
webcam, VPN egress or GPU. Egress gateways, GPU (both kinds), webcam passthrough, image
pre-pulling, WireGuard, host-path volume mappings, Secure Boot, node tuning and cloud storage
mappings all drop out.

---

## OpenShift (ROSA / ARO / self-managed)

### Node OS and kernel modules

RHCOS ships no `apt` and is not intended to be built on, so `nodePrep.modules.v4l2loopback.method`
should be `kmm` on OpenShift: KMM is the RHEL-native answer and Red Hat ships a supported build of
it. Where the cluster is airgapped or you would rather not build in-cluster,
`nodePrep.modules.v4l2loopback.kmm.build.enabled=false` with prebuilt per-kernel images is the same
Mode A path as everywhere else. `method: build` is possible only with a pre-baked builder image
carrying everything the compile needs, which is more work than KMM for less result.

Note that this repo pins the upstream KMM operator; on OpenShift you would normally install Red
Hat's KMM operator from OperatorHub instead. The `Module` resource the chart renders targets the
`kmm.sigs.x-k8s.io/v1beta1` schema — **verify** the operator version you install reconciles it
before assuming the chart's output is accepted.

### RWX storage for profiles

**ODF / CephFS** is the native RWX answer on OpenShift, and an external NFS export is the common
alternative. The bundled `nfs-server-provisioner` runs a pod that needs an SCC it does not have by
default and will `CrashLoopBackOff` without one — prefer ODF rather than granting an SCC to a
storage stand-in. See [RWX storage for profiles](rwx-storage-for-profiles.md#before-you-start).

### GPU

Use **Red Hat's certified NVIDIA GPU Operator from OperatorHub**, not the `gpuOperator` subchart in
this umbrella. It is the supported path on OpenShift, it integrates with the Node Feature Discovery
operator, and it handles the SCC and driver-toolkit plumbing that the upstream chart does not.
Leave `gpuOperator.enabled=false` and set only `agent.gpu.enabled=true`, which is the half that
makes Kasm request the resource. EGL/DRI still needs the driver present on the node image and
`/dev/dri` exposed.

### External access and client IP

`Route` is the native path, and the chart renders one:

```yaml
agent:
  route:
    enabled: true
    annotations:
      haproxy.router.openshift.io/timeout: "3600s"
    tls:
      termination: passthrough
```

Two things to get right:

* **The router timeout is effectively mandatory.** The OpenShift router closes idle connections
  after 30 seconds; a session websocket dies almost immediately without
  `haproxy.router.openshift.io/timeout` in `agent.route.annotations`.
* **Passthrough means the browser sees the session proxy's own certificate.** Under the default
  `agent.route.tls.termination: passthrough` the hostname in `agent.route.host` (or
  `agent.publicHostname`) is matched against that certificate, so
  `agent.sessionProxy.certificate.enabled=true` — or a Secret in
  `agent.sessionProxy.certSecretName` — has to cover the public hostname and its wildcard. Use
  `edge` or `reencrypt` if you would rather terminate at the router.

Client IP behaviour behind the OpenShift router is the router's, not the chart's; where you bypass
it with `agent.sessionProxy.service.type=LoadBalancer`,
`agent.sessionProxy.service.externalTrafficPolicy=Local` and
`agent.sessionProxy.proxyProtocol.*` behave as they do anywhere else. Full comparison of the five
exposure methods: [External access and TLS](external-access-and-tls.md#step-2--pick-one-exposure-option).

### Security baseline

**This is the section that matters most on OpenShift, and it is not the same mechanism as
everywhere else.** OpenShift gates privileged pods with **SecurityContextConstraints**, evaluated
per-ServiceAccount, in addition to PSA. The default `restricted-v2` SCC that every ServiceAccount
gets blocks **all three** privileged charts: `nodePrep`, `videoDevicePlugin` and `egressInstaller`
are rejected until something grants them more. The namespace label alone does nothing here.

Each privileged DaemonSet's ServiceAccount needs the `privileged` SCC bound to it, and
`egressInstaller` additionally needs `hostPID` and `hostNetwork` permitted under that SCC — the
`privileged` SCC covers host namespaces, but a custom SCC written to be narrower may not. Grant
these deliberately and record them; they are the same trade-off as
[privileged workloads and cluster policy](privileged-workloads-and-policies.md#steps) describes,
expressed in OpenShift's vocabulary.

This repository has **not validated SCC binding on OpenShift** — the existing how-to says so
explicitly, and this page does not upgrade that claim. Treat it as work you own, and **verify
against current provider docs** for the exact `oc adm policy` grammar your version uses.

### Networking specifics

OVN-Kubernetes **enforces** `NetworkPolicy`, so this is the one topic where OpenShift is the easy
case: `networkPolicies.enabled=true` does what it says, and the operator's per-workspace policies
are enforced too. Rows 5, 13 and 25 need no cluster work here beyond the baseline.

The egress installer is the hard case. OpenShift's CNI layout involves Multus and OVN-Kubernetes
and its plugin bin dir is **not** `/opt/cni/bin` in the way `distro: vanilla` assumes, so set the
path explicitly:

```yaml
egressInstaller:
  enabled: true
  distro: openshift          # not a recognized preset -> cniBinDir becomes required
  cniBinDir: /var/lib/cni/bin   # read this off the node's own runtime config; do not copy it
```

An unrecognized `distro` with no `cniBinDir` **fails template rendering on purpose** — the chart
would rather not install than install into a directory whose wrongness is silent. Whether chaining
onto a Multus/OVN-Kubernetes conflist works at all is unverified here; combined with the SCC
requirement, treat the egress installer on OpenShift as a proof-of-concept before a plan. Method:
[Egress installer node prerequisites](egress-installer-node-prerequisites.md#steps), and read
[kasm-egress-installer § Read this before installing](../../charts/kasm-egress-installer/README.md#read-this-before-installing)
first.

### Serverless and restricted modes

OpenShift has no equivalent of Fargate or Autopilot in the sense that matters here: ROSA, ARO and
hosted-control-plane variants all give you real worker nodes you can schedule DaemonSets onto. The
restriction on OpenShift is **policy, not node access** — `restricted-v2` is the default SCC, and
everything privileged stays blocked until it is granted. Nothing drops out on capability grounds;
things drop out because you decided not to grant the SCC, which is a decision you can revisit. Record which way you went.

Node tuning is also a policy-shaped problem here: kubelet settings come from a `KubeletConfig`
MachineConfig object and the node **reboots** to apply it, so `nodePrep.tuning.swap.enabled=true`
is a change to plan a maintenance window around. `nodePrep.tuning.sysctls.enabled=true` has no such
prerequisite. See [Node tuning and swap](node-tuning-and-swap.md#verify) for how to prove the
kubelet setting is actually live before enabling swap.

---

## Before you pick a provider

Distilled from the above. Answer these before the cluster exists, because several of them cannot be
changed afterwards.

- [ ] **Node image chosen with kernel modules in mind.** If webcam (`v4l2loopback`) or WireGuard on
      a pre-5.6 kernel is in scope, the node image ships headers *and* a toolchain — or you have
      committed to KMM with prebuilt per-kernel images. Bottlerocket and COS cannot build.
- [ ] **If KMM with prebuilt images: a plan for kernel churn.** Node auto-upgrade changes kernels;
      an image tag must exist for every kernel release in the fleet, before the node joins.
- [ ] **An RWX StorageClass identified** — EFS, Azure Files/ANF, Filestore, or ODF/CephFS — with
      its performance tier chosen for a browser-profile workload, not taken by default. The
      in-cluster `nfs-server-provisioner` is a starting point, not a plan.
- [ ] **A driver strategy for GPU**, and only one: provider-installed drivers with
      `gpuOperator.driver.enabled=false`, GKE's own DaemonSet with `gpuOperator.enabled=false`, or
      the operator's driver container on a generic image. `agent.gpu.enabled=true` on every path.
- [ ] **`/dev/dri` present on the node image** if EGL/DRI graphics acceleration is in scope. No
      chart prepares this.
- [ ] **An exposure method picked and its idle timeout raised to ≥ 3600s** — ALB/NLB attributes,
      Azure LB annotation (and its ceiling checked), GKE `BackendConfig`/`GCPBackendPolicy`, or
      `haproxy.router.openshift.io/timeout`. Every provider default is too low.
- [ ] **A client-IP strategy chosen**, exactly one:
      `agent.sessionProxy.service.externalTrafficPolicy=Local` **or**
      `agent.sessionProxy.proxyProtocol.enabled=true` with `trustedCIDRs` *and* the load balancer
      actually sending PROXY protocol.
- [ ] **The security baseline understood in the right vocabulary.** PSA plus any cloud policy
      add-on on EKS/AKS/GKE (`pod-security.kubernetes.io/enforce=privileged` on the namespace);
      **SCCs** on OpenShift, bound per-ServiceAccount, with host namespaces for `egressInstaller`.
- [ ] **A NetworkPolicy engine selected at cluster creation** if network isolation or
      multi-tenancy matters — VPC CNI's policy feature or Calico/Cilium on EKS, Azure NPM/Calico/
      Cilium on AKS, Dataplane V2 on GKE. OVN-Kubernetes already enforces on OpenShift. AKS in
      particular is a creation-time choice.
- [ ] **The egress installer treated as verify-first.** CNI bin dir read off the node's own
      containerd config, chaining proven with a throwaway pod, and the no-daemon failure window
      accepted — before any of it reaches production.
- [ ] **No serverless node pool for anything node-level.** Fargate, Autopilot and AKS virtual nodes
      cannot run `nodePrep`, `videoDevicePlugin`, `egressInstaller`, KMM, `gpuOperator`, the rclone
      CSI node plugin or `agent.imagePuller`. Keep those sessions on real nodes and pin them with
      `agent.workspacesNodeSelector`.
- [ ] **Swap left off** unless `failSwapOn: false` is provably live on the node's kubelet.
      `nodePrep.tuning.sysctls.enabled=true` is safe everywhere.
- [ ] **Every "verify" on this page actually verified** against the provider's current
      documentation for your cluster's version, region and node-image generation. Nothing here was
      run on a cloud cluster.

## Related reading

* [Cluster configuration how-tos](README.md) — the eleven per-topic procedures this page cuts
  across, each with its own verification commands.
* [What works on Kubernetes](../feature-matrix.md) — every Kasm feature, whether it works, and
  what it needs from the cluster.
* [kasm-agent → Cluster preparation checklist](../../charts/kasm-agent/README.md#cluster-preparation-checklist)
  — the short list: the features people turn on most often, and the values that turn them on.
* [Architecture → Deployment topologies](../architecture.md#deployment-topologies) — namespace
  layouts, and why the two-namespace one keeps the control plane out of a `privileged` namespace.
