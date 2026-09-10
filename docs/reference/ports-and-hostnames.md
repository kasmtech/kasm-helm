# Ports and hostnames

> **Applies to:** both halves

Every port, Service name and hostname the charts render or expect. `<release>` is the Helm release
name (`kasm` in the tutorial), `<zone>` the zone name (`default` unless `kasm-helm.kasmZones`
names others), `<agent>` the `Agent` resource name (`kasm-agent.agent.name`, default `k8s-agent`),
`<ns>` the namespace.

## Control plane

| What | Name | Port | Notes |
| ---- | ---- | ---- | ----- |
| Proxy, in-cluster Service | `<release>-proxy-<zone>` | 8080 http, 8443 https | What Ingress, HTTPRoute and Route backends point at; `backendProtocol` picks the listener. The agent registers here at 8080 http when `inClusterControlPlane` derives it |
| Proxy, external Service | `<release>-proxy-ext-<zone>` | 443 | Rendered when `kasm-helm.proxyService.type` is `LoadBalancer` or `NodePort`; publishes 443 onto the proxy's 8443. The release notes read its address back from `<release>-proxy-ext-default` |
| API | `<release>-api` | 8080 | Internal |
| Manager | `<release>-manager` | 8181 | Internal |
| Database | `<release>-db`, or `kasm-helm.database.hostname` when `standalone: true` | `kasm-helm.database.port` (5432) | PostgreSQL 16 |
| Guacamole | `<release>-guac-<zone>` | 3000, nginx sidecar 9000 | Primary-region zones only |
| RDP gateway | `<release>-rdp-gateway-<zone>` | 3389 (from `directRdpService.loadBalancerPort`), nginx sidecar 9001 | Raw TCP; never behind an Ingress. Typed `LoadBalancer`/`NodePort` by `directRdpService`, or fronted by a `TCPRoute`. Primary-region zones only |
| RDP HTTPS gateway | `<release>-rdp-https-gateway-<zone>` | 9443, nginx sidecar 9002 | Reached through the proxy; nothing to publish |
| Credentials Secret | `<release>-secrets` | | `admin-password`, `user-password`, `db-password`, `service-token`, `manager-token` |
| Certificate Secret | `kasm-helm.certificate.secretName`, else `<release>-cert-manager` | | Self-signed when neither `secretName` nor cert-manager is set; CN = `publicAddr` or `kasm.local` |
| Public hostname | `kasm-helm.publicAddr` | 443 | The certificate name, the Ingress/Route/Gateway host, and what Kasm advertises to agents |
| Zone hostnames | `kasm-helm.kasmZones[].proxy_hostname` | `kasmZones[].proxy_port` (443) | Kasm builds session URLs from the zone's port, not from the Service |

## Agent

| What | Name | Port | Notes |
| ---- | ---- | ---- | ----- |
| Session proxy Service | `<agent>-session-proxy` | 4444 https, 4445 http | Created by the operator. 4444 serves `kasm-agent.agent.sessionProxy.certSecretName`; 4445 is for a front end that already terminated TLS |
| Session proxy, relayed hostname | `<agent>-session-proxy.<ns>.svc.cluster.local` | 4444 | The derived `publicHostname` on the relayed default |
| Session proxy, direct-connect hostname | `kasm-agent.agent.publicHostname` | `kasm-agent.agent.publicPort` (443) | Must be a sibling of `publicAddr` under one parent domain |
| Session proxy certificate | `kasm-agent.agent.sessionProxy.certSecretName` (`kasm-session-proxy-tls`) | | Self-signed by the release unless it already exists or `sessionProxy.certificate.enabled` |
| Node ports, when pinned | `sessionProxy.service.httpsNodePort`, `httpNodePort` | 30000 to 32767 | Pin 4444 and 4445 respectively |
| Workspace pod | one Service per session | 6901 | The KasmVNC listener the session proxy forwards to |
| Manager, as the agent sees it | `kasm-agent.agent.manager.hostname` | `manager.port` (443) over `manager.scheme` (https), path `manager.pathPrefix` (`/manager_api`) | Derived to `<release>-proxy-default.<ns>.svc.cluster.local`, 8080, http by `inClusterControlPlane` |
| Manager token | Secret `kasm-agent.agent.manager.existingTokenSecret`, key `tokenSecretKey` (`token`) | | Derived to `<release>-secrets` / `manager-token` by `inClusterControlPlane` |
| OpenTelemetry collector | `<release>-kasm-otel-collector` | 4318 OTLP/HTTP, 4317 OTLP/gRPC, 13133 health | The agent exports to `http://<release>-kasm-otel-collector:4318` by default |
| Baseline NetworkPolicy ports | `networkPolicies.manager.ports` (443, 80), `apiServer.ports` (6443, 443), `sessionProxy.ports` (4444, 4445), `otelBackend.ports` (4317, 4318, 9000) | | Policy is evaluated after DNAT: add the ingress controller's backend port (Traefik 8443) or 8080 for the in-cluster proxy |

## Idle timeouts

Sessions are long-lived WebSockets. The control-plane proxy relays with `proxy_read_timeout 1800s`,
fixed in its ConfigMap. Everything that fronts the session proxy on direct-connect needs 3600s or
more; the per-mechanism knobs are in
[LoadBalancer and NodePort, Idle timeouts](../how-to/networking/loadbalancer-nodeport.md#idle-timeouts).
