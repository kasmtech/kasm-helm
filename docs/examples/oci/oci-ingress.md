---

title: OCI Native Ingress
description: Deploy Kasm in OCI using the OCI Native Ingress Controller
author: Kasm Technologies
-------------------------

# OCI Native Ingress

This guide explains how to deploy **Kasm** into **Oracle Cloud (OCI) OKE** (Oracle Kubernetes Engine) using the [OCI Native Ingress Controller](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengsettingupnativeingresscontroller.htm). For the OCI Load Balancer Service approach, see the [OCI Load Balancer Service guide](./oci-service.md).

> ⚠️ **Notice:** \
> Refer to the [oci-ingress-class.yaml](./oci-ingress-class.yaml) for a sample manifest to set up the OCI Native Ingress Controller. \
> Refer to the [oci-ingress-example.yaml](./oci-ingress-example.yaml) for a sample `values.yaml` to jump start your Helm deployment.

---

## Required Helm Values

Configure these settings in your `values.yaml` for a Kasm deployment with the OCI Native Ingress Controller:

| Variable                   | Value        | Description                                                                                                           |
| -------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------- |
| `proxyService.type`        | `ClusterIP`  | Must be `ClusterIP` so the Helm chart creates an Ingress (not a LoadBalancer Service).                                |
| `ingress.enabled`          | `true`       | Enables the Ingress resource in the Helm chart.                                                                       |
| `ingress.tls`              | `true/false` | Set `true` for HTTPS access to Kasm, `false` for HTTP.                                                                |
| `ingress.backendProtocol`  | `http/https` | Protocol for the Load Balancer to communicate with Kasm. Use `https` for secure backend (adds proper LB annotations). |
| `ingress.ingressClassName` | *your value* | Must match the name of the `IngressClass` created for the OCI Ingress Controller.                                     |
| `ingress.annotations`      | `{}`         | Add any OCI Load Balancer-specific annotations (see below).                                                           |
| `certificate.secretName`   | *your value* | Name of the Kubernetes secret holding the TLS certificate. Required for HTTPS or secure backend protocols.            |

> *Configure all other Helm variables as needed for your OKE cluster and environment.*

---

## Common OCI LB Annotations

Add these annotations to `ingress.annotations` in your values file as needed:

**Required for standard operation:**

```yaml
oci-native-ingress.oraclecloud.com/http-listener-port: "80"
oci-native-ingress.oraclecloud.com/https-listener-port: "443"
```

**Optional & Advanced (health checks, TLS, etc.):**

```yaml
oci-native-ingress.oraclecloud.com/backend-tls-enabled: "true"
oci-native-ingress.oraclecloud.com/healthcheck-protocol: "HTTP"
oci-native-ingress.oraclecloud.com/healthcheck-port: "8443"
oci-native-ingress.oraclecloud.com/healthcheck-path: "/api/__healthcheck"
oci-native-ingress.oraclecloud.com/healthcheck-interval-milliseconds: "30000"
oci-native-ingress.oraclecloud.com/healthcheck-timeout-milliseconds: "3000"
oci-native-ingress.oraclecloud.com/healthcheck-retries: "3"
oci-native-ingress.oraclecloud.com/healthcheck-return-code: "200"
oci-native-ingress.oraclecloud.com/healthcheck-response-regex: '{"ok": true}'
```

---

### Using OCI Certificates Service for LB Certificate

To use the **OCI Certificates service** for your Load Balancer certificate, add:

```yaml
oci-native-ingress.oraclecloud.com/certificate-ocid: ocid1.certificate.oc1.iad.amaaaaaa______gabc
```

> **Note:**
> Even if you use the OCI Certificates service for the Load Balancer certificate, you **must** still create a Kubernetes certificate secret and set its name in `certificate.secretName`.
> This secret does **not** need to be trusted by the world, but is required for:
>
> * Internal Kasm service communication
> * Backend communication when `ingress.backendProtocol` is set to `"https"`

---

**See the [OCI documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengsettingupnativeingresscontroller.htm) for advanced setup and troubleshooting.**
