# Admit the agent on OpenShift

> **Applies to:** agent · what OpenShift's SecurityContextConstraints need from the agent half, and which features run there in a different mode or not at all · **Charts/values:** `agent.openshift.scc.enabled`, `agent.openshift.scc.workspace.*`, `agent.workspaceSecurity.*`, `nodePrep.openshift.scc.enabled`, `videoDevicePlugin.openshift.scc.enabled`, `agent.seccomp.backend`, `nodePrep.modules.v4l2loopback.method`

## Why this is needed

OpenShift admits pods through SecurityContextConstraints (SCCs), not through the Pod Security
labels the other pages use. Every pod is matched against the SCCs its ServiceAccount may use, and
the default for an ordinary account is `restricted-v2`: a random non-root UID, no capability adds,
no privilege escalation, `runtime/default` seccomp only, no hostPath. A namespace label changes
none of that.

A Kasm session cannot run under `restricted-v2`, even though it runs as `kasm-user` (uid 1000)
with privilege escalation off: it pins uid 1000 and `fsGroup: 1000` rather than taking the
namespace's random range, adds `SYS_CHROOT` for the browser sandbox on top of `drop: ALL`, and
carries a `Localhost` seccomp profile when its image ships one. An image that needs root (a run
config with `user: root`, root `exec_configs`, session recording) needs more still: uid 0 and the
eight capabilities a root session keeps. None of the built-in SCCs fits. `nonroot-v2` and
`restricted-v2` admit no capability adds beyond `NET_BIND_SERVICE` and no `Localhost` seccomp,
`anyuid` admits no capability adds, and OpenShift 4.20's user-namespace SCCs, `restricted-v3` and
`nested-container`, admit `SETUID`/`SETGID` at most. So sessions need SCCs of their own, and the
operator runs every session under a ServiceAccount of its own, `<agent>-workspace`, so they can be
granted to sessions and to nothing else. `agent.openshift.scc.enabled` ships the SCCs and the
grant. The agent Deployment, the session proxy, the image puller and the standby placeholders set
no UID and stay under `restricted-v2`.

### Root sessions: the three root modes

`agent.workspaceSecurity.rootMode` decides where a root session's uid 0 comes from, and the chart
shapes its SCCs to match. A uid-1000 session is the same in every mode.

| `rootMode` | Root sessions run as | OpenShift needs | SCCs the chart ships |
| ---------- | -------------------- | --------------- | -------------------- |
| `host` (default) | host uid 0, the way every session ran before user namespaces | Any release | `<name>` for uid 1000, and `<name>-root`: any uid, the eight root capabilities, no user-namespace requirement, so a container escape is root on the node |
| `userns` | uid 0 inside a pod user namespace (`hostUsers: false`): root in the pod, an unprivileged uid on the node | OpenShift 4.20 or newer (user namespaces GA; tech preview in 4.17 to 4.19) | `<name>` for uid 1000, and `<name>-root`: any uid, the eight root capabilities, `userNamespaceLevel: RequirePodLevel`, so uid 0 is admitted only in a pod user namespace |
| `forbid` | never; an image that asks for root fails to launch | Any release | `<name>` alone |

`<name>` is `kasm-<namespace>-<agent>-workspace`: `MustRunAsNonRoot`, `drop: ALL` required,
`SYS_CHROOT` and `NET_BIND_SERVICE` under the default `baseline` profile (`NET_BIND_SERVICE` alone
under `restricted`), and privilege escalation plus `SETUID`/`SETGID` only with
`workspaceSecurity.sudo`. It sits above `root` in OpenShift's restrictiveness ordering, so a
uid-1000 session is admitted by it and only a root session reaches `<name>-root`. Under
`userNamespaces: always` it also requires a pod user namespace. `profile` and `userNamespaces` shape
only this SCC and `rootMode` only the root one; they are independent, so `profile: restricted` with
the default `host` is valid. Where the namespace's Pod Security label enforces `restricted`, only
`profile: restricted` sessions pass and root sessions are refused whatever their `rootMode`;
`rootMode: forbid` is the natural companion there, not a requirement. The two SCCs are separate because
one cannot do both jobs: `RequirePodLevel` would refuse the ordinary uid-1000 pods, and without it
the root SCC would admit host root.

`host` is the default because it works on every release, runtime and volume, and only images
that need root run that way. `userns` locks root sessions down on 4.20 and later, within the
user-namespace limits, which apply on OpenShift too: a root session cannot mount an NFS-backed
volume (NFS or EFS persistent profiles, NFS storage mappings; see [Storage](../storage/README.md)),
cannot mount an OCI image volume (a Nix image's `imageMounts`) on a node whose CRI-O runs runc,
which idmaps bind mounts only, and device passthrough into it is limited. Stay on `host` on an
older release or when a root image needs one of those, and use `forbid` when no image in the
catalog should run as root at all.

What each run mode can and cannot do, feature by feature, is in
[Session run modes](../../explanation/session-run-modes.md); every component's account and SCC, and
what each OpenShift release supports, is in the
[OpenShift support matrix](../../reference/openshift-support-matrix.md).

The rest of the agent family lands in one of three places:

| Feature | On OpenShift | How |
| ------- | ------------ | --- |
| Sessions | Supported | `agent.openshift.scc.enabled=true` |
| Inline seccomp profiles | Supported, two modes | `agent.seccomp.backend=spo` with the Security Profiles Operator installed, or `installer` with the `privileged` SCC granted to `<agent>-seccomp-installer` (done by the same switch) |
| Webcam passthrough | Supported, KMM mode only | `nodePrep.modules.v4l2loopback.method=kmm` (RHCOS has no headers or toolchain), a builder image carrying the node kernel's headers and modules (the Driver Toolkit), `nodePrep.openshift.scc.enabled=true` for KMM's worker and build pods, plus `videoDevicePlugin.openshift.scc.enabled=true` |
| Node sysctls and swap | Supported | `nodePrep.openshift.scc.enabled=true` |
| Nix images (`imageMounts`) | OpenShift 4.22 or newer | Needs the ImageVolume feature (Kubernetes 1.35); add `image` to `agent.openshift.scc.workspace.volumes` |
| Device passthrough by path (`/dev/dri`, `/dev/video*` in an image's run config) and host bind mounts | Supported with a wider SCC | `agent.openshift.scc.workspace.allowHostPath=true` |
| Per-session VPN egress (`egressInstaller`) | Supported, attachment mode | `egressInstaller.distro=openshift` (a Multus NetworkAttachmentDefinition runs the shim, since OpenShift's primary CNI configuration cannot be chained), `egressInstaller.openshift.scc.enabled=true`, and `agent.egress.networkAttachment=kasm-egress` |

## Before you start

- Cluster-admin. Every SCC and every `use` grant is a cluster-scoped object.
- The control plane on OpenShift first: [OpenShift Route](../networking/openshift-route.md) covers
  `kasm-helm.isOpenshift`, the Routes and the router timeout.
- The namespace layout from [Privileged workloads and cluster policy](privileged-workloads.md).
  On OpenShift the `privileged` label is still set, by the SCC label syncer, once an account in the
  namespace can use the `privileged` SCC; you do not set it yourself.
- For inline seccomp profiles, decide the backend. `spo` needs the
  [Security Profiles Operator](https://github.com/kubernetes-sigs/security-profiles-operator) from
  OperatorHub and runs nothing on the nodes; `installer` runs a root DaemonSet with a hostPath
  mount and needs the `privileged` SCC. [Workspace seccomp profiles](seccomp-profiles.md).
- For webcams, the Kernel Module Management operator from OperatorHub (Red Hat's, from
  `redhat-operators`), a registry KMM can push to, and a builder image that carries the node
  kernel's `kernel-devel` and module tree, which the Driver Toolkit does:
  [Webcam and kernel modules](webcam-kernel-modules.md),
  [OpenShift support matrix](../../reference/openshift-support-matrix.md#operators-from-operatorhub).
- For Nix images, an OpenShift release whose Kubernetes is 1.35 or newer:

  ```console
  oc version -o json | jq -r .serverVersion.gitVersion
  ```

  Expected: `v1.35.x` or later. Earlier releases have no ImageVolume and no fallback.
- Only to lock root sessions down with `rootMode: userns`: OpenShift 4.20 or newer, no NFS-backed
  volume on a root session, and no Nix image (`imageMounts`) that needs root on a node whose CRI-O
  runs runc, which idmaps bind mounts only. The default, `host`, needs none of this.

## Steps

1. **Grant the sessions their SCCs, for the root mode you picked.**

   ```yaml
   kasm-agent:
     agent:
       workspaceSecurity:
         rootMode: host          # default; userns on 4.20+ to lock root down; forbid for no root at all
       openshift:
         scc:
           enabled: true
   ```

   The SCCs are named `kasm-<namespace>-<agent>-workspace` and, unless `rootMode` is `forbid`,
   `kasm-<namespace>-<agent>-workspace-root`, and admit exactly what the operator sets for each run
   mode (the table above), plus `RunAsAny` fsGroup, the three seccomp forms, and the volume kinds a
   session uses. Widen them only for what your catalog needs: `capabilities` for an image whose
   run config adds more (a non-empty list replaces the derived set on both SCCs, so list every
   capability a session needs), `allowHostPath` for device passthrough by path or Docker-style
   volume mappings, `allowPrivileged` for a privileged image, `volumes` plus `image` for Nix
   images.

2. **Pick the seccomp backend**, if any image in the catalog ships an inline profile.

   ```yaml
   kasm-agent:
     agent:
       seccomp:
         enabled: true
         backend: spo            # or installer
   ```

   With `installer`, step 1's switch also grants the `privileged` SCC to the
   `<agent>-seccomp-installer` ServiceAccount, which the installer's root hostPath DaemonSet needs.
   With `spo`, nothing else is granted.

3. **Webcams, if wanted.** KMM builds and loads `v4l2loopback`; the device plugin advertises the
   devices and needs the `privileged` SCC for its `/dev` mount.

   ```yaml
   kasm-agent:
     nodePrep:
       enabled: true
       image:                                # the builder: the release's Driver Toolkit
         registry: image-registry.openshift-image-registry.svc:5000
         repository: openshift/driver-toolkit
         tag: latest
       openshift:
         scc:
           enabled: true                     # KMM's worker pods run under this account
       modules:
         v4l2loopback:
           enabled: true
           method: kmm
           kmm:
             image:
               registry: image-registry.openshift-image-registry.svc:5000
               repository: kasm-agent/v4l2loopback
             imageRepoSecret: kmm-registry   # a token that may push to the namespace's image streams
             registryTLS:
               insecureSkipTLSVerify: true   # the internal registry's service-CA certificate
             build:
               baseImageRegistryTLS:
                 insecureSkipTLSVerify: true
     videoDevicePlugin:
       enabled: true
       openshift:
         scc:
           enabled: true
   ```

   `nodePrep.openshift.scc.enabled` covers both kinds of KMM pod: the worker pods, which run under
   the chart's account with `privileged`, and the build pods, which KMM always runs as the
   namespace's `default` account with the node's `/lib/modules` mounted, with `hostmount-anyuid`.

   The builder must match the nodes' kernel exactly: the Driver Toolkit carries the headers and
   modules of the release's own kernel, and the image KMM builds links that module tree in so the
   worker can load `v4l2loopback`'s in-tree dependency, `videodev`. On OKD the Driver Toolkit can
   drift from the nodes' kernel; see the
   [support matrix](../../reference/openshift-support-matrix.md#operators-from-operatorhub).

4. **Per-session VPN egress, if wanted.** OpenShift's CNI configuration belongs to the Cluster
   Network Operator, so the shim runs as a Multus additional network, and only sessions with egress
   are attached to it.

   ```yaml
   kasm-agent:
     agent:
       egress:
         networkAttachment: kasm-egress   # the installer's networkAttachment.name
     egressInstaller:
       enabled: true
       distro: openshift                 # /var/lib/cni/bin and mode: attachment
       openshift:
         scc:
           enabled: true
   ```

   The NetworkAttachmentDefinition lands in the release namespace, where the sessions run.

5. **Install or upgrade.**

   ```console
   helm upgrade --install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
     -n kasm --create-namespace -f values.yaml
   ```

## Verify

The SCCs exist and are granted to the operator's workspace account:

```console
oc get scc kasm-kasm-k8s-agent-workspace kasm-kasm-k8s-agent-workspace-root \
  -o custom-columns='NAME:.metadata.name,RUNASUSER:.runAsUser.type,USERNS:.userNamespaceLevel'
oc -n kasm get rolebinding k8s-agent-workspace-scc -o jsonpath='{.subjects[0].name}{"\n"}'
```

Expected with the default `rootMode: host`: the first SCC with `MustRunAsNonRoot`, the second with
`RunAsAny` and `<none>` (with `userns`, `RequirePodLevel` there; with `forbid`, only the first
exists), and `k8s-agent-workspace`.

Launch a session, then read which SCC admitted its pod, its run mode, and the agent's own pod:

```console
oc -n kasm get pods -l app.kubernetes.io/component=workspace \
  -o custom-columns='NAME:.metadata.name,MODE:.metadata.labels.kasm\.com/run-mode,SCC:.metadata.annotations.openshift\.io/scc'
oc -n kasm get pods -l app.kubernetes.io/component=agent \
  -o custom-columns='NAME:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc'
```

Expected: a `nonroot` session under `kasm-kasm-k8s-agent-workspace`, a `userns-root` or
`host-root` session under `kasm-kasm-k8s-agent-workspace-root`, the agent under `restricted-v2`.

## Chart values

```yaml
kasm-helm:
  isOpenshift: true
  publicAddr: kasm.example.com
  proxyService:
    type: ClusterIP
  route:
    enabled: true
    tls:
      termination: edge
      insecureEdgeTerminationPolicy: Redirect

kasm-agent:
  agent:
    workspaceSecurity:
      rootMode: host                  # default; userns (4.20+) to lock root down; forbid for no root
    openshift:
      scc:
        enabled: true
        workspace:
          allowHostPath: false        # true for /dev passthrough by path or volume mappings
          # volumes: [..., image]     # OpenShift 4.22+ only, for Nix images
    seccomp:
      enabled: true
      backend: spo                    # or installer
    route:                            # direct-connect only
      enabled: true
      tls:
        termination: passthrough
  nodePrep:                           # webcams only
    enabled: true
    modules:
      v4l2loopback:
        enabled: true
        method: kmm
  videoDevicePlugin:                  # webcams only
    enabled: true
    openshift:
      scc:
        enabled: true
  egressInstaller:                    # per-session VPN egress only
    enabled: true
    distro: openshift
    openshift:
      scc:
        enabled: true
```

With `egressInstaller`, also set `agent.egress.networkAttachment: kasm-egress`.

Installing the charts directly, drop the `kasm-helm:` and `kasm-agent:` keys.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| A session's Deployment has `0` pods; its events say `unable to validate against any security context constraint` and list `runAsUser: Invalid value: 0` | The image asks for root (a `user: root` run config, root `exec_configs`, recording) and `agent.workspaceSecurity.rootMode` is `forbid`, so no root SCC exists; or the SCCs are not granted at all, or the operator predates the `<agent>-workspace` ServiceAccount and the pods still use `default` | Pick `rootMode: host` (the default) or `userns` (4.20+) if the image must run as root, or `rootFeatures: downgrade` if only its root commands or recording ask for it; otherwise `agent.openshift.scc.enabled=true`, and `kubectl -n <ns> get sa <agent>-workspace` must exist |
| A root session fails with `UserNamespacesUnsupported` | `rootMode: userns` on OpenShift before 4.20, whose API server drops the pod's `hostUsers: false` | `rootMode: host` (the default) or `forbid` |
| The session pod is admitted but stays `ContainerCreating`/`CreateContainerError` with `mount_setattr` and `idmap` in its events | A `userns-root` session (or any session under `userNamespaces: always`) mounts an NFS-backed volume, which cannot be idmap-mounted into a user namespace | Move the profile to S3 or block storage, set `rootFeatures: downgrade` if the image only asks for root through its commands or recording, or `rootMode: host`; see [Storage](../storage/README.md) |
| The session pod is admitted but stays `CreateContainerError`; its events say `runc create failed: invalid mount` naming the image volume's destination (`/nix`) and `id-mapped mounts are only supported for bind-mounts` | An image with `imageMounts` (the Nix images) runs as a `userns-root` session (or any session under `userNamespaces: always`) on a node whose CRI-O uses runc, which cannot idmap an image volume | `rootMode: host`, or `rootFeatures: downgrade` if the image only asks for root through its commands or recording |
| The same event lists `capabilities.add: Invalid value: "SYS_ADMIN"` (or another name) | The image's run config adds a capability the SCC does not list | Add it to `agent.openshift.scc.workspace.capabilities`, together with the derived set it replaces |
| The same event lists `hostPath volumes are not allowed to be used` | The image passes a device or a volume mapping by host path | `agent.openshift.scc.workspace.allowHostPath=true` |
| The same event lists `image volumes are not allowed to be used` | A Nix image's `imageMounts` | `image` in `agent.openshift.scc.workspace.volumes`, on OpenShift 4.22 or newer |
| `<agent>-seccomp-installer` DaemonSet has `DESIRED n / CURRENT 0` | The `privileged` SCC is not granted to its account | `agent.openshift.scc.enabled=true` with `seccomp.backend=installer`, or switch to `spo` |
| `videoDevicePlugin` or `nodePrep` DaemonSet has `DESIRED n / CURRENT 0` | Same, for the DaemonSet's own account | `videoDevicePlugin.openshift.scc.enabled=true`, `nodePrep.openshift.scc.enabled=true` |
| `egressInstaller` pods stay in `CreateContainerError` with `failed to mkdir /opt/cni/bin` | `distro` is not `openshift`, and the default `cniBinDir` does not exist on RHCOS | `egressInstaller.distro=openshift` |
| `egressInstaller` pods run and log `verified kasm-egress-cni chaining`, but sessions get no tunnel | The installer is in chain mode; the only conflists it can find are the unused examples under `/etc/cni/net.d` | `egressInstaller.distro=openshift`, which switches to attachment mode |
| Sessions with egress get no `wg`/`tun` interface; their pod has no `k8s.v1.cni.cncf.io/networks` annotation | `agent.egress.networkAttachment` is not set | Set it to the installer's `networkAttachment.name` |
| An egress session's pod stays `ContainerCreating` with a Multus error naming `kasm-egress` | The NetworkAttachmentDefinition is not in the session's namespace | Install the egress installer in the agent's namespace, or set `agent.egress.networkAttachment` to `<namespace>/kasm-egress` |
| KMM reports `pods "<name>-build-..." is forbidden: unable to validate against any security context constraint` naming `hostPath` | KMM's build pods run as the namespace's `default` account and mount `/lib/modules` | `nodePrep.openshift.scc.enabled=true`, which grants `default` `hostmount-anyuid` |
| KMM reports `cannot set blockOwnerDeletion if an ownerReference refers to a resource you can't set finalizers on` | The upstream KMM's operator account lacks `update` on its resources' `finalizers`, which OpenShift requires | Use Red Hat's KMM, or bind the upstream operator's account to a ClusterRole with `update` on `kmm.sigs.x-k8s.io` `*/finalizers` |
| KMM's build fails with `certificate signed by unknown authority` pushing to or pulling from `image-registry.openshift-image-registry.svc:5000` | The internal registry's certificate comes from the cluster's service CA | `nodePrep.modules.v4l2loopback.kmm.registryTLS.insecureSkipTLSVerify=true`, and `kmm.build.baseImageRegistryTLS.insecureSkipTLSVerify=true` for a builder image there |
| KMM's build fails with `Unable to find a match: /usr/src/kernels/<kernel>` | The builder image's repositories no longer carry `kernel-devel` for the nodes' kernel | Build from the Driver Toolkit, whose headers match the release |
| KMM's worker pod crash-loops with `Unknown symbol in module` | The builder image had no module tree for the kernel, so the image's `modules.dep` does not name `videodev` | Build from the Driver Toolkit |

Anything else: [Troubleshooting](../../reference/troubleshooting.md).

## Decisions

- [ ] `kasm-helm.isOpenshift=true` and the Routes, from [OpenShift Route](../networking/openshift-route.md).
- [ ] Root mode chosen: `agent.workspaceSecurity.rootMode` `host` (the default), `userns` (OpenShift 4.20+, no NFS profiles or runc image volumes for root images), or `forbid`.
- [ ] `agent.openshift.scc.enabled=true`; `allowHostPath`, `allowPrivileged`, `capabilities` and `volumes` widened only for what the catalog needs.
- [ ] Seccomp backend chosen: `spo` (SPO installed) or `installer` (`privileged` SCC granted by the same switch).
- [ ] Webcams: `nodePrep.modules.v4l2loopback.method=kmm` built from the Driver Toolkit, `nodePrep.openshift.scc.enabled=true`, `videoDevicePlugin.openshift.scc.enabled=true`.
- [ ] Nix images: OpenShift 4.22 or newer, `image` in the SCC's `volumes`.
- [ ] Egress: `egressInstaller.distro=openshift`, `egressInstaller.openshift.scc.enabled=true`, `agent.egress.networkAttachment=kasm-egress`; or `egressInstaller.enabled=false`.
- [ ] Sessions verified under the workspace SCC and the agent under `restricted-v2`.
