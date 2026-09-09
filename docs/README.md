# Kasm on Kubernetes — documentation

Kasm on Kubernetes is **two halves**: the control plane (the `kasm-helm` chart — the web UI, the
API, the database) and one or more agents (the `kasm-agent` family — where sessions actually run).
They are deployed, published and certificated independently, and almost every decision below
applies to both. Pages say explicitly which half they are talking about.

## Reading order

1. **[Architecture](overview/architecture.md)** — the two halves, the chart dependency tree, and the
   deployment topologies. Start here if you have not deployed Kasm on Kubernetes before.
2. **[The charts](overview/charts.md)** — what each of the ten charts installs, and which one you
   want.
3. **[What works on Kubernetes](reference/feature-matrix.md)** — every Kasm feature, whether it
   works here, and what it needs from the cluster. Read this before promising anyone a feature.
4. **[Planning](planning/README.md)** — the decision sequence, in order, ending in a values file you
   can install. Everything below hangs off it.
5. **[Install and verify](operate/install-and-verify.md)** — the order to install in, and the
   commands that prove each step worked.

## Planning

| Topic | Covers |
| ----- | ------ |
| [Planning overview](planning/README.md) | The decision sequence and the master checklist |
| [Supported platforms](planning/support.md) | Kubernetes versions, distributions, and what changes on EKS / AKS / GKE / OpenShift |
| [Managed providers in detail](planning/managed-providers.md) | Per-provider specifics for every feature |
| [Capacity](planning/capacity.md) | What a session costs, the four ceilings, node sizing |
| [Multi-zone](planning/multi-zone.md) | `kasmZones`, per-zone hostnames and agents, what multi-zone forces |
| [Networking](planning/networking/README.md) | Publishing both halves — certificates first, then one mechanism per half |
| [Storage](planning/storage/README.md) | Profiles, user mappings, recordings, the node image store |
| [Database](planning/database.md) | Bundled PostgreSQL or your own, sizing, backup and restore |
| [Registries and image pulling](planning/registries.md) | Private registries, pull secrets, pre-pulling |
| [Airgap](planning/airgap.md) | The four things that need mirroring, in order |
| [Nodes and devices](planning/nodes/README.md) | GPU, webcam, kernel modules, Secure Boot, swap, privileged workloads |
| [Security](planning/security.md) | Pod Security, RBAC, isolation, what the charts need and why |

## Operating

| Topic | Covers |
| ----- | ------ |
| [Install and verify](operate/install-and-verify.md) | Install order, and what good looks like at each step |
| [Upgrade](operate/upgrade.md) | Chart and CRD upgrade discipline |
| [Uninstall](operate/uninstall.md) | What Helm removes, and what it leaves behind |
| [Backup and restore](operate/backup-restore.md) | The database, and what else is stateful |
| [Troubleshooting](operate/troubleshooting.md) | Symptom → cause → command |

## Reference

| Page | Covers |
| ---- | ------ |
| [What works on Kubernetes](reference/feature-matrix.md) | Feature-by-feature support and requirements |
| [Kasm settings → agent CRD fields](reference/settings-to-crd.md) | How manager-side settings map onto the cluster |
| [Preseeding](reference/preseed.md) | Seeding the database at install time |
| [Default users](reference/default-users.md) · [Default API users](reference/default-api-users.md) | What `defaultUsers` / `defaultApiUsers` create |

Per-chart value reference lives in each chart's own README, generated from its `values.yaml` — for
example [`kasm-helm`](../charts/kasm-helm/README.md) and
[`kasm-agent`](../charts/kasm-agent/README.md).

## How these pages are organised

* **Overview** answers *what is this*. **Planning** answers *what do I decide*. **Operating**
  answers *what do I run, and what should I see*. **Reference** answers *what is the exact value*.
* Every planning page covers **both halves** — the control plane and the agent — and says which is
  which.
* Every verification command shows its **expected output**, so you can tell a healthy result from a
  plausible-looking broken one.
* All install commands use the **published charts** at `oci://registry-1.docker.io/kasmweb/`. See
  [Where the charts are published](../README.md#where-the-charts-are-published).
