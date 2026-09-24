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
| `userns` (default) | uid 0 inside a pod user namespace (`hostUsers: false`): root in the pod, an unprivileged uid on the node | OpenShift 4.20 or newer (user namespaces GA; tech preview in 4.17 to 4.19) | `<name>` for uid 1000, and `<name>-root`: any uid, the eight root capabilities, `userNamespaceLevel: RequirePodLevel`, so uid 0 is admitted only in a pod user namespace |
| `host` | host uid 0, the way every session ran before user namespaces | Any release | `<name>` for uid 1000, and `<name>-root`: any uid, the eight root capabilities, no user-namespace requirement, so a container escape is root on the node |
| `forbid` | never; an image that asks for root fails to launch | Any release | `<name>` alone |

`<name>` is `kasm-<namespace>-<agent>-workspace`: `MustRunAsNonRoot`, `drop: ALL` required,
`SYS_CHROOT` and `NET_BIND_SERVICE` under the default `baseline` profile (`NET_BIND_SERVICE` alone
under `restricted`), and privilege escalation plus `SETUID`/`SETGID` only with
`workspaceSecurity.sudo`. It sits above `root` in OpenShift's restrictiveness ordering, so a
uid-1000 session is admitted by it and only a root session reaches `<name>-root`. Under
`userNamespaces: always` it also requires a pod user namespace. The two SCCs are separate because
one cannot do both jobs: `RequirePodLevel` would refuse the ordinary uid-1000 pods, and without it
the root SCC would admit host root.

`userns` is the mode to want on 4.20 and later. The user-namespace limits apply on OpenShift too: a
root session cannot mount an NFS-backed volume (NFS or EFS persistent profiles, NFS storage
mappings; see [Storage](../storage/README.md)), and device passthrough into it is limited. Use
`host` on an older release or when a root image has to reach an NFS profile, and `forbid` when no
image in the catalog should run as root at all.

The rest of the agent family lands in one of three places:

| Feature | On OpenShift | How |
| ------- | ------------ | --- |
| Sessions | Supported | `agent.openshift.scc.enabled=true` |
| Inline seccomp profiles | Supported, two modes | `agent.seccomp.backend=spo` with the Security Profiles Operator installed, or `installer` with the `privileged` SCC granted to `<agent>-seccomp-installer` (done by the same switch) |
| Webcam passthrough | Supported, KMM mode only | `nodePrep.modules.v4l2loopback.method=kmm` (RHCOS has no headers or toolchain) plus `videoDevicePlugin.openshift.scc.enabled=true` |
| Node sysctls and swap | Supported | `nodePrep.openshift.scc.enabled=true` |
| Nix images (`imageMounts`) | OpenShift 4.22 or newer | Needs the ImageVolume feature (Kubernetes 1.35); add `image` to `agent.openshift.scc.workspace.volumes` |
| Device passthrough by path (`/dev/dri`, `/dev/video*` in an image's run config) and host bind mounts | Supported with a wider SCC | `agent.openshift.scc.workspace.allowHostPath=true` |
| Per-session VPN egress (`egressInstaller`) | **Not supported** | The daemon chains into `*.conflist` files under `/etc/cni/net.d`; OpenShift's CRI-O reads a single Multus `.conf` that the Cluster Network Operator owns, so there is nothing to chain into |

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
- For webcams, the Kernel Module Management operator from OperatorHub and a registry KMM can push
  to: [Webcam and kernel modules](webcam-kernel-modules.md).
- For Nix images, an OpenShift release whose Kubernetes is 1.35 or newer:

  ```console
  oc version -o json | jq -r .serverVersion.gitVersion
  ```

  Expected: `v1.35.x` or later. Earlier releases have no ImageVolume and no fallback.

## Steps

1. **Grant the sessions their SCCs, for the root mode you picked.**

   ```yaml
   kasm-agent:
     agent:
       workspaceSecurity:
         rootMode: userns        # 4.20+; host on older releases; forbid for no root at all
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
       modules:
         v4l2loopback:
           enabled: true
           method: kmm
           kmm:
             image:
               registry: image-registry.openshift-image-registry.svc:5000
               repository: kasm-agent/v4l2loopback
     videoDevicePlugin:
       enabled: true
       openshift:
         scc:
           enabled: true
   ```

   `nodePrep.openshift.scc.enabled` is only for `tuning.sysctls` or `tuning.swap`, which run the
   privileged DaemonSet; a KMM-only `nodePrep` renders no DaemonSet and needs no grant.

4. **Leave `egressInstaller.enabled` off.** See the table above.

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

Expected with `rootMode: userns`: the first SCC with `MustRunAsNonRoot`, the second with `RunAsAny`
and `RequirePodLevel` (with `host`, `<none>` there; with `forbid`, only the first exists), and
`k8s-agent-workspace`.

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
      rootMode: userns                # OpenShift 4.20+; host before that; forbid for no root
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
  egressInstaller:
    enabled: false
```

Installing the charts directly, drop the `kasm-helm:` and `kasm-agent:` keys.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| A session's Deployment has `0` pods; its events say `unable to validate against any security context constraint` and list `runAsUser: Invalid value: 0` | The image asks for root (a `user: root` run config, root `exec_configs`, recording) and `agent.workspaceSecurity.rootMode` is `forbid`, so no root SCC exists; or the SCCs are not granted at all, or the operator predates the `<agent>-workspace` ServiceAccount and the pods still use `default` | Pick `rootMode: userns` (4.20+) or `host` if the image must run as root, or `rootFeatures: downgrade` if only its root commands or recording ask for it; otherwise `agent.openshift.scc.enabled=true`, and `kubectl -n <ns> get sa <agent>-workspace` must exist |
| The session pod is admitted but stays `ContainerCreating`/`CreateContainerError` with `mount_setattr` and `idmap` in its events | A `userns-root` session (or any session under `userNamespaces: always`) mounts an NFS-backed volume, which cannot be idmap-mounted into a user namespace | Move the profile to S3 or block storage, set `rootFeatures: downgrade` if the image only asks for root through its commands or recording, or `rootMode: host`; see [Storage](../storage/README.md) |
| The same event lists `capabilities.add: Invalid value: "SYS_ADMIN"` (or another name) | The image's run config adds a capability the SCC does not list | Add it to `agent.openshift.scc.workspace.capabilities`, together with the derived set it replaces |
| The same event lists `hostPath volumes are not allowed to be used` | The image passes a device or a volume mapping by host path | `agent.openshift.scc.workspace.allowHostPath=true` |
| The same event lists `image volumes are not allowed to be used` | A Nix image's `imageMounts` | `image` in `agent.openshift.scc.workspace.volumes`, on OpenShift 4.22 or newer |
| `<agent>-seccomp-installer` DaemonSet has `DESIRED n / CURRENT 0` | The `privileged` SCC is not granted to its account | `agent.openshift.scc.enabled=true` with `seccomp.backend=installer`, or switch to `spo` |
| `videoDevicePlugin` or `nodePrep` DaemonSet has `DESIRED n / CURRENT 0` | Same, for the DaemonSet's own account | `videoDevicePlugin.openshift.scc.enabled=true`, `nodePrep.openshift.scc.enabled=true` |
| `egressInstaller` pods run but report no conflist to chain, and sessions get no tunnel | OpenShift's CNI configuration is a Multus `.conf`, which the installer cannot chain into | Not supported; disable it |

Anything else: [Troubleshooting](../../reference/troubleshooting.md).

## Decisions

- [ ] `kasm-helm.isOpenshift=true` and the Routes, from [OpenShift Route](../networking/openshift-route.md).
- [ ] Root mode chosen: `agent.workspaceSecurity.rootMode` `userns` (OpenShift 4.20+, no NFS profiles for root images), `host`, or `forbid`.
- [ ] `agent.openshift.scc.enabled=true`; `allowHostPath`, `allowPrivileged`, `capabilities` and `volumes` widened only for what the catalog needs.
- [ ] Seccomp backend chosen: `spo` (SPO installed) or `installer` (`privileged` SCC granted by the same switch).
- [ ] Webcams: `nodePrep.modules.v4l2loopback.method=kmm`, `videoDevicePlugin.openshift.scc.enabled=true`.
- [ ] Nix images: OpenShift 4.22 or newer, `image` in the SCC's `volumes`.
- [ ] `egressInstaller.enabled=false`.
- [ ] Sessions verified under the workspace SCC and the agent under `restricted-v2`.
