# Upstream auth (management) endpoint

> **Applies to:** control plane (`kasm-helm`)

## Why this is needed

Kasm advertises a per-zone **Upstream Auth Address**: the URL external Kasm Agents and Windows
services use to reach the control plane's API and manager (`/api/`, `/manager_api/`). By default it
is `$request_host$`, meaning agents talk to whatever front door users do. The `upstreamAuth` values
publish a separate, out-of-band URL for that management traffic instead — typically a **private
load balancer** or an internal ingress class/Gateway, so the management plane never rides the
public data path. Nothing requires it to be private; the value of the feature is the separate
route, load balancer, and address.

The backend is the same per-zone Kasm proxy Service the front door publishes. The proxy's nginx is
hostname-agnostic, so no extra workload is deployed — only the publishing object is new.

## Before you start

- A working front-door exposure (any of the five; the upstream auth choice is independent).
- Whatever infrastructure the chosen publisher needs: an internal load-balancer scheme your cloud
  supports, an internal ingress controller class, or a Gateway with an internal address.
- A DNS name per zone for the management endpoint, resolvable by your agents.

## Pick one publisher

Enable at most one of the five; the chart fails the render if two are set:

| Values | Publishes with | Private by |
| ------ | -------------- | ---------- |
| `upstreamAuth.service.enabled` | one `LoadBalancer`/`NodePort` Service per zone | internal-scheme annotations |
| `upstreamAuth.ingress.enabled` | one Ingress, one host rule per zone | an internal `ingressClassName` |
| `upstreamAuth.route.enabled` | one OpenShift Route per zone | router sharding / internal router |
| `upstreamAuth.httpRoute.enabled` | one HTTPRoute per zone | an internal Gateway |
| `upstreamAuth.tlsRoute.enabled` | one TLSRoute per zone, SNI passthrough | an internal Gateway; TLS ends at the Kasm proxy |

## Private LoadBalancer Service

The smallest setup. One Service per deployed zone (`<release>-upstream-auth-<zone>`), port 443 to
the proxy's HTTPS port, selecting the same proxy pods the front door uses:

```yaml
publicAddr: kasm.example.com
proxyService:
  type: ClusterIP
ingress:
  enabled: true          # the public front door, unchanged

upstreamAuth:
  hostname: kasm-mgmt.example.com
  service:
    enabled: true
    annotations:
      # AWS internal NLB; other providers use their own annotation:
      #   Azure:  service.beta.kubernetes.io/azure-load-balancer-internal: "true"
      #   GCP:    networking.gke.io/load-balancer-type: "Internal"
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
```

Point `kasm-mgmt.example.com` (private DNS) at the load balancer once it provisions; the address is
printed by the install notes, or:

```console
kubectl get svc <release>-upstream-auth-default \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}'; echo
```

This is raw L4 — no host routing — so a multi-zone cluster gets **one load balancer per zone**. To
share one, use an L7/SNI publisher below.

## Internal Ingress or Gateway

One object (Ingress) or one object per zone (Route/HTTPRoute/TLSRoute), each host routing to that
zone's own proxy Service. An internal controller class or Gateway keeps the endpoint private while
the front door stays public:

```yaml
upstreamAuth:
  hostname: kasm-mgmt.example.com
  httpRoute:
    enabled: true
    parentRefs:
      - name: internal-gateway
        namespace: kube-system
```

The Gateway API notes from the front-door pages apply unchanged: the route carries no certificate
(reference this chart's Secret from the listener's `certificateRefs`), and `tlsRoute` needs a
`protocol: TLS`, `tls.mode: Passthrough` listener. Zones that cannot share `parentRefs` get their
own entry in `upstreamAuth.httpRoute.zones[]` / `upstreamAuth.tlsRoute.zones[]`.

## Multi-zone

Per-zone hostnames come from `kasmZones[].upstream_auth_address`; the primary zone falls back to
`upstreamAuth.hostname`. Every deployed zone needs its **own** address (the chart fails on
duplicates), because each routes to that zone's own proxy Service — this holds both when several
zones' management planes share the primary cluster and when several same-`region_name` zones deploy
together. One shared internal load balancer serving all of them is fine with the L7/SNI publishers:

```yaml
kasmZones:
  - name: zonea
    proxy_hostname: zonea.kasm.example.com
    primary: true                          # gets upstreamAuth.hostname
  - name: zoneb
    proxy_hostname: zoneb.kasm.example.com
    upstream_auth_address: mgmt-b.example.com
  - name: zonec
    proxy_hostname: zonec.kasm.example.com
    seedOnly: true                         # published by its own cluster, not this one
```

A `seedOnly` zone never renders management objects here and never inherits `upstreamAuth.hostname`;
its own cluster's values file publishes its endpoint.

## What the hostname feeds

- **The database preseed** (`kasmConfig.generatePreseed`): each zone's `upstream_auth_address` is
  seeded with the resolved hostname; untouched zones keep `$request_host$`. The preseed applies
  only when the database is initialized — on an existing deployment, set the zone's Upstream Auth
  Address in the admin UI (Infrastructure → Zones) as well.
- **Certificate SANs**: resolved hostnames are added to the cert-manager Certificate and the
  self-signed fallback. Kasm agents do **not** validate the certificate, so this is hygiene rather
  than a functional requirement — what it prevents is hostname-matching front ends (ingress-nginx,
  Traefik) quietly serving their default certificate for a host the Secret's cert doesn't cover.
  A bring-your-own front-door certificate that lacks the management hostnames can be swapped out on
  the upstream auth Ingress with `upstreamAuth.ingress.secretName`; either way the endpoint keeps
  working. The self-signed Secret is reused across upgrades and keyed to `publicAddr`; adding a
  management hostname to an existing install does not regenerate it — delete the Secret to force a
  new one, or use a real certificate.
- **The install notes** print the management URL and the per-zone `kubectl get svc` one-liners.

## Ports

The host-bearing publishers require a **bare hostname** — the render fails on `host:port`. A
non-443 port (a pinned NodePort, say) belongs only in the zone's `upstream_auth_address` preseed
value or the admin UI, as `host:port`, with the Service publisher. In that case leave
`upstreamAuth.hostname` for the Service and set the zone value explicitly.

> **Migrating from the legacy (pre-1.x) chart:** the old chart called this values key
> `upstream_auth_addr` and built ingress hosts from it; the key here is the zone's
> `upstream_auth_address` plus the `upstreamAuth` block.
