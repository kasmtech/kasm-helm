# RWX storage for persistent profiles

> **Applies to:** agent · **Charts/values:** `nfs-server-provisioner.enabled`, `nfs-server-provisioner.persistence.enabled`, `nfs-server-provisioner.persistence.storageClass`, `nfs-server-provisioner.persistence.size`, `nfs-server-provisioner.storageClass.create`, `nfs-server-provisioner.storageClass.name`, `nfs-server-provisioner.storageClass.reclaimPolicy`, `nfs-server-provisioner.storageClass.mountOptions`

## Why this is needed

A Kasm persistent profile is a PVC the operator attaches to every session a user launches. With a
`ReadWriteOnce` class that PVC binds to one node, so the user's next session must land on that same
node or fail to start. **Shared** profiles - the same profile mounted by more than one session, or a
session that must be schedulable anywhere - need a `ReadWriteMany` StorageClass. No chart value
creates the profile itself: `spec.profiles` on the `KasmWorkspace` comes from the Kasm manager. The
charts' only job here is making an RWX class exist.

## Before you start

* A working agent install ([Install on one cluster](../install/one-cluster.md) or [Install in two namespaces](../install/two-namespaces.md)).
* You can create a PVC in the agent namespace.
* Decide which of the two paths you are on: an RWX class the cluster already has, or the bundled
  in-cluster NFS server.

Distro / cloud variants:

| Platform | RWX option that already exists |
| -------- | ------------------------------ |
| k3s | None by default - `local-path` is RWO. Use the bundled NFS provisioner (verified on k3s, backed by `local-path`) or an external NFS appliance. |
| kubeadm / vanilla | Whatever CSI driver you installed. CephFS/Rook and NFS-CSI are the common RWX ones. |
| EKS | Amazon EFS CSI driver (`efs.csi.aws.com`). EBS is RWO only. |
| AKS | Azure Files (`file.csi.azure.com`), class `azurefile-csi`. Azure Disk is RWO only. |
| GKE | Filestore CSI (`filestore.csi.storage.gke.io`). PD is RWO only. |
| OpenShift | ODF/CephFS. The bundled NFS provisioner needs an SCC that permits its pod - prefer ODF. |

`nfs-server-provisioner` is a **single point of failure** and is a starting point, not a production
storage recommendation. It is also **un-aliased** in `values.yaml` (the upstream chart has no
`nameOverride`), so the key is the kebab-case chart name, not a camelCase alias.

## Steps

1. **Check what the cluster already offers.**

   ```console
   kubectl get storageclass
   kubectl get csidriver
   ```

2. **Path A - use an existing RWX class.** Nothing to install. Skip to *Verify* with the class name
   you found, then go to step 5.

3. **Path B - install the in-cluster NFS server.** Add to your agent values:

   ```yaml
   nfs-server-provisioner:
     enabled: true
     persistence:
       enabled: true          # without this, every profile is lost when the NFS pod restarts
       storageClass: local-path   # the block class the export is carved from
       size: 200Gi
     storageClass:
       create: true
       name: kasm-rwx
       reclaimPolicy: Retain
       mountOptions:
         - vers=4.1
         - noatime
   ```

   `persistence.storageClass` is the *block* class backing the NFS export (`local-path` on k3s,
   `gp3` on EKS, and so on). `storageClass.name` is the *RWX* class Kasm will reference.

4. **Apply it.**

   ```console
   helm upgrade --install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
     -n kasm-agent -f values.yaml
   ```

   Under [kasm-platform](../../../charts/kasm-platform/README.md) the same block nests under
   `kasm-agent:` - see [Chart values](#chart-values).

5. **Point Kasm at the class.** The profile path and its StorageClass are Kasm manager settings
   (workspace / group *Persistent Profile Path* and the zone's storage configuration), not chart
   values. Set the class name from step 2 or 3 there.

## Verify

Create a throwaway RWX claim in the agent namespace:

```console
kubectl -n kasm-agent apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rwx-probe
spec:
  accessModes: [ReadWriteMany]
  storageClassName: kasm-rwx
  resources:
    requests:
      storage: 1Gi
EOF

kubectl -n kasm-agent get pvc rwx-probe
```

Expected indicator: `STATUS` is **`Bound`** within a few seconds. `Pending` means no provisioner
accepted a `ReadWriteMany` claim on that class.

```console
kubectl -n kasm-agent delete pvc rwx-probe
```

Then launch two sessions for the same user on different nodes and confirm both start.

## Chart values

Under the `kasm-platform` umbrella:

```yaml
kasm-agent:
  nfs-server-provisioner:
    enabled: true
    persistence:
      enabled: true
      storageClass: local-path
      size: 200Gi
    storageClass:
      create: true
      name: kasm-rwx
```

Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `nfs-server-provisioner:`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Test PVC stays `Pending`, events say `no persistent volumes available` | The class is RWO-only (EBS, PD, Azure Disk, `local-path`) | Use an RWX driver, or Path B above |
| Profiles empty after a cluster restart | `nfs-server-provisioner.persistence.enabled` left `false` - the export lived on the pod's ephemeral storage | Enable it and set `persistence.storageClass` + `persistence.size`; re-provision |
| Second session for a user stays `Pending` on a node | RWO profile PVC is bound to another node | Move to an RWX class, or pin sessions with `agent.workspacesNodeSelector` |
| `--set nfsServerProvisioner.enabled=true` does nothing | The dependency is un-aliased | Use the kebab-case key: `--set nfs-server-provisioner.enabled=true` (escape the dots as needed) |
| NFS pods `CrashLoopBackOff` on OpenShift | The provisioner needs an SCC it does not have | Use ODF/CephFS instead |

## Decisions

- [ ] Cluster inventory taken (`kubectl get storageclass`, `kubectl get csidriver`)
- [ ] An RWX StorageClass exists - cloud-native or `nfs-server-provisioner.enabled=true`
- [ ] If bundled: `nfs-server-provisioner.persistence.enabled=true` with a backing `storageClass` and `size`
- [ ] `nfs-server-provisioner.storageClass.name` chosen and recorded
- [ ] Test PVC with `accessModes: [ReadWriteMany]` reaches `Bound`
- [ ] The class name is configured in the Kasm manager's profile settings
- [ ] Two concurrent sessions for the same user start on different nodes
