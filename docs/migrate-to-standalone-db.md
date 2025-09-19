---
title: Migrate Kubernetes DB to Standalone DB
description: Migrating a Kubernetes-hosted Kasm Database to a standalone DB server
author: Kasm Technologies
---

# Migrate Kubernetes DB to Standalone DB

This guide walks you through safely migrating your Kubernetes-based Kasm DB to a standalone PostgreSQL database while continuing to run Kasm in Kubernetes.

> ⚠️ **Warning:**\
> To migrate to a standalone database, you must first ensure that you are running the latest version of the Kasm Helm. Refer to [Upgrading Kasm on Kubernetes](./kasm-upgrade.md) for instructions on upgrading Kasm to the latest version.
> Ensure you have already provisioned a PostgreSQL v14 instance, and that it is fully configured to accept connections.
> The database must be network-accessible from your target Kubernetes cluster where the Kasm Helm chart will be deployed.

---

### 1. Backup Your Database and Secrets

- Enable DB Backup Cronjob
  ```bash
  helm upgrade --no-hooks {helm-release-name} {kasm-chart-path} -n {namespace} --reuse-values --set dbManagement.backupCron.enabled=true \
  --set dbManagement.backupCron.pvcName=kasm-db-dump-pvc \
  --set dbManagement.initialize=false
  ```
Replace the placeholders:
1. {helm-release-name}: Your Kasm Helm release name. Run `helm list -n {namespace}` if you are unsure.
2. {namespace}: The namespace where your Kasm deployment is running
3. {kasm-chart-path}: Path to the Kasm chart directory (e.g., `/home/user/kasm-helm/charts/kasm`)

- Manually trigger DB Backup Cronjob
  ```bash
  kubectl create job --from=cronjob/kasm-db-backup-cron kasm-db-backup-manual -n {namespace}
  ```
  
Note: If a job with the same name already exists from a previous upgrade, delete it by running:
  ```bash
  kubectl delete job kasm-db-backup-manual -n {namespace}
  ```

- Get the backup file name
  ```bash
  kubectl get pods -n {namespace} | grep kasm-db-backup-manual
  kubectl logs kasm-db-backup-manual-{id} -n {namespace}
  ```

- **Sample output:**

  ```text
  Starting backup to /data/kasm-db-dump/kasm_dump_20250821_13.56.39.tar
  Backup complete
  ```

Note: note down the filename `kasm_dump_20250821_13.56.39.tar`.

- Cleanup

  ```bash
  kubectl -n {namespace} delete job kasm-db-backup-manual
  ```

- Backup secrets and store output securely:

  ```bash
  kubectl -n {namespace} get secrets/{kasm-secrets} --template='{{ range $key, $value := .data }}{{ printf "%s: %s\n" $key ($value | base64decode) }}{{ end }}'
  ```

Replace the placeholder {kasm-secrets} with the kasm secret name, run command `kubectl -n {namespace} get secret | grep secrets` to get the secret name. It should have the value of `{helm-release-name}-secrets`

- **Sample output:**

  ```bash
  admin-password: xxx
  db-password: xxx
  manager-token: xxx
  redis-password: xxx
  service-token: xxx
  user-password: xxx
  ```

---

### 2. Updating StatefulSet PVC Retention Policy

```bash
helm upgrade --no-hooks {helm-release-name} {kasm-chart-path} -n {namespace} --reuse-values --set database.storage.retentionPolicy.whenDeleted=Retain --set annotations.pvc."helm\.sh/resource-policy"="keep"
```
Replace the placeholders:
1. {helm-release-name}:  Your Kasm helm release name
2. {namespace}: The namespace where your Kasm deployment is running
3. {kasm-chart-path}: Path to the kasm chart directory (e.g., `/home/user/kasm-helm/charts/kasm`)

Verify the retention policy is updated:
```bash
kubectl -n {namespace} get statefulset {kasm-db-statefulset-name} -o yaml | grep whenDeleted
```
Replace `{kasm-db-statefulset-name}` with the actual db statefulset name, you can get the statefulset name by using the command `kubectl -n {namespace} get statefulset`. It should have the value of {helm-release-name}-db-statefulset.

Expected output:
```text
  whenDeleted: Retain
```

Verify the pvc `kasm-db-dump-pvc` is updated
```bash
kubectl -n {namespace} get pvc kasm-db-dump-pvc -o yaml | grep "helm\.sh/resource-policy"
```

Expected output:
```text
  helm.sh/resource-policy: keep
```

---

### 3. Delete Kasm Helm Release

> ⚠️ **Warning:**\
>  will remove your Kasm deployment. However, because you updated the StatefulSet PVC retention policy in Step 2, your database and persistent volumes will be preserved.


```bash
helm uninstall kasm -n {namespace} 
```

---

### 4. Update Helm Chart Values for Migration

> ⚠️ **Warning:**\
> Make sure you have already created the database and database user in your postgres instance before continue further.
> Recommended DB name: `kasm`
> Recommended DB username: `kasmapp`


**Step 1: Create the Database Password Secret**

Store the manually created database user's password in a Kubernetes secret:

```bash
kubectl -n {namespace} create secret generic kasm-db-secret --from-literal=kasm-db-secret-key='YOUR_PASSWORD' 
```

- Replace `{namespace}` with the Kubernetes namespace used in previous steps.
- Replace `YOUR_PASSWORD` with the password of the manually created PostgreSQL user.

**Step 2: Configure the values.yaml**
Ensure the `database` and `dbManagement` sections in your values.yaml is configured correctly for your external PostgreSQL instance.

| Variable                                    | Value        | Description                                                                                                                                                                 |
|---------------------------------------------|--------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `database.standalone`                       | `true`       | Disable Kasm’s internal DB and use your external PostgreSQL v14 instance.                                                                                                   |
| `database.hostname`                         | *your value* | The hostname or IP address of your PostgreSQL server.                                                                                                                       |
| `database.port`                             | *your value* | The port number used to connect to the PostgreSQL server.                                                                                                                   |
| `database.kasmDbName`                       | *your value* | Name of the Kasm database.                                                                                                                                                  |
| `database.kasmDbUser`                       | *your value* | Username that Kasm uses to access the database.                                                                                                                             |
| `database.kasmDbSecret`                     | *your value* | Kubernetes Secret name/key that holds the password for kasmDbUser.                                                                                                          |
| `database.postgresMasterUser`               | `{}`         | Keep this field empty `{}` for standalone db migration.                                                                                                                     |
| `dbManagement.initialize`                   | `false`      | Disable the DB initialisation                                                                                                                                               |
| `dbManagement.upgrade.enable`               | `true`       | Enable the DB upgrade/migration                                                                                                                                             |
| `dbManagement.upgrade.oldDbSecretsName`     | *your value* | The old kasm secret name, run command `kubectl -n {namespace} get secret \| grep secrets` to get the secret name. It should have the value of `{helm-release-name}-secrets` |
| `dbManagement.upgrade.oldDbBackupFileName`  | *your value* | The file name of the db dump file from Step 1, e.g., `kasm_dump_20250821_13.56.39.tar`                                                                                      |


See example below.

```yaml
database:
  standalone: true
  hostname: "YOUR_DB_HOSTNAME"
  port: "YOUR_DB_PORT"
  kasmDbName: kasm
  kasmDbUser: kasmapp
  kasmDbSecret:
    name: kasm-db-secret
    key: kasm-db-secret-key
  postgresMasterUser: {}
dbManagement:
  initialize: false
  upgrade:
    enable: true
    oldDbSecretsName: kasm-secrets
    oldDbBackupFileName: kasm_dump_20250901_14.26.05.tar
```

---

### 5. Reinstall the Kasm Helm Release

```bash
cd /path/to/kasm-helm-new/charts
helm install kasm ./kasm -n {namespace}
```

Notes:
1. The `{namespace}` must be the same namespace where your backup job was deployed.
2. Ensure you have already updated your values.yaml (see Step 4) before installing.

---

### 6. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the helm note via:
  ```bash
  helm get notes kasm -n {namespace}
  ```

## Upgrade Troubleshooting

Click here for [Troubleshooting assistance](./troubleshooting.md)