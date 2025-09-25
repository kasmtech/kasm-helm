---
title: Proxy Multi Region Docker Sessions
description: Guide to deploy Kasm dedicated proxy to support multi-region users
author: Kasm Technologies
---

# Proxy Multi Region Docker Sessions

By default, if you have users across multiple regions, all of their session traffic is routed through the Kubernetes cluster where the Kasm Helm chart is deployed.

To improve the user experience, you can configure the Helm chart for a multi-zone deployment and provision dedicated proxy VMs in various regions. This ensures that user session traffic is routed through the user’s local region instead of always being sent back to the central Kubernetes cluster, reducing latency and improving performance.

> ⚠️ **Warning:**\
> If you plan to proxy both the Docker and RDP sessions, see [Proxy Multi Region RDP and Docker Sessions](./proxy-multi-region-docker-and-rdp-sessions.md) instead.


---

## Deploy Multi-zone Kasm Helm

In [values.yaml](../charts/kasm/values.yaml), configure the section `kasmZones` to define multiple zones.

For example:

```yaml
publicAddr: kasm.acme.com
kasmZones: 
   - name: default
     upstream_auth_addr: kasm.acme.com
   - name: EU
     upstream_auth_addr: eu.kasm.acme.com
```

Then, follow the steps in [README](../README.md) to install Kasm Helm chart.

---

## Deploy Dedicated Proxy

> ⚠️ **Warning:**\
> Your Kasm agents for a given zone (e.g., EU) should be deployed in the same region as the dedicated proxy. This ensures session traffic remains local to the region, minimizing latency and optimizing performance.
> The dedicated proxy must have network connectivity to all Kasm agents within its zone.


Install a dedicated proxy on a VM in the desired region.

```bash
cd /tmp
curl -O https://kasm-static-content.s3.amazonaws.com/xxx
tar -xf kasm_release*.tar.gz
sudo bash kasm_release/install.sh --role proxy --api-hostname {UPSTREAM_AUTH_ADDR}
```

Modify the command as follows:
1. Replace the `curl` URL to the latest Kasm download release, available [here](https://kasmweb.com/downloads). 
2. UPSTREAM_AUTH_ADDR: The `upstream_auth_addr` for the zone you configured in `values.yaml`, e.g., `eu.kasm.acme.com`.

Important: Your dedicated proxy should use the same parent domain as the `upstream_auth_addr`. 

For example, if your configuration is:
```yaml
upstream_auth_addr: eu.kasm.acme.com
```

then the proxy address should be something like:
```text
proxy-eu.kasm.acme.com
```

For more detailed explanation, see [Kasm Dedicated Proxy Documentation](https://kasmweb.com/docs/latest/install/multi_server_install/multi_installation_proxy.html).


## Configure Kasm Zone

- **Login your Kasm UI**. You can retrieve the admin user `admin@kasm.local` password with the following command

```bash
kubectl get secret --namespace {namespace} kasm-secrets \                                                   
  -o jsonpath="{.data.admin-password}" | base64 -d
```

- In Kasm Admin UI, go to **Infrastructure** -> **Deployment Zones** -> **Edit**  your desired zone (e.g., EU).
    1. Upstream Auth Address: Change to `upstream_auth_addr` from your `values.yaml`. For example, `eu.kasm.acme.com`.
    2. Proxy Hostname: Change to your dedicated proxy address. For example, `proxy-eu.kasm.acme.com`.

