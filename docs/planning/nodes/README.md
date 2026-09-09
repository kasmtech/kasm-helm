> **Applies to:** the agent half — every page here prepares the nodes sessions run on · **Charts/values:** `nodePrep.*`, `videoDevicePlugin.*`, `agent.gpu.*`, `agent.workspacesNodeSelector`

# Nodes and devices

Sessions are pods, and some Kasm features need something from the **node** that a pod cannot ask
for: a kernel module, a device plugin, a GPU driver, a relaxed security policy. Those are what these
pages cover.

None of this applies to the control plane, which runs as ordinary workloads on any node.

| Page | Covers | Key values |
| ---- | ------ | ---------- |
| [GPU nodes](gpu.md) | CUDA workspaces and EGL/DRI graphics acceleration | `gpuOperator.enabled`<br>`agent.gpu.enabled` |
| [Kernel modules and webcam](kernel-modules-and-webcam.md) | Webcam passthrough (`v4l2loopback`), WireGuard on older kernels | `nodePrep.enabled`<br>`nodePrep.modules.v4l2loopback.*`<br>`videoDevicePlugin.enabled` |
| [Secure Boot](secure-boot.md) | Signing modules so they load on Secure Boot nodes | `nodePrep.secureBoot.existingMokSecret`<br>`nodePrep.modules.v4l2loopback.kmm.sign.enabled` |
| [Tuning and swap](tuning-and-swap.md) | Node sysctls and swap, and the sizing behind every session | `nodePrep.tuning.swap.enabled`<br>`nodePrep.tuning.sysctls.enabled` |
| [Privileged workloads](privileged-workloads.md) | Host paths, Pod Security admission, multi-tenancy | `agent.workspacesNodeSelector`<br>`nodePrep.enabled`<br>`egressInstaller.enabled` |

## Before any of them

Two decisions come first, because they change what every page here does:

1. **Which nodes run sessions.** `agent.workspacesNodeSelector` pins sessions — and the
   agent-managed module installer and device plugin that follow them — to a labelled pool. Without
   it, everything here applies to every node in the cluster.
2. **What your cluster's Pod Security admission allows.** `nodePrep` and `egressInstaller` run
   privileged; on a `restricted` namespace they will not start at all. See
   [Privileged workloads](privileged-workloads.md) and [Security](../security.md).

On a managed service, several of these behave differently — node images, driver installation and
signing all vary. See [Managed providers](../managed-providers.md).
