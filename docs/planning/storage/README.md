> **Applies to:** both halves · **Charts/values:** `nfs-server-provisioner.*`, `csiRclone.*`, `agent.storageMappings.*`, `kasm-helm.database.storage`

# Storage

## Persistent profiles

The profile is a PVC the operator attaches to every session a user launches. The access mode
decides the scheduling story.

| Choice | When | Values |
| ------ | ---- | ------ |
| An existing **RWX** class — EFS, Azure Files/ANF, Filestore, ODF/CephFS, NFS | Production. Shared profiles need `ReadWriteMany`. | none — point Kasm at the class name |
| **RWO** (EBS, PD, Azure Disk, local-path) | Single-node-affine profiles only | none — but the PVC pins every future session to that node |
| The bundled in-cluster NFS server | A cluster with no RWX driver; a starting point, not a plan | `nfs-server-provisioner.enabled=true` **and** `nfs-server-provisioner.persistence.enabled=true` — without the second, profiles are lost when the NFS pod restarts |

Pick the performance tier deliberately: a browser profile is a many-small-files workload, which is
NFS's worst case. Procedure: [RWX storage for profiles](rwx-profiles.md).

## User storage mappings (rclone / S3 / Drive)

Two values, always — the driver alone mounts nothing and the agent flag alone points at a driver
that is not there:

```yaml
csiRclone:
  enabled: true
agent:
  storageMappings:
    enabled: true
    installationID: <scopes the derived StorageClass and Secret names>
```

The cluster must supply **FUSE on every session node** (`/dev/fuse` present, module loaded); no
chart builds or loads it. `csiRclone` is cluster-scoped — one release per cluster. Procedure:
[Cloud storage mappings (rclone CSI)](cloud-mappings.md).

## Recordings

Session recording is a **licensed** Kasm feature. Without the entitlement, sessions start with the
recorder disabled even when the upload location and the `record_sessions` group setting are both
configured; the API logs *"Session recording is configured but not licensed"*. Confirm the licence
before budgeting for any of the below.

Recording buffers on the **session pod's ephemeral storage** until it uploads —
`KasmWorkspace.spec.recordingBufferSize`, `3Gi` by default, with the operator seeding the
container's ephemeral-storage request/limit to cover it. It survives a container restart, not pod
loss: an evicted or OOM-killed pod loses an in-flight recording. Nothing mounts a PVC at
`/opt/kasm/recordings` automatically.

Plan for it: budget the ephemeral floor per concurrent recorded session into the node disk
([3.3](../capacity.md#the-four-ceilings)), configure the upload location and object-storage credentials on the
control plane, and make sure workspace pods can reach the Kasm API Service — and the bucket — if
`networkPolicies.enabled=true`.

## The node image store

`80GB + (users × space_per_user)` on the volume backing the container runtime's image store, not on
the root filesystem in general. Image GC at `imageGCHighThresholdPercent: 90` /
`imageGCLowThresholdPercent: 80` — a kubelet setting no chart can make, and one worth aligning with
the agent's own `disk_usage_limit: 0.90`. See
[kasm-agent → Node sizing](../../../charts/kasm-agent/README.md#node-sizing).

Pre-pulling changes the launch experience, not the arithmetic. The operator creates a
`KasmImagePuller` from the manager's own image list without being asked; `agent.imagePuller.enabled`
and `agent.imagePuller.images` stage extra images regardless, and
`agent.imageAvailabilityPolicy` (`all` or `any`) decides when an image counts as available. It
needs the container runtime socket from a DaemonSet — impossible on serverless node pools.
Procedure: [Private registries and image pulling](../registries.md).

**Decisions**

- [ ] RWX class identified (or RWO accepted, with the node-pinning consequence understood).
- [ ] If using the bundled NFS server: `persistence.enabled=true`, and it is understood to be a single point of failure.
- [ ] Storage mappings decided; if yes, FUSE confirmed on every session node and `csiRclone` enabled in exactly one release.
- [ ] Recording decided; buffer size, ephemeral floor, upload target and egress path all planned.
- [ ] Image-store volume sized with Kasm's formula; kubelet image-GC thresholds set on the node.
- [ ] Pre-pull strategy chosen, and the runtime socket confirmed reachable from a DaemonSet.

---

## Procedures

* [RWX storage for profiles](rwx-profiles.md) — the shared filesystem persistent profiles need.
* [Cloud storage mappings](cloud-mappings.md) — the rclone CSI driver for per-user S3 / Drive mounts.

## The control-plane half

The control plane holds storage of its own, separate from anything sessions use:

* **The database** — `kasm-helm.database.storage` when the bundled PostgreSQL runs in-cluster.
  See [Database](../database.md).
* **Backups** — `kasm-helm.dbManagement` writes to its own PVC. See
  [Backup and restore](../../operate/backup-restore.md).
* **Guacamole recordings** staged before upload, on the control-plane side rather than the agent's.
