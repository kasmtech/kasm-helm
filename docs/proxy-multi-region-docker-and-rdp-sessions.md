---
title: Proxy Multi Region RDP and Docker Sessions
description: Guide to deploy Kasm dedicated and connection proxy to support multi-region RDP and Docker sessions
author: Kasm Technologies
---

# Proxy Multi Region RDP and Docker Sessions

By default, if you have users across multiple regions, all of their session traffic is routed through the Kubernetes cluster where the Kasm Helm chart is deployed.

To improve the user experience, you can configure the Helm chart for a multi-zone deployment and provision dedicated and connection proxy VMs in various regions. This ensures that user session traffic is routed through the user’s local region instead of always being sent back to the central Kubernetes cluster, reducing latency and improving performance.

> ⚠️ **Warning:**\
> If you plan to proxy only the Docker sessions, see [Proxy Multi Region Docker Sessions](./proxy-multi-region-docker-sessions.md) instead.
> This guide requires 2 separate VMs within the same region.

---

## Deploy Multi-zone Kasm Helm

In [values.yaml](../charts/kasm/values.yaml), configure the section `kasmZones` to define multiple zones.

For example:

```yaml
publicAddr: kasm.contoso.com
kasmZones: 
   - name: US
     upstream_auth_addr: us.kasm.contoso.com
   - name: EU
     upstream_auth_addr: eu.kasm.contoso.com
```

Then, follow the steps in [README](../README.md) to install Kasm Helm chart.

**Note**: 
1. If your Kubernetes cluster is located in the US, you do not need to deploy external dedicated and connection proxy for the US zone, since the Helm chart already includes a Kasm dedicated proxy within your cluster. A dedicated proxy is only required for the EU zone to serve EU users.
2. The first zone in the list is treated as the primary zone. Traffic to the configured `publicAddr` in the ingress rule will be routed to this primary zone.

---

## Install Kasm Connection Proxy

> ⚠️ **Warning:**\
> The Kasm Connection Proxy must be installed on a separate VM from the Dedicated Proxy. It must have network connectivity to all Windows VMs within the zone that users will access via RDP in Kasm.

Install Kasm connection proxy on a VM in the desired region:

```bash
cd /tmp
curl -O https://kasm-static-content.s3.amazonaws.com/xxx
tar -xf kasm_release*.tar.gz
sudo bash kasm_release/install.sh --role guac --api-hostname {upstream_auth_addr} --public-hostname {CONNECTION_PROXY_HOSTNAME} --registration-token {SERVICE_REGISTRATION_TOKEN} --server-zone {SERVER_ZONE}
```

Modify the command as follows:
1. Replace the `curl` URL to the latest Kasm download release, available [here](https://kasmweb.com/downloads).
2. UPSTREAM_AUTH_ADDR: The `upstream_auth_addr` for the zone you configured in `values.yaml`, e.g., `eu.kasm.contoso.com`.
3. CONNECTION_PROXY_HOSTNAME: The IP, hostname, or FQDN of this Kasm connection proxy that is resolvable and reachable by the dedicated proxy.
4. SERVICE_REGISTRATION_TOKEN: You can find your token with command `kubectl get secret --namespace {namespace} kasm-secrets -o jsonpath="{.data.service-token}" | base64 -d`
5. SERVER_ZONE: The `name` for the zone you configured in `values.yaml`, e.g., `EU`.


---

## Instal Kasm Dedicated Proxy

> ⚠️ **Warning:**\
> The Kasm dedicated proxy need to be installed on a separate VM as the Kasm connection proxy. It must have network connectivity to all Kasm Agents and the Connection Proxy within its zone.

Install the Kasm dedicated proxy on a separate VM in the desired region:

```bash
cd /tmp
curl -O https://kasm-static-content.s3.amazonaws.com/xxx
tar -xf kasm_release*.tar.gz
sudo bash kasm_release/install.sh --role proxy --api-hostname {upstream_auth_addr} --no-start
```

Modify the command as follows:
1. Replace the `curl` URL to the latest Kasm download release, available [here](https://kasmweb.com/downloads).
2. UPSTREAM_AUTH_ADDR: The `upstream_auth_addr` for the zone you configured in `values.yaml`, e.g., `eu.kasm.contoso.com`.

Important: Your dedicated proxy should use the same parent domain as the `upstream_auth_addr`.

For example, if your configuration is:
```yaml
upstream_auth_addr: eu.kasm.contoso.com
```

then the proxy address should be something like:
```text
proxy-eu.kasm.contoso.com
```

For more detailed explanation, see [Kasm Dedicated Proxy Documentation](https://kasmweb.com/docs/latest/install/multi_server_install/multi_installation_proxy.html).

## Additional Kasm Dedicated Proxy Config

Modify and Edit the following command on the Kasm dedicated proxy server.

Replace the value of `CONNECTION_PROXY_HOSTNAME` with the actual connection proxy address, the address needs to be resolvable and reachable by this dedicated proxy VM.


```bash
CONNECTION_PROXY_HOSTNAME="xxx.xxx.xxx.xxx"

sudo tee /tmp/kasmguac_locations.conf >/dev/null <<EOF
location ~ /kasmguac/([0-9a-f-]+)/(\w+)(?!/vnc.htmlguaclite)(/.+) {
  if (\$request_method = OPTIONS) {
    rewrite .* /_options_response last;
  }

  set \$kasm_id  \$1;
  set \$service  \$2;
  set \$new_path \$3;

  proxy_http_version      1.1;
  proxy_set_header        Host ${CONNECTION_PROXY_HOSTNAME};
  proxy_set_header        Upgrade \$http_upgrade;
  proxy_set_header        Connection "upgrade";
  proxy_set_header        X-Real-IP \$remote_addr;
  proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header        X-Forwarded-Proto \$scheme;
  proxy_set_header        X-Kasm-ID "\${kasm_id}";
  proxy_set_header        Authorization "Bearer \${connect_auth}";
  proxy_set_header        Cookie "username=\$cookie_username; session_token=\$cookie_session_token; kasm_client_key=\$cookie_kasm_client_key";

  proxy_pass              https://${CONNECTION_PROXY_HOSTNAME}:443/guac_connect/\$service\$new_path;
  proxy_read_timeout      1800s;
  proxy_send_timeout      1800s;
  proxy_connect_timeout   1800s;
  proxy_buffering         off;
  client_max_body_size 1G;
  expires                 4h;

  proxy_hide_header   'Access-Control-Allow-Credentials';
  proxy_hide_header   'Access-Control-Allow-Origin';
  proxy_hide_header   'Access-Control-Allow-Methods';
  proxy_hide_header   'Access-Control-Allow-Headers';
  proxy_hide_header   'Strict-Transport-Security';
  proxy_hide_header   'X-Content-Type-Options';
  add_header 'Access-Control-Allow-Origin' \$http_origin 'always';
  add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' 'always';
  add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' 'always';
  add_header 'Access-Control-Allow-Credentials' 'true' 'always';
  add_header 'Strict-Transport-Security' "max-age=63072000" always;
  add_header 'X-Content-Type-Options' 'nosniff';
  add_header              Cache-Control "private";
}

location ~ /kasmguac/([0-9a-f-]+)/vnc/vnc.htmlguaclite {
  if (\$request_method = OPTIONS) {
    rewrite .* /_options_response last;
  }

  set \$kasm_id \$1;

  proxy_http_version      1.1;
  proxy_set_header        Host ${CONNECTION_PROXY_HOSTNAME};
  proxy_set_header        Upgrade \$http_upgrade;
  proxy_set_header        Connection "upgrade";
  proxy_set_header        X-Real-IP \$remote_addr;
  proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header        X-Kasm-ID "\${kasm_id}";
  proxy_set_header        Cookie "username=\$cookie_username; session_token=\$cookie_session_token; kasm_client_key=\$cookie_kasm_client_key";

  proxy_pass              https://${CONNECTION_PROXY_HOSTNAME}:443/guac_connect/vnc/vnc.htmlguaclite\$is_args\$args;
  proxy_read_timeout      1800s;
  proxy_send_timeout      1800s;
  proxy_connect_timeout   1800s;
  proxy_buffering         off;
  client_max_body_size 1G;
  expires                 4h;
  add_header              Cache-Control "private";

  proxy_hide_header   'Access-Control-Allow-Credentials';
  proxy_hide_header   'Access-Control-Allow-Origin';
  proxy_hide_header   'Access-Control-Allow-Methods';
  proxy_hide_header   'Access-Control-Allow-Headers';
  proxy_hide_header   'Strict-Transport-Security';
  proxy_hide_header   'X-Content-Type-Options';
  add_header 'Access-Control-Allow-Origin' \$http_origin 'always';
  add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' 'always';
  add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' 'always';
  add_header 'Access-Control-Allow-Credentials' 'true' 'always';
  add_header 'Strict-Transport-Security' "max-age=63072000" always;
  add_header 'X-Content-Type-Options' 'nosniff';
}

EOF

sudo sed -i "/location \/_options_response {/e cat /tmp/kasmguac_locations.conf" \
  /opt/kasm/current/conf/nginx/services.d/upstream_proxy.conf
  
sudo /opt/kasm/bin/start
```

## Configure Kasm Zone

- **Login your Kasm UI**. You can retrieve the admin user `admin@kasm.local` password with the following command

```bash
kubectl get secret --namespace {namespace} kasm-secrets \                                                   
  -o jsonpath="{.data.admin-password}" | base64 -d
```

- In Kasm Admin UI, go to **Infrastructure** -> **Deployment Zones** -> **Edit**  your desired zone (e.g., EU).
    1. Upstream Auth Address: Change to `upstream_auth_addr` from your `values.yaml`. For example, `eu.kasm.contoso.com`.
    2. Proxy Hostname: Change to your dedicated proxy address. For example, `proxy-eu.kasm.contoso.com`.
    3. RDP HTTPS Proxy Hostname: Change to your dedicated proxy address. For example, `proxy-eu.kasm.contoso.com`.

