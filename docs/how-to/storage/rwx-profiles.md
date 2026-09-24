# RWX storage for persistent profiles

> **Applies to:** agent · **Charts/values:** `agent.persistentProfiles.storageClass`, `agent.persistentProfiles.accessModes`, `agent.persistentProfiles.capacity`, `agent.workspaceSecurity.rootMode`, `agent.workspaceSecurity.rootFeatures`, `nfs-server-provisioner.enabled`, `nfs-server-provisioner.persistence.enabled`, `nfs-server-provisioner.persistence.storageClass`, `nfs-server-provisioner.persistence.size`, `nfs-server-provisioner.storageClass.create`, `nfs-server-provisioner.storageClass.name`, `nfs-server-provisioner.storageClass.reclaimPolicy`, `nfs-server-provisioner.storageClass.mountOptions`

## Why this is needed

A Kasm persistent profile is a PVC the operator attaches to every session a user launches. With a
`ReadWriteOnce` class that PVC binds to one node, so the user's next session must land on that same
node or fail to start. **Shared** profiles - the same profile mounted by more than one session, or a
session that must be schedulable anywhere - need a `ReadWriteMany` StorageClass. No chart value
creates the profile itself: `spec.profiles` on the `KasmWorkspace` comes from the Kasm manager,
which sends only the profile path. The class, access modes and size of every profile PVC are the
agent's defaults, `agent.persistentProfiles`; left empty, the cluster's default StorageClass,
`ReadWriteOnce` and `10Gi` apply. The charts' job here is making an RWX class exist and naming it
there.

### NFS profiles and root sessions

A session that runs as root does so, by default, as host root
(`agent.workspaceSecurity.rootMode: host`), and NFS profiles work on it as on any other pod. This
section applies only once root sessions are locked down into a pod user namespace
(`rootMode: userns`), where every volume on the pod is idmap-mounted. The NFS client cannot do
that: a root session with an NFS-backed profile is admitted and scheduled, then fails to create its
container with a `mount_setattr` / `idmap` error. That covers the bundled `nfs-server-provisioner`,
NFS-CSI, Amazon EFS and GCP Filestore. Ordinary uid-1000 sessions, which is most of a stock catalog,
are unaffected, unless `workspaceSecurity.userNamespaces` is `always`.

Under `rootMode: userns`, for an image that needs root (a `user: root` run config, root
`exec_configs`, session recording) and a user who needs their profile on it, pick one:

| Option | Trade-off |
| ------ | --------- |
| An S3 profile (the manager's S3-style persistent profiles) | Nothing is mounted, so nothing to idmap; the profile syncs at session start and stop |
| A block-storage class (ext4 or XFS on EBS, PD, Azure Disk, Ceph RBD) | Idmap-mounts fine, but `ReadWriteOnce`: the profile pins its user's sessions to one node at a time |
| `agent.workspaceSecurity.rootFeatures: downgrade` | Works only where root is asked for through `exec_configs` or recording, not a `user: root` run config: the session stays at uid 1000, the root commands run as `kasm-user`, recording is off |
| `agent.workspaceSecurity.rootMode: host` (the default) | Root sessions run as host root, with no user namespace and no idmap; a container escape is root on the node |

## Before you start

* A working agent install ([Install on one cluster](../install/one-cluster.md) or [Install in two namespaces](../install/two-namespaces.md)).
* You can create a PVC in the agent namespace.
* Decide which of the two paths you are on: an RWX class the cluster already has, or the bundled
  in-cluster NFS server.

Distro / cloud variants:

| Platform | RWX option that already exists |
| -------- | ------------------------------ |
| k3s | None by default - `local-path` is RWO. Use the bundled NFS provisioner (backed by `local-path`) or an external NFS appliance. |
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

5. **Point the agent's profile defaults at the class.** The manager never names a class, so the
   agent's defaults decide every profile PVC:

   ```yaml
   kasm-agent:
     agent:
       persistentProfiles:
         storageClass: kasm-rwx
         accessModes: [ReadWriteMany]
         capacity: 20Gi                # default 10Gi
   ```

   A `helm upgrade` with these rolls the agent; profile PVCs created afterwards use them, existing
   ones keep what they were created with. Nothing else in the cluster changes: the default
   StorageClass stays whatever it is.

6. **Turn profiles on in the manager, as on any Kasm.** The workspace's *Persistent Profile Path*
   (for example `/profiles/{username}/{image_id}`) and the group's *Allow Persistent Profile*
   setting are Kasm configuration and work the same here
   ([Kasm docs: Workspaces](https://www.kasmweb.com/docs/latest/guide/workspaces.html)). The
   operator turns the path into a PVC of `persistentProfiles.capacity` mounted at the session's home.

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

Then launch a session for a user whose workspace has a persistent profile path and check the PVC
it produced:

```console
kubectl -n kasm-agent get pvc | grep kasm-profile-
```

Expected: one `kasm-profile-<profile name>-<hash>` claim, `Bound`, the size from
`persistentProfiles.capacity`, and its `STORAGECLASS` column showing `kasm-rwx` with `RWX` access.
`local-path` and `RWO` there means the agent's defaults are not set (step 5) or the PVC predates
them. The PVC outlives the session: destroy it, relaunch, and a file written to
the home directory is still there. Then launch two sessions for the same user on different nodes
and confirm both start.

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
| Profile PVCs bind on `local-path` (or another RWO class) although `kasm-rwx` exists | `agent.persistentProfiles.storageClass` is empty, so the cluster default wins | Set it (step 5) and upgrade; existing profile PVCs keep their class |
| `--set nfsServerProvisioner.enabled=true` does nothing | The dependency is un-aliased | Use the kebab-case key: `--set nfs-server-provisioner.enabled=true` (escape the dots as needed) |
| NFS pods `CrashLoopBackOff` on OpenShift | The provisioner needs an SCC it does not have | Use ODF/CephFS instead |
| A session for a root-needing image stays `ContainerCreating` or `CreateContainerError`, events mention `mount_setattr` and `idmap`; the same user's other sessions start | It is a `userns-root` session (`kubectl get pod -L kasm.com/run-mode`) and its profile is NFS-backed, which cannot be idmap-mounted into a user namespace | One of the options in [NFS profiles and root sessions](#nfs-profiles-and-root-sessions) |

## Decisions

- [ ] Cluster inventory taken (`kubectl get storageclass`, `kubectl get csidriver`)
- [ ] An RWX StorageClass exists - cloud-native or `nfs-server-provisioner.enabled=true`
- [ ] If bundled: `nfs-server-provisioner.persistence.enabled=true` with a backing `storageClass` and `size`
- [ ] `nfs-server-provisioner.storageClass.name` chosen and recorded
- [ ] Test PVC with `accessModes: [ReadWriteMany]` reaches `Bound`
- [ ] `agent.persistentProfiles.storageClass` names the RWX class, `accessModes` is `[ReadWriteMany]`, `capacity` chosen
- [ ] Persistent Profile Path set on the workspace and allowed for the group, in the manager
- [ ] A launched session's `kasm-profile-*` PVC shows the RWX class
- [ ] Two concurrent sessions for the same user start on different nodes
- [ ] On an NFS-backed class under `rootMode: userns`: root-needing images either get S3 or block profiles, `rootFeatures: downgrade`, or `rootMode: host` (the default)
