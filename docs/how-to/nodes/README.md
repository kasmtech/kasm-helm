# Nodes and devices

> **Applies to:** agent

Sessions are pods, and some Kasm features need something from the **node** that a pod cannot ask
for: a kernel module, a device plugin, a GPU driver, a relaxed security policy. None of it applies
to the control plane, which runs as ordinary workloads on any node.

| Page | Task | Key values |
| ---- | ---- | ---------- |
| [Scope workspaces to specific nodes](scope-workspaces-to-nodes.md) | Pin sessions and the node-level DaemonSets to a labelled pool, taints included | `agent.workspacesNodeSelector`<br>`nodePrep.nodeSelector` |
| [Privileged workloads and cluster policy](privileged-workloads.md) | Label the namespace, clear the policy engine; do this first | `nodePrep.enabled`<br>`egressInstaller.enabled` |
| [GPU nodes](gpu.md) | CUDA workspaces and EGL/DRI graphics acceleration | `gpuOperator.enabled`<br>`agent.gpu.enabled` |
| [Webcam and kernel modules](webcam-kernel-modules.md) | Webcam passthrough (`v4l2loopback`), WireGuard on older kernels | `nodePrep.modules.v4l2loopback.*`<br>`videoDevicePlugin.enabled` |
| [Secure Boot](secure-boot.md) | Sign modules so they load on Secure Boot nodes | `nodePrep.secureBoot.existingMokSecret`<br>`nodePrep.modules.v4l2loopback.kmm.sign.enabled` |
| [Node tuning and swap](tuning-and-swap.md) | Node sysctls and swap, kubelet first | `nodePrep.tuning.swap.enabled`<br>`nodePrep.tuning.sysctls.enabled` |

Two decisions come before any of them. **Which nodes run sessions:** `agent.workspacesNodeSelector`
pins sessions, and the module installer and device plugin that follow them, to a labelled pool;
without it everything here applies to every node ([Scope workspaces to specific
nodes](scope-workspaces-to-nodes.md), [Capacity](../../explanation/capacity.md)).
**What the namespace permits:** `nodePrep`, `videoDevicePlugin` and `egressInstaller` run
privileged, and the label that admits them covers the whole namespace
([Security posture](../../explanation/security-posture.md)). On a managed service, node images,
driver installation and signing all differ: [Managed providers](../../explanation/managed-providers.md).
