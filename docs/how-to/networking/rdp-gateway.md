# Publish the RDP gateway

> **Applies to:** control plane

## Why this is needed

RDP and RemoteApp workspaces are Windows or Linux hosts **outside** the cluster; the control
plane's RDP gateway brokers native RDP clients to them. It speaks raw TCP on 3389, so no Ingress,
HTTPRoute or Route can carry it. Two ways exist to publish it, and the chart refuses both at once.
The RDP HTTPS gateway (`components.rdpHttpsGateway`) needs nothing on this page; the chart
publishes nothing extra for it.

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#eef3f8","primaryBorderColor":"#5b7a99","primaryTextColor":"#1d2b3a","secondaryColor":"#fbf3e6","secondaryBorderColor":"#b8863b","tertiaryColor":"#eaf5ec","tertiaryBorderColor":"#4f8a5b","lineColor":"#5b7a99","fontFamily":"Inter, Helvetica, Arial, sans-serif","fontSize":"14px"},"flowchart":{"curve":"basis","htmlLabels":true}}}%%
flowchart LR
  rdp["RDP client"] -->|"TCP 3389 · rdp.kasm.example.com"| lb["LoadBalancer"]
  lb -->|"TCP 3389"| svc["Service kasm-rdp-gateway-default"]
  svc -->|"TCP 3389"| gwpod["RDP gateway pod"]
  gwpod -->|"TCP 3389"| host["RDP host outside the cluster"]
  classDef ext fill:#fbf3e6,stroke:#b8863b
  class rdp,lb,host ext
```

## Before you start

- `kasm-helm.components.rdpGateway.enabled: true` (the default).
- A hostname for RDP clients, `rdp.kasm.example.com` below. It is required on both paths: the
  gateway serves under it and Kasm advertises it to clients.
- For `directRdpService`: a load balancer that is **Layer 4 / TCP** (an NLB, not an ALB; an HTTP
  load balancer cannot carry RDP), or a node port open to clients.
- For `tcpRoute`: Gateway API **1.6** or newer (`TCPRoute` in the standard channel as `v1`), a
  `protocol: TCP` listener on the Gateway, and an implementation that serves TCPRoute. Being in the
  CRD bundle is not the same as the data plane implementing it.

## Steps

1. **Pick one path.** `directRdpService.enabled` and `tcpRoute.enabled` together fail the render:
   the gateway Service stays `ClusterIP` while a Gateway fronts it.

2. **Path A: a Service of its own.**

   ```yaml
   kasm-helm:
     directRdpService:
       enabled: true
       type: LoadBalancer            # or NodePort
       rdpAccessURL: rdp.kasm.example.com
       loadBalancerPort: 3389        # LoadBalancer only; ignored for NodePort
       annotations:
         service.beta.kubernetes.io/aws-load-balancer-type: nlb
   ```

   The chart types the existing `<release>-rdp-gateway-<zone>` Service accordingly and publishes
   `loadBalancerPort` onto the gateway's 3389. Point DNS for `rdpAccessURL` at the address the
   Service gets.

3. **Path B: a Gateway API TCPRoute.** Follow
   [Gateway API: the RDP gateway (TCPRoute)](gateway-api-tcproute.md), which also covers the
   listener-per-zone rule multi-zone imposes.

4. **Upgrade the release.**

## Verify

```console
kubectl -n kasm get svc kasm-rdp-gateway-default
```

Expected on path A: `TYPE LoadBalancer` with an `EXTERNAL-IP` (not `<pending>`) and
`3389:<nodeport>/TCP` in `PORT(S)`, or `TYPE NodePort` with the node port. On path B the Service
stays `ClusterIP` and the TCPRoute reports `Accepted=True`.

```console
nc -vz rdp.kasm.example.com 3389
```

Expected: `succeeded` (or `open`). Then connect a native RDP client through Kasm.

## Chart values

```yaml
kasm-helm:
  components:
    rdpGateway:
      enabled: true
  directRdpService:
    enabled: true
    type: LoadBalancer
    rdpAccessURL: rdp.kasm.example.com
    loadBalancerPort: 3389
```

Installing `kasm-helm` directly, drop the `kasm-helm:` key.

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md). Specific to this page: a render error naming
`rdpAccessURL` means it was left empty; a render error naming both `directRdpService` and `tcpRoute`
means both are on; an `EXTERNAL-IP` stuck at `<pending>` means no load-balancer provider.

## Decisions

- [ ] One path chosen: `directRdpService` or `tcpRoute`, never both.
- [ ] `rdpAccessURL` set and its DNS pointing at the published address.
- [ ] Load balancer confirmed Layer 4 / TCP, or the node port open to clients.
- [ ] With `tcpRoute`: Gateway API 1.6+, a TCP listener, and the implementation proven to serve TCPRoute.
- [ ] Multi-zone: one listener per primary-region zone.
