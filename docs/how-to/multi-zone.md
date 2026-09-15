# Deploy multiple zones

> **Applies to:** both halves · **Charts/values:** `kasm-helm.kasmZones`, `kasm-helm.publicAddr`, `kasm-helm.ingress.*`, `kasm-helm.route.*`, `kasm-helm.tcpRoute.zones`, `agent.zone`, `agent.publicHostname`

## Why this is needed

A Kasm zone is a routing boundary: users are directed to a zone, and the agents registered in it
launch their sessions. On Kubernetes each zone gets its own manager, proxy and hostname on the
control plane and its own agent release, and an agent joins the zone of the manager it registers
with. Why it is shaped this way, what fans out per zone and what does not, is
[Zones](../explanation/multi-zone.md); this page is the values.

## Before you start

- A front end that routes by hostname: an [Ingress](networking/ingress.md), an
  [OpenShift Route](networking/openshift-route.md) or a
  [Gateway API route](networking/gateway-api-httproute.md). `proxyService.type=LoadBalancer` or
  `NodePort` alongside `kasmZones` is refused by the chart. The chart publishes only `publicAddr`;
  each zone's `proxy_hostname` is served by its own backend, usually behind a different ingress or
  load balancer entirely, and is not published here.
- Capacity for a control-plane stack **per zone**: each `kasmZones` entry renders its own API,
  manager, proxy, Guacamole and RDP gateways (the last three for primary-region zones), roughly the
  requests of the whole single-zone control plane again ([Capacity](../explanation/capacity.md)).
- One certificate covering `publicAddr` **and** every zone's `proxy_hostname`
  ([Certificates](networking/certificates.md)).
- One agent release per zone, each registering through **that zone's hostname**
  (`agent.manager.hostname` = the zone's `proxy_hostname`, or its in-cluster
  `<release>-proxy-<zone>` Service), with `agent.zone` set to the same zone name and its own
  `agent.publicHostname` on direct-connect.
- A `kasmZones` entry does two things: it renders the zone's manager and proxy, and it preseeds
  the zone record at database initialization. On an existing control plane the preseed no longer
  runs, so add the entry to the values **and** create the zone with the same name and hostname
  under Infrastructure → Zones ([Kasm docs: Deployment Zones](https://www.kasmweb.com/docs/latest/guide/zones/deployment_zones.html)).
  A zone created in the admin UI alone has no manager in a Kubernetes control plane, and no
  Kubernetes agent can join it.

## Steps

1. **Declare the zones on the control plane.**

   ```yaml
   kasm-helm:
     publicAddr: kasm.example.com
     kasmConfig:
       generatePreseed: true
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

   Every entry renders an API (`<release>-api-<zone>`), a manager (`<release>-manager-<zone>`) and
   a proxy (`<release>-proxy-<zone>`) of its own, plus Guacamole and the RDP gateways in the primary
   region.

   | Field | Meaning |
   | ----- | ------- |
   | `name` | The zone name. `zone_name` is accepted as an alias; `name` wins when both are set |
   | `proxy_hostname` | The zone's external hostname; it builds the ingress, Route and certificate entries and the zone's preseed. `proxyAddress` is a deprecated alias |
   | `primary` | Exactly one zone when several are configured (a lone zone is implicitly primary). Traffic to `publicAddr` routes here |
   | `seedOnly` | Preseeds the zone record without deploying it here; the zone's workloads install from their own cluster ([Multi-cluster zones](#multi-cluster-zones)) |
   | `region_name` | Groups zones into a region; Guacamole and the RDP gateways are rendered for primary-region zones only |
   | `proxy_connections`, `upstream_auth_address` | The direct-connect pair, per zone: [Switch sessions to direct-connect](networking/direct-connect.md) |

2. **Install one agent release per zone, each registering through its zone's hostname.** An agent
   joins the zone of the manager it registers with, so `agent.manager.hostname` is the zone's
   `proxy_hostname`, **not** `publicAddr`: an agent pointed at `kasm.example.com` reaches the
   primary zone's manager and lands in the primary zone whatever `agent.zone` says. `agent.zone`
   labels what the agent reports and must match the zone name; it never moves an agent.

   ```console
   helm install kasm-agent-zonea oci://registry-1.docker.io/kasmweb/kasm-agent \
     -n kasm-agent-zonea --create-namespace \
     --set agent.zone=zonea \
     --set agent.publicHostname=sessions-zonea.example.com \
     --set agent.manager.hostname=zonea.kasm.example.com \
     --set agent.manager.existingTokenSecret=kasm-manager-token
   ```

   In the control plane's own cluster the in-cluster Service works too:
   `agent.manager.hostname=kasm-proxy-zonea.kasm.svc.cluster.local` with `port: 8080` and
   `scheme: http`. The second and later releases on the same cluster set `operator.enabled=false`;
   the operator is a cluster singleton.

3. **Gateway API listeners.** The proxy's single `HTTPRoute` (for `publicAddr`) attaches through
   `httpRoute.parentRefs`:

   ```yaml
   kasm-helm:
     httpRoute:
       enabled: true
       parentRefs:
         - name: kasm-gateway
           namespace: kube-system
           sectionName: kasm-https        # the publicAddr listener
   ```

   The RDP gateway through the Gateway API always needs a listener per primary-region zone, named
   in `kasm-helm.tcpRoute.zones`: [Gateway API: the RDP gateway](networking/gateway-api-tcproute.md).
   Through `directRdpService` each zone's Service gets its own external address and one
   `loadBalancerPort` applies to all.

## Verify

```console
kubectl -n kasm get svc -l app.kubernetes.io/component=manager -o name
kubectl -n kasm get svc -l app.kubernetes.io/component=proxy -o name
kubectl -n kasm get svc -l app.kubernetes.io/component=connection-proxy -o name
```

Expected, for the example above:

```text
service/kasm-manager-zonea
service/kasm-manager-zoneb
service/kasm-manager-zonec
service/kasm-proxy-zonea
service/kasm-proxy-zoneb
service/kasm-proxy-zonec
service/kasm-connection-proxy-zonea
service/kasm-connection-proxy-zoneb
```

Three managers, three proxies, two connection proxies: `zonec` is in another region. Then, per agent
release:

```console
kubectl -n kasm-agent-zonea get agents.agent.kasm.com
```

Expected: `k8s-agent Ready`, which means it registered with a manager and its heartbeats are
arriving. The `Agent` status carries no zone (only `phase` and the conditions), so which zone it
joined is only visible on the control plane: **Infrastructure → Agents** lists the agent (by its
session-proxy hostname) in `zonea`, or the admin API's `get_servers` shows it with
`zone_name: zonea`. An agent listed in the primary zone instead registered through `publicAddr` or
the `default` proxy; fix `agent.manager.hostname`.

## Chart values

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  kasmConfig:
    generatePreseed: true
  kasmZones:
    - name: zonea
      proxy_hostname: zonea.kasm.example.com
      region_name: us-east
      primary: true
    - name: zoneb
      proxy_hostname: zoneb.kasm.example.com
      region_name: us-east
  certificate:
    certManager:
      enabled: true
      addWildCard: true               # *.kasm.example.com covers every zone hostname
      issuerName: letsencrypt-prod
      issuerKind: ClusterIssuer
  ingress:
    enabled: true
    ingressClassName: nginx
  proxyService:
    type: ClusterIP
```

Each agent release, as in step 2, with `zone`, `manager.hostname` and `publicHostname` per zone.

## Multi-cluster zones

One cluster per zone, one shared external database. The cluster that initializes the database
lists every zone and marks the ones hosted elsewhere `seedOnly: true`, so their zone records
(hostname, port, RDP settings) are preseeded without rendering any of their workloads, routing
rules or certificate hostnames locally:

```yaml
# Cluster 1 (seeds the database, hosts ashburn)
kasmZones:
  - name: ashburn
    proxy_hostname: ashburn.kasm.example.com
    primary: true
  - name: frankfurt
    proxy_hostname: frankfurt.kasm.example.com
    seedOnly: true
```

Every other cluster lists only its own zone(s), pointed at the shared database with seeding off:

```yaml
# Cluster 2 (hosts frankfurt)
kasmZones:
  - name: frankfurt
    proxy_hostname: frankfurt.kasm.example.com
database:
  standalone: false
  hostname: db.kasm.example.com
dbManagement:
  initialize: false
```

Zone names must match the seeded records exactly; each cluster's components register into their
zone row by name. The primary zone cannot be `seedOnly`, at least one zone per values file must
deploy, and a `seedOnly` zone must not share a `region_name` with a deployed zone; zones in one
region deploy to one cluster.

## Troubleshooting

[Troubleshooting](../reference/troubleshooting.md). Specific to this page: sessions launching in one
zone only, or an agent listed in the primary zone despite its `agent.zone`, is every agent
registering through `publicAddr` (or the derived `<release>-proxy-default` Service) and so
joining the primary zone's manager; point each at its zone's hostname. A manual move under
Infrastructure → Agents is undone by the next heartbeat. A zone missing its RDP gateway is
`region_name`.

## Decisions

- [ ] Zone names chosen; `primary` on exactly one (only a single-zone list may leave it implicit).
- [ ] `region_name` set on every zone that needs Guacamole and an RDP gateway.
- [ ] `proxy_hostname` per zone, all under the parent domain shared with the agents.
- [ ] A hostname-routing front end, not `proxyService.type=LoadBalancer`.
- [ ] One certificate covering `publicAddr` and every `proxy_hostname`.
- [ ] One agent release per zone, `agent.manager.hostname` = that zone's hostname, `agent.zone` matching, `operator.enabled=false` on all but one per cluster.
- [ ] On an existing control plane: the zone created under Infrastructure → Zones as well as in `kasmZones`.
- [ ] With `tcpRoute`: one listener per primary-region zone in `tcpRoute.zones`.
