# Cluster configuration how-tos

These are the actionable versions of the **"What you need"** column in
[What works on Kubernetes](../feature-matrix.md): what to do, in order, with the commands that
prove it worked.

Working out *which* of them you need, and in what order? [**Planning a Kasm agent deployment**](../planning.md)
is the decision sequence these procedures execute.

| How-to | Covers | Key values |
| ------ | ------ | ---------- |
| [RWX storage for profiles](rwx-storage-for-profiles.md) | Persistent profiles | `nfs-server-provisioner.enabled`<br>`nfs-server-provisioner.persistence.enabled`<br>`nfs-server-provisioner.storageClass.name` |
| [Cloud storage mappings (rclone CSI)](cloud-storage-rclone-csi.md) | Cloud storage mappings | `csiRclone.enabled`<br>`agent.storageMappings.enabled` |
| [NetworkPolicy enforcement](network-policy-enforcement.md) | Network isolation<br>Web filtering<br>Multi-tenancy<br>Telemetry | `networkPolicies.enabled`<br>`networkPolicies.manager.ports`<br>`networkPolicies.otelBackend.cidr` |
| [Privileged workloads and policies](privileged-workloads-and-policies.md) | Volume mappings (host paths)<br>Multi-tenancy | `agent.workspacesNodeSelector`<br>`nodePrep.enabled`<br>`egressInstaller.enabled` |
| [GPU nodes (CUDA and EGL/DRI)](gpu-nodes.md) | GPU workspaces (CUDA)<br>GPU graphics acceleration (EGL/DRI)<br>Node targeting | `gpuOperator.enabled`<br>`agent.gpu.enabled`<br>`agent.workspacesNodeSelector` |
| [External access and TLS](external-access-and-tls.md) | External access to sessions<br>TLS<br>The login cookie | `agent.gatewayRoute.enabled`<br>`agent.ingress.enabled`<br>`agent.sessionProxy.certificate.enabled`<br>`kasm-helm.kasmConfig.authDomain` |
| [Private registries and image pulling](private-registries-and-image-pulling.md) | Private image registries<br>Image pre-pulling | `agent.workspaceImagePullSecrets`<br>`agent.imagePullSecrets`<br>`agent.imagePuller.enabled` |
| [Kernel modules and webcam](kernel-modules-and-webcam.md) | Webcam passthrough<br>WireGuard on old kernels | `nodePrep.enabled`<br>`nodePrep.modules.v4l2loopback.enabled`<br>`videoDevicePlugin.enabled` |
| [Secure Boot](secure-boot.md) | Secure Boot nodes | `nodePrep.secureBoot.existingMokSecret`<br>`nodePrep.modules.v4l2loopback.kmm.sign.enabled` |
| [Node tuning and swap](node-tuning-and-swap.md) | Node tuning and swap, and the node sizing behind every session | `nodePrep.tuning.swap.enabled`<br>`nodePrep.tuning.sysctls.enabled` |
| [Egress installer node prerequisites](egress-installer-node-prerequisites.md) | Egress gateways (per-session VPN) | `egressInstaller.enabled`<br>`egressInstaller.distro`<br>`egressInstaller.cniBinDir` |
| [Managed Kubernetes providers: what changes](managed-kubernetes-providers.md) | Cross-cutting — everything above, on EKS / AKS / GKE / OpenShift | `nodePrep.modules.v4l2loopback.method`<br>`agent.sessionProxy.service.externalTrafficPolicy`<br>`egressInstaller.distro` |

Related reading:

* [What works on Kubernetes](../feature-matrix.md) — every Kasm feature, whether it works, and
  what it needs from the cluster.
* [Architecture](../architecture.md) — the ten charts, how they compose, and which one to install.
