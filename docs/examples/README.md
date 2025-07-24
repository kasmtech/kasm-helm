---
title: Deployment Examples Table of Contents
description: Practical examples of Kasm deployments
author: Kasm Technologies
---

# Kasm Helm Deployment Examples

This guide provides practical examples and configuration pointers for deploying Kasm on Kubernetes across major cloud providers.

> ⚠️ **Notice:**
> The examples in this guide are starting points only. They are **not** fully production-ready manifests. Kubernetes environments are highly variable. Always adapt these examples to fit your cluster's resources, networking, and security requirements.

---

## How to Use These Examples

* Each example includes an associated `*.yaml` file with comments explaining the modified or critical variable values.
* **You must replace** example values with those that match your environment (e.g., DNS names, load balancer types, storage classes).
* Use these as a baseline for your own automation or infrastructure-as-code practices.

---

## Provided Cloud Examples

### AWS (Amazon Web Services)

* [AWS with Load Balancer Ingress](./aws/aws-ingress.md)
* [AWS with Load Balancer Service](./aws/aws-service.md)
* [AWS with Amazon RDS (Postgres)](./aws/aws-rds.md)

### Oracle Cloud (OCI)

* [OCI with Load Balancer Ingress](./oci/oci-ingress.md)
* [OCI with Load Balancer Service](./oci/oci-service.md)

### Google Cloud Platform (GCP)

* [GCP with Load Balancer Ingress](./gcp/gcp-ingress.md)
* [GCP with Cloud SQL (Postgres)](./gcp/gcp-cloud-sql.md)
* [GCP with Cloud Managed Certificates](./gcp/gcp-cloud-managed-cert.md)

---

## Additional Tips

* Review each linked example for notes on custom values or prerequisites specific to that platform.
* Refer to the [main deployment guide](../README.md) for foundational Helm and Kasm configuration.
* See the [Kasm docs](https://kasmweb.com/docs/) and your cloud provider's Kubernetes documentation for best practices on security, networking, and scaling.

---
