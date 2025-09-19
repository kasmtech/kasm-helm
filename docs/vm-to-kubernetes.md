---
title: Migrate from VM to Kubernetes
description: Step-by-step guide to migrate your existing VM-based Kasm deployment to a Kubernetes-based Kasm deployment
author: Kasm Technologies
---

# Migrate from VM to Kubernetes

You can migrate your Kasm from a VM deployment to Kubernetes using one of the following methods:
- [**Option A:**](#option-a-use-the-k8s-db-backup-job) Use a Kubernetes backup job *(when your Kubernetes cluster can directly access the existing database server).*
- [**Option B:**](#option-b-manual-db-backup--upload) Perform a manual database backup on the VM and upload it into Kubernetes.

### Option A: Use the K8s DB Backup Job

###### 1. **Create the required Kasm secrets:**

> ⚠️ **Warning:**\
> The secret values must be base64 encoded.
> You can base64 encode your secret with `echo -n {secret-value} | base64`


- Edit and apply `./template-files/kasm-secrets.yaml` in your target namespace, filling in the values from your current VM deployment.

  ```bash
  # Create namespace if it doesn't already exist
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
  
- (Optional) Exclude Kasm Logs from the backup 

Modify the following line in `db-backup.yaml`:

  ```text
  pg_dump -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -Ft > /data/kasm-db-dump/kasm_dump.tar
  ```

Change it to:

  ```text
  pg_dump -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -Ft  --exclude-table-data=logs > /data/kasm-db-dump/kasm_dump.tar
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
  # Create namespace if it doesn't already exist
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
  
- **Validate the dump file size:**

Confirm the `Final size: 206191616 bytes` matches your local backup file size exactly.

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

## Upgrade Troubleshooting

Click here for [Troubleshooting assistance](./troubleshooting.md)