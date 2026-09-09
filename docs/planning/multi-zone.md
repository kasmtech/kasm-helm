> **Applies to:** both halves · **Charts/values:** `kasm-helm.kasmZones`, `kasm-helm.publicAddr`, `kasm-helm.ingress.*`, `kasm-helm.route.*`, `kasm-helm.httpRoute.*`, `kasm-helm.tcpRoute.zones`, `agent.zone`, `agent.publicHostname`

# Multi-zone

A Kasm **zone** is a routing boundary: users are directed to a zone, and the agents registered in
that zone launch their sessions. On Kubernetes each zone gets its own hostname on the control plane
and its own agent release, so multi-zone is the shape you want for multi-region deployments, or
wherever sessions must run near particular data.

`kasmZones` is empty by default, which is not the same as "no zones" — the chart runs a single
implicit zone called `default`, which is why the control plane's Services are named
`<release>-proxy-default` rather than `<release>-proxy`. Setting `kasmZones` replaces that implicit
zone with the ones you name.

## What multi-zone forces

Three consequences, all of which are easier to accept before installing than after:

1. **An ingress layer is mandatory.** Each zone answers on its own hostname, and one load balancer
   cannot route by hostname. `proxyService.type=LoadBalancer` alongside `kasmZones` is refused by
   the chart; use an [Ingress](networking/ingress.md), an
   [OpenShift Route](networking/openshift-route.md) or the
   [Gateway API](networking/gateway-api.md).
2. **One certificate covers every hostname** — `publicAddr` plus every zone's `proxy_hostname`. A
   wildcard on the shared parent is the least painful answer. See
   [multi-zone coverage](networking/certificates.md#multi-zone-coverage).
3. **One agent release per zone**, each with `agent.zone` matching a zone name and its own
   `agent.publicHostname`.

## Declaring zones

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  kasmZones:
    - name: zonea
      proxy_hostname: zonea.kasm.example.com
      region_name: us-east
      primary: true
    - name: zoneb
      proxy_hostname: zoneb.kasm.example.com
      region_name: us-east
    - name: zonec
      proxy_hostname: zonec.kasm.example.com
      region_name: eu-west
```

| Field | Meaning |
| ----- | ------- |
| `name` | The zone name. `zone_name` is accepted as an alias; `name` wins when both are set. |
| `proxy_hostname` | The zone's external hostname — it builds the ingress/Route/certificate entries and the zone's preseed. `proxyAddress` is a deprecated alias; `proxy_hostname` wins. |
| `primary` | Marks the primary zone. At most one may set it; with none set, the first entry is primary. Traffic to `publicAddr` routes here. |
| `region_name` | Groups zones into a region. It decides which zones get the region-scoped components — see below. |

## Zone routing: the pair that picks the topology

Every zone — including the implicit `default` one — carries two settings that together choose
between the direct-connect and proxied topologies. They are a **matched pair**: Kasm's defaults are
consistent with each other for the proxied shape, and both have to change together for
direct-connect, which is what these charts assume. See
[Direct-connect or proxied](networking/README.md#direct-connect-or-proxied).

```yaml
kasm-helm:
  kasmZones:
    - name: default
      proxy_hostname: kasm.example.com
      proxy_connections: false                 # not the default, which is true
      upstream_auth_address: kasm.example.com  # not the default, which is $request_host$
```

**`proxy_connections: false` — browsers connect straight to the agent.** The default, `true`, means
the browser connects to the *control plane's* proxy, which relays the session upstream to the agent.
That is the right shape when agents have no public hostname of their own, which is the usual Docker
and VM case. The Kubernetes agent is the opposite: it publishes its own hostname and terminates its
own TLS, which is the whole reason for
[the hostname pair](networking/README.md#the-hostname-pair-and-the-authorization-domain).

Left at `true`, the relay forwards the browser's original `Host` header upstream. Behind any
host-routing ingress — which is how Kubernetes publishes things — that header does not match the
agent's route, and the request 404s. So this is not a workaround; it is selecting the direct-connect
topology these charts are built around.

**`upstream_auth_address` — where the agent validates the session.** Its default, `$request_host$`,
resolves to the *incoming request's* host. In the proxied shape that is the control plane's name,
because the relay forwards the browser's `Host` — which is exactly why the two defaults are
consistent as they ship. Switch to direct-connect and the incoming host becomes the agent itself, so
the session proxy would try to validate sessions against itself. Set it to the control plane's
address explicitly.

**Both only apply at database initialization.** Like everything else preseeded, they are written
when the database is created and never again. On an existing deployment, make the same two changes
in the admin UI under **Infrastructure → Zones** — see
[Database → seeding at initialization](database.md#seeding-at-initialization).

## What gets rendered per zone

Not everything fans out, and the difference catches people:

| Component | Scope |
| --------- | ----- |
| Proxy Service, ingress rule / Route / Gateway API route | **every** zone, plus one for `publicAddr` → the primary zone |
| Guacamole, RDP gateway, RDP HTTPS gateway | **primary-region zones only** — zones sharing the primary zone's `region_name` |
| API, manager, database | one set per deployment, not per zone |

In the example above, `zonea` and `zoneb` share `us-east` with the primary, so both get a
Guacamole and an RDP gateway. `zonec` in `eu-west` gets a proxy and a route, and no RDP gateway.
Zones with **no** `region_name` are never in the primary region unless they *are* the primary zone —
which is why a two-zone list with no regions set produces only one RDP gateway.

```console
$ kubectl -n kasm get svc -l app.kubernetes.io/component=proxy -o name
service/kasm-proxy-zonea
service/kasm-proxy-zoneb
service/kasm-proxy-zonec

$ kubectl -n kasm get svc -l app.kubernetes.io/component=rdp-gateway -o name
service/kasm-rdp-gateway-zonea
service/kasm-rdp-gateway-zoneb
```

Three proxies, two RDP gateways — `zonec` is in another region. If that is not what you expected,
`region_name` is the value to check.

## The agent side

One release per zone. `agent.zone` has to match a `kasmZones` name exactly, and each zone's agent
gets its own session hostname:

```console
helm install kasm-agent-zonea oci://registry-1.docker.io/kasmweb/kasm-agent \
  -n kasm-agent-zonea --create-namespace \
  --set agent.zone=zonea \
  --set agent.publicHostname=sessions-zonea.example.com \
  --set agent.manager.hostname=kasm.example.com
```

The agent registers into its zone at first heartbeat. A `zone` that matches no zone in the control
plane leaves the agent registered but unusable — the manager has nowhere to route sessions:

```console
$ kubectl -n kasm-agent-zonea get agent -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.zone}{"\n"}{end}'
k8s-agent Ready zonea
```

An empty `.status.zone`, or a phase stuck short of `Ready`, is the mismatch.

## The RDP gateway is the awkward one

If you publish the RDP gateway through the Gateway API, each primary-region zone needs its own
Gateway listener, because a `TCPRoute` matches on neither hostname nor SNI. See
[Gateway API → multi-zone needs a listener per zone](networking/gateway-api.md#multi-zone-needs-a-listener-per-zone).

Through `directRdpService` instead, each zone's Service is published on its own external address by
whatever provisions load balancers, and one `loadBalancerPort` applies to all of them.

## Checklist

- [ ] Zone names chosen, and `primary` set on exactly one (or deliberately left to the first entry).
- [ ] `region_name` set on every zone that needs a Guacamole and RDP gateway.
- [ ] `proxy_hostname` chosen for every zone, all under the parent domain shared with the agents.
- [ ] An ingress, Route or Gateway API route configured — not `proxyService.type=LoadBalancer`.
- [ ] One certificate covering `publicAddr` and every `proxy_hostname`.
- [ ] One agent release per zone, `agent.zone` matching, each with its own `publicHostname`.
- [ ] With `tcpRoute`: one Gateway listener per primary-region zone, named in `tcpRoute.zones`.
