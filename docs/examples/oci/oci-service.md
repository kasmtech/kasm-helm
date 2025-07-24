---
title: OCI Service
description: Deploy Kasm in OCI using a Kubernetes service with an OCI LB
author: Kasm Technologies
---

# OCI Service

This guide explains how to deploy **Kasm** into **Oracle Cloud (OCI) OKE** (Oracle Kubernetes Engine) using a standard Kubernetes LoadBalancer Service. For the OCI Native Ingress Controller approach, see the [OCI Native Ingress guide](./oci-ingress.md).

> ⚠️ **Notice:**\
> Refer to the [oci-service-example.yaml](./oci-ingress-example.yaml) for a sample `values.yaml` to jump start your Helm deployment.

---

## Required Helm Values

Configure these settings in your `values.yaml` for a Kasm deployment with the LoadBalancer Service:

| Variable                   | Value              | Description                                                                            |
| -------------------------- | ------------------ | -------------------------------------------------------------------------------------- |
| `proxyService.type`        | `LoadBalancer`     | Must be `LoadBalancer` so the Helm chart exposes a service (not an Ingress).           |
| `proxyService.annotations` | `{}`               | Add any OCI Load Balancer-specific annotations (see below).                            |
| `ingress.enabled`          | `false`            | Ingress should be disabled for Service-based exposure.                                 |
| `certificate.secretName`   | *your cert secret* | Name of the Kubernetes secret holding the TLS certificate. Required for HTTPS support. |

> *Configure all other Helm variables as needed for your OKE cluster and environment.*

---

## Common OCI Load Balancer Annotations

Add these annotations to `proxyService.annotations` in your `values.yaml` as needed:

**Required for basic operation:**

```yaml
oci.oraclecloud.com/load-balancer-type: "lb"
external-dns.alpha.kubernetes.io/hostname: "kasm.contoso.com"
service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "1000"
service.beta.kubernetes.io/oci-load-balancer-ssl-ports: "443"
service.beta.kubernetes.io/oci-load-balancer-tls-secret: <your cert secret name>
service.beta.kubernetes.io/oci-load-balancer-backend-protocol: "HTTP"
service.beta.kubernetes.io/oci-load-balancer-tls-backendset-secret: "backendset-cert-secret-name"
```

**Optional/advanced:**

```yaml
service.beta.kubernetes.io/oci-load-balancer-subnet1: "ocid1.subnet.oc1.iad.aaaaaaaa..."
oci.oraclecloud.com/oci-network-security-groups: "ocid1.networksecuritygroup.oc1.iad.aaaaaaaa..."
oci.oraclecloud.com/oci-load-balancer-backendset-ssl-config: '{"CipherSuiteName":"oci-default-http2-tls-12-13-ssl-cipher-suite-v1", "Protocols":["TLSv1.2","TLSv1.3"]}'
oci.oraclecloud.com/oci-load-balancer-listener-ssl-config: '{"CipherSuiteName":"oci-default-http2-tls-12-13-ssl-cipher-suite-v1", "Protocols":["TLSv1.2","TLSv1.3"]}'
```

---

**See the [OCI documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingloadbalancer_topic-Summaryofannotations.htm) for advanced setup and troubleshooting.**
