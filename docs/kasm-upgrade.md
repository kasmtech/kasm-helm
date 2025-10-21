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
| Upgrade legacy `kasm-single-zone` chart 1.17.0 -> 1.1180.0 | [Upgrade Legacy Helm Deployment](legacy-helm-chart-upgrade.md)    |
| Upgrade new `kasm` chart 1.1170.0 -> 1.1180.0              | [Upgrade Existing Helm Deployment](new-helm-chart-upgrade.md)     |
| Migrate VM deployment → K8s (v1.1180.0/latest)             | [Migrate from VM to Kubernetes](vm-to-kubernetes.md)              |

### Assumptions:
---
> - You have admin access to your Kubernetes cluster
> - `kubectl` and `helm` are installed and configured
> - You have backup and restore permissions

---

## Determine Kasm Chart Version
To determine which Kasm Helm chart you are currently using, run the following command.

```bash
helm show chart /path/to/kasm/helm/chart
```

Interpret the output as follows:

- **Legacy chart** (kasm-single-zone):
  
  The output contains:
  ```text
  name: kasm-single-zone
  version: 1.1x.0
  ```

- **New chart** (kasm):

  The output contains:
  ```text
  name: kasm
  version: 1.11xx.0
  ```

## Upgrade Troubleshooting

Click here for [Troubleshooting assistance](./troubleshooting.md)