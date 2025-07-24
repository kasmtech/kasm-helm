# Kasm Helm Deployment Documentation Index

Welcome to the Kasm Helm deployment documentation!

Use this guide as your starting point for deploying Kasm into your Kubernetes environment. You'll find links to key how-tos, upgrade instructions, certificate management, and cloud-specific examples. For deep dives on Kasm features and advanced platform administration, refer to the [official Kasm documentation](https://kasmweb.com/docs/latest/index.html).

---

## 📑 Table of Contents

<!-- BEGIN TOC -->


### Helm Docs

| Title | Description |
|---|---|
| [Migrate Kubernetes DB to Standalone DB](migrate-to-standalone-db.md) | Migrating a Kubernetes-hosted Kasm Database to a standalone DB server |
| [Upgrading Kasm on Kubernetes](kasm-upgrade.md) | Step-by-step guide to upgrade your Kubernetes-based Kasm deployment |
| [Upload Certs to K8S](upload-certs-to-k8s.md) | How to create and add TLS secrets to your Kubernetes cluster for Kasm. |

### Examples > Aws - ***Incomplete***

| Title | Description |
|---|---|
| [AWS Ingress Example](examples/aws/aws-ingress.md) | Deploy Kasm in AWS using an AWS LB Ingress controller |
| [AWS RDS DB Example](examples/aws/aws-rds.md) | Deploy Kasm in AWS using an AWS RDS Database |
| [AWS Service Example](examples/aws/aws-service.md) | Deploy Kasm in AWS using an AWS LB without Ingress (i.e. connected directly to an exposed Kubernetes service). |

### Examples > Gcp - ***Incomplete***

| Title | Description |
|---|---|
| [GCP Cloud SQL](examples/gcp/gcp-cloud-sql.md) | Deploy Kasm in GCP using a Cloud SQL PostgreSQL DB instance |
| [GCP Cloud-Managed Certificates](examples/gcp/gcp-cloud-managed-cert.md) | Deploy Kasm in GCP using an LB ingress and cloud-managed certificates |
| [GCP Ingress](examples/gcp/gcp-ingress.md) | Deploy Kasm in GCP using an LB ingress |

### Examples > Oci

| Title | Description |
|---|---|
| [OCI Ingress](examples/oci/oci-ingress.md) | Deploy Kasm in OCI using the OCI Native Ingress Controller |
| [OCI Service](examples/oci/oci-service.md) | Deploy Kasm in OCI using a Kubernetes service with an OCI LB |

<!-- END TOC -->