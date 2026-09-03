# External access and TLS

> **Applies to:** [Feature matrix](../feature-matrix.md) rows 20 (External access / ingress) and 22 (TLS / trusted CA) · **Charts/values:** `agent.publicHostname`, `agent.publicPort`, `agent.gatewayRoute.*`, `agent.tlsRoute.*`, `agent.httpRoute.*`, `agent.ingress.*`, `agent.route.*`, `agent.sessionProxy.service.*`, `agent.sessionProxy.proxyProtocol.*`, `agent.sessionProxy.certificate.*`, `agent.sessionProxy.certSecretName`, `kasm-helm.publicAddr`, `kasm-helm.ingress.*`, `kasm-helm.route.*`, `kasm-helm.proxyService.type`, `kasm-helm.certificate.*`, `kasm-helm.trustedCaBundle.*`, `kasm-helm.kasmConfig.authDomain`

## Why this is needed

The two halves of a Kasm deployment are exposed **independently**. Users log in to the control
plane; their browsers then stream the session **directly** from the agent's session proxy. Each half
terminates its own TLS, on its own hostname. Get the hostnames, the certificate coverage, the
websocket timeout or the auth-cookie domain wrong and the symptom is always the same-looking
failure — a 404, a 401, or a session that dies after a minute.

## Before you start

* Two hostnames, **siblings under one parent domain** — for example `kasm.example.com` (control
  plane `kasm-helm.publicAddr`) and `sessions.example.com` (agent `agent.publicHostname`). They must
  differ, and the Kasm Authorization Domain must be their shared parent.
* DNS for both, pointing at whatever fronts the cluster.
* Exactly **one** exposure method on the agent side. All five point at the same Service.
* Whatever fronts the session proxy must hold **WebSockets** open: idle timeout ≥ 3600s (or an L4
  idle timeout ≥ 3600s where nothing speaks HTTP).
* cert-manager plus an `Issuer`/`ClusterIssuer`, if you want certificates issued in-cluster.

Distro / cloud variants:

| Platform | Usual choice |
| -------- | ------------ |
| k3s | Traefik. Gateway API provider is **not** on by default — enable it with a `HelmChartConfig` (step 2a). Verified live. |
| kubeadm / vanilla | ingress-nginx (`agent.ingress`), or any Gateway API implementation. |
| EKS / AKS / GKE | Cloud LB in front of ingress-nginx, or `agent.sessionProxy.service.type=LoadBalancer` straight onto the proxy. Raise the LB idle timeout (an AWS NLB defaults to 350s). |
| OpenShift | `agent.route.enabled=true` — passthrough termination is the native path. |

## Steps

1. **Pick one exposure method.**

   | Value | Shape | When |
   | ----- | ----- | ---- |
   | `agent.gatewayRoute.enabled=true` | Operator-managed Gateway API `TLSRoute`, SNI passthrough | **Preferred** where the operator supports it — the route and the Service cannot drift |
   | `agent.tlsRoute.enabled=true` | The same passthrough `TLSRoute`, owned by the Helm release | Older operators, or when the route must be a release object |
   | `agent.httpRoute.enabled=true` | Gateway API `HTTPRoute`, TLS terminated at the Gateway | Standard Gateway API setups |
   | `agent.ingress.enabled=true` | `networking.k8s.io/v1` Ingress | ingress-nginx / Traefik ingress |
   | `agent.route.enabled=true` | OpenShift `Route` | OpenShift |
   | *(none)* + `agent.sessionProxy.service.type` | `NodePort` / `LoadBalancer` on the proxy Service | No ingress layer at all |

   Full comparison: [External access](../../charts/kasm-agent-instance/README.md#external-access) and
   [`gatewayRoute` vs `tlsRoute`](../../charts/kasm-agent-instance/README.md#gatewayroute-vs-tlsroute--who-owns-the-route).

2. **Gateway API path.** The Gateway's listener must both carry the hostname **and admit routes from
   the agent's namespace**.

   **2a — k3s / Traefik.** The Gateway provider is off by default; enable it with a `HelmChartConfig`
   in `kube-system` (k3s reconciles it automatically). This is the shape that was verified on the lab
   cluster; check `helm show values traefik/traefik` against your Traefik version:

   ```yaml
   apiVersion: helm.cattle.io/v1
   kind: HelmChartConfig
   metadata:
     name: traefik
     namespace: kube-system
   spec:
     valuesContent: |-
       providers:
         kubernetesGateway:
           enabled: true
       gateway:
         enabled: true
         listeners:
           websecure:
             port: 8443              # Traefik's backend port; :443 on the node DNATs to it
             protocol: HTTPS
             hostname: sessions.example.com
             namespacePolicy: All    # must admit the agent namespace
             certificateRefs:
               - name: kasm-agent-public-tls
   ```

   Then in the agent values:

   ```yaml
   agent:
     httpRoute:
       enabled: true
       parentRefs:
         - name: traefik-gateway
           namespace: kube-system
   ```

   **2b — TLS passthrough** (`agent.gatewayRoute` or `agent.tlsRoute`) needs a listener declared with
   `protocol: TLS` and `tls.mode: Passthrough`. A normal terminating HTTPS listener will not serve a
   `TLSRoute`, and `TLSRoute` ships only in the Gateway API's **experimental** channel:

   ```yaml
   listeners:
     - name: tls-passthrough
       protocol: TLS
       port: 443
       hostname: sessions.example.com
       tls:
         mode: Passthrough
       allowedRoutes:
         namespaces:
           from: Selector
           selector:
             matchLabels:
               kubernetes.io/metadata.name: kasm-agent
   ```

   ```yaml
   agent:
     gatewayRoute:
       enabled: true
       parentRef:
         name: traefik-gateway
         namespace: kube-system
         sectionName: tls-passthrough
   ```

   Note the shape difference: `gatewayRoute.parentRef` is a **single** reference;
   `tlsRoute.parentRefs` is a list.

3. **Set the websocket / idle timeout.** Ingress path:

   ```yaml
   agent:
     ingress:
       enabled: true
       className: nginx
       annotations:
         nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
         nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
       tls:
         - secretName: kasm-agent-public-tls
           hosts:
             - sessions.example.com
   ```

   OpenShift: `haproxy.router.openshift.io/timeout: "3600s"` in `agent.route.annotations`.
   Passthrough routes and direct Service exposure have no HTTP knob — raise the **L4 idle timeout**
   on the Gateway's data plane or the load balancer instead.

4. **Issue the session-proxy certificate.** Browsers connect to the proxy directly, so its
   certificate must be publicly trusted — a cluster-internal CA is not enough. Cover the public
   hostname **and** its wildcard:

   ```yaml
   agent:
     sessionProxy:
       certificate:
         enabled: true
         issuerRef:
           kind: ClusterIssuer
           name: letsencrypt-prod
         dnsNames:
           - sessions.example.com
           - "*.sessions.example.com"
   ```

   Bringing your own instead: create a `kubernetes.io/tls` Secret in the release namespace and set
   `agent.sessionProxy.certSecretName`.

   On the control-plane side, either supply `kasm-helm.certificate.secretName` or let cert-manager
   issue it, keeping the wildcard on:

   ```yaml
   kasm-helm:
     certificate:
       secretName: kasm-tls
       certManager:
         enabled: true
         addWildCard: true
         issuerName: letsencrypt-prod
         issuerKind: ClusterIssuer
   ```

5. **Set the Kasm Authorization Domain** to the shared parent, or every direct session connection
   401s. On a **fresh** control plane this is a value:

   ```yaml
   kasm-helm:
     kasmConfig:
       generatePreseed: true
       authDomain: example.com
   ```

   On an **existing** control plane the preseed does not run — change *Kasm Auth Domain* in
   Settings → Auth, and the zone's *Proxy Connections* (off) and *Upstream Auth Address* (the control
   plane's `publicAddr`) in Infrastructure → Zones. Background:
   [Running alongside the kasm-helm control plane](../../charts/kasm-agent/README.md#running-alongside-the-kasm-helm-control-plane).

6. **Keep the control plane on `ClusterIP`** when an ingress fronts it. A `LoadBalancer` there claims
   the node's :443, which the controller fronting the session proxy usually already holds — the chart
   rejects that combination outright.

   ```yaml
   kasm-helm:
     proxyService:
       type: ClusterIP
     ingress:
       enabled: true
       ingressClassName: traefik
       backendProtocol: http
   ```

7. **Preserve real client IPs** (optional, pick one):

   ```yaml
   agent:
     sessionProxy:
       service:
         type: LoadBalancer
         externalTrafficPolicy: Local     # L4: no SNAT, but only routes via nodes running a proxy pod
   ```

   ```yaml
   agent:
     sessionProxy:
       proxyProtocol:
         enabled: true                    # L7: the fronting proxy MUST send PROXY protocol
         trustedCIDRs:
           - 10.0.0.0/16
   ```

   `proxyProtocol` is all-or-nothing: once on, nginx requires a PROXY header on **every** connection,
   so browsers, health checks and `curl` hitting the listener directly all break.

8. **Internal CAs inside the cluster** go in with
   `kasm-helm.trustedCaBundle.enabled=true` and `kasm-helm.trustedCaBundle.caCerts`. CA certificates
   *inside sessions* are a different mechanism entirely — file mappings under
   `/usr/local/share/ca-certificates/` plus an `update-ca-certificates` start command.

**TLS passthrough (`agent.gatewayRoute` / `agent.tlsRoute`) — verified recipe.** The Gateway needs a listener with `protocol: TLS` and `tls.mode: Passthrough` for the passthrough hostname; on Traefik 3.7 (Gateway API 1.5.1) it can share port 8443 with the terminated HTTPS listener as long as the hostnames differ:

```yaml
- name: sessions-passthrough
  port: 8443
  protocol: TLS
  hostname: sessions.example.com
  tls:
    mode: Passthrough
  allowedRoutes:
    namespaces:
      from: Selector
      selector:
        matchExpressions:
          - {key: kubernetes.io/metadata.name, operator: In, values: [kasm, kasm-agent]}
```

Point the route at it with `agent.gatewayRoute.parentRef.sectionName=sessions-passthrough` and `agent.gatewayRoute.hostnames[0]=sessions.example.com`; the session proxy certificate must cover that hostname (the `*.<publicHostname>` wildcard does). Prove it is really passthrough by comparing certificate fingerprints — the client must receive the **session proxy's** certificate, not the gateway's:

```console
kubectl get secret kasm-session-proxy-tls -n kasm -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -fingerprint -sha256
echo | openssl s_client -servername sessions.example.com -connect <node-or-lb>:443 2>/dev/null | openssl x509 -noout -fingerprint -sha256
```

Check the listener's own `Accepted`/`Programmed` conditions and the TLSRoute's `status.parents` before trusting a k3s `HelmChartConfig` edit: on this lab the identical listener declared through Traefik's chart values made the chart's upgrade job fail and briefly removed the Gateway object, while patching the live Gateway programmed it immediately. Validate on the Gateway first, then move the listener into your chart values.

## Verify

```console
curl -k -sS -o /dev/null -w '%{http_code}\n' https://sessions.example.com/
openssl s_client -connect sessions.example.com:443 -servername sessions.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -ext subjectAltName
```

Expected indicators:

* The `curl` returns an HTTP status from the session proxy — **`404` is normal** with no active
  session. A connection refused/timeout means the route or the Service exposure is wrong.
* The certificate's SANs include `sessions.example.com`. On a passthrough route
  (`gatewayRoute`/`tlsRoute`/OpenShift `Route`) the certificate you see is the **session proxy's
  own**; on `httpRoute`/`ingress` it is the Gateway's.
* Gateway API path:

  ```console
  kubectl -n kasm-agent get httproute,tlsroute -o wide
  kubectl -n kasm-agent describe httproute <name> | grep -A3 'Parents\|Accepted'
  ```

  `Accepted: True` and `ResolvedRefs: True`. `Accepted: False` with `NotAllowedByListeners` means the
  listener does not admit this namespace.
* Log in at the control-plane hostname and launch a session: the browser URL bar shows the **agent's**
  hostname, and the session stays up past 60 seconds (proof the websocket timeout is raised).

## Chart values

Minimal, under the `kasm-platform` umbrella:

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  proxyService:
    type: ClusterIP
  ingress:
    enabled: true
    ingressClassName: traefik
  certificate:
    secretName: kasm-tls
  kasmConfig:
    generatePreseed: true
    authDomain: example.com

kasm-agent:
  agent:
    publicHostname: sessions.example.com
    gatewayRoute:
      enabled: true
      parentRef:
        name: traefik-gateway
        namespace: kube-system
        sectionName: tls-passthrough
    sessionProxy:
      certificate:
        enabled: true
        issuerRef:
          kind: ClusterIssuer
          name: letsencrypt-prod
        dnsNames:
          - sessions.example.com
          - "*.sessions.example.com"
```

Installing the charts directly? Drop the `kasm-agent:` key (start at `agent:`) for `kasm-agent`, and
drop the `kasm-helm:` key for `kasm-helm`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Session connect returns **401** | The auth cookie is scoped to the control-plane hostname only | Set the Kasm Auth Domain to the shared parent — `kasm-helm.kasmConfig.authDomain` on a fresh install, Settings → Auth on an existing one; then use a fresh incognito window |
| Session connect returns **404** from the ingress | The zone's *Proxy Connections* is on, so traffic is relayed with the original `Host` header and matches no route | Disable *Proxy Connections* and set *Upstream Auth Address* to the control plane's `publicAddr` |
| Session dies after ~60s (ingress-nginx) or ~30s (OpenShift router) | Default proxy timeouts cut the websocket | `proxy-read-timeout` / `proxy-send-timeout` `3600`, or `haproxy.router.openshift.io/timeout: 3600s` |
| Idle passthrough sessions dropped at ~350s | The L4 idle timeout on the load balancer (AWS NLB default) | Raise the LB idle timeout; there is no HTTP knob on a passthrough path |
| `HTTPRoute`/`TLSRoute` shows `Accepted: False` | The Gateway listener does not admit the agent namespace, or the hostname does not match | Fix the listener's `allowedRoutes` and `hostname` |
| `TLSRoute` not recognised by the API server | It ships in the Gateway API **experimental** channel only | Install the experimental CRDs, or use `httpRoute`/`ingress` |
| Browser certificate warning on the session hostname | Passthrough route serving the session proxy's own certificate, which does not cover the public hostname | Add the hostname (and `*.<hostname>`) to `agent.sessionProxy.certificate.dnsNames`, or provision `agent.sessionProxy.certSecretName` |
| NodePort answers in-cluster, refused from a LAN client | The environment does not route 30000–32767 to the nodes | Open the range, or front the proxy with an ingress/LB |
| Everything breaks the moment PROXY protocol is enabled | The fronting proxy is not sending a PROXY header | Enable it on the load balancer too, or turn `agent.sessionProxy.proxyProtocol.enabled` back off |
| Some clients time out with `externalTrafficPolicy: Local` | Traffic routed via a node with no session-proxy pod | Raise `agent.sessionProxy.replicas`, pin with `nodeSelector`, or use an LB that honours the health check |
| Control-plane install rejected with a port conflict | `kasm-helm.proxyService.type=LoadBalancer` alongside an ingress | Set it to `ClusterIP` |

- **Agent shows `Degraded=True/TLSRouteForbidden` (or `TLSRouteUnavailable`) and no TLSRoute appears** → the operator cannot manage TLSRoutes: its `manager-role` lacks the `gateway.networking.k8s.io/tlsroutes` rule, or the TLSRoute CRD is not served (Gateway API standard channel ≥ 1.5). Everything else keeps reconciling — Service, session proxy, workspaces — so sessions stay up; only `agent.gatewayRoute` is unfulfilled and `GatewayRouteAccepted=False`. Fix: reinstall/upgrade the operator chart (its `manager-role` ships the rule; a `helm upgrade` also reverts any manual RBAC edit) or install the Gateway API CRDs, then the operator creates the TLSRoute and the condition clears without a restart of anything else.

## Checklist

- [ ] Two sibling hostnames under one parent domain, DNS in place
- [ ] Exactly one of `gatewayRoute` / `tlsRoute` / `httpRoute` / `ingress` / `route` / direct `sessionProxy.service`
- [ ] Gateway listener carries the hostname and admits the agent namespace (passthrough listener uses `protocol: TLS`, `tls.mode: Passthrough`)
- [ ] Websocket / L4 idle timeout ≥ 3600s on whatever fronts the proxy
- [ ] Session-proxy certificate covers the public hostname **and** `*.<hostname>`, publicly trusted
- [ ] Control-plane certificate in place; `kasm-helm.proxyService.type=ClusterIP` behind an ingress
- [ ] Kasm Auth Domain set to the shared parent; zone *Proxy Connections* off, *Upstream Auth Address* set
- [ ] Client-IP strategy chosen (`externalTrafficPolicy=Local` **or** `proxyProtocol` + `trustedCIDRs`)
- [ ] `curl -k https://<agent hostname>/` answers (404 with no session is expected)
- [ ] A browser session connects and survives past 60 seconds
