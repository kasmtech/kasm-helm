# LoadBalancer and NodePort

> **Applies to:** both halves

## Why this is needed

No ingress controller, no Gateway, no router: the Service is the external address, and TLS
terminates on the workload itself. This is the `kasm-platform` default for the control plane
(`kasm-helm.proxyService.type: LoadBalancer`), the one option that needs neither an ingress
controller nor a load-balancer provider (`NodePort`), and the common way to publish an agent on a
relayed zone from another cluster, because a Service does no `Host` routing.

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#eef3f8","primaryBorderColor":"#5b7a99","primaryTextColor":"#1d2b3a","secondaryColor":"#fbf3e6","secondaryBorderColor":"#b8863b","tertiaryColor":"#eaf5ec","tertiaryBorderColor":"#4f8a5b","lineColor":"#5b7a99","fontFamily":"Inter, Helvetica, Arial, sans-serif","fontSize":"14px"},"flowchart":{"curve":"basis","htmlLabels":true}}}%%
flowchart LR
  browser["Browser"] -->|"HTTPS 443 · the workload's certificate"| lb["LoadBalancer"]
  lb -->|"TCP 8443 · Service kasm-proxy-ext-default"| cp["Control plane proxy"]
  lb -->|"TCP 4444 · Service k8s-agent-session-proxy"| sp["Session proxy"]
  sp -->|"6901"| ws["Workspace pod"]
  classDef agent fill:#eaf5ec,stroke:#4f8a5b
  classDef ext fill:#fbf3e6,stroke:#b8863b
  class sp,ws agent
  class browser,lb ext
```

## Before you start

- For `LoadBalancer`: a controller that provisions one (a cloud provider, MetalLB, the ServiceLB
  that ships with k3s and k3d, or `cloud-provider-kind` for kind). Without one the Service sits at
  `<pending>` forever:

  ```console
  kubectl get svc -A | grep LoadBalancer
  ```

  Expected: existing LoadBalancer Services show real addresses in `EXTERNAL-IP`. MetalLB's
  speaker skips nodes carrying `node.kubernetes.io/exclude-from-external-load-balancers`, which
  kubeadm puts on control-plane nodes: on a single-node or control-plane-only cluster the address
  is allocated and never announced until `speaker.ignoreExcludeLB=true` is set (MetalLB 0.16).
- A Service publishes the session proxy's **own** ports, 4444 (HTTPS) and 4445 (HTTP). The
  `Agent` resource has no Service port field, so a `LoadBalancer` Service never presents 443;
  only a load balancer you run outside the Service can map 443 to 4444.

- For `NodePort`: a port in 30000 to 32767 open on every node the load balancer or DNS points at,
  and a node address clients can reach (`kubectl get nodes -o wide`). A VM host that only forwards
  443 refuses the connection before Kubernetes sees it.
- An L4 idle timeout of 3600s or more on whatever fronts the Service; see
  [Idle timeouts](#idle-timeouts). An AWS NLB defaults to 350s.
- Certificates: the workload's own is what browsers see. The control plane's is
  `kasm-helm.certificate.secretName` or the self-signed default; the session proxy's is
  `kasm-agent.agent.sessionProxy.certSecretName` (`kasm-session-proxy-tls`), self-signed unless you
  pre-create it or enable `sessionProxy.certificate`. On direct-connect the session proxy's must be
  publicly trusted; on the relayed default browsers never see it. [Certificates](certificates.md).

> **Note.** On k3s, Traefik already holds `:443` on every node through ServiceLB. The default
> `proxyService.type=LoadBalancer` asks for the same port, so its ServiceLB pods never schedule and
> the Service stays `<pending>` while the release looks healthy. Use `NodePort`, or publish through
> Traefik with an [Ingress](ingress.md).

## Steps

1. **Control plane, `LoadBalancer`.** The chart renders a second, externally typed Service
   `<release>-proxy-ext-<zone>` publishing 443 onto the proxy's HTTPS listener; the in-cluster
   `<release>-proxy-<zone>` stays as it is.

   ```yaml
   kasm-helm:
     publicAddr: kasm.example.com
     proxyService:
       type: LoadBalancer
       annotations:
         service.beta.kubernetes.io/aws-load-balancer-type: nlb
   ```

   Two combinations the chart refuses: `LoadBalancer` or `NodePort` **with** an Ingress, Route or
   Gateway API route (a second door with a different certificate and timeouts, and on k3s a port
   collision), and either **with** `kasmZones` (one address cannot route by hostname; multi-zone
   needs a front end).

2. **Control plane, `NodePort`.** Kubernetes assigns a port from 30000 to 32767 unless you pin one.

   ```yaml
   kasm-helm:
     proxyService:
       type: NodePort
       nodePort: 31443          # optional; omit to let Kubernetes choose
   ```

   > **Warning.** Kasm builds session URLs from the zone's `proxy_port`, not from this Service.
   > Publish on 32010 while the zone still says 443 and users log in, then every session sends the
   > browser to `https://<host>:443/…` where nothing listens. Set `kasm-helm.kasmZones[].proxy_port`
   > to the node port (preseed, so at database initialization) or change **Proxy Port** under
   > Infrastructure → Zones on a running deployment.

3. **Agent.** Two ports, two owners. `agent.publicPort` is the port the **manager and API** use
   to reach the session proxy (the hello and create calls for every launch, and the session
   proxy's own hairpin); it must be the port the Service actually exposes, and it is derived to
   4444 only while `publicHostname` is left empty, 443 otherwise. Browsers, on direct-connect,
   are sent to `publicHostname` on the **zone's `proxy_port`**, which Kasm reads from the zone
   record and never from `publicPort`. So a NodePort, or a LoadBalancer on anything but 443, needs
   the zone's *Proxy Port* set to the same number: `kasm-helm.kasmZones[].proxy_port` at
   database initialization, or **Infrastructure → Zones** on a running deployment
   ([Kasm docs: Deployment Zones](https://www.kasmweb.com/docs/latest/guide/zones/deployment_zones.html)).
   Verified on Kasm 1.19: with `publicPort: 30443` and the zone at 443, the API reached the agent
   on 30443 and the browser was sent to `:443`. On the relayed default the zone's `proxy_port` is
   the control plane's published port instead, and `publicPort` is the only port that matters for
   the agent.

   LoadBalancer:

   ```yaml
   kasm-agent:
     agent:
       publicHostname: sessions.example.com
       publicPort: 4444                 # the Service exposes the proxy's own 4444, not 443
       sessionProxy:
         service:
           type: LoadBalancer
           externalTrafficPolicy: Local
   ```

   On direct-connect, set the zone's Proxy Port to 4444 as well, or run a load balancer outside
   the Service that maps 443 to 4444 and keep both at 443.

   NodePort with a pinned port:

   ```yaml
   kasm-agent:
     agent:
       publicHostname: sessions.example.com
       publicPort: 30443
       sessionProxy:
         service:
           type: NodePort
           httpsNodePort: 30443
   ```

   `httpsNodePort` pins the proxy's HTTPS listener (4444); `httpNodePort` pins the plain-HTTP one
   (4445) for when TLS is terminated in front. Both stay stable across reconciles even unpinned.
   On direct-connect, set the zone's Proxy Port to 30443 and finish
   [Switch sessions to direct-connect](direct-connect.md). The step-2 warning applies to the
   agent the same way: a zone has one `proxy_port`, so on direct-connect the sessions' port is
   the one it has to carry.

4. **Install or upgrade**, then point DNS at the address the Service gets.

## Verify

```console
kubectl -n kasm get svc kasm-proxy-ext-default
```

Expected:

```text
NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)         AGE
kasm-proxy-ext-default   LoadBalancer   10.43.10.201   10.0.0.42      443:31856/TCP   2m
```

or, for `NodePort`, `TYPE NodePort` with `443:32010/TCP`. `EXTERNAL-IP` stuck at `<pending>` means
no load-balancer controller.

```console
curl -sk -o /dev/null -w '%{http_code}\n' https://<address>/
kubectl -n kasm-agent get svc k8s-agent-session-proxy
curl -kI https://sessions.example.com:4444/      # :30443 on the NodePort example
```

Expected: `200` from the control plane; the session-proxy Service with a real `EXTERNAL-IP` and
`4444:<nodeport>/TCP,4445:<nodeport>/TCP`, or `4444:30443/TCP` on the NodePort example; an HTTP
status line from the session hostname on that port, `404` being correct with no session, served
with the session proxy's own certificate. Run the `curl` from **outside** the cluster, on the
network path a user will be on: a NodePort that answers from a node and refuses from a laptop is
a firewall problem. On direct-connect, launch a session and read the port in the address bar: it
is the zone's `proxy_port`, and it must be the one that answered above. The session-proxy access
log then shows the hairpin, `/desktop/<id>/...` followed by `/container/<id>/...`, both `200`.

## Chart values

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  proxyService:
    type: LoadBalancer           # or NodePort, with nodePort: 31443

kasm-agent:
  agent:
    publicHostname: sessions.example.com
    publicPort: 4444             # the Service port; 30443 with a pinned NodePort
    sessionProxy:
      service:
        type: LoadBalancer       # or NodePort, with httpsNodePort
        externalTrafficPolicy: Local
```

On direct-connect the zone's `proxy_port` carries the same number.

Installing the charts directly, drop the `kasm-helm:` and `kasm-agent:` keys.

## Preserving real client IPs

Optional. One mechanism works today:

```yaml
kasm-agent:
  agent:
    sessionProxy:
      service:
        type: LoadBalancer
        externalTrafficPolicy: Local     # L4: no SNAT, but only routes via nodes running a proxy pod
```

Verified: with `Local` the session-proxy access log records the client's own address; with the
default `Cluster` it records the node's SNAT address.

> **Warning.** `agent.sessionProxy.proxyProtocol.enabled` and `trustedCIDRs` are accepted by the
> chart and written to the `Agent` resource, but they are **not yet honoured by the operator**: the
> session proxy's nginx keeps a plain `listen 4444 ssl` with no `proxy_protocol` or
> `set_real_ip_from`, the Deployment is not rolled, and plain connections keep answering. Do not
> enable PROXY protocol on a load balancer expecting the session proxy to read it; use
> `externalTrafficPolicy: Local` until the operator implements it.

## Idle timeouts

Kasm sessions are long-lived WebSockets, and every default in this space is too short. This is
the one table; other pages link here.

| Path | Knob |
| ---- | ---- |
| `kasm-agent.agent.ingress` (ingress-nginx) | `nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"` and `proxy-send-timeout` in `agent.ingress.annotations`; the default is 60s |
| `kasm-agent.agent.route` (OpenShift) | `haproxy.router.openshift.io/timeout: "3600s"` in `agent.route.annotations`; the default is 30s |
| `kasm-agent.agent.httpRoute` | the Gateway data plane's own idle timeout; not a Kasm value |
| `kasm-agent.agent.httpRoute` on Envoy Gateway | a `ClientTrafficPolicy` targeting the Gateway, with `spec.timeout.tcp.idleTimeout` and `spec.timeout.http.idleTimeout` at `3600s`; the defaults are one hour for the connection and five minutes for a stream. Verified on Envoy Gateway 1.6 |
| passthrough and published Service | no HTTP knob exists; raise the **L4 idle timeout** on the Gateway's data plane or the load balancer (an AWS NLB defaults to 350s) |
| the relayed default | fixed at 1800s (30 minutes) in the control-plane proxy ConfigMap; not a value. Switch to direct-connect to go past it |

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md).

## Decisions

- [ ] `LoadBalancer` with a provider that hands out addresses, or `NodePort` with the range open and the zone's `proxy_port` matched.
- [ ] Not combined with an Ingress, Route or Gateway API route, and not with `kasmZones`.
- [ ] `agent.publicPort` equals the port the Service exposes (4444, or the pinned node port); on direct-connect the zone's `proxy_port` equals it too.
- [ ] Client-IP strategy: `externalTrafficPolicy: Local`; `proxyProtocol` left off until the operator honours it.
- [ ] L4 idle timeout raised to 3600s on whatever fronts the Service.
- [ ] Certificates: the workload's own, publicly trusted where browsers reach it directly.
