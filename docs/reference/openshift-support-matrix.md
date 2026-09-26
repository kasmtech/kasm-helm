# OpenShift support matrix

> **Applies to:** agent · what runs on which OpenShift release, under which SecurityContextConstraint, and what does not run at all · **Charts/values:** `agent.openshift.scc.*`, `agent.workspaceSecurity.*`, `agent.seccomp.*`, `nodePrep.modules.v4l2loopback.kmm.*`, `videoDevicePlugin.openshift.scc.enabled`, `driDevicePlugin.openshift.scc.enabled`, `egressInstaller.enabled`

The how-to is [Admit the agent on OpenShift](../how-to/nodes/openshift.md); this page is the lookup
table behind it. OKD, the community distribution, behaves the same except where a row says otherwise.
What each session run mode can and cannot do on any cluster, OpenShift or not, is in
[Session run modes](../explanation/session-run-modes.md).

✅ Supported · ⚠️ Supported with a limit · ❌ Not supported

[Releases](#releases) · [Components and their SCCs](#components-and-their-sccs) ·
[Features](#features) · [Operators from OperatorHub](#operators-from-operatorhub)

## Releases

What changes between releases is the Kubernetes underneath: user namespaces (the `userns` root mode)
and image volumes (Nix images) arrive with it. Everything not listed in this table works the same on
every release shown.

| OpenShift | Kubernetes | uid-1000 sessions | Root sessions, `rootMode: host` (default) | Root sessions, `rootMode: userns` | Nix images (`imageMounts`) |
| --------- | ---------- | ----------------- | ----------------------------------------- | --------------------------------- | -------------------------- |
| 4.18 | 1.31 | ✅ | ✅ | ❌ user namespaces are tech preview; see below | ❌ no ImageVolume |
| 4.19 | 1.32 | ✅ | ✅ | ❌ user namespaces are tech preview | ❌ no ImageVolume |
| 4.20 | 1.33 | ✅ | ✅ | ✅ | ❌ no ImageVolume |
| 4.21 | 1.34 | ✅ | ✅ | ✅ | ❌ no ImageVolume |
| 4.22 | 1.35 | ✅ | ✅ | ✅ | ✅ `image` in `agent.openshift.scc.workspace.volumes` |
| 5.0 | 1.36 | ✅ | ✅ | ✅ | ✅ `image` in `agent.openshift.scc.workspace.volumes` |

- **`rootMode: userns` before 4.20.** The root SCC relies on the `userNamespaceLevel:
  RequirePodLevel` field to admit uid 0 only inside a pod user namespace. On a release whose API
  server does not know the field, it is dropped, and the root SCC would then admit host uid 0 under
  a setting that promises otherwise. The chart has no version gate: use `rootMode: host` (the
  default) or `forbid` there.
- **Nix images and user namespaces.** On 4.22 and later a Nix image that needs root runs under
  `rootMode: host`. Under `userns` it fails on nodes whose CRI-O uses runc, which idmaps bind mounts
  only; see [Session run modes](../explanation/session-run-modes.md).

## Components and their SCCs

Every pod the agent family runs, the account it runs as, and the SCC that admits it. "Chart" means
the grant is rendered by the switch in the last column; nothing here needs `oc adm policy` by hand
except the KMM build account.

| Pod | ServiceAccount | SCC | Granted by |
| --- | -------------- | --- | ---------- |
| Operator | `controller-manager` | `restricted-v2` | Nothing (default) |
| Agent API | `<agent>-agent` | `restricted-v2` | Nothing (default) |
| Session proxy | `<agent>-nginx-sidecar` | `restricted-v2` | Nothing (default) |
| Image puller, standby placeholders | the namespace's `default` | `restricted-v2` | Nothing (default) |
| uid-1000 sessions | `<agent>-workspace` | `kasm-<ns>-<agent>-workspace` | `agent.openshift.scc.enabled` |
| Root sessions (`host-root`, `userns-root`) | `<agent>-workspace` | `kasm-<ns>-<agent>-workspace-root` | `agent.openshift.scc.enabled` (absent under `rootMode: forbid`) |
| Seccomp installer DaemonSet (`seccomp.backend: installer`) | `<agent>-seccomp-installer` | `privileged` | `agent.openshift.scc.enabled` |
| DRI device plugin | its own | `privileged` | `driDevicePlugin.openshift.scc.enabled` |
| Video device plugin | its own | `privileged` | `videoDevicePlugin.openshift.scc.enabled` |
| Node prep DaemonSet (`tuning.*`, `method: build`) | `<release>-kasm-node-prep` | `privileged` | `nodePrep.openshift.scc.enabled` |
| KMM worker pods (load the module) | `<release>-kasm-node-prep` | `privileged` | `nodePrep.openshift.scc.enabled` |
| KMM build pods (kaniko, in-cluster builds only) | the namespace's `default` | `hostmount-anyuid` | **By hand**: KMM gives build pods no account of their own and mounts the node's `/lib/modules` into them |
| Egress installer | its own | - | ❌ Not supported (below) |

The workspace SCCs list `runtime/default`, `*` and `unconfined` as their seccomp profiles. `*` is how
an SCC admits `Localhost` profiles: OpenShift matches `localhost/<path>` entries literally and has no
`localhost/*` wildcard, and every inline profile the seccomp backends install has a path of its own.

Granting the KMM build account, in the namespace the agent release installs `nodePrep` into:

```console
oc adm policy add-scc-to-user hostmount-anyuid -z default -n <namespace>
```

## Features

| Feature | Status | Requires on OpenShift | Notes |
| ------- | ------ | --------------------- | ----- |
| Desktop, browser and app sessions (uid 1000) | ✅ | `agent.openshift.scc.enabled=true` | Admitted by the workspace SCC, `MustRunAsNonRoot` |
| Images that need root | ✅ | Same; `rootMode` picks `host` (any release) or `userns` (4.20+) | See [Releases](#releases) |
| Session recording | ✅ | Same | A root feature: the session runs in the root mode (`rootFeatures: promote`, the default) |
| `profile: restricted` sessions | ✅ | Same | Drops `SYS_CHROOT`; only `NET_BIND_SERVICE` survives an image's `cap_add` |
| Inline seccomp profiles, SPO backend | ✅ | The Security Profiles Operator from OperatorHub | See [Operators from OperatorHub](#operators-from-operatorhub) for the SELinux setting on RHEL 10-based nodes |
| Inline seccomp profiles, installer backend | ✅ | `agent.openshift.scc.enabled=true` grants the installer `privileged` | Runs a root DaemonSet with a hostPath mount |
| Webcam passthrough | ⚠️ | KMM (`nodePrep.modules.v4l2loopback.method=kmm`), `videoDevicePlugin.openshift.scc.enabled=true`, the build-account grant above | Nodes carry no compiler or headers, so the chart's own `build` method cannot run. The builder image must carry the node kernel's `kernel-devel` and module tree: see [Operators from OperatorHub](#operators-from-operatorhub) |
| GPU, NVIDIA (CUDA, NVENC, Vulkan) | ✅ | The certified NVIDIA GPU Operator from OperatorHub, not the `gpuOperator` subchart; `agent.gpu.enabled=true` | Works in every run mode, `userns-root` included |
| GPU, DRI (VA-API, EGL on `/dev/dri`) | ⚠️ | `driDevicePlugin.enabled=true`, `driDevicePlugin.openshift.scc.enabled=true` | Not in `userns-root` sessions: the device nodes are unmapped there. The agent does not offer DRI to such a session |
| Device passthrough by host path (`/dev/...` in a run config), Docker-style volume mappings | ⚠️ | `agent.openshift.scc.workspace.allowHostPath=true` | Widens the workspace SCCs for every session |
| Privileged images (`run_config.privileged`) | ⚠️ | `agent.openshift.scc.workspace.allowPrivileged=true`, `rootMode: host` | Refused under `userns` and `forbid` |
| Nix images (`imageMounts`) | ⚠️ | 4.22 or newer, `image` in `agent.openshift.scc.workspace.volumes` | Root Nix images under `rootMode: host` only |
| Persistent profiles, S3 | ✅ | Nothing | Every run mode |
| Persistent profiles, NFS/EFS-backed volumes | ⚠️ | Nothing | Not in `userns-root` sessions (the NFS client cannot idmap-mount) |
| Control plane Route | ✅ | `kasm-helm.isOpenshift=true`, `kasm-helm.route.enabled=true` | [OpenShift Route](../how-to/networking/openshift-route.md) |
| Direct-connect Route to the session proxy | ✅ | `agent.route.enabled=true` | TLS passthrough; the session proxy presents its own certificate |
| Node sysctls and swap | ✅ | `nodePrep.openshift.scc.enabled=true` | Runs the privileged node prep DaemonSet |
| Image pre-pulling | ✅ | Nothing | Runs under `restricted-v2` |
| Per-session VPN egress (`egressInstaller`) | ❌ | - | See below |

**Why egress does not run.** The egress installer works by chaining a CNI plugin into the runtime's
CNI configuration. OpenShift's CRI-O reads its configuration from `/etc/kubernetes/cni/net.d`, where
the only file is the Multus `00-multus.conf` that the Cluster Network Operator owns and rewrites, and
its plugins from `/var/lib/cni/bin`. With the default `cniBinDir` the daemon cannot start at all
(`/opt/cni` cannot be created on RHCOS). Pointed at OpenShift's directories, it starts and reports
its chaining as verified, but the only conflists it finds are the unused `crio-bridge` and
`loopback` examples under `/etc/cni/net.d`. Pods keep their normal networking; sessions simply never
get a tunnel. Keep `egressInstaller.enabled=false`.

## Operators from OperatorHub

| Operator | Used for | On OpenShift |
| -------- | -------- | ------------ |
| Kernel Module Management | Webcams (`method: kmm`) | Use Red Hat's KMM from the `redhat-operators` catalog; its build pods can start from the Driver Toolkit (`driver-toolkit` image stream in the `openshift` namespace), which carries the `kernel-devel` and module tree of the release's own kernel. Point `nodePrep.image.*` at it. The upstream KMM (OperatorHub.io catalog) runs too, with two gaps: its operator account lacks `update` on its own resources' `finalizers`, which OpenShift's `OwnerReferencesPermissionEnforcement` requires before it creates build and worker pods (grant it with a ClusterRole), and it knows nothing of the Driver Toolkit |
| Kernel Module Management, registry | Webcams | OpenShift's internal registry (`image-registry.openshift-image-registry.svc:5000`) works as the kmod registry, with `imageRepoSecret` holding a token for an account that may push to the namespace's image streams. Its certificate is signed by the cluster's service CA, which the build pod does not trust: set `nodePrep.modules.v4l2loopback.kmm.registryTLS.insecureSkipTLSVerify=true`, and `kmm.build.baseImageRegistryTLS.insecureSkipTLSVerify=true` when the builder image lives there too |
| Kernel Module Management, OKD | Webcams | OKD's Driver Toolkit is built from CentOS Stream at release time and its kernel can be newer than the nodes' (`kernel-devel` for a node's exact kernel then exists nowhere in the Stream repositories). The release payload's `stream-coreos-extensions` image carries the matching `kernel-devel` RPM and `stream-coreos` the matching module tree; a builder image assembled from those two works |
| Security Profiles Operator | Seccomp, `backend: spo` | On RHEL 10 and CentOS Stream CoreOS 10 nodes, the upstream SPO's SELinux component fails to start and takes the node daemon with it. Kasm needs only its seccomp half: set `spec.selinux.enable: false` on the `spod` object in the operator's namespace |
| NVIDIA GPU Operator | GPU | The certified operator, with its own ClusterPolicy; leave the `gpuOperator` subchart disabled |
