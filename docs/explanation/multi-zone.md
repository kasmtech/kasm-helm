# Zones

> **Applies to:** both halves

A Kasm **zone** is a routing boundary: users are directed to a zone, and the agents registered in
that zone launch their sessions. On Kubernetes each zone gets its own hostname on the control plane
and its own agent release, so multi-zone is the shape you want for multi-region deployments, or
wherever sessions must run near particular data.

`kasmZones` is empty by default, which is not the same as "no zones" - the chart runs a single
implicit zone called `default`, which is why the control plane's Services are named
`<release>-proxy-default` rather than `<release>-proxy`. Setting `kasmZones` replaces that implicit
zone with the ones you name.

## What multi-zone forces

The values are in [Deploy multiple zones](../how-to/multi-zone.md); this page is why.

Three consequences, all of which are easier to accept before installing than after:

1. **An ingress layer is mandatory.** Each zone answers on its own hostname, and one load balancer
   cannot route by hostname. `proxyService.type=LoadBalancer` alongside `kasmZones` is refused by
   the chart; use an [Ingress](../how-to/networking/ingress.md), an
   [OpenShift Route](../how-to/networking/openshift-route.md) or the
   [Gateway API](../how-to/networking/gateway-api-httproute.md).
2. **One certificate covers every hostname** - `publicAddr` plus every zone's `proxy_hostname`. A
   wildcard on the shared parent is the least painful answer. See
   [Certificates](../how-to/networking/certificates.md).
3. **One agent release per zone**, each registering through that zone's hostname
   (`agent.manager.hostname`), with `agent.zone` matching the zone name and its own
   `agent.publicHostname`. The section below says why the hostname, not `agent.zone`, decides.

## Zone routing: the pair that picks the topology

Every zone, the implicit `default` one included, carries two settings that together choose
between the relayed and direct-connect topologies. They are a **matched pair**: Kasm's defaults are
consistent with each other for the relayed shape, which is what a no-values install runs, and both
have to change together to switch a zone to direct-connect. See
[Deployment topologies](topologies.md#relayed-or-direct-connect).

```yaml
kasm-helm:
  kasmZones:
    - name: default
      proxy_hostname: kasm.example.com
      proxy_connections: false                 # not the default, which is true
      upstream_auth_address: kasm.example.com  # not the default, which is $request_host$
```

**`proxy_connections`: who the browser talks to.** The default, `true`, means the browser connects
to the *control plane's* proxy, which relays the session upstream to the agent; on one cluster the
agent's in-cluster Service is enough for that, with no public hostname at all. `false` means the
browser connects straight to the agent, which then needs a public hostname, a trusted certificate
and the cookie scope from [Switch sessions to direct-connect](../how-to/networking/direct-connect.md).

Left at `true` with the agent published behind a host-routing Ingress or HTTPRoute, the relay
forwards the browser's original `Host` header upstream, which matches no route on the agent side and
returns 404. A relayed zone needs the agent reachable by Service or by SNI, not by `Host`.

**`upstream_auth_address`: where the agent validates the session.** Its default, `$request_host$`,
resolves to the *incoming request's* host. In the relayed shape that is the control plane's name,
because the relay forwards the browser's `Host`, which is exactly why the two defaults are
consistent as they ship. Switch to direct-connect and the incoming host becomes the agent itself, so
the session proxy would try to validate sessions against itself. Set it to the control plane's
address explicitly.

**Both only apply at database initialization.** Like everything else preseeded, they are written
when the database is created and never again. On an existing deployment, make the same two changes
in the admin UI under **Infrastructure → Zones**; see [Database](../how-to/database.md).

## What gets rendered per zone

Not everything fans out, and the difference catches people:

| Component | Scope |
| --------- | ----- |
| API (`<release>-api-<zone>`), manager (`<release>-manager-<zone>`), proxy Service (`<release>-proxy-<zone>`) | every **deployed** zone (zones marked `seedOnly: true` render none of these) |
| Ingress rule / Route / Gateway API route | one, for `publicAddr` → the primary zone; zone `proxy_hostname`s are served by their own backend, not published by this chart |
| Guacamole, RDP gateway, RDP HTTPS gateway | **primary-region zones only** - zones sharing the primary zone's `region_name` |
| Database, credentials Secret, certificate | one per deployment, not per zone |

In the example above, `zonea` and `zoneb` share `us-east` with the primary, so both get a
Guacamole and an RDP gateway. `zonec` in `eu-west` gets a proxy, and no RDP gateway.
Zones with **no** `region_name` are never in the primary region unless they *are* the primary zone  - 
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

Three proxies, two RDP gateways - `zonec` is in another region. If that is not what you expected,
`region_name` is the value to check.

## Which zone an agent joins

A zone is a manager. Every deployed `kasmZones` entry renders one (a `seedOnly: true` zone's manager lives in that zone's own cluster), and each zone's proxy forwards
`/manager_api` to its own manager, so an agent joins the zone of the manager it registers with:
the one behind `agent.manager.hostname`. An agent pointed at `publicAddr` reaches the primary
zone's proxy and lands in the primary zone; one pointed at `zonec.kasm.example.com` (or the
in-cluster `<release>-proxy-zonec` Service) lands in `zonec`. `agent.zone` only labels what the
agent reports and has to match; it never moves an agent, and a move made by hand under
Infrastructure → Agents is undone by the next heartbeat.

The same rule is why a zone created only in the admin UI cannot take a Kubernetes agent: it has a
record in the database and no manager on the control plane. Add it to `kasmZones` without `seedOnly` (which renders
the manager) and, on an existing database where the preseed no longer runs, create the zone in
the admin UI with the same name and hostname. Verified on Kasm 1.19: an agent with `agent.zone`
naming a UI-created zone registered into `default`.

## The RDP gateway is the awkward one

If you publish the RDP gateway through the Gateway API, each primary-region zone needs its own
Gateway listener, because a `TCPRoute` matches on neither hostname nor SNI. See
[Gateway API: the RDP gateway (TCPRoute)](../how-to/networking/gateway-api-tcproute.md).

Through `directRdpService` instead, each zone's Service is published on its own external address by
whatever provisions load balancers, and one `loadBalancerPort` applies to all of them.
