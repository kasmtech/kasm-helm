# Session run modes: what root and non-root sessions can do

> **Applies to:** agent · what each of the three session run modes supports, and where each one stops · **Charts/values:** `agent.workspaceSecurity.rootMode`, `agent.workspaceSecurity.rootFeatures`, `agent.workspaceSecurity.profile`, `agent.workspaceSecurity.sudo`, `agent.workspaceSecurity.userNamespaces`, `agent.workspaceSecurity.supplementalGroups`

Every session pod runs in one of three modes, and carries it as its `kasm.com/run-mode` label.
[Security posture](security-posture.md#session-run-identity) explains why there are three and what
each one is worth against a container escape; this page is the feature list, so you can tell before
a rollout which images and settings need which mode.

| Run mode | Runs as | When |
| -------- | ------- | ---- |
| `nonroot` | `kasm-user`, uid and gid 1000, no privilege escalation, every capability dropped except the profile's | Every session whose image does not ask for root. That is every stock Kasm image |
| `host-root` | uid 0 on the node, the eight capabilities a Kasm root session keeps | An image that asks for root, under `rootMode: host` (the default) |
| `userns-root` | uid 0 inside a pod user namespace (`hostUsers: false`), an unprivileged uid range on the node | An image that asks for root, under `rootMode: userns` |

An image asks for root in one of three ways: its run config sets `user: root` (or `privileged:
true`); its `exec_configs` run a command as root (start and stop commands, and the go and assign
actions the manager runs later); or session recording is on. The first always makes a root session.
For the other two, `rootFeatures` decides: `promote` (the default) runs the session in `rootMode`,
`downgrade` keeps it at uid 1000 and runs those commands as `kasm-user`, with recording off, and
`reject` refuses the launch. Under `rootMode: forbid` there is no root mode: an image whose run config
asks for root fails to launch, and `promote` behaves as `downgrade`.

## Feature by feature

✅ Works · ⚠️ Works with a limit · ❌ Does not work

| Feature | `nonroot` | `host-root` | `userns-root` |
| ------- | --------- | ----------- | ------------- |
| Desktop, browser and app sessions | ✅ | ✅ | ✅ |
| Chromium-based browsers' sandbox | ✅ under `profile: baseline` (the default), which keeps `SYS_CHROOT`. ⚠️ under `profile: restricted`, which drops it | ✅ | ✅ |
| `sudo` inside the session | ⚠️ only with `workspaceSecurity.sudo: true`, which turns privilege escalation and `SETUID`/`SETGID` back on for every uid-1000 session | ✅ | ✅ |
| Run config `user: root` | Not applicable: the image runs in a root mode instead | ✅ | ✅ |
| Run config `privileged: true` | Not applicable | ✅ | ❌ refused at launch |
| Extra capabilities (`cap_add` in the run config) | ✅ under `baseline`. ⚠️ under `restricted`, only `NET_BIND_SERVICE` is kept | ✅ | ✅ confined to the user namespace |
| Root start and stop commands (`exec_configs` with `user: root`) | ⚠️ with `rootFeatures: downgrade`, run as `kasm-user`; a command that genuinely needs root fails inside the session | ✅ | ✅ |
| Go and assign actions run as root after launch | ⚠️ run as `kasm-user` with a warning (`promote`, `downgrade`), or refused (`reject`): a running pod cannot change mode | ✅ | ✅ |
| Session recording | ⚠️ only through promotion to a root mode; with `downgrade` the session runs unrecorded | ✅ | ✅ |
| Writable file mappings | ⚠️ destinations under `$HOME` only; one only root can write is logged and skipped | ✅ | ✅ |
| Persistent profiles on S3 | ✅ | ✅ | ✅ |
| Persistent profiles and storage mappings on NFS or EFS | ✅ | ✅ | ❌ the NFS client cannot idmap-mount; the session fails with `IdmapMountUnsupported` |
| Persistent profiles on block storage (ext4, xfs) | ✅ | ✅ | ✅ |
| Nix images (`imageMounts`) | Not applicable: they ask for root | ✅ | ⚠️ not on nodes whose runtime uses runc, which idmaps bind mounts only |
| NVIDIA GPU: CUDA, NVENC, Vulkan | ✅ | ✅ | ✅ the device files are world-accessible, so their unmapped ownership does not matter |
| DRI GPU (`/dev/dri`): VA-API, EGL | ✅ with the render group added (`supplementalGroups`, or the cluster's DRI groups, which the agent adds) | ✅ | ❌ the device nodes appear as `nobody`, mode 0660; the agent plans no DRI for such a session |
| Webcam (`kasm.com/video`) | ✅ with the node prep chart's default `deviceMode: 0666` | ✅ | ⚠️ opens only because the default `deviceMode: 0666` is world-accessible; with udev's `0660` the device is `nobody`'s, as for DRI |
| Device passthrough by host path | ✅ where the device's group is added | ✅ | ⚠️ owned by `nobody` inside the namespace |
| Inline seccomp profiles | ✅ resolved against the session's own capabilities | ✅ | ✅ |
| Per-session VPN egress | ✅ | ✅ | ✅ the tunnel lives in the pod's network namespace, not its user namespace |
| Highest Pod Security level | `restricted` under `profile: restricted`; `baseline` otherwise | `baseline` on paper, `privileged` in effect | `baseline` |
| OpenShift SCC | `kasm-<ns>-<agent>-workspace` | `kasm-<ns>-<agent>-workspace-root` | `kasm-<ns>-<agent>-workspace-root`, with `userNamespaceLevel: RequirePodLevel` |
| A container escape lands as | uid 1000 on the node | root on the node | an unprivileged, per-pod uid on the node |

## What `userns-root` needs from the cluster

The two uid-0 modes run the same container; only the pod's user namespace differs, so everything
`userns-root` cannot do comes from the node stack:

- Kubernetes 1.33 or newer (user namespaces on by default; GA in 1.36). On OpenShift, 4.20 or newer.
- containerd 2.0 or CRI-O 1.25, with runc 1.2 or crun 1.9.
- A 6.3 or newer kernel on the session nodes, for idmapped `tmpfs`.
- Volumes on local filesystems: ext4, xfs, btrfs, tmpfs, overlayfs. Not NFS or EFS.

A node that cannot do it fails the pod with an event, and nothing in the API says so beforehand. That
is why `rootMode: userns` is a statement about the cluster, and why the default is `host`, which runs
everywhere.

## `userNamespaces: always`

`userNamespaces: always` puts uid-1000 sessions in a user namespace too, as defence in depth. They then
inherit the `userns-root` column's limits (NFS and EFS volumes, runc image volumes, DRI and
host-path devices) without needing root, and on OpenShift the uid-1000 SCC requires a pod user
namespace as well.

## Choosing

- **Keep the defaults** (`rootMode: host`, `rootFeatures: promote`, `profile: baseline`) unless a
  policy requires otherwise. Stock images run as uid 1000; only images that ask for root run as host
  root.
- **`rootMode: userns`** on Kubernetes 1.33+ (OpenShift 4.20+) when no root image needs NFS-backed
  storage, a DRI GPU, or Nix image volumes on runc.
- **`rootMode: forbid`** when no image in the catalog should run as root at all, and in namespaces
  whose Pod Security label enforces `restricted`, where every root session is refused at admission
  anyway.
- **`profile: restricted`** for `restricted` Pod Security, accepting that Chromium's sandbox and any
  capability beyond `NET_BIND_SERVICE` are gone.
