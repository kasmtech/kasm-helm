---
title: Upgrading Kasm on Kubernetes
description: Step-by-step guide to upgrade your Kubernetes-based Kasm deployment
author: Kasm Technologies
---

# Upgrading Kasm on Kubernetes

This guide walks you through safely **upgrading your Kasm deployment on Kubernetes** or **migrating from a VM-based deployment**.

---

## 🚦 Upgrade/Migration Scenarios

| Scenario                                       | Use This Section                                                                    |
| ---------------------------------------------- | ----------------------------------------------------------------------------------- |
| Upgrade Helm chart v1.17.0 → v1.1170.0         | [Upgrade Existing Helm Deployment](#upgrade-existing-helm-deployment-v1170--v11170) |
| Upgrade Kasm v1.16.x (K8s) → v1.17.0           | [Upgrade Existing Helm Deployment](#upgrade-existing-helm-deployment-v1170--v11170) |
| Migrate VM deployment → K8s (v1.1170.0/latest) | [Migrate from VM to Kubernetes](#migrate-from-vm-to-kubernetes)                     |

> **Assumptions:**
>
> - You have admin access to your Kubernetes cluster
> - `kubectl` and `helm` are installed and configured
> - You have backup and restore permissions

---

## Upgrade Existing Helm Deployment (v1.17.0 → v1.1170.0)

### **At a Glance: Upgrade Steps**

1. [Backup your Kasm database](#1-backup-your-database)
2. [Delete your old Kasm Helm release](#2-delete-old-kasm-helm-release)
3. [Download and configure the new Helm chart](#3-download-and-configure-new-helm-chart)
4. [Update Helm chart values for upgrade](#4-update-helm-chart-values-for-upgrade)
5. [Install the new release](#5-install-the-new-release)
6. [Verify and log in](#6-verify-and-log-in)

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

### 2. Delete Old Kasm Helm Release

> ⚠️ **Warning:**\
> This deletes your Kasm deployment but **does not delete** your database or persistent volumes.

```bash
helm delete kasm -n kasm-namespace
```

---

### 3. Download and Configure New Helm Chart

- Download the latest chart and follow [main README instructions](../README.md) to get the correct release branch.
- Refer to the [Detailed docs](../charts/kasm/README.md) for available configuration settings.

---

### 4. Update Helm Chart Values for Upgrade

Edit `charts/kasm/values.yaml` in the new chart directory:

```yaml
dbManagement:
  initialize: false
  upgrade:
    enable: true
```

> 🔎 *Leave other **`dbManagement.upgrade`** values as default unless you customized your PVC or DB backup file name.*

---

### 5. Install the New Release

```bash
cd /path/to/kasm-helm-new/charts
helm install kasm ./kasm -n kasm-namespace
```

---

### 6. Verify and Log In

- Wait several minutes for all services to come online.
- Access your Kasm environment using the `publicAddr` value you set.
- For admin and user credentials, see the output or retrieve secrets via:
  ```bash
  kubectl get secret --namespace kasm-namespace kasm-helm-secrets -o jsonpath="{.data.admin-password}" | base64 -d
  ```

---

## Upgrading from Kasm v1.16.x (K8s) to v1.17.0

**Follow all the same steps as above.**\
These upgrade procedures are valid for both Helm and Kasm version upgrades.

---

## Migrate from VM to Kubernetes

There are **two primary methods** to migrate your Kasm database from a VM deployment to a Kubernetes deployment:

- **Option A:** Use a Kubernetes backup job (K8s can access your existing DB server)
- **Option B:** Manually backup and upload your DB

### Option A: Use the K8s DB Backup Job

1. **Create the required Kasm secrets:**

   - Edit and apply `./template-files/kasm-secrets.yaml` in your target namespace, populating secrets with values from your current deployment.

     ```bash
     # Create Secrets
     kubectl apply -f ./template-files/kasm-secrets.yaml -n kasm-namespace
     ```

2. **Deploy the backup job template:**

   - Update the environment variables in `db-backup.yaml` as needed:
     ```yaml
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
     kubectl apply -f ./template-files/db-backup.yaml -n kasm-namespace
     ```

3. **Once the backup job completes successfully,** [proceed with the Helm upgrade steps above](#upgrade-existing-helm-deployment-v1170--v11170).

---

### Option B: Manual DB Backup & Upload

1. **Backup your database on the VM:**\
   Follow the official Kasm docs:

   - [Container DB Backup](https://kasmweb.com/docs/latest/guide/database.html#backups)
   - [Standalone DB Backup](https://kasmweb.com/docs/latest/how_to/remote_database.html#backing-up-the-postgresql-server)

2. **Rename the backup file to** `kasm_dump.tar`.

3. **Create the required secrets** as described above.

4. **Deploy the upload pod:**

   ```bash
   kubectl apply -f ./template-files/kasm-upload.yaml -n kasm-namespace
   ```

5. **Copy the DB backup into the pod:**

   ```bash
   kubectl cp /path/to/kasm_dump.tar kasm-namespace/upload-<pod-id>:/data/kasm-db-dump/kasm_dump.tar
   ```

6. **Once upload completes,** [proceed with the Helm upgrade steps above](#upgrade-existing-helm-deployment-v1170--v11170).

---

## Troubleshooting

- **Backup job fails:** Check logs and DB credentials; ensure network access between K8s and DB server.
- **Pods not coming up after upgrade:** See [troubleshooting docs](https://kasmweb.com/docs/latest/troubleshooting/).
- **Custom PVC or backup names:** If you changed file/PVC names, update `values.yaml` accordingly.

