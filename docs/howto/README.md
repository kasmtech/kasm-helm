# Cluster configuration how-tos

These are the actionable versions of the [feature matrix](../feature-matrix.md)'s **"Outside the
charts (cluster prerequisites)"** column: what to do, in order, with the commands that prove it
worked.

| How-to | Covers (feature rows) | Key values |
| ------ | --------------------- | ---------- |
| [RWX storage for profiles](rwx-storage-for-profiles.md) | 2 — Persistent user profiles | `nfs-server-provisioner.enabled`<br>`nfs-server-provisioner.persistence.enabled`<br>`nfs-server-provisioner.storageClass.name` |
| [Cloud storage mappings (rclone CSI)](cloud-storage-rclone-csi.md) | 3 — Cloud storage mappings | `csiRclone.enabled`<br>`agent.storageMappings.enabled` |
| [NetworkPolicy enforcement](network-policy-enforcement.md) | 5 — Network isolation<br>13 — Web filtering<br>25 — Multi-tenancy<br>Telemetry | `networkPolicies.enabled`<br>`networkPolicies.manager.ports`<br>`networkPolicies.otelBackend.cidr` |
| [Privileged workloads and policies](privileged-workloads-and-policies.md) | 17 — Host volume / bind mounts<br>25 — Multi-tenancy | `agent.workspacesNodeSelector`<br>`nodePrep.enabled`<br>`egressInstaller.enabled` |
| [GPU nodes (CUDA and EGL/DRI)](gpu-nodes.md) | 7 — GPU acceleration (CUDA)<br>8 — GPU graphics (EGL/DRI)<br>18 — Node targeting | `gpuOperator.enabled`<br>`agent.gpu.enabled`<br>`agent.workspacesNodeSelector` |
| [External access and TLS](external-access-and-tls.md) | 20 — External access / ingress<br>22 — TLS / trusted CA | `agent.gatewayRoute.enabled`<br>`agent.ingress.enabled`<br>`agent.sessionProxy.certificate.enabled`<br>`kasm-helm.kasmConfig.authDomain` |
| [Private registries and image pulling](private-registries-and-image-pulling.md) | 15 — Image pre-pulling<br>23 — Private image registries | `agent.workspaceImagePullSecrets`<br>`agent.imagePullSecrets`<br>`agent.imagePuller.enabled` |
| [Kernel modules and webcam](kernel-modules-and-webcam.md) | 9 — Webcam (v4l2loopback)<br>16 — Kernel module management (WireGuard) | `nodePrep.enabled`<br>`nodePrep.modules.v4l2loopback.enabled`<br>`videoDevicePlugin.enabled` |
| [Secure Boot](secure-boot.md) | 26 — Secure Boot (signed kernel modules) | `nodePrep.secureBoot.existingMokSecret`<br>`nodePrep.modules.v4l2loopback.kmm.sign.enabled` |
| [Node tuning and swap](node-tuning-and-swap.md) | 1 — Core workspace (node sizing, `/dev/shm`, swap) | `nodePrep.tuning.swap.enabled`<br>`nodePrep.tuning.sysctls.enabled` |
| [Egress installer node prerequisites](egress-installer-node-prerequisites.md) | 6 — Egress VPN (per-session tunnel) | `egressInstaller.enabled`<br>`egressInstaller.distro`<br>`egressInstaller.cniBinDir` |
| [Managed Kubernetes providers: what changes](managed-kubernetes-providers.md) | Cross-cutting — every row above, on EKS / AKS / GKE / OpenShift | `nodePrep.modules.v4l2loopback.method`<br>`agent.sessionProxy.service.externalTrafficPolicy`<br>`egressInstaller.distro` |

Related reading:

* [Feature matrix](../feature-matrix.md) — every Kasm workspace feature, the chart and values that
  provide it, and what the cluster has to supply first.
* [Architecture](../architecture.md) — the ten charts, how they compose, and which one to install.
* [kasm-agent → Cluster preparation checklist](../../charts/kasm-agent/README.md#cluster-preparation-checklist)
  — the same ground as a single table, per chart value.
