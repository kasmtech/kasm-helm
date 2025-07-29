---
title: GCP Ingress
description: Deploy Kasm in GCP using an LB ingress
author: Kasm Technologies
---

# GKE Native Ingress

This guide explains how to deploy **Kasm** into **Google Cloud Platform (GCP) GKE** (Google Kubernetes Engine) using the [GKE Ingress Controller](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress). For the GKE Load Balancer Service approach, see the [GKE Load Balancer Service guide](./gcp-service.md).

> ⚠️ **Notice:** \
> Refer to the [gcp-ingress-example.yaml](./gcp-ingress-basic.yaml) for a sample `values.yaml` to jump start your Helm deployment.

---

## Configure the values.yaml

Configure these settings in your `values.yaml` for a Kasm deployment with GKE ingress controller.

| Variable                    | Value        | Description                                                                                                                             |
|-----------------------------|--------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| `publicAddr`                | *your value* | The URL used to access the Kasm deployment, which can be a private address, must be resolvable by the systems that interface with Kasm. |
| `certificate.secretName`    | *your value* | Name of the Kubernetes secret holding the TLS certificate.                                                                              |
| `proxyService.type`         | `ClusterIP`  | Must be `ClusterIP` so the Helm chart creates an Ingress (not a LoadBalancer Service).                                                  |
| `ingress.enabled`           | `true`       | Enables the Ingress resource in the Helm chart.                                                                                         |
| `ingress.tls`               | `true/false` | Set `true` for HTTPS access to Kasm, `false` for HTTP.                                                                                  |
| `ingress.backendProtocol`   | `http`       | Protocol for the Load Balancer to communicate with Kasm. Currently, this must be set to `http`  for GKE ingress.                        |
| `ingress.annotations`       | `{}`         | Add any GKE ingress annotations (see below).                                                                                            |

> *Configure all other Helm variables as needed for your GKE cluster and environment.*

---

## Common GKE Ingress Annotations

Add these annotations to `ingress.annotations` in your values file as needed:

```yaml
kubernetes.io/ingress.class: 'gce'
kubernetes.io/ingress.allow-http: 'false'
kubernetes.io/ingress.global-static-ip-name: 'kasm-test'
```

Update the value of `kubernetes.io/ingress.global-static-ip-name` to match your static GCP Global IP name.

Note: The `kubernetes.io/ingress.global-static-ip-name` annotation requires that the specified IP address already exists in your GCP project. To reserve a static global IP, see the [GCP documentation](https://cloud.google.com/vpc/docs/reserve-static-external-ip-address#reserve_new_static).

For the list of all GKE ingress annotation options, see [GKE Ingress Annotations](https://cloud.google.com/kubernetes-engine/docs/how-to/load-balance-ingress#ingress_annotations).

## (Optional) Ingress Backend Config

To customize the GKE ingress backend configuration, such as setting a custom backend timeout, define a `BackendConfig` object in the `extraObjects` section of your `values.yaml`.
For more details, see the [GKE Ingress Backend Config](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-configuration#configuring_ingress_features_through_backendconfig_parameters)

```yaml
  - apiVersion: cloud.google.com/v1
    kind: BackendConfig
    metadata:
      name: kasm-proxy-backend-config
    spec:
      timeoutSec: 28800
      connectionDraining:
        drainingTimeoutSec: 60
```

Then, add the following annotation under `proxyService.annotations` to associate the configuration with the proxy service:

```yaml
cloud.google.com/backend-config: '{"default": "kasm-proxy-backend-config"}'
```