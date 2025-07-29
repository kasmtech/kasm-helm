---
title: GCP Kubernetes Service
description: Deploy Kasm in GCP Using Kubernetes Service
author: Kasm Technologies
---

# GKE Kubernetes Service

This guide explains how to deploy **Kasm** into **Google Cloud Platform (GCP) GKE** (Google Kubernetes Engine) using the Kubernetes Service.

> ⚠️ **Notice:** \
> Refer to the [gcp-service.yaml](./gcp-service.yaml) for a sample `values.yaml` to jump start your Helm deployment.

---

## Configure the values.yaml

Configure these settings in your `values.yaml` for a Kasm deployment with GKE Kubernetes Service.

| Variable                       | Value          | Description                                                                                                                             |
|--------------------------------|----------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| `publicAddr`                   | *your value*   | The URL used to access the Kasm deployment, which can be a private address, must be resolvable by the systems that interface with Kasm. |
| `certificate.secretName`       | *your value*   | Name of the Kubernetes secret holding the TLS certificate.                                                                              |
| `proxyService.type`            | `Loadbalancer` | Must be `Loadbalancer` for GCP to create LB in your project.                                                                            |

> *Configure all other Helm variables as needed for your GKE cluster and environment.*

---

## Required GKE Service Annotations

Add the following annotations to the `proxyService.annotation` section of your values.yaml:

```yaml
    cloud.google.com/l4-rbs: "enabled"
    cloud.google.com/app-protocols: '{"":"HTTPS"}'
```

- `cloud.google.com/l4-rbs: "enabled"`: Instructs GKE to create a backend service-based external passthrough Network Load Balancer.
- `cloud.google.com/app-protocols: '{"":"HTTPS"}'`: Ensures that the external Kasm proxy load balancer service communicates over port 443 (HTTPS) for secure communication between the GCP load balancer and the external Kasm proxy service.


For more details, refer to 
- [GKE Service Annotations](https://cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer-parameters#service_parameters)
- [HTTPS (TLS) between Load Balancer and your Application](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-xlb#https_tls_between_load_balancer_and_your_application).


## (Optional) Assign Static IP to the GCP Load Balancer
```yaml
    networking.gke.io/load-balancer-ip-addresses: 'eu-west2-test'
```

Update the value of `networking.gke.io/load-balancer-ip-addresses` to match your static GCP regional IP name.

Note: The `networking.gke.io/load-balancer-ip-addresses` annotation requires that the specified regional IP address already exists in your GCP project. To reserve a static regional IP, see the [GCP documentation](https://cloud.google.com/vpc/docs/reserve-static-external-ip-address#reserve_new_static).


## (Optional) Service Backend Config

To customize the GKE service backend configuration, such as setting a custom backend timeout, define a `BackendConfig` object in the `extraObjects` section of your `values.yaml`.
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

