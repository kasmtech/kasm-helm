---
title: Migrate Kubernetes DB to Standalone DB
description: Migrating a Kubernetes-hosted Kasm Database to a standalone DB server
author: Kasm Technologies
---

# Migrate Kubernetes DB to Standalone DB

This guide walks you through safely **migrating your Kubernetes-based Kasm DB** to a **Standalone DB with a Kubernetes-hosted Kasm**.

---

### 1. Backup Your Database

> ⚠️ **Required:**\
> Do **not** skip this step. Without a database backup, you risk irreversible data loss.

- Deploy the [DB backup job template](./template-files/db-backup.yaml) to your Kasm namespace:

  ```bash
  kubectl apply -f ./template-files/db-backup.yaml -n kasm-namespace
  kubectl logs backup-<job-id> -n kasm-namespace --follow
  ```

- **Sample output:**

  ```
  db-is-ready db:5432 - accepting connections
  kasm-old-db-backup-container Creating DB Backup...
  -rwxr-xr-x. 1 kasm kasm 1.8M Jul 23 18:26 /data/kasm-db-dump/kasm_dump.tar
  ```

---

### 2. Updating StatefulSet PVC Retention Policy

```bash
helm upgrade kasm kasm-single-zone -n kasm-namespace --reuse-values --set kasmApp.servicesToDeploy.db.persistentVolumeClaimRetentionPolicy.enabled=true --set kasmApp.servicesToDeploy.db.persistentVolumeClaimRetentionPolicy.whenDeleted=Retain
```

### 3. Delete Old Kasm Helm Release

> ⚠️ **Warning:**\
> Because of the earlier step (2. Updating the StatefulSet PVC Retention Policy), this action removes your Kasm deployment but retains your database and persistent volumes.


```bash
helm delete kasm -n kasm-namespace
```

---

### 4. Download and Configure New Helm Chart

- Download the latest chart and follow [main README instructions](../README.md) to get the correct release branch.
- Refer to the [Detailed docs](../charts/kasm/README.md) for available configuration settings.

---

### 5. Update Helm Chart Values for Upgrade (even if you are not upgrading, the process is the same)

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
helm install kasm ./kasm -n kasm-namespace
```

---

### 7. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the output or retrieve secrets via:
  ```bash
  kubectl get secret --namespace kasm-namespace kasm-helm-secrets -o jsonpath="{.data.admin-password}" | base64 -d
  ```
