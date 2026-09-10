# Deploy multiple zones

> **Applies to:** both halves · **Charts/values:** `kasm-helm.kasmZones`, `kasm-helm.publicAddr`, `kasm-helm.ingress.*`, `kasm-helm.route.*`, `kasm-helm.httpRoute.*`, `kasm-helm.tcpRoute.zones`, `agent.zone`, `agent.publicHostname`

## Why this is needed

A Kasm zone is a routing boundary: users are directed to a zone, and the agents registered in it
launch their sessions. On Kubernetes each zone gets its own hostname on the control plane and its
own agent release. Why it is shaped this way, what fans out per zone and what does not, is
[Zones](../explanation/multi-zone.md); this page is the values.

## Before you start

- A front end that routes by hostname: an [Ingress](networking/ingress.md), an
  [OpenShift Route](networking/openshift-route.md) or a
  [Gateway API route](networking/gateway-api-httproute.md). `proxyService.type=LoadBalancer` or
  `NodePort` alongside `kasmZones` is refused by the chart.
- One certificate covering `publicAddr` **and** every zone's `proxy_hostname`
  ([Certificates](networking/certificates.md)).
- One agent release per zone, each with `agent.zone` matching a zone name and its own
  `agent.publicHostname` on direct-connect.
- Zones are preseeded at database initialization. On an existing control plane, create and edit
  them under Infrastructure → Zones instead ([Kasm docs: Deployment Zones](https://www.kasmweb.com/docs/latest/guide/zones/deployment_zones.html)).

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

   | Field | Meaning |
   | ----- | ------- |
   | `name` | The zone name. `zone_name` is accepted as an alias; `name` wins when both are set |
   | `proxy_hostname` | The zone's external hostname; it builds the ingress, Route and certificate entries and the zone's preseed. `proxyAddress` is a deprecated alias |
   | `primary` | At most one zone; with none set the first entry is primary. Traffic to `publicAddr` routes here |
   | `region_name` | Groups zones into a region; Guacamole and the RDP gateways are rendered for primary-region zones only |
   | `proxy_connections`, `upstream_auth_address` | The direct-connect pair, per zone: [Switch sessions to direct-connect](networking/direct-connect.md) |

2. **Install one agent release per zone.** `agent.zone` must match a `kasmZones` name exactly.

   ```console
   helm install kasm-agent-zonea oci://registry-1.docker.io/kasmweb/kasm-agent \
     -n kasm-agent-zonea --create-namespace \
     --set agent.zone=zonea \
     --set agent.publicHostname=sessions-zonea.example.com \
     --set agent.manager.hostname=kasm.example.com \
     --set agent.manager.existingTokenSecret=kasm-manager-token
   ```

   The second and later releases on the same cluster set `operator.enabled=false`; the operator is
   a cluster singleton.

3. **The RDP gateway through the Gateway API** needs a listener per primary-region zone, named in
   `kasm-helm.tcpRoute.zones`: [Gateway API: the RDP gateway](networking/gateway-api-tcproute.md).
   Through `directRdpService` each zone's Service gets its own external address and one
   `loadBalancerPort` applies to all.

## Verify

```console
kubectl -n kasm get svc -l app.kubernetes.io/component=proxy -o name
kubectl -n kasm get svc -l app.kubernetes.io/component=rdp-gateway -o name
```

Expected, for the example above:

```text
service/kasm-proxy-zonea
service/kasm-proxy-zoneb
service/kasm-proxy-zonec
service/kasm-rdp-gateway-zonea
service/kasm-rdp-gateway-zoneb
```

Three proxies, two RDP gateways: `zonec` is in another region. Then, per agent release:

```console
kubectl -n kasm-agent-zonea get agents.agent.kasm.com \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.zone}{"\n"}{end}'
```

Expected: `k8s-agent Ready zonea`. An empty `.status.zone`, or a phase short of `Ready`, is a zone
name that matches nothing on the control plane; the agent is registered but unusable.

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

Each agent release, as in step 2, with `zone` and `publicHostname` per zone.

## Troubleshooting

[Troubleshooting](../reference/troubleshooting.md). Specific to this page: sessions launching in one
zone only is `agent.zone` not matching a `kasmZones` name; a zone missing its RDP gateway is
`region_name`.

## Decisions

- [ ] Zone names chosen; `primary` on exactly one, or deliberately left to the first entry.
- [ ] `region_name` set on every zone that needs Guacamole and an RDP gateway.
- [ ] `proxy_hostname` per zone, all under the parent domain shared with the agents.
- [ ] A hostname-routing front end, not `proxyService.type=LoadBalancer`.
- [ ] One certificate covering `publicAddr` and every `proxy_hostname`.
- [ ] One agent release per zone, `agent.zone` matching, `operator.enabled=false` on all but one per cluster.
- [ ] With `tcpRoute`: one listener per primary-region zone in `tcpRoute.zones`.
