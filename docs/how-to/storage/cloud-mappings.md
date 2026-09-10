# Cloud storage mappings (rclone CSI)

> **Applies to:** agent · **Charts/values:** `csiRclone.enabled`, `agent.storageMappings.enabled`, `agent.storageMappings.installationID`, `csiRclone.driver.name`, `csiRclone.storageClasses`, `csiRclone.node.nodeSelector`

## Why this is needed

Kasm cloud storage mappings mount an rclone remote (S3, GCS, Azure Blob, WebDAV, SFTP, Drive) into a
session at launch. On Kubernetes that mount is performed by the Veloxpack rclone CSI driver, whose
node plugin uses **FUSE** on the host. Two things must both be true: the driver has to be installed,
and the agent has to be told to ask for it. Setting one alone fails quietly - the driver mounts
nothing nobody requested, and the agent flag alone points `KASM_RCLONE_CSI_ENABLED` at a driver that
is not there.

## Before you start

* A working agent install, and the ability to `helm upgrade` it.
* **FUSE on every node that runs sessions.** Most distributions ship `fuse` in-tree; you need
  `/dev/fuse` present and the module loaded.
* The rclone CSI driver is **cluster-scoped** - enable `csiRclone` in at most one release per
  cluster, and leave it off if the driver is already installed by something else
  ([Scope](../../../charts/kasm-agent/README.md#scope)).
* The remote's credentials, as an rclone INI stanza, entered in the manager. The operator writes
  them into a per-session Secret that the CSI driver reads. The same stanza, credentials included,
  is also carried in `KasmWorkspace.spec.storageMappings[].config.configData` today, so anyone who
  can read `KasmWorkspace` resources in the agent namespace can read them; scope that RBAC
  accordingly.

Distro / cloud variants for FUSE:

| Platform | Notes |
| -------- | ----- |
| k3s | `fuse` is in-tree on the usual host distros; `/dev/fuse` is present. Verified. |
| kubeadm / vanilla | `modprobe fuse` on each node, and persist it (`/etc/modules-load.d/fuse.conf`). |
| EKS (AL2023 / Bottlerocket) | AL2023 has `fuse`. Bottlerocket is locked down - verify before committing. |
| AKS (Ubuntu) / GKE (COS, Ubuntu) | `/dev/fuse` present by default. |
| OpenShift (RHCOS) | `fuse` present; the CSI node plugin needs an SCC that permits privileged/`hostPath`. |

`kasm-node-prep` does **not** build or load `fuse` - it is not one of `nodePrep.modules.*`. Treat
FUSE as a node-image prerequisite.

## Steps

1. **Confirm FUSE on the nodes.** Per node, over SSH:

   ```console
   lsmod | grep -i fuse
   test -e /dev/fuse && echo "/dev/fuse present"
   ```

   Or from inside the cluster, one node at a time:

   ```console
   kubectl debug node/<node> -it --image=busybox -- \
     sh -c 'ls -l /host/dev/fuse; grep -c fuse /host/proc/filesystems'
   ```

   If it is missing: `modprobe fuse` and add it to `/etc/modules-load.d/fuse.conf`.

2. **Turn on both halves.**

   ```yaml
   csiRclone:
     enabled: true
   agent:
     storageMappings:
       enabled: true
       installationID: kasm-prod    # optional; scopes the names of the per-session volumes and Secrets
   ```

3. **Upgrade the release.**

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
     -n kasm-agent -f values.yaml
   ```

4. **Configure the mapping in the Kasm manager** (Admin → Storage Providers / storage mappings).
   For every session that carries a mapping the operator binds a static PersistentVolume and
   claim pair (`<workspace>-<mount>-sm-pv`, `<workspace>-<mount>-sm`) to the rclone CSI driver and
   writes the rclone configuration into a Secret beside them (`<workspace>-<mount>-sm-config`);
   all three go when the session does. No StorageClass is created. You do **not** need
   `csiRclone.storageClasses` for Kasm mappings - that pass-through list is only for StorageClasses
   you want to declare yourself.

   Three manager-side rules decide whether the mapping ever reaches a session:

   * **Use a Custom provider for S3-compatible storage that is not AWS.** The built-in S3 provider
     validates by running a live AWS `ListBuckets` when the mapping is created, so MinIO, Ceph RGW
     and Cloudflare R2 are rejected before anything is saved. Create a **Custom** storage provider
     instead, with `volume_config.driver: rclone` and the same `driver_opts` you would have given
     the built-in one - `type: s3`, `s3-provider`, `s3-endpoint`, `s3-region`, the access keys, and
     `path` set to the bucket. That path skips the validation call and mounts end to end.
   * **One storage provider per distinct mount path.** The per-mapping `target` is not persisted:
     every mapping on a provider mounts at that provider's `default_target`. Point two mappings at
     one provider and they collide - the second lands at a hash-suffixed path instead. Per-mapping
     `read_only` *is* honoured.
   * **User-scoped mappings need a group setting.** A mapping assigned to a *user* rather than to a
     group or an image is dropped silently unless that user's group has `allow_user_storage_mapping`
     enabled; the API logs *"User-based storage mappings defined but not allowed via group
     settings"*. A user mapping also disqualifies the session from pre-staging (*"User storage
     mappings eliminates request from session staging"*). Group- and image-scoped mappings need
     nothing extra.

5. **Restrict the node plugin** to session nodes if sessions are pinned:

   ```yaml
   csiRclone:
     node:
       nodeSelector:
         kasm-workspaces: "true"
   ```

## Verify

```console
kubectl get csidriver rclone.csi.veloxpack.io
kubectl get daemonset -A | grep -i rclone
kubectl get pods -A -o wide | grep -i rclone
```

Expected indicators:

* `kubectl get csidriver rclone.csi.veloxpack.io` returns the object (not `NotFound`).
* The node-plugin DaemonSet reports `DESIRED == READY`, with a pod **Running on every node that
  runs sessions**.
* Launch a session with the mapping attached; the remote's contents appear at the mapped path,
  and beside the session:

  ```console
  kubectl -n kasm-agent get pv,pvc,secret | grep -- '-sm'
  ```

  Expected: a PersistentVolume `kasm-<workspace>-<mount>-sm-pv` (`RWX`, `Retain`), a claim
  `<workspace>-<mount>-sm` `Bound` to it, and a Secret `<workspace>-<mount>-sm-config`, where
  `<mount>` is the mount path with its slashes turned into dashes (`/mnt/minio` gives
  `mnt-minio`). Inside the pod, `mount | grep rclone` shows the remote on the mapped path as
  `fuse.rclone`. All three objects are removed with the session.

## Chart values

Under the `kasm-platform` umbrella:

```yaml
kasm-agent:
  csiRclone:
    enabled: true
  agent:
    storageMappings:
      enabled: true
      installationID: kasm-prod
```

Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `csiRclone:` / `agent:`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Mapping configured in the manager, nothing mounts, no PVC created | `agent.storageMappings.enabled` is `false` | Set it; both values are required |
| PVC created but the session pod stays `ContainerCreating`, events show `driver name rclone.csi.veloxpack.io not found` | The CSI driver is not installed in this cluster | `csiRclone.enabled=true` (in exactly one release) |
| Mount fails on some nodes only, events mention `fuse` or `/dev/fuse` | FUSE missing on those nodes | `modprobe fuse` + persist; or keep sessions off those nodes with `agent.workspacesNodeSelector` |
| `CSIDriver "rclone.csi.veloxpack.io" already exists` on install | A second release also sets `csiRclone.enabled=true` | Leave it enabled in one release only |
| Creating an S3 mapping fails validation against MinIO / Ceph RGW / R2 | The built-in S3 provider runs a live AWS `ListBuckets` at create time | Use a **Custom** provider with `volume_config.driver: rclone` and the same `driver_opts` |
| Two mappings on one provider, the second mounts at an unexpected hash-suffixed path | The per-mapping `target` is not persisted - the provider's `default_target` wins | One storage provider per distinct mount path |
| A user-assigned mapping never appears in the session; the API logs "not allowed via group settings" | The user's group does not have `allow_user_storage_mapping` | Enable that group setting, or scope the mapping to the group or the image instead |
| Credentials appear stale after rotating the remote | Each session's Secret is written at launch from the mapping as saved in the manager | Re-save the mapping in the manager and relaunch sessions |

## Decisions

- [ ] `/dev/fuse` and the `fuse` module confirmed on every session node
- [ ] `csiRclone.enabled=true` in exactly one release in this cluster
- [ ] `agent.storageMappings.enabled=true`
- [ ] `kubectl get csidriver rclone.csi.veloxpack.io` returns the object
- [ ] Node-plugin DaemonSet Running on every session node
- [ ] Mapping configured in the Kasm manager; a session's `-sm` PV, PVC and Secret appear at launch
- [ ] RBAC on `KasmWorkspace` resources reviewed, since the rclone stanza is readable there
- [ ] Non-AWS S3 endpoints configured as a **Custom** provider (`volume_config.driver: rclone`)
- [ ] One storage provider per distinct mount path
- [ ] User-scoped mappings only where the group has `allow_user_storage_mapping` enabled
- [ ] A session launches with the remote mounted
