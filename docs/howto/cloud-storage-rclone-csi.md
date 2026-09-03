# Cloud storage mappings (rclone CSI)

> **Applies to:** [Feature matrix](../feature-matrix.md) row 3 (Cloud storage mappings — rclone / S3 / Drive) · **Charts/values:** `csiRclone.enabled`, `agent.storageMappings.enabled`, `agent.storageMappings.installationID`, `csiRclone.driver.name`, `csiRclone.storageClasses`, `csiRclone.node.nodeSelector`

## Why this is needed

Kasm cloud storage mappings mount an rclone remote (S3, GCS, Azure Blob, WebDAV, SFTP, Drive) into a
session at launch. On Kubernetes that mount is performed by the Veloxpack rclone CSI driver, whose
node plugin uses **FUSE** on the host. Two things must both be true: the driver has to be installed,
and the agent has to be told to ask for it. Setting one alone fails quietly — the driver mounts
nothing nobody requested, and the agent flag alone points `KASM_RCLONE_CSI_ENABLED` at a driver that
is not there.

## Before you start

* A working agent install, and the ability to `helm upgrade` it.
* **FUSE on every node that runs sessions.** Most distributions ship `fuse` in-tree; you need
  `/dev/fuse` present and the module loaded.
* The rclone CSI driver is **cluster-scoped** — enable `csiRclone` in at most one release per
  cluster, and leave it off if the driver is already installed by something else
  ([Scope](../../charts/kasm-agent/README.md#scope)).
* The remote's credentials, as an rclone INI stanza. The operator keeps them in a Secret; they never
  appear in the `KasmWorkspace` CR or the StorageClass.

Distro / cloud variants for FUSE:

| Platform | Notes |
| -------- | ----- |
| k3s | `fuse` is in-tree on the usual host distros; `/dev/fuse` is present. Verified. |
| kubeadm / vanilla | `modprobe fuse` on each node, and persist it (`/etc/modules-load.d/fuse.conf`). |
| EKS (AL2023 / Bottlerocket) | AL2023 has `fuse`. Bottlerocket is locked down — verify before committing. |
| AKS (Ubuntu) / GKE (COS, Ubuntu) | `/dev/fuse` present by default. |
| OpenShift (RHCOS) | `fuse` present; the CSI node plugin needs an SCC that permits privileged/`hostPath`. |

`kasm-node-prep` does **not** build or load `fuse` — it is not one of `nodePrep.modules.*`. Treat
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
       installationID: kasm-prod    # optional; scopes derived StorageClass/Secret names
   ```

3. **Upgrade the release.**

   ```console
   helm upgrade --install kasm-agent charts/kasm-agent \
     -n kasm-agent -f values.yaml
   ```

4. **Configure the mapping in the Kasm manager** (Admin → Storage Providers / storage mappings). The
   operator derives one cluster-scoped StorageClass per unique rclone backend, keyed by a hash of the
   rclone INI, and creates the credential Secret itself. You do **not** need
   `csiRclone.storageClasses` for Kasm mappings — that pass-through list is only for StorageClasses
   you want to declare yourself.

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
* After a mapping is configured in the manager, `kubectl get sc` shows a class with
  `PROVISIONER` = `rclone.csi.veloxpack.io`.
* Launch a session with the mapping attached; the remote's contents appear at the mapped path.

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
| Credentials appear stale after rotating the remote | The StorageClass is keyed by a hash of the rclone INI — a changed INI is a new backend | Re-save the mapping in the manager and relaunch sessions |

## Checklist

- [ ] `/dev/fuse` and the `fuse` module confirmed on every session node
- [ ] `csiRclone.enabled=true` in exactly one release in this cluster
- [ ] `agent.storageMappings.enabled=true`
- [ ] `kubectl get csidriver rclone.csi.veloxpack.io` returns the object
- [ ] Node-plugin DaemonSet Running on every session node
- [ ] Mapping configured in the Kasm manager, derived StorageClass visible
- [ ] A session launches with the remote mounted
