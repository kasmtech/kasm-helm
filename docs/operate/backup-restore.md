> **Applies to:** the control plane's database, and everything else holding state · **Charts/values:** `kasm-helm.dbManagement.*`, `kasm-helm.database.*`

# Backup and restore

## What is stateful, and what is not

| Stateless — rebuild freely | Stateful — plan for it |
| -------------------------- | ---------------------- |
| The agent Deployment and the session proxy (the operator recreates both from the `Agent` CR) | The control-plane database — the entire configuration: users, groups, images, zones, settings |
| The operator itself | Persistent profile PVCs — they survive `KasmWorkspace` deletion when `persistent: true` |
| The OTel collector (in-flight telemetry only) | **Recordings in flight** — buffered on the session pod's ephemeral storage; a lost pod loses them |
| The DaemonSets, apart from node-wide `tuning.*` state | Node-wide state `nodePrep.tuning.*` leaves behind: swap stays active and sysctls stay raised after `helm uninstall` |

Back up the control-plane database — `kasm-helm.dbManagement.backupCron.enabled` with a schedule and
a PVC, plus the manifests in `examples/db-backup.yaml` and `examples/db-restore.yaml`. Draining a
node for maintenance destroys the sessions on it; drain the sessions first if recordings matter.
Rolling back `nodePrep.tuning.swap` has its own reversed order —
[Node tuning and swap](../planning/nodes/tuning-and-swap.md#steps), step 7.

**Decisions**

- [ ] Upgrade order documented for whoever runs it: CRDs → operator → agent.
- [ ] Version-lockstep rule owned, including the `kasm-platform` `Chart.yaml` pin and `manager/agent_version`.
- [ ] CRD upgrade path chosen and written down (Helm release, or `kubectl apply --server-side`).
- [ ] "Never `helm rollback` the CRD release" understood by everyone with upgrade rights.
- [ ] Uninstall runbook — custom resources first — stored somewhere findable.
- [ ] Control-plane database backups configured and a restore actually rehearsed.
- [ ] Node-drain procedure accounts for in-flight sessions and recordings.
- [ ] Node-wide `tuning.*` rollback order known before it is ever enabled.

---

## Backing up the database

`kasm-helm.dbManagement` runs backups as a CronJob against its own PVC, and restores from one. The
worked examples are checked in:

* [`examples/db-backup.yaml`](../../examples/db-backup.yaml) — scheduled backup to the management PVC.
* [`examples/db-restore.yaml`](../../examples/db-restore.yaml) — restore from a backup already on that PVC.
* [`examples/db-upload.yaml`](../../examples/db-upload.yaml) — load a dump taken elsewhere, which is
  also the path in from a Docker-based Kasm.

An **external** database (`database.standalone=true`) is backed up by whatever runs it; the chart's
backup machinery does not reach it. See [Database](../planning/database.md).
