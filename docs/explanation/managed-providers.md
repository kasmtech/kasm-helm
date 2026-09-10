# Managed providers: what changes

> **Applies to:** both halves · the consolidated view of the *Distro / cloud variants* rows every how-to carries, plus the parts that only make sense across pages · **Charts/values:** `nodePrep.modules.v4l2loopback.method`, `nodePrep.modules.v4l2loopback.kmm.build.enabled`, `nodePrep.tuning.swap.enabled`, `nodePrep.tuning.sysctls.enabled`, `videoDevicePlugin.enabled`, `gpuOperator.enabled`, `gpuOperator.driver.enabled`, `agent.gpu.enabled`, `agent.httpRoute.*`, `agent.ingress.*`, `agent.route.*`, `agent.gatewayRoute.*`, `agent.tlsRoute.*`, `agent.sessionProxy.service.*`, `agent.sessionProxy.proxyProtocol.*`, `networkPolicies.enabled`, `egressInstaller.distro`, `egressInstaller.cniBinDir`, `nfs-server-provisioner.enabled`, `csiRclone.enabled`

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
   policy add-on sits on top of it, and - on OpenShift - whether Pod Security Admission is even
   the mechanism.

Those three decide which of the optional charts are *possible*, not merely which are convenient.
`nodePrep`, `videoDevicePlugin` and `egressInstaller` are privileged, node-level DaemonSets; on a
read-only node image or a serverless node pool they do not degrade gracefully, they cannot run at
all. This page is where that gets said once, instead of on every how-to.

**How this page was written - read this before you quote it.** The provider specifics below come
from each vendor's own documentation and from this repo's chart behaviour as **verified on k3s**.
They have **not** been run against EKS, AKS, GKE or OpenShift; the chart behaviour they rest on was
verified on k3s and kubeadm clusters only. Where a claim depends on a node-image
generation, a cluster-creation-time choice, a region, or a control-plane version, it is marked
**verify against current provider docs** - treat those as a pointer to the vendor's procedure, not
as a promise. The chart values are the half that *is* verified: every value in backticks below
exists in one of this repo's `values.yaml` files.

## Cross-provider matrix

Rows are the cluster-configuration topics, each linking its how-to. Each cell names the provider-native option and
says whether the chart's default path works there.

| Topic | Amazon EKS | Azure AKS | Google GKE | OpenShift (ROSA / ARO / self-managed) | Notes |
| ----- | ---------- | --------- | ---------- | ------------------------------------- | ----- |
| [RWX storage for profiles](../how-to/storage/rwx-profiles.md) | EFS CSI (`efs.csi.aws.com`). EBS is RWO. | Azure Files (`azurefile-csi`), or Azure NetApp Files. Disk is RWO. | Filestore CSI (`filestore.csi.storage.gke.io`). PD is RWO. | ODF/CephFS, or an external NFS export. | Prefer the provider class. `nfs-server-provisioner.enabled=true` works anywhere but is a single point of failure - and needs an SCC on OpenShift. |
| [Cloud storage mappings (rclone CSI)](../how-to/storage/cloud-mappings.md) | AL2023 has FUSE. **Bottlerocket: verify.** | Ubuntu node images have `/dev/fuse`. | COS and Ubuntu have `/dev/fuse`. **Autopilot: no.** | RHCOS has `fuse`; the CSI node plugin needs a privileged SCC. | `csiRclone.enabled=true` + `agent.storageMappings.enabled=true`. The node plugin is a privileged DaemonSet - same gate as the rest. |
| [NetworkPolicy enforcement](../how-to/networking/network-policies.md) | VPC CNI enforces **only** with its network-policy feature enabled; else Calico or Cilium. | Choose Azure NPM, Calico or Cilium **at cluster creation**. | Dataplane V2 (or the legacy network-policy add-on). | OVN-Kubernetes enforces. Works out of the box. | `networkPolicies.enabled=true` renders objects that are inert without an enforcing CNI - the worst failure mode, because it looks like it worked. |
| [Privileged workloads and policies](../how-to/nodes/privileged-workloads.md) | PSA available, `restricted` not enforced by default. Label the namespace. | Same, plus the Azure Policy add-on if enabled. | Same, plus Policy Controller. **Autopilot forbids privileged pods.** | **SCCs, not PSA.** Default `restricted-v2` blocks every privileged chart until a role binding grants `privileged`. | `pod-security.kubernetes.io/enforce=privileged` is necessary everywhere and *not sufficient* on OpenShift. |
| [GPU nodes (CUDA and EGL/DRI)](../how-to/nodes/gpu.md) | Accelerated AMIs ship drivers → `gpuOperator.driver.enabled=false`. | GPU node pools ship drivers by default → `gpuOperator.driver.enabled=false`. | GKE installs drivers with its **own** DaemonSet → prefer `gpuOperator.enabled=false`. | Use Red Hat's certified NVIDIA GPU Operator from OperatorHub, not the `gpuOperator` subchart. | Never install drivers twice. `agent.gpu.enabled=true` is required on every path, including EGL/DRI. |
| [Networking](../how-to/networking/README.md) | AWS Load Balancer Controller: ALB → `agent.ingress`, NLB → `agent.sessionProxy.service.type=LoadBalancer`. | App Gateway for Containers, ingress-nginx, or Azure LB straight onto the Service. | GKE Gateway controller is Gateway API native → `agent.httpRoute`. | `agent.route.enabled=true`, `passthrough` termination. | Every path needs a **≥ 3600s** websocket/idle timeout, and every provider's default is far below it. |
| [Registries and airgap](../how-to/registries-and-airgap.md) | ECR via the node role or IRSA; a static Secret expires every 12h. | ACR attached with `az aks update --attach-acr`. | Artifact Registry via Workload Identity or the node service account. | A `dockerconfigjson` Secret linked to the ServiceAccount. | `agent.imagePuller.enabled=true` needs the CRI socket from a DaemonSet - impossible on serverless node pools. |
| [Webcam and kernel modules](../how-to/nodes/webcam-kernel-modules.md) | AL2023 needs the matching `kernel-devel`. **Bottlerocket cannot build.** | Ubuntu node images ship headers. **Azure Linux: verify.** | Ubuntu node images work. **COS cannot build**; auto-upgrade churns kernels. | RHCOS ships no `apt` and no toolchain - KMM is the native answer. | Where `method: build` cannot work, use `nodePrep.modules.v4l2loopback.method=kmm` with `nodePrep.modules.v4l2loopback.kmm.build.enabled=false` and prebuilt per-kernel images. |
| [Secure Boot](../how-to/nodes/secure-boot.md) | Off on the default AMIs. | Off unless a Trusted Launch node pool enables it - **verify.** | Off unless Shielded VM Secure Boot is on - **verify.** | Bare-metal and private-cloud concern; KMM signing is the native path. | MOK enrolment is a **firmware** step. On a managed node image you generally cannot reach the firmware - bake a signed module into a custom image, or leave Secure Boot off. |
| [Node tuning and swap](../how-to/nodes/tuning-and-swap.md) | kubelet config via the node-pool bootstrap / launch template - **verify** what is exposed. | `kubeletConfig` on the node pool exposes a subset - **verify.** | Node system config exposes a subset. **Autopilot: none.** | `KubeletConfig` MachineConfig; the node reboots to apply it. | `nodePrep.tuning.sysctls.enabled=true` is safe everywhere. Leave `nodePrep.tuning.swap.enabled=false` unless you can prove `failSwapOn: false` is live. |
| [Egress installer node prerequisites](../how-to/networking/egress.md) | The default `distro: vanilla`. Chaining onto VPC CNI **unverified**; impossible on Fargate. | The default `distro: vanilla`. Chaining onto Azure CNI **unverified**. | The default `distro: vanilla`. Chaining onto Dataplane V2 **unverified**; impossible on Autopilot. | Multus/OVN-Kubernetes layout - set `egressInstaller.cniBinDir` explicitly. | The chained-CNI shim fails *every* pod sandbox on a node when it misbehaves. Prove it with the test pod in [Verify](../how-to/networking/egress.md#verify) before relying on it anywhere. |

---


## Before you pick a provider

Distilled from the above. Answer these before the cluster exists, because several of them cannot be
changed afterwards.

- [ ] **Node image chosen with kernel modules in mind.** If webcam (`v4l2loopback`) or WireGuard on
      a pre-5.6 kernel is in scope, the node image ships headers *and* a toolchain - or you have
      committed to KMM with prebuilt per-kernel images. Bottlerocket and COS cannot build.
- [ ] **If KMM with prebuilt images: a plan for kernel churn.** Node auto-upgrade changes kernels;
      an image tag must exist for every kernel release in the fleet, before the node joins.
- [ ] **An RWX StorageClass identified** - EFS, Azure Files/ANF, Filestore, or ODF/CephFS - with
      its performance tier chosen for a browser-profile workload, not taken by default. The
      in-cluster `nfs-server-provisioner` is a starting point, not a plan.
- [ ] **A driver strategy for GPU**, and only one: provider-installed drivers with
      `gpuOperator.driver.enabled=false`, GKE's own DaemonSet with `gpuOperator.enabled=false`, or
      the operator's driver container on a generic image. `agent.gpu.enabled=true` on every path.
- [ ] **`/dev/dri` present on the node image** if EGL/DRI graphics acceleration is in scope. No
      chart prepares this.
- [ ] **An exposure method picked and its idle timeout raised to ≥ 3600s** - ALB/NLB attributes,
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
      multi-tenancy matters - VPC CNI's policy feature or Calico/Cilium on EKS, Azure NPM/Calico/
      Cilium on AKS, Dataplane V2 on GKE. OVN-Kubernetes already enforces on OpenShift. AKS in
      particular is a creation-time choice.
- [ ] **The egress installer treated as verify-first.** CNI bin dir read off the node's own
      containerd config, chaining proven with a throwaway pod, and the no-daemon failure window
      accepted - before any of it reaches production.
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

* [What works on Kubernetes](../reference/feature-matrix.md) - every Kasm feature, whether it works, and
  what it needs from the cluster.
* [kasm-agent, Cluster preparation checklist](../../charts/kasm-agent/README.md#cluster-preparation-checklist)
  - the short list: the features people turn on most often, and the values that turn them on.
* [Deployment topologies](topologies.md) - namespace layouts, and why the two-namespace one keeps
  the control plane out of a `privileged` namespace.
