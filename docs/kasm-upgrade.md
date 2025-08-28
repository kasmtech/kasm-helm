---
title: Upgrading Kasm on Kubernetes
description: Step-by-step guide to upgrade your Kubernetes-based Kasm deployment
author: Kasm Technologies
---

# Upgrading Kasm on Kubernetes

This guide walks you through safely **upgrading your Kasm deployment on Kubernetes** or **migrating from a VM-based deployment**.

---

## 🚦 Upgrade/Migration Scenarios

| Scenario                                                   | Use This Section                                                  |
|------------------------------------------------------------|-------------------------------------------------------------------|
| Upgrade legacy `kasm-single-zone` chart 1.17.0 -> 1.118.0  | [Upgrade Legacy Helm Deployment](#upgrade-legacy-helm-deployment) |
| Upgrade new `kasm` chart 1.117.0 -> 1.118.0                | [Upgrade Existing Helm Deployment](#upgrade-new-helm-deployment)  |
| Migrate VM deployment → K8s (v1.1180.0/latest)             | [Migrate from VM to Kubernetes](#migrate-from-vm-to-kubernetes)   |

> **Assumptions:**
>
> - You have admin access to your Kubernetes cluster
> - `kubectl` and `helm` are installed and configured
> - You have backup and restore permissions

---

## Determine Kasm Chart Version
To determine which Kasm Helm chart you are current using, run the following command.

```bash
helm show chart /path/to/kasm/helm/chart
```

You are using legacy `kasm-single-zone` chart if its output includes `name: kasm-single-zone` and `version: 1.1x.0-develop`.

You are using the new `kasm` chart if its output includes `name: kasm` and `version: 1.11xx.0`.



## Upgrade Legacy Helm Deployment
If you are using the legacy `kasm-single-zone` chart, follow the steps below to upgrade your Kasm Helm deployment.

### **At a Glance: Upgrade Steps**

1. [Backup your Kasm database](#1-backup-your-database-and-secrets)
2. [Updating StatefulSet PVC Retention Policy](#2-updating-statefulset-pvc-retention-policy)
3. [Delete your old Kasm Helm release](#3-delete-old-kasm-helm-release)
4. [Download and configure the new Helm chart](#4-download-and-configure-new-helm-chart)
5. [Update Helm chart values for upgrade](#5-update-helm-chart-values-for-upgrade)
6. [Install the new release](#6-install-the-new-release)
7. [Verify and log in](#7-verify-and-log-in)

---

### 1. Backup Your Database and Secrets

- Deploy the [DB backup job template](./template-files/db-backup.yaml) to your Kasm namespace:

  ```bash
  kubectl apply -f ./template-files/db-backup.yaml -n {namespace}
  kubectl logs backup-<job-id> -n {namespace} --follow
  ```

- **Sample output:**

  ```
  kasm-old-db-backup-container Creating DB Backup...
  -rwxr-xr-x. 1 kasm kasm 1.8M Jul 23 18:26 /data/kasm-db-dump/kasm_dump.tar
  ```

- Backup Secrets, make sure to save the output in a safe place.

  ```bash
  kubectl -n {namespace} get secrets/kasm-secrets --template='{{ range $key, $value := .data }}{{ printf "%s: %s\n" $key ($value | base64decode) }}{{ end }}'
  ```

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
helm upgrade --no-hooks {helm-release-name} {old-chart-path} -n {namespace} --reuse-values --set kasmApp.servicesToDeploy.db.persistentVolumeClaimRetentionPolicy.enabled=true --set kasmApp.servicesToDeploy.db.persistentVolumeClaimRetentionPolicy.whenDeleted=Retain
```
Replace the placeholders:
1. {helm-release-name}:  Your Kasm helm release name, execute `helm list -n {namespace}` if you not sure your helm release name
2. {namespace}: The namespace where your Kasm deployment is running
3. {old-chart-path}: Path to the old chart directory (e.g., `/home/user/kasm-helm/kasm-single-zone`)

Verify the retention policy is updated:
```bash
kubectl -n {namespace} get statefulset kasm-db-statefulset -o yaml | grep whenDeleted
```
make sure the output is
```bash
  whenDeleted: Retain
```

---

### 3. Delete Old Kasm Helm Release

> ⚠️ **Warning:**\
> Because of the earlier step (2. Updating the StatefulSet PVC Retention Policy), this action removes your Kasm deployment but retains your database and persistent volumes.


```bash
helm uninstall kasm -n {namespace}  --no-hooks
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
```

> 🔎 *Leave other **`dbManagement.upgrade`** values as default unless you customized your PVC or DB backup file name.*

---

### 6. Install the New Release

```bash
cd /path/to/kasm-helm-new/charts
helm install kasm ./kasm -n {namespace}
```

Notes:
1. The {namespace} must be the same namespace where your old chart and backup job was deployed.
2. Ensure you have already updated your values.yaml (see Step 5) before running the install.

---

### 7. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the helm note via:
  ```bash
  helm get notes kasm -n {namespace}
  ```

---

## Upgrade New Helm Deployment

If you are using the new `kasm` chart, follow the steps below to upgrade your Kasm Helm deployment.

---

### **At a Glance: Upgrade Steps**

1. [Backup your Kasm database](#1-backup-your-database-and-secrets)
2. [Updating StatefulSet PVC Retention Policy](#2-updating-statefulset-pvc-retention-policy)
3. [Delete your old Kasm Helm release](#3-delete-old-kasm-helm-release)
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
1. {helm-release-name}:  Your Kasm helm release name, execute `helm list -n {namespace}` if you not sure your helm release name
2. {namespace}: The namespace where your Kasm deployment is running
3. {old-chart-path}: Path to the old chart directory (e.g., `/home/user/kasm-helm/charts/kasm`)

- Manually trigger DB Backup Cronjob
  ```bash
  kubectl create job --from=cronjob/kasm-db-backup-cron kasm-db-backup-manual -n {namespace}
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

- Backup Secrets, make sure to save the output in a safe place.

  ```bash
  kubectl -n {namespace} get secrets/{kasm-secrets} --template='{{ range $key, $value := .data }}{{ printf "%s: %s\n" $key ($value | base64decode) }}{{ end }}'
  ```

Replace the placeholder {kasm-secrets with the kasm secret name, run command `kubectl -n {namespace} get secret | grep secrets` to get the secret name. It should have the value of `{helm-release-name}-secrets`


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
helm upgrade --no-hooks {helm-release-name} {old-chart-path} -n {namespace} --reuse-values --set database.storage.retentionPolicy.whenDeleted=Retain --set annotations.pvc."helm\.sh/resource-policy"="keep"
```
Replace the placeholders:
1. {helm-release-name}:  Your Kasm helm release name
2. {namespace}: The namespace where your Kasm deployment is running
3. {old-chart-path}: Path to the old chart directory (e.g., `/home/user/kasm-helm/charts/kasm`)

Verify the retention policy is updated:
```bash
kubectl -n {namespace} get statefulset {kasm-db-statefulset-name} -o yaml | grep whenDeleted
```
Replace `{kasm-db-statefulset-name}` with the actual db statefulset name, you can get the statefulset name by using the command `kubectl -n {namespace} get statefulset`. It should have the value of {helm-release-name}-db-statefulset.

make sure the output is
```text
  whenDeleted: Retain
```

Verify the pvc `kasm-db-dump-pvc` is updated
```bash
kubectl -n {namespace} get pvc kasm-db-dump-pvc -o yaml | grep "helm\.sh/resource-policy"
```

make sure the output is
```text
  helm.sh/resource-policy: keep
```

---

### 3. Delete Old Kasm Helm Release

> ⚠️ **Warning:**\
> Because of the earlier step (2. Updating the StatefulSet PVC Retention Policy), this action removes your Kasm deployment but retains your database and persistent volumes.


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
1. The {namespace} must be the same namespace where your old chart and backup job was deployed.
2. Ensure you have already updated your values.yaml (see Step 5) before running the install.

---

### 7. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the helm note via:
  ```bash
  helm get notes kasm -n {namespace}
  ```

---

## Migrate from VM to Kubernetes

There are **two primary methods** to migrate your Kasm database from a VM deployment to a Kubernetes deployment:

- **Option A:** Use a Kubernetes backup job (K8s can access your existing DB server)
- **Option B:** Manually backup and upload your DB

### Option A: Use the K8s DB Backup Job

###### 1. **Create the required Kasm secrets:**

> ⚠️ **Warning:**\
> The secret values must be base64 encoded.
> You can base64 encode your secret with `echo -n {secret-value} | base64`


- Edit and apply `./template-files/kasm-secrets.yaml` in your target namespace, populating secrets with values from your current deployment.

  ```bash
  # Create namespace if you haven't already
  kubectl create ns {namespace}
     
  # Create Secrets
  kubectl apply -f ./template-files/kasm-secrets.yaml -n {namespace}
  ```

- Verify the created secret values
  
  ```bash
  kubectl -n {namespace} get secrets/kasm-secrets --template='{{ range $key, $value := .data }}{{ printf "%s: %s\n" $key ($value | base64decode) }}{{ end }}'
  ```

###### 2. **Deploy the backup job template:**

- Update the environment variables in `db-backup.yaml` as needed:
  ```yaml
   initContainers:
     - name: db-is-ready
       env:
         - name: POSTGRES_HOST
           value: <DB host or IP>
         - name: POSTGRES_PORT
           value: <DB port>
     
  containers:
      env:
        - name: POSTGRES_HOST
          value: <DB host or IP>
        - name: POSTGRES_PORT
          value: <DB port>
        - name: POSTGRES_DB
          value: kasm
        - name: POSTGRES_USER
          value: kasmapp
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              key: db-password
              name: kasm-secrets
  ```
     
- Deploy:
  ```bash
  # Create backup job
  kubectl apply -f ./template-files/db-backup.yaml -n {namespace}
  kubectl logs backup-<job-id> -n {namespace} --follow
  ```

- **Sample output:**

  ```
  kasm-old-db-backup-container Creating DB Backup...
  -rwxr-xr-x. 1 kasm kasm 1.8M Jul 23 18:26 /data/kasm-db-dump/kasm_dump.tar
  ```

###### 3. Download and Configure Helm Chart

- Download the latest chart and follow [main README instructions](../README.md) to get the correct release branch.
- Refer to the [Detailed docs](../charts/kasm/README.md) for available configuration settings and installation instructions.

---

###### 4. Update Helm Chart Values

Edit `charts/kasm/values.yaml` in the chart directory:

```yaml
dbManagement:
  initialize: false
  upgrade:
    enable: true
```

> 🔎 *Leave other **`dbManagement.upgrade`** values as default unless you customized your PVC name.*

---

###### 5. Install the Helm Chart

```bash
cd /path/to/kasm-helm-charts
helm install kasm ./kasm -n {namespace}
```

Notes: Ensure you have already updated your values.yaml (see Step 5) before running the install.

---

###### 6. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the helm note via:
  ```bash
  helm get notes kasm -n {namespace}
  ```

---

### Option B: Manual DB Backup & Upload

###### 1. **Backup your database on the VM:**\
   Follow the official Kasm docs:

   - [Container DB Backup](https://kasmweb.com/docs/latest/guide/database.html#backups)
   - [Standalone DB Backup](https://kasmweb.com/docs/latest/how_to/remote_database.html#backing-up-the-postgresql-server)

---

###### 2. **Rename the backup file to** `kasm_dump.tar`.

---

###### 3. **Create the required Kasm secrets:**

> ⚠️ **Warning:**\
> The secret values must be base64 encoded.
> You can base64 encode your secret with `echo -n {secret-value} | base64`

- Edit and apply `./template-files/kasm-secrets.yaml` in your target namespace, populating secrets with values from your current deployment.

  ```bash
  # Create namespace if you haven't already
  kubectl create ns {namespace}
     
  # Create Secrets
  kubectl apply -f ./template-files/kasm-secrets.yaml -n {namespace}
  ```

- Verify the created secret values

  ```bash
  kubectl -n {namespace} get secrets/kasm-secrets --template='{{ range $key, $value := .data }}{{ printf "%s: %s\n" $key ($value | base64decode) }}{{ end }}'
  ```

---

###### 4. **Deploy the upload pod:**

   ```bash
   kubectl apply -f ./template-files/db-upload.yaml -n {namespace}
   ```

###### 5. **Copy the DB backup into the pod:**

   ```bash
   kubectl cp /path/to/kasm_dump.tar {namespace}/upload-<pod-id>:/data/kasm-db-dump/kasm_dump.tar
   ```

###### 6. **Verify the Upload**

- **View Upload Pod Logs:**
  ```
  kubectl -n {namespace} logs upload-<pod-id>
  ```

- **Sample output:**

  ```
  Waiting for DB file upload...
  Waiting for DB file upload...
  Waiting for DB file upload...
  File uploading!
  ⏳ Upload in progress... (size: 150240768 bytes)
  ⏳ Upload in progress... (size: 206191616 bytes)
  ✅ File upload complete. Final size: 206191616 bytes
  ```
  
- **Compare the dump file size:**

Confirm the `Final size: 206191616 bytes` is exactly the same as your local backup file.

###### 7. Download and Configure Helm Chart

- Download the latest chart and follow [main README instructions](../README.md) to get the correct release branch.
- Refer to the [Detailed docs](../charts/kasm/README.md) for available configuration settings and installation instructions.

---

###### 8. Update Helm Chart Values

Edit `charts/kasm/values.yaml` in the chart directory:

```yaml
dbManagement:
  initialize: false
  upgrade:
    enable: true
```

> 🔎 *Leave other **`dbManagement.upgrade`** values as default unless you customized your PVC name.*

---

###### 9. Install the Helm Chart

```bash
cd /path/to/kasm-helm-charts
helm install kasm ./kasm -n {namespace}
```

Notes: Ensure you have already updated your values.yaml (see Step 8) before running the install.

---

###### 10. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the helm note via:
  ```bash
  helm get notes kasm -n {namespace}
  ```


---

## Troubleshooting

- **Backup job fails:** Check logs and DB credentials; ensure network access between K8s and DB server.
- **Pods not coming up after upgrade:** See [troubleshooting docs](https://kasmweb.com/docs/latest/guide/troubleshooting.html).
- **Custom PVC or backup names:** If you changed file/PVC names, update `values.yaml` accordingly.

