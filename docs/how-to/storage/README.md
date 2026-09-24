# Storage

> **Applies to:** both halves

Two procedures cover what sessions need from storage; the rest is a pointer.

| Page | Task | Key values |
| ---- | ---- | ---------- |
| [RWX storage for persistent profiles](rwx-profiles.md) | A `ReadWriteMany` class for shared profiles: the cloud's own, or the bundled NFS server | `nfs-server-provisioner.enabled`<br>`nfs-server-provisioner.persistence.enabled` |
| [Cloud storage mappings](cloud-mappings.md) | The rclone CSI driver for per-user S3, Drive and similar mounts | `csiRclone.enabled`<br>`agent.storageMappings.enabled` |

**NFS and root sessions.** A session whose image needs root runs, by default, as host root
(`agent.workspaceSecurity.rootMode: host`), and every volume works on it. Locked down to root inside
a pod user namespace (`rootMode: userns`), it cannot mount an NFS-backed volume (the bundled NFS
server, NFS-CSI, EFS, Filestore): the container fails to create with a `mount_setattr` / `idmap`
error. On a runc node it cannot mount an OCI image volume either (a Nix image's `imageMounts`:
`id-mapped mounts are only supported for bind-mounts`). uid-1000 sessions are unaffected. Under
`userns`, for root-needing images use S3 profiles or block storage, `rootFeatures: downgrade` where
only root commands or recording ask for root, or go back to `rootMode: host`
([RWX storage for persistent profiles](rwx-profiles.md#nfs-profiles-and-root-sessions)).
**Recordings** are a licensed Kasm feature; without the entitlement, sessions start with the
recorder off and the API logs "Session recording is configured but not licensed". A recording
buffers on the session pod's ephemeral storage (`KasmWorkspace.spec.recordingBufferSize`, `3Gi` by
default) until it uploads; it survives a container restart, not pod loss. Budget the floor per
recorded session into node disk ([Capacity](../../explanation/capacity.md#the-four-ceilings)), and
if `networkPolicies.enabled=true` let workspace pods reach the Kasm API Service and the bucket.

**The node image store** is `80GB + (users × space_per_user)` on the volume backing the container
runtime, with kubelet image GC at 90/80 percent, a setting no chart can make
([Node tuning and swap](../nodes/tuning-and-swap.md)). Pre-pulling changes the launch experience,
not the arithmetic: [Registries and airgap](../registries-and-airgap.md).

**The control plane** holds storage of its own: the bundled database on `kasm-helm.database.storage`
([Database](../database.md)) and backups on the `kasm-helm.dbManagement` PVC
([Day 2](../day-2.md#backup)).
