# Day 2: upgrade, uninstall, backup, restore

> **Applies to:** both halves

## Before you start

- Know which release owns the CRDs: the operator chart's `crds/` directory, or a `kasm-agent-crds`
  release ([Install the CRDs as their own release](install/crds.md)).
- Read the target version's `charts/kasm-helm/CHANGELOG.md` for the Postgres major it ships and
  anything it needs set before the upgrade.
- Know what is stateful. The control-plane database is the deployment; persistent-profile PVCs
  outlive their sessions; an in-flight recording lives on the session pod's ephemeral storage and
  dies with the pod; `nodePrep.tuning.*` leaves swap active and sysctls raised on the node after
  `helm uninstall`. The agent Deployment, the session proxy, the operator and the collector are
  stateless and rebuilt from the `Agent` resource.

## Steps

### Upgrade the control plane

A Kasm version bump is a database migration, and the chart drives it. On `helm upgrade` with
`dbManagement.upgrade.enable: true`, in order:

1. **Pre-upgrade hooks.** A PVC `<release>-<version>-db-pre-upgrade-backup` (5 Gi, on
   `backupStorageClass` or the default class), then a Job that `pg_dump`s the current database,
   minus the `logs` table data, to `/data/kasm-db-dump/<oldDbBackupFileName>` on it. `helm upgrade`
   blocks until that dump exists.
2. **The new manifests.** The bundled database is a StatefulSet named per Kasm version
   (`<release>-db-1-19-0`), so the new version starts an empty database on the Postgres major it
   ships. The previous StatefulSet is removed; its PVC is kept.
3. **The upgrade Job.** Its `db-major-version-is-ready` init container waits for the database to
   answer at the expected major. Then, if a `settings` table exists, the Job runs the schema
   migration in place; if not, it `pg_restore`s the dump first, then migrates. The pods roll after it.

So for the bundled database the dump is how the data moves, which is why the chart refuses
`skipBackupAndRestore` there. For an external database the dump is a safety copy and the migration
runs in place.

1. **Values for the upgrade.** `initialize` and `upgrade.enable` cannot both be true; the render
   fails with the reason.

   ```yaml
   kasm-helm:
     dbManagement:
       initialize: false               # the database exists now
       upgrade:
         enable: true                  # only while the Kasm version changes
         oldDbBackupFileName: kasm_dump.tar
         backupStorageClass: ""        # a class that can bind 5 Gi; empty = the default class
         oldDbHostname: ""             # see below
         oldDbSecretsName: ""          # only if the previous release kept credentials under another name
   ```

   `oldDbHostname` is the Service the backup Job dumps from. It defaults to `kasm-db`, which is
   only right when the release is named `kasm`; for any other release name set it to
   `<release>-db`. With an external database leave it empty; `database.hostname` is used.

2. **Run the upgrade**, a strict `helm upgrade` rather than `--install`, with a timeout that covers
   the dump:

   ```console
   helm upgrade kasm oci://registry-1.docker.io/kasmweb/kasm-platform --version <new version> \
     -n kasm -f values.yaml --timeout 15m
   ```

   Installing `kasm-helm` directly, use its chart and drop the `kasm-helm:` key from the values.

3. **External database on a new Postgres major.** The chart's expected major changes with the Kasm
   version (16 for 1.19). Two ways through, both exercised by this repository's upgrade tests:

   - Let the chart back up, then upgrade the server while the upgrade Job's init container is
     waiting: it polls `database.hostname` until the new major answers, and the migration runs
     against the carried-over data. `pg_upgrade` or a managed provider's major-version upgrade fits
     here.
   - Upgrade the server yourself first (dump, new major, restore), then run `helm upgrade` with
     `skipBackupAndRestore: true`, and the Job runs only the schema migration. Same major, nothing
     to do: the migration runs in place either way.

4. **Afterwards.** Set `upgrade.enable: false` again so routine `helm upgrade`s do not re-run the
   hooks; keep `initialize: false` for the life of the deployment. Delete the previous version's
   database PVC and the pre-upgrade backup PVC only after the verification below and a real login.

5. **Rolling back** after the migration ran is not `helm rollback`: the old pods cannot run on the
   new schema. Reinstall the previous chart version with `initialize: false`, then load the
   pre-upgrade dump with [`examples/db-upload.yaml`](../../examples/db-upload.yaml). Keep the dump
   until you are sure.

### Upgrade the agent stack


1. **Order: CRDs, then operator, then agent.** A new operator expects its new schema, so the CRDs
   must accept the fields it writes before it starts. With a `kasm-agent-crds` release:

   ```console
   helm upgrade kasm-agent-crds oci://registry-1.docker.io/kasmweb/kasm-agent-crds -n kasm-system
   helm upgrade kasm oci://registry-1.docker.io/kasmweb/kasm-platform -n kasm -f values.yaml
   ```

   Without one, apply the schemas out of band first; `helm upgrade` never touches a `crds/` CRD:

   ```console
   kubectl apply --server-side -f charts/kasm-agent-operator/crds/
   helm upgrade kasm oci://registry-1.docker.io/kasmweb/kasm-platform -n kasm -f values.yaml
   ```

   In the normal case the operator and the agent are one release (the `kasm-agent` umbrella carries
   both); they separate only where a second agent runs with `operator.enabled=false`, and then the
   operator's release goes first.

2. **Keep the versions in step.** `kasm-platform` pins both dependency versions in its `Chart.yaml`;
   the control plane's `manager/agent_version` setting gates which agent builds it accepts, so an
   agent image tag out of step with the control plane shows up as a **registration failure**, not a
   runtime error. `make version-check-agent` enforces the pins in this repository.

3. **Never `helm rollback` the CRD release.** It reinstates an older schema underneath objects
   stored in the newer one and the API server prunes the extra fields, silently. Roll forward.

### Uninstall

Two steps, always, for anything with an `Agent`. `helm uninstall` would delete the `Agent` and
`KasmWorkspace` resources and the operator that clears their finalizers at the same time; the
deletions hang, and a later operator install processes the stale deletion and tears things down.

```console
kubectl delete kasmworkspaces.agent.kasm.com --all -n kasm --wait   # ends live sessions
kubectl delete agents.agent.kasm.com --all -n kasm --wait
helm uninstall kasm -n kasm
```

What survives, by design: the CRDs (Helm never removes a `crds/` CRD, and the `kasm-agent-crds`
templates carry `helm.sh/resource-policy: keep`), the control plane's PersistentVolumeClaims (the
database, any backup volume) and its credentials Secret (a pre-install hook). Delete them
deliberately, once you are sure; deleting a CRD cascades to every custom resource of that kind in
every namespace. Deleting the namespace is what makes the next install fresh, because it removes
the database PVC and the preseed applies again.

### Backup

The bundled database (`kasm-helm.database.standalone: false`) is backed up by the chart's own
CronJob to its own PVC:

```yaml
kasm-helm:
  dbManagement:
    backupCron:
      enabled: true
      schedule: "0 2 * * *"
```

A one-off backup is the checked-in Job [`examples/db-backup.yaml`](../../examples/db-backup.yaml),
deployed in the release namespace. An **external** database (`standalone: true`) is backed up by
whoever runs it; the chart's machinery does not reach it.

### Restore

- From a backup on the management PVC: [`examples/db-restore.yaml`](../../examples/db-restore.yaml).
- From a dump taken elsewhere, including a Docker-based Kasm:
  [`examples/db-upload.yaml`](../../examples/db-upload.yaml).

Both run against the bundled database in the release namespace. Rehearse one before it matters.

### Node maintenance

Draining a node destroys the sessions on it; drain the sessions first if recordings matter. Rolling
back `nodePrep.tuning.swap` has its own reversed order, chart off first, then `swapoff`, then the
kubelet setting: [Node tuning and swap](nodes/tuning-and-swap.md#steps).

## Verify

After a control-plane upgrade:

```console
kubectl get jobs -n kasm -l app.kubernetes.io/component=pre-upgrade-backup
kubectl get jobs -n kasm -l app.kubernetes.io/component=db-upgrade
kubectl get pvc -n kasm
kubectl logs -n kasm -l app.kubernetes.io/component=db-upgrade --tail=5
kubectl get pods -n kasm
curl -k -o /dev/null -w '%{http_code}\n' https://<address>/
```

Expected: both Jobs `1/1` complete; the pre-upgrade backup PVC `Bound` beside the new
`<release>-db-<version>` PVC; the upgrade log ending in the schema migration, after either
`Database exists, running upgrade now...` or a `pg_restore`; every pod `Running`; and `200` from the
login page. Then sign in, and launch one session.

After an agent-stack upgrade:

```console
helm list -n kasm
kubectl get agents.agent.kasm.com -n kasm
kubectl get crd agents.agent.kasm.com -o jsonpath='{.metadata.annotations.controller-gen\.kubebuilder\.io/version}{"\n"}'
```

Expected: the new chart version, `PHASE Ready`, and the CRD annotation matching the operator build
you upgraded to.

After an uninstall:

```console
kubectl get agents.agent.kasm.com,kasmworkspaces.agent.kasm.com -A
kubectl get pvc,secret -n kasm
```

Expected: `No resources found` for the custom resources; the database PVC and `kasm-secrets` still
listed until you delete them.

After a backup run:

```console
kubectl get jobs -n kasm | grep -i backup
```

Expected: the most recent backup Job `Complete`.

## Chart values

```yaml
kasm-helm:
  dbManagement:
    initialize: false                 # after the first install, always
    upgrade:
      enable: false                   # true only while the Kasm version changes
      oldDbBackupFileName: kasm_dump.tar
      backupStorageClass: ""
      oldDbHostname: ""               # <release>-db when the release is not named kasm
      oldDbSecretsName: ""
      skipBackupAndRestore: false     # external database only, after upgrading the server yourself
    backupCron:
      enabled: true
      schedule: "0 2 * * *"
```

Installing `kasm-helm` directly, drop the `kasm-helm:` key.

## Troubleshooting

[Troubleshooting](../reference/troubleshooting.md). Specific to this page: an `Agent` deletion that
hangs after `helm uninstall` ran first means the operator is gone; reinstall the operator chart to
reap the finalizer.

## Decisions

- [ ] Control-plane upgrade rehearsed once: `initialize: false`, `upgrade.enable: true`, the dump verified on its PVC, `enable` set back to false afterwards.
- [ ] External database: the Postgres major the target Kasm version expects is known, and which of the two server-upgrade paths applies.
- [ ] Upgrade order documented for whoever runs it: control plane, then CRDs, then operator, then agent.
- [ ] Version-lockstep rule owned, including the `kasm-platform` `Chart.yaml` pins and `manager/agent_version`.
- [ ] CRD upgrade path chosen and written down: Helm release, or `kubectl apply --server-side`.
- [ ] "Never `helm rollback` the CRD release" understood by everyone with upgrade rights.
- [ ] Uninstall runbook, custom resources first, stored somewhere findable.
- [ ] Control-plane database backups configured and a restore rehearsed.
- [ ] Node-drain procedure accounts for in-flight sessions and recordings.
- [ ] Node-wide `tuning.*` rollback order known before it is ever enabled.
