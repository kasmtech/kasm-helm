---
title: Kasm Kubernetes Troubleshooting
description: Recommendations and resources useful when troubleshooting a Kasm Kubernetes deployment
author: Kasm Technologies
---

# Troubleshooting

Recommendations and resources useful when troubleshooting a Kasm Kubernetes deployment

### Backup job fails

- Check logs output of the DB Backup job pod

  ```bash
  # Print job logs
  kubectl logs job/backup -n {namespace}

  # Follow job logs
  kubectl logs job/backup -n {namespace} -f
  ```

- Verify DB credentials
  - Locate current DB password (depends on your PostgreSQL deployment methodology)
    - Cloud provider often provides it in a secret, so check the cloud provider
    - If you deployed in a VM, you can get the current DB password from the `/opt/kasm/current/docker/docker-compose.yaml` file under the `db` service
    - If you deployed via the Helm chart, you can check the DB secret using the command below:

  ```bash
  kubectl get secret --namespace {namespace} {helm-release-name}-secrets -o jsonpath="{.data.db-password}" | base64 -d
  ```

- Ensure network access between K8s and DB server
  - Exec into the Kasm Backup pod pod and verify it can connect to the DB server

  ```bash
  # Exec into Kasm Backup pod
  kubectl exec -it kasm-old-db-backup-container-{random-string} -- /bin/bash

  # Verify connectivity and DB availability
  kasm@{pod-name}:/# pg_isready -h {db-hostname} -p 5432 -d kasm -U kasmapp
  kasm-db:5432 - accepting connections    # <-- You should see this if you can connect to the DB server
  ```

### General Kasm troubleshooting

- See [troubleshooting docs](https://kasmweb.com/docs/latest/guide/troubleshooting.html).

### Custom PVC or backup names

- If you changed file/PVC names, update `values.yaml` accordingly

