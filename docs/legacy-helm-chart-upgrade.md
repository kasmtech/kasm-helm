---
title: Upgrade Legacy Helm Deployment
description: Step-by-step guide to upgrade your Kubernetes-based Kasm deployment from the legacy Helm chart to the new Helm chart
author: Kasm Technologies
---

# Upgrade Legacy Helm Deployment

If you are using the legacy `kasm-single-zone` chart, follow the steps below to upgrade your Kasm Helm deployment.

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

- Backup secrets and store output securely:

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

### 2. Update StatefulSet PVC Retention Policy

This ensures your Persistent Volumes are preserved when the Helm release is deleted.

```bash
helm upgrade --no-hooks {helm-release-name} {old-chart-path} -n {namespace} --reuse-values --set kasmApp.servicesToDeploy.db.persistentVolumeClaimRetentionPolicy.enabled=true --set kasmApp.servicesToDeploy.db.persistentVolumeClaimRetentionPolicy.whenDeleted=Retain
```

Replace the placeholders:
1. {helm-release-name}:  The name of your Kasm Helm release. Run `helm list -n {namespace}` if you are unsure of the release name.
2. {namespace}: The Kubernetes namespace where your Kasm deployment is running.
3. {old-chart-path}: The file path to your existing chart directory (for example: `/home/user/kasm-helm/kasm-single-zone`).

Verify the retention policy has been updated:
```bash
kubectl -n {namespace} get statefulset kasm-db-statefulset -o yaml | grep whenDeleted
```

Expected output (If you don’t see this, the retention policy isn’t applied correctly):
```bash
  whenDeleted: Retain
```

---

### 3. Delete the Old Kasm Helm Release

> ⚠️ **Warning:**\
> This step will remove your Kasm deployment. However, because you updated the StatefulSet PVC retention policy in Step 2, your database and persistent volumes will be preserved.

```bash
helm uninstall kasm -n {namespace} --no-hooks
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