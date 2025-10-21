---
title: Upgrade New Helm Deployment
description: Step-by-step guide to upgrade your Kubernetes-based Kasm deployment if you deployed using the new Helm chart
author: Kasm Technologies
---

# Upgrade New Helm Deployment

If you are using the new `kasm` chart, follow the steps below to upgrade your Kasm Helm deployment.

---

### **At a Glance: Upgrade Steps**

1. [Backup your Kasm database](#1-backup-your-database-and-secrets)
2. [Update StatefulSet PVC Retention Policy](#2-update-statefulset-pvc-retention-policy)
3. [Delete your old Kasm Helm release](#3-delete-the-old-kasm-helm-release)
4. [Download and configure the new Helm chart](#4-download-and-configure-new-helm-chart)
5. [Update Helm chart values for upgrade](#5-update-helm-chart-values-for-upgrade)
6. [Install the new release](#6-install-the-new-release)
7. [Verify and log in](#7-verify-and-log-in)

---

### 1. Backup Your Database and Secrets

- Enable DB Backup Cronjob
  ```bash
  helm upgrade --no-hooks {helm-release-name} {old-chart-path} -n {namespace} --reuse-values --set dbManagement.backupCron.enabled=true \
  --set dbManagement.backupCron.pvcName=kasm-db-dump-pvc \
  --set dbManagement.initialize=false
  ```
Replace the placeholders:
1. {helm-release-name}: The name of your Kasm Helm release. Run `helm list -n {namespace}` if you are unsure of the release name.
2. {namespace}: The namespace where your Kasm deployment is running
3. {old-chart-path}: The path to your existing chart directory. Example: `/home/user/kasm-helm/charts/kasm`


- Manually trigger DB Backup Cronjob
  ```bash
  kubectl create job --from=cronjob/kasm-db-backup-cron kasm-db-backup-manual -n {namespace}
  ```

Note: If a job with the same name already exists from a previous upgrade, delete it by running:
  ```bash
  kubectl delete job kasm-db-backup-manual -n {namespace}
  ```
  
- Retrieve the backup file name
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

- Clean up the manual job:

  ```bash
  kubectl -n {namespace} delete job kasm-db-backup-manual
  ```

- Backup secrets and store output securely:

  ```bash
  kubectl -n {namespace} get secrets/{kasm-secrets} --template='{{ range $key, $value := .data }}{{ printf "%s: %s\n" $key ($value | base64decode) }}{{ end }}'
  ```

Replace the placeholder {kasm-secrets} with the actual kasm secret name. To find it, run:

```bash
kubectl -n {namespace} get secret | grep secrets
```

The secret name should match the format `{helm-release-name}-secrets`.


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

### 2. Update StatefulSet PVC Retention Policy

Run the following command to update the PVC retention policy:
```bash
helm upgrade --no-hooks {helm-release-name} {old-chart-path} -n {namespace} --reuse-values --set database.storage.retentionPolicy.whenDeleted=Retain --set annotations.pvc."helm\.sh/resource-policy"="keep"
```
Replace the placeholders:
1. {helm-release-name}:  Your Kasm Helm release name.
2. {namespace}: The namespace where your Kasm deployment is running.
3. {old-chart-path}: Path to the old chart directory (e.g., `/home/user/kasm-helm/charts/kasm`)

Verify the retention policy has been updated (Ignore this step if using standalone DB):
```bash
kubectl -n {namespace} get statefulset {kasm-db-statefulset-name} -o yaml | grep whenDeleted
```

Replace `{kasm-db-statefulset-name}` with the actual db statefulset name, you can get the statefulset name by using the command `kubectl -n {namespace} get statefulset`. It should have the value of {helm-release-name}-db-statefulset.

Expected output:
```text
  whenDeleted: Retain
```

Verify the PVC `kasm-db-dump-pvc` is updated
```bash
kubectl -n {namespace} get pvc kasm-db-dump-pvc -o yaml | grep "helm\.sh/resource-policy"
```

Expected output:
```text
  helm.sh/resource-policy: keep
```

---

### 3. Delete the Old Kasm Helm Release

> ⚠️ **Warning:**\
>This step will remove your Kasm deployment. However, because you updated the StatefulSet PVC retention policy in Step 2, your database and persistent volumes will be preserved.

```bash
helm uninstall kasm -n {namespace} 
```

---

### 4. Download and Configure New Helm Chart

- Download the latest chart and follow [main README instructions](../README.md) to get the correct release branch.
- Refer to the [Detailed docs](../charts/kasm/README.md) for available configuration settings and installation instructions.

---

### 5. Update Helm Chart Values for Upgrade

Edit `charts/kasm/values.yaml` in the new chart directory:

```yaml
dbManagement:
  initialize: false
  upgrade:
    enable: true
    oldDbSecretsName: {kasm-secrets}
    oldDbBackupFileName: {db-dump-filename}
```

Replace the placeholders:
1. {kasm-secrets}: the kasm secret name, run command `kubectl -n {namespace} get secret | grep secrets` to get the secret name. It should have the value of `{helm-release-name}-secrets`. 
2. {db-dump-filename}: the file name of the db dump file from Step 1, e.g., `kasm_dump_20250821_13.56.39.tar`

> 🔎 *Leave other **`dbManagement.upgrade`** values as default unless you customized your PVC name.*

---

### 6. Install the New Release

```bash
cd /path/to/kasm-helm-new/charts
helm install kasm ./kasm -n {namespace}
```

Notes:
1. The `{namespace}` must be the same namespace where your old chart and backup job was deployed.
2. Ensure you have already updated your values.yaml (see Step 5) before running the install.

---

### 7. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the helm note via:

  ```bash
  helm get notes kasm -n {namespace}
  ```

## Upgrade Troubleshooting

Click here for [Troubleshooting assistance](./troubleshooting.md)