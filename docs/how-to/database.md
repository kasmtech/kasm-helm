# Database

> **Applies to:** control plane · **Charts/values:** `kasm-helm.database.*`, `kasm-helm.dbManagement.*`, `kasm-helm.kasmConfig.*`

## Why this is needed

Kasm keeps everything durable in one PostgreSQL database: users, groups, workspace definitions,
zones, settings, session history. Lose an agent and you lose running sessions; lose the database
and you lose the deployment. Bundled or external is decided before the first install, because
moving between them means a dump and reload.

## Before you start

- **PostgreSQL 16 is a requirement, not a recommendation.** Kasm's schema and migrations assume it.
- Decide between the two:

  | | Bundled (`standalone: false`, the default) | External (`standalone: true`) |
  | --- | --- | --- |
  | Runs as | a StatefulSet in the release, on `database.storage` | wherever you already run PostgreSQL 16 |
  | Backups | the chart's `dbManagement` CronJob to its own PVC | yours |
  | Upgrades | the chart runs the migration Jobs | the chart runs the migration Jobs |
  | Survives | pod loss; not PVC loss | whatever your platform gives you |
  | Best for | evaluation, single-cluster, small deployments | production, HA, an existing DBA team |

- External only: a database and a role that owns it, created by you (the chart creates the schema,
  not the database or the role), and network reach from the cluster. With
  `networkPolicies.enabled=true` the egress path to the database host has to be permitted
  ([NetworkPolicy enforcement](networking/network-policies.md)).

## Steps

1. **Bundled.** Size the volume for the deployment, not the session count: the database grows with
   users, groups, workspaces and session *history*, which grows without bound. Plan to prune it or
   grow the volume.

   ```yaml
   kasm-helm:
     database:
       standalone: false
       storage:
         size: 20Gi
         storageClassName: ""      # empty uses the cluster default
   ```

   The PVC survives `helm uninstall` by design ([Day 2](day-2.md#uninstall)).

2. **External.** Supply credentials through a Secret, not inline values.

   ```yaml
   kasm-helm:
     database:
       standalone: true
       hostname: postgres.internal.example.com
       port: 5432
       kasmDbName: kasm
       kasmDbUser: kasmapp
       kasmDbSecret:
         existingSecret: kasm-db-credentials
         existingSecretKey: password
   ```

3. **Seeding happens once.** `kasmConfig` and the preseed values apply only when the database is
   **initialized**: a fresh database, never an existing one. That covers zones, the auth domain,
   default users, API credentials and the workspace library. On an existing database the same
   changes are made in the admin UI or through the admin API ([Preseeding](../reference/preseed.md)).
   `kasmConfig.authDomain` matters only on direct-connect ([Switch sessions to direct-connect](networking/direct-connect.md));
   the relayed default needs no change.

4. **Install or upgrade the release.**

## Verify

```console
kubectl -n kasm get job -l app.kubernetes.io/component=db-init
kubectl -n kasm logs job/kasm-db-init --tail=3
```

Expected:

```text
NAME           STATUS     COMPLETIONS   DURATION   AGE
kasm-db-init   Complete   1/1           47s        3m
INFO  seeding default properties
INFO  seeding default users
INFO  database initialization complete
```

A completed Job on a database that already had a schema does nothing, which is correct.

## Chart values

```yaml
kasm-helm:
  database:
    standalone: false
    storage:
      size: 20Gi
  dbManagement:
    backupCron:
      enabled: true
      schedule: "0 2 * * *"
```

Installing `kasm-helm` directly, drop the `kasm-helm:` key. Backup and restore procedures are in
[Day 2](day-2.md#backup).

## Troubleshooting

A `kasm-db-init` Job stuck at `0/1` with `could not translate host name` is DNS or NetworkPolicy
reaching an external database, not credentials; stuck with an authentication error is credentials.
Otherwise [Troubleshooting](../reference/troubleshooting.md).

## Decisions

- [ ] Bundled or external decided before the first install.
- [ ] External: PostgreSQL 16 confirmed; database and owning role created; egress permitted if NetworkPolicies are on.
- [ ] Bundled: `database.storage.size` and class chosen, with history growth in mind.
- [ ] Credentials supplied through `existingSecret`, never inline.
- [ ] Preseed content settled before the database initializes; it never re-applies.
- [ ] A backup path that has been restored from once.
