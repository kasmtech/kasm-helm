# OpenShift Route

> **Applies to:** both halves

## Why this is needed

The native path on OpenShift. The router is always there, it handles WebSockets, and `passthrough`
termination gives the agent half end-to-end TLS without the Gateway API. Set
`kasm-helm.isOpenshift=true` as well, so the chart drops its explicit UID/GID settings and lets
OpenShift assign them from the namespace's range.

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#eef3f8","primaryBorderColor":"#5b7a99","primaryTextColor":"#1d2b3a","secondaryColor":"#fbf3e6","secondaryBorderColor":"#b8863b","tertiaryColor":"#eaf5ec","tertiaryBorderColor":"#4f8a5b","lineColor":"#5b7a99","fontFamily":"Inter, Helvetica, Arial, sans-serif","fontSize":"14px"},"flowchart":{"curve":"basis","htmlLabels":true}}}%%
flowchart LR
  browser["Browser"] -->|"HTTPS 443"| route["OpenShift router"]
  route -->|"HTTP 8080 · edge · kasm.example.com"| cp["Control plane proxy"]
  route -->|"TCP 4444 · passthrough · sessions.apps.ocp.example.com"| sp["Session proxy"]
  sp -->|"6901"| ws["Workspace pod"]
  classDef agent fill:#eaf5ec,stroke:#4f8a5b
  classDef ext fill:#fbf3e6,stroke:#b8863b
  class sp,ws agent
  class browser,route ext
```

## Before you start

- The `route.openshift.io` API, so OpenShift or OKD:

  ```console
  kubectl api-resources --api-group=route.openshift.io
  ```

  Expected: a `routes` row. Nothing means this is not OpenShift.

- A router shard that admits the namespaces, and the hostnames under a domain the router serves:

  ```console
  oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}{"\n"}'
  ```

  Expected: something like `apps.ocp.example.com`. A hostname under it needs no extra DNS; one
  outside it needs its own record pointing at the router.

- Certificates: for the control plane's `edge` termination, a certificate the router serves; for
  the agent's `passthrough`, a publicly trusted certificate on the session proxy covering the
  hostname and its wildcard ([Certificates](certificates.md)).
- The router's default connection timeout is **30 seconds**; the annotation in
  [Idle timeouts](loadbalancer-nodeport.md#idle-timeouts) is effectively mandatory on the agent.
- SecurityContextConstraints gate the privileged charts on OpenShift in addition to Pod Security
  admission: [Privileged workloads and cluster policy](../nodes/privileged-workloads.md).

## Steps

1. **Control plane.** Leaving `route.tls` empty renders a Route with no TLS stanza at all, plain
   HTTP on port 80; set at least `termination`.

   ```yaml
   kasm-helm:
     isOpenshift: true
     publicAddr: kasm.example.com
     proxyService:
       type: ClusterIP
     route:
       enabled: true
       backendProtocol: http
       tls:
         termination: edge
         insecureEdgeTerminationPolicy: Redirect
   ```

   Multi-zone renders one Route per zone plus one for `publicAddr`, because a Route carries a single
   host; `route.*` settings apply to all of them and the certificate must cover every zone hostname.
   `ingress.enabled` and `route.enabled` are mutually exclusive.

2. **Agent, direct-connect only.**

   ```yaml
   kasm-agent:
     agent:
       publicHostname: sessions.apps.ocp.example.com
       route:
         enabled: true
         annotations:
           haproxy.router.openshift.io/timeout: "3600s"
         tls:
           termination: passthrough
           insecureEdgeTerminationPolicy: Redirect
       sessionProxy:
         certificate:
           enabled: true
           issuerRef:
             kind: ClusterIssuer
             name: letsencrypt-prod
           dnsNames:
             - sessions.apps.ocp.example.com
             - "*.sessions.apps.ocp.example.com"
   ```

   `route.host` defaults to `publicHostname`. `route.backendPort` follows the termination mode when
   left empty: 4444 for `passthrough` and `reencrypt`, 4445 for `edge`. On direct-connect, finish
   [Switch sessions to direct-connect](direct-connect.md), and read its warning first: a
   `passthrough` Route routes on SNI, which the session proxy's own hairpin does not send, so
   expect the known issue there; `edge` and `reencrypt` route on the `Host` header. A relayed
   agent from another cluster behind a `passthrough` Route is unverified for the same reason. None
   of this has been exercised on OpenShift itself.

3. **Install or upgrade.**

   ```console
   helm upgrade --install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
     -n kasm --create-namespace -f values.yaml
   ```

## Verify

```console
kubectl -n kasm get routes.route.openshift.io
```

Expected:

```text
NAME               HOST/PORT                  SERVICES            PORT   TERMINATION     WILDCARD
kasm-proxy         kasm.example.com           kasm-proxy-zonea    8080   edge/Redirect   None
kasm-proxy-zoneb   zoneb.kasm.example.com     kasm-proxy-zoneb    8080   edge/Redirect   None
```

An empty TLS column means the Route was rendered with no TLS stanza. On direct-connect:

```console
kubectl -n kasm-agent get route -o jsonpath='{range .items[*]}{.spec.host}{"  "}{.spec.tls.termination}{"  "}{.spec.port.targetPort}{"\n"}{end}'
curl -kI https://sessions.apps.ocp.example.com/
```

Expected: your host, `passthrough`, target port `4444`; an HTTP status line, `404` being correct
with no session. Then a session that survives past 60 seconds.

## Chart values

```yaml
kasm-helm:
  isOpenshift: true
  publicAddr: kasm.example.com
  proxyService:
    type: ClusterIP
  route:
    enabled: true
    backendProtocol: http
    tls:
      termination: edge
      insecureEdgeTerminationPolicy: Redirect

kasm-agent:                          # direct-connect only
  agent:
    publicHostname: sessions.apps.ocp.example.com
    route:
      enabled: true
      annotations:
        haproxy.router.openshift.io/timeout: "3600s"
      tls:
        termination: passthrough
```

Installing the charts directly, drop the `kasm-helm:` and `kasm-agent:` keys.

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md).

## Decisions

- [ ] `kasm-helm.isOpenshift=true`.
- [ ] `route.tls.termination` set on both halves; `proxyService.type=ClusterIP`.
- [ ] Hostnames under the router's domain, or DNS records pointing at the router.
- [ ] `haproxy.router.openshift.io/timeout: "3600s"` on the agent Route.
- [ ] Session-proxy certificate publicly trusted for `passthrough`.
- [ ] SCC bindings handled for any privileged chart.
