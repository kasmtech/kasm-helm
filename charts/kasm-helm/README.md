# Kasm on Kubernetes

![Version: 1.1200.0-develop](https://img.shields.io/badge/Version-1.1200.0--develop-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Kasm is a platform specializing in providing secure browser-based workspaces for a wide range of applications and industries. Its main goal is to provide isolated and secure environments that can be accessed via web browsers, ensuring that users can perform tasks without risking the security of their local systems.

**Homepage:** <https://kasm.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## Requirements

Kubernetes: `>= 1.24.0-0`

## Documentation

Please see our [official documentation site](https://docs.kasm.com) for more information.

> **Note:** Make sure to select the correct Kasm Workspaces version in the top-right version selector on the documentation site to ensure the guides match your deployment.

This page is the chart reference; the [documentation index](../../docs/README.md) has the tutorial and the how-to guides.

## Prerequisites

* Kubernetes 1.24 or newer (older versions of Kubernetes may work, however, we try to keep this chart updated to [supported versions of Kubernetes](https://kubernetes.io/releases/))
* Helm 3.18.x or newer ([installation](https://helm.sh/docs/helm/helm_install/))
* An ingress controller, a Gateway API implementation, or a cloud load balancer, depending on how you publish Kasm — see below. Gateway API 1.5 or newer for `tlsRoute`, and 1.6 or newer for `tcpRoute`.
* [cert-manager](https://cert-manager.io/) when `certificate.certManager.enabled` is set.

## Installing from Rancher

In Rancher, add `https://helm.kasm.com` (or `oci://registry-1.docker.io/kasmweb/kasm-helm`) as a
Repository under Apps, then install the chart from the catalog. The install form covers the
essentials (public hostname, deployment size, Ingress, certificate, credentials, database) and the
YAML editor takes everything else in this reference. Installed this way the proxy is published by a
`NodePort` Service on port 30443 rather than a LoadBalancer, because RKE2 ships no LoadBalancer
implementation; the chart generates a database preseed that makes the default zone advertise that
port in session URLs and turns on "Automatically Enable Agents" (`kasmConfig.autoEnableAgents`), so
the install is usable without a visit to the admin UI. `proxyService.type`, `proxyService.nodePort`,
`kasmConfig.generatePreseed` and `kasmConfig.autoEnableAgents` each override their part. A
cluster-wide system default registry is
honoured: Rancher passes it as `global.cattle.systemDefaultRegistry` and it replaces the registry of
every image the chart renders. The step-by-step guide is
[Install from Rancher](../../docs/how-to/install/rancher.md).

## Publishing Kasm outside the cluster

The Kasm proxy Service can be published five ways, and **at most one may be used** — all of them
front the same Service, so enabling two gives one hostname two owners. The chart fails the render
with an explicit message rather than letting the conflict reach the cluster.

| Values | Publishes with | TLS terminates at | Use when |
| ------ | -------------- | ----------------- | -------- |
| `ingress.enabled` | `networking.k8s.io/v1` Ingress | the ingress controller | an ingress controller already fronts the cluster |
| `route.enabled` | OpenShift `Route` | the OpenShift router (`edge` by default) | OpenShift |
| `httpRoute.enabled` | Gateway API `HTTPRoute` | the Gateway | a Gateway API implementation fronts the cluster |
| `tlsRoute.enabled` | Gateway API `TLSRoute`, SNI passthrough | the Kasm proxy itself | TLS must not terminate on shared cluster infrastructure |
| `proxyService.type` = `LoadBalancer` or `NodePort` | the Service itself, on `<release>-proxy-ext-<zone>` | the Kasm proxy itself | no ingress layer at all |

The last row is the default (`LoadBalancer`) and needs a cluster that actually provisions load
balancers — a cloud, MetalLB, or `cloud-provider-kind` run as root. Where there is none, or where
something already holds `:443` (k3s ships Traefik doing exactly that), `NodePort` publishes on a
port from 30000–32767 instead and needs no provider and no ingress controller. Pin it with
`proxyService.nodePort`, or let Kubernetes choose.

**Both external types are rejected alongside any of the first four**, because the ingress, Route or
Gateway already owns the external address — set `proxyService.type=ClusterIP` there. Both are also
rejected with `kasmZones`, since neither can route by hostname.

> **Match `kasmZones[].proxy_port` to the port users reach.** Kasm builds session URLs from the
> zone's `proxy_port`, not from this Service. Publishing on a node port while the zone still says
> 443 gives a working login and sessions that send the browser to a port nothing serves.

### Certificates differ between the Ingress and the Gateway API

An Ingress carries its own TLS block, so `ingress.tls` wires `certificate.secretName` straight into
it. A Gateway API route carries no certificate at all — the **Gateway's listener** does. With
`httpRoute` or `tlsRoute`, this chart still mints the Secret (through `certificate.certManager`, or
whatever you put in `certificate.secretName`), but you have to reference it from that listener's
`certificateRefs` yourself, and add a `ReferenceGrant` when the Gateway lives in another namespace.
`tlsRoute` additionally needs the listener to be `protocol: TLS` with `tls.mode: Passthrough`; a
terminating HTTPS listener will not serve it.

### Multi-zone

With `kasmZones` set, every front-door publisher still carries exactly one host rule: `publicAddr`,
pointing at the primary zone's proxy Service. Zone `proxy_hostname`s are associated with a different
backend, usually behind a different ingress or load balancer entirely, so this chart publishes no
routing rules for them. The chart-minted certificate still covers `publicAddr` and every deployed
zone's `proxy_hostname` (unless `certificate.certManager.addWildCard` narrows it to `publicAddr`
plus its wildcard).

### The upstream auth (management) endpoint

`upstreamAuth` publishes a separate, out-of-band URL for the zone's **Upstream Auth Address** — the
address external Kasm Agents and Windows services use for `/api/` and `/manager_api/` — typically a
private load balancer or an internal ingress class/Gateway, though nothing requires it to be
private. The backend is the same per-zone proxy Service the front door publishes (the proxy's nginx
is hostname-agnostic), so no extra workload is deployed; only the publishing object is new.

The same five mechanisms are available, **at most one of them**, and the choice is fully independent
of the front-door choice — the headline combination is `ingress.enabled` for users plus an internal
`upstreamAuth.service` LoadBalancer for agents:

| Values | Publishes with | Private by |
| ------ | -------------- | ---------- |
| `upstreamAuth.service.enabled` | one `LoadBalancer`/`NodePort` Service per zone, `<release>-upstream-auth-<zone>` | internal-scheme `annotations`, e.g. `service.beta.kubernetes.io/aws-load-balancer-scheme: internal` |
| `upstreamAuth.ingress.enabled` | one Ingress, one host rule per zone | an internal `ingressClassName` |
| `upstreamAuth.route.enabled` | one OpenShift `Route` per zone | router sharding / an internal router |
| `upstreamAuth.httpRoute.enabled` | one `HTTPRoute` per zone | an internal Gateway (`parentRefs`, per-zone `zones[].parentRefs`) |
| `upstreamAuth.tlsRoute.enabled` | one `TLSRoute` per zone, SNI passthrough | an internal Gateway; TLS terminates at the Kasm proxy |

Per-zone hostnames come from `kasmZones[].upstream_auth_address`, with `upstreamAuth.hostname` as
the primary (or implicit default) zone's fallback; each zone's hostname routes to **that zone's own**
proxy Service, and every deployed zone needs its own address. The L7 publishers share one load
balancer across zones by hostname/SNI; the Service publisher is raw L4 and creates one load balancer
per zone. Resolved hostnames are written to the database preseed (`kasmConfig.generatePreseed`).
They are NOT added to the cert-manager/self-signed certificate SANs: upstream auth addresses
typically live in a private DNS zone a public issuer cannot validate, and Kasm agents do not
validate the certificate. If a hostname-matching front end (ingress-nginx, Traefik) should serve a
certificate covering the management hostnames, provide one on the upstream auth Ingress with
`upstreamAuth.ingress.secretName`. The preseed only applies when the database is
initialized — on an existing deployment, also set the address in the Kasm admin UI
(Infrastructure → Zones).

### The RDP Gateway

`components.rdpGateway.enabled` speaks raw RDP, so it is published separately from the proxy — by
`directRdpService` as a `LoadBalancer` or `NodePort` Service, or by `tcpRoute` as a Gateway API
`TCPRoute`. Set one or the other, not both.

`tcpRoute` needs Gateway API 1.6 or newer, where `TCPRoute` is standard-channel `v1`. Shipping in
the standard bundle is not the same as the data plane implementing it, so confirm your Gateway
implementation supports `TCPRoute` before choosing it over a Service. And because a `TCPRoute`
matches on neither hostname nor SNI, zones cannot share one listener the way they do for
`httpRoute`: when more than one zone sits in the primary region, give each an entry in
`tcpRoute.zones` with its own `parentRefs[].sectionName`.

## Migrating to connection-proxy

Guac, RDP Gateway, and RDP HTTPS Gateway are consolidated into a single `connection-proxy` StatefulSet. `components.guac`, `components.rdpGateway`, and `components.rdpHttpsGateway` are removed from `values.yaml`; use `components.connectionProxy` instead. See [CHANGELOG.md](./CHANGELOG.md) for the breaking-change summary.

| Old key | New key | Notes |
| --- | --- | --- |
| `components.guac.enabled` | `components.connectionProxy.guac.enabled` | |
| `components.guac.image.{registry,repository,tag}` | `components.connectionProxy.guac.image.{registry,repository,tag}` | |
| `components.guac.guacClusterSize` | `components.connectionProxy.guac.guacClusterSize` | |
| `components.guac.replicas` | `components.connectionProxy.replicas` | Merged with `rdpGateway.replicas` / `rdpHttpsGateway.replicas` into one shared value |
| `components.guac.healthCheckTiming` | `components.connectionProxy.guac.healthCheckTiming` | |
| `components.guac.resources` | `components.connectionProxy.guac.resources` | |
| `components.guac.recordingData.pvcSize` | `components.connectionProxy.guac.recordingData.pvcSize` | |
| `components.guac.recordingData.storageClassName` | `components.connectionProxy.guac.recordingData.storageClassName` | |
| `components.guac.annotations` | `components.connectionProxy.annotations` | Now pod/StatefulSet-level, shared across all three services |
| `components.guac.labels` | `components.connectionProxy.labels` | Shared, pod/StatefulSet-level |
| `components.guac.nginxSidecar.resources` | `components.connectionProxy.nginx.resources` | Merged; one nginx container for all three services |
| `components.guac.nginxSidecar.healthCheckTiming` | `components.connectionProxy.nginx.healthCheckTiming` | Merged |
| `components.guac.nginxSidecar.extraVolumes` | `components.connectionProxy.extraVolumes` | Merged, now pod-level |
| `components.guac.nginxSidecar.extraVolumeMounts` | `components.connectionProxy.extraVolumeMounts` | Merged, now pod-level |
| `components.guac.extraVolumes` | `components.connectionProxy.extraVolumes` | Merged, pod-level |
| `components.guac.extraVolumeMounts` | `components.connectionProxy.extraVolumeMounts` | Merged, pod-level |
| `components.guac.extraContainers` | `components.connectionProxy.extraContainers` | Merged, pod-level |
| `components.guac.extraInitContainers` | `components.connectionProxy.extraInitContainers` | Merged, pod-level |
| `components.rdpGateway.enabled` | `components.connectionProxy.rdpGateway.enabled` | |
| `components.rdpGateway.image.{registry,repository,tag}` | `components.connectionProxy.rdpGateway.image.{registry,repository,tag}` | |
| `components.rdpGateway.replicas` | `components.connectionProxy.replicas` | Merged (see above); single-replica `fail` restriction removed |
| `components.rdpGateway.healthCheckTiming` | `components.connectionProxy.rdpGateway.healthCheckTiming` | |
| `components.rdpGateway.resources` | `components.connectionProxy.rdpGateway.resources` | |
| `components.rdpGateway.iniConfigMapName` | `components.connectionProxy.rdpGateway.iniConfigMapName` | |
| `components.rdpGateway.annotations` | `components.connectionProxy.annotations` | Merged, shared, pod/StatefulSet-level |
| `components.rdpGateway.labels` | `components.connectionProxy.labels` | Merged, shared, pod/StatefulSet-level |
| `components.rdpGateway.nginxSidecar.resources` | `components.connectionProxy.nginx.resources` | Merged |
| `components.rdpGateway.nginxSidecar.healthCheckTiming` | `components.connectionProxy.nginx.healthCheckTiming` | Merged |
| `components.rdpGateway.nginxSidecar.extraVolumes` | `components.connectionProxy.extraVolumes` | Merged, pod-level |
| `components.rdpGateway.nginxSidecar.extraVolumeMounts` | `components.connectionProxy.extraVolumeMounts` | Merged, pod-level |
| `components.rdpGateway.extraVolumes` | `components.connectionProxy.extraVolumes` | Merged, pod-level |
| `components.rdpGateway.extraVolumeMounts` | `components.connectionProxy.extraVolumeMounts` | Merged, pod-level |
| `components.rdpGateway.extraContainers` | `components.connectionProxy.extraContainers` | Merged, pod-level |
| `components.rdpGateway.extraInitContainers` | `components.connectionProxy.extraInitContainers` | Merged, pod-level |
| `components.rdpHttpsGateway.enabled` | `components.connectionProxy.rdpHttpsGateway.enabled` | |
| `components.rdpHttpsGateway.image.{registry,repository,tag}` | `components.connectionProxy.rdpHttpsGateway.image.{registry,repository,tag}` | |
| `components.rdpHttpsGateway.replicas` | `components.connectionProxy.replicas` | Merged (see above) |
| `components.rdpHttpsGateway.healthCheckTiming` | `components.connectionProxy.rdpHttpsGateway.healthCheckTiming` | |
| `components.rdpHttpsGateway.resources` | `components.connectionProxy.rdpHttpsGateway.resources` | |
| `components.rdpHttpsGateway.annotations` | `components.connectionProxy.annotations` | Merged, shared, pod/StatefulSet-level |
| `components.rdpHttpsGateway.labels` | `components.connectionProxy.labels` | Merged, shared, pod/StatefulSet-level |
| `components.rdpHttpsGateway.nginxSidecar.resources` | `components.connectionProxy.nginx.resources` | Merged |
| `components.rdpHttpsGateway.nginxSidecar.healthCheckTiming` | `components.connectionProxy.nginx.healthCheckTiming` | Merged |
| `components.rdpHttpsGateway.nginxSidecar.extraVolumes` | `components.connectionProxy.extraVolumes` | Merged, pod-level |
| `components.rdpHttpsGateway.nginxSidecar.extraVolumeMounts` | `components.connectionProxy.extraVolumeMounts` | Merged, pod-level |
| `components.rdpHttpsGateway.extraVolumes` | `components.connectionProxy.extraVolumes` | Merged, pod-level |
| `components.rdpHttpsGateway.extraVolumeMounts` | `components.connectionProxy.extraVolumeMounts` | Merged, pod-level |
| `components.rdpHttpsGateway.extraContainers` | `components.connectionProxy.extraContainers` | Merged, pod-level |
| `components.rdpHttpsGateway.extraInitContainers` | `components.connectionProxy.extraInitContainers` | Merged, pod-level |
| *(new)* | `components.connectionProxy.enabled` | New top-level gate; when false, no StatefulSet/Service/ConfigMap renders for this component |
| *(new)* | `components.connectionProxy.nginx.image.{registry,repository,tag}` | New; the consolidated nginx image is now explicitly configurable (`kasmweb/proxy`), previously implicit via internal constants |
| *(new)* | `directRdpService.perServiceSettings` | New list, one entry per connection-proxy replica, with per-entry `rdpAccessURL` (required), `zone` (required with more than one primary-region zone), `loadBalancerPort`, `annotations`, `labels` (all optional) |
| `directRdpService.rdpAccessURL` | `directRdpService.rdpAccessURL` (unchanged key, changed semantics) | Kept as a deprecated legacy singular; only honored at 1 replica when `perServiceSettings` is empty |

## Direct RDP Service

Set `directRdpService.enabled: true` to expose the Kasm RDP Gateway on port 3389 for native RDP clients, alongside the browser-based paths already served by the connection proxy.

### One Service per replica

The connection proxy is a StatefulSet and scales with `deploymentSize` (or `components.connectionProxy.replicas`). Each replica needs its own externally reachable RDP address, so the chart renders one Service per replica, named `<release>-connection-proxy-<zone>-rdp-<ordinal>` and selected by `statefulset.kubernetes.io/pod-name` so it targets exactly one pod.

Provide one `perServiceSettings` entry per replica. With one primary-region zone (the common case, `kasmZones` unset or a single zone), ordinal is simply the entry's position in the list:

```yaml
directRdpService:
  enabled: true
  type: LoadBalancer
  perServiceSettings:
    - rdpAccessURL: rdp0.kasm.example.com
      annotations:
        external-dns.alpha.kubernetes.io/hostname: rdp0.kasm.example.com
    - rdpAccessURL: rdp1.kasm.example.com
      annotations:
        external-dns.alpha.kubernetes.io/hostname: rdp1.kasm.example.com
```

Rendering fails if there are fewer entries than replicas. `rdpAccessURL` is the address Kasm registers for that replica, so it must resolve to that replica's own Service.

The legacy `directRdpService.rdpAccessURL` (a single string) is still accepted, but only with one replica, one primary-region zone, and an empty `perServiceSettings`.

### Multiple zones

With more than one primary-region zone configured in `kasmZones`, each zone gets its own set of connection-proxy replicas and needs its own RDP addresses, so a flat `perServiceSettings` list can't tell them apart. Every entry needs a `zone` field naming which zone it belongs to; ordinal is then the entry's position among that zone's own entries, so entries for different zones can be interleaved in any order:

```yaml
directRdpService:
  enabled: true
  type: LoadBalancer
  perServiceSettings:
    - zone: zone-a
      rdpAccessURL: rdp0.zone-a.kasm.example.com
    - zone: zone-b
      rdpAccessURL: rdp0.zone-b.kasm.example.com
    - zone: zone-a
      rdpAccessURL: rdp1.zone-a.kasm.example.com
```

Rendering fails if any entry omits `zone`, names a zone that isn't configured, or if a zone ends up with fewer entries than that zone's replica count. The legacy singular `rdpAccessURL` is rejected outright with more than one zone, since it has no way to express which zone it belongs to.

### Load balancer type

RDP is raw TCP on port 3389, not HTTP, so an HTTP (layer 7) load balancer cannot carry it. Where the provider does not already use a network (layer 4) load balancer, request one by annotation:

| Provider | Annotation |
| --- | --- |
| OCI | `oci.oraclecloud.com/load-balancer-type: "nlb"` |
| AWS | `service.beta.kubernetes.io/aws-load-balancer-type: "nlb"` |
| Azure | Not required; LoadBalancer Services are layer 4 by default |
| GCP | Not required; LoadBalancer Services are layer 4 by default |

### Shared and per-Service annotations

`directRdpService.annotations` and `directRdpService.labels` are applied to **every** per-replica Service. Anything that must differ per Service belongs in `perServiceSettings[i]` instead: external-dns hostnames, static IP or EIP allocation IDs, per-AZ subnets, and provider load balancer names.

Putting those in the shared map gives every replica the same identity. With external-dns, for example, every replica publishes the same hostname, so clients are round-robined across pods instead of reaching the replica that holds their session.

Precedence is most specific first: `perServiceSettings[i]` overrides `directRdpService.annotations`, which overrides the chart-wide `annotations`.

### Cost and addresses

N replicas means N load balancers. OCI Network Load Balancers are free; AWS, Azure and GCP bill per load balancer.

`perServiceSettings[i].loadBalancerPort` overrides the shared `loadBalancerPort` for a single Service. This supports providers that can share one load balancer address across Services on distinct ports (for example MetalLB's `metallb.universe.tf/allow-shared-ip`), so several replicas can share an address instead of consuming one each. If you use this, confirm that the `rdpAccessURL` you register for each replica matches the address and port clients actually connect to.

`type: NodePort` avoids load balancers entirely, but exposes a high port on every node and moves firewall management to the node level; many environments prohibit it.

## Chart value settings in `values.yaml`

## Values

<table>
	<thead>
		<th>Key</th>
		<th>Type</th>
		<th>Default</th>
		<th>Description</th>
	</thead>
	<tbody>
		<tr>
			<td id="affinity"><a href="./values.yaml#L1254">affinity</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Configure node affinity settings for Kasm pods -  [Kubernetes Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/). Kasm is not guaranteed to work with Affinity settings - use caution if you must configuring these settings. The below, optional object passes in raw Affinity rules for Pods, Nodes, etc. for your environment. Make sure you use the correct values below as this Helm chart will not do any error checking for you. </td>
		</tr>
		<tr>
			<td id="annotations"><a href="./values.yaml#L1274">annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to apply to all deployed resources </td>
		</tr>
		<tr>
			<td id="applyHealthChecks"><a href="./values.yaml#L1262">applyHealthChecks</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Add Pod/Container healthchecks settings for Kasm resources </td>
		</tr>
		<tr>
			<td id="applySecurity"><a href="./values.yaml#L1258">applySecurity</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Apply Pod/Container security settings for Kasm resources </td>
		</tr>
		<tr>
			<td id="certificate--certManager"><a href="./values.yaml#L499">certificate.certManager</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
addWildCard: true
annotations: {}
enabled: false
issuerGroup: ""
issuerKind: ""
issuerName: ""
labels: {}
</pre>
</div>
			</td>
			<td>For additional cert-manager configuration/deployment information refer to the online documentation [Cert Manager Docs](https://cert-manager.io/v1.1-docs/installation/kubernetes/).   NOTE: If you do not enable `cert-manager`, you must generate your own certificates and add them as a Kubernetes secret, or present cloud-managed certificates.  Refer to [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/), and  [Kubernetes TLS Secret](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_secret_tls/) for more information. </td>
		</tr>
		<tr>
			<td id="certificate--secretName"><a href="./values.yaml#L488">certificate.secretName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Set the secret name where the certificate is stored. This secret name will store a certificate created by `cert-manager` if you set `cert-manager.enabled` to true </td>
		</tr>
		<tr>
			<td id="certificate--selfSigned"><a href="./values.yaml#L474">certificate.selfSigned</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
</pre>
</div>
			</td>
			<td>Last-resort certificate, so that an install with no certificate configured at all still starts instead of hanging in ContainerCreating. </td>
		</tr>
		<tr>
			<td id="certificate--selfSigned--enabled"><a href="./values.yaml#L484">certificate.selfSigned.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Generate a self-signed certificate when, and only when, neither `certificate.secretName` nor `certificate.certManager.enabled` is set. A Secret this release generated is reused on upgrade, so the certificate is stable and does not restart pods; a Secret of that name created by anyone else is left untouched and used as-is.  The result is **not publicly trusted**: browsers warn on it, and it is intended for evaluation only. Supply `certificate.secretName`, or enable `certificate.certManager`, for anything else. Set this to `false` to go back to requiring a certificate up front. </td>
		</tr>
		<tr>
			<td id="clusterDomain"><a href="./values.yaml#L1241">clusterDomain</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
cluster.local
</pre>
</div>
			</td>
			<td>Cluster-wide Kubernetes DNS domain name </td>
		</tr>
		<tr>
			<td id="components--api--annotations"><a href="./values.yaml#L898">components.api.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the Kasm api Deployment</td>
		</tr>
		<tr>
			<td id="components--api--extraContainers"><a href="./values.yaml#L926">components.api.extraContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: sidecar-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--api--extraInitContainers"><a href="./values.yaml#L932">components.api.extraInitContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: init-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--api--extraVolumeMounts"><a href="./values.yaml#L920">components.api.extraVolumeMounts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes Kasm API container Example:    extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="components--api--extraVolumes"><a href="./values.yaml#L911">components.api.extraVolumes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm API container Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="components--api--healthCheckTiming"><a href="./values.yaml#L894">components.api.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="components--api--image"><a href="./values.yaml#L874">components.api.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/api
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--api--image--tag"><a href="./values.yaml#L878">components.api.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="components--api--labels"><a href="./values.yaml#L902">components.api.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to add to the Kasm api Deployment</td>
		</tr>
		<tr>
			<td id="components--api--replicas"><a href="./values.yaml#L880">components.api.replicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Override the replica count set by deploymentSize. Set to 0 to use the deploymentSize preset (default).</td>
		</tr>
		<tr>
			<td id="components--api--resources"><a href="./values.yaml#L900">components.api.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure the Kasm api Deployment resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--api--threadPool"><a href="./values.yaml#L935">components.api.threadPool</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
20
</pre>
</div>
			</td>
			<td>Number of CherryPy worker threads for the API server.  Increase under high concurrency. Default is 20.</td>
		</tr>
		<tr>
			<td id="components--api--threadPoolLogInterval"><a href="./values.yaml#L938">components.api.threadPoolLogInterval</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Seconds between background logs of CherryPy thread-pool usage  (Threads/Active/Idle/Queue). Set to 0 to disable. Default is 0.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--annotations"><a href="./values.yaml#L1025">components.connectionProxy.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the Kasm Connection Proxy StatefulSet</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--enabled"><a href="./values.yaml#L1021">components.connectionProxy.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the entire Kasm Connection Proxy workload (nginx plus the guac, rdp-gateway, and rdp-https-gateway service containers). When false, no StatefulSet, Services, or ConfigMaps are rendered for this component. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--extraContainers"><a href="./values.yaml#L1200">components.connectionProxy.extraContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: sidecar-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--extraInitContainers"><a href="./values.yaml#L1206">components.connectionProxy.extraInitContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: init-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--extraVolumeMounts"><a href="./values.yaml#L1194">components.connectionProxy.extraVolumeMounts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm Connection Proxy containers Example:   extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--extraVolumes"><a href="./values.yaml#L1185">components.connectionProxy.extraVolumes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm Connection Proxy pod Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac"><a href="./values.yaml#L1061">components.connectionProxy.guac</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
guacClusterSize: 0
healthCheckTiming:
    livenessProbe: {}
    readinessProbe: {}
image:
    registry: docker.io
    repository: kasmweb/kasm-guac
    tag: ""
recordingData:
    pvcSize: 10
    storageClassName: ""
resources: {}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm Guac service container running inside the Connection Proxy pod. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--enabled"><a href="./values.yaml#L1065">components.connectionProxy.guac.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the Kasm Guacamole web RDP service - [Kasm Guac Service](https://docs.kasm.com/docs/latest/guide/connection_proxies#guacamole-guac). </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--guacClusterSize"><a href="./values.yaml#L1076">components.connectionProxy.guac.guacClusterSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Override the Cluster Size count set by deploymentSize. Use this value to set the number of `guacd` processes running in the Guacamole pod. Set to 0 to use deploymentSize preset (default).</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--healthCheckTiming"><a href="./values.yaml#L1092">components.connectionProxy.guac.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--image"><a href="./values.yaml#L1069">components.connectionProxy.guac.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/kasm-guac
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--image--tag"><a href="./values.yaml#L1073">components.connectionProxy.guac.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--recordingData"><a href="./values.yaml#L1097">components.connectionProxy.guac.recordingData</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
pvcSize: 10
storageClassName: ""
</pre>
</div>
			</td>
			<td>PVC backing guac /tmp for session recording segments. See [Session Recording](https://docs.kasm.com/docs/latest/guide/session_recording) for sizing guidance.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--recordingData--pvcSize"><a href="./values.yaml#L1099">components.connectionProxy.guac.recordingData.pvcSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
10
</pre>
</div>
			</td>
			<td>PVC size in GiB.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--recordingData--storageClassName"><a href="./values.yaml#L1101">components.connectionProxy.guac.recordingData.storageClassName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>StorageClass. Blank uses the cluster default.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--guac--resources"><a href="./values.yaml#L1078">components.connectionProxy.guac.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure the Kasm Guac container resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--labels"><a href="./values.yaml#L1027">components.connectionProxy.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to add to the Kasm Connection Proxy StatefulSet</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--nginx"><a href="./values.yaml#L1031">components.connectionProxy.nginx</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
healthCheckTiming:
    livenessProbe: {}
    readinessProbe: {}
image:
    registry: docker.io
    repository: kasmweb/proxy
    tag: ""
resources: {}
</pre>
</div>
			</td>
			<td>Configuration for the consolidated nginx container fronting the guac, rdp-gateway, and rdp-https-gateway service containers. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--nginx--healthCheckTiming"><a href="./values.yaml#L1055">components.connectionProxy.nginx.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--nginx--image"><a href="./values.yaml#L1035">components.connectionProxy.nginx.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/proxy
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--nginx--image--tag"><a href="./values.yaml#L1039">components.connectionProxy.nginx.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--nginx--resources"><a href="./values.yaml#L1041">components.connectionProxy.nginx.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure resources for the nginx container. Leave empty to use the chart default.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpGateway"><a href="./values.yaml#L1105">components.connectionProxy.rdpGateway</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
healthCheckTiming:
    livenessProbe: {}
    readinessProbe: {}
image:
    registry: docker.io
    repository: kasmweb/rdp-gateway
    tag: ""
iniConfigMapName: ""
resources: {}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm RDP Gateway service container running inside the Connection Proxy pod. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpGateway--enabled"><a href="./values.yaml#L1109">components.connectionProxy.rdpGateway.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the Kasm RDP Gateway service - [Kasm RDP Gateway](https://docs.kasm.com/docs/latest/guide/connection_proxies#rdp-gateway). </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpGateway--healthCheckTiming"><a href="./values.yaml#L1138">components.connectionProxy.rdpGateway.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpGateway--image"><a href="./values.yaml#L1113">components.connectionProxy.rdpGateway.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/rdp-gateway
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpGateway--image--tag"><a href="./values.yaml#L1117">components.connectionProxy.rdpGateway.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpGateway--iniConfigMapName"><a href="./values.yaml#L1122">components.connectionProxy.rdpGateway.iniConfigMapName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of a user-created ConfigMap providing a custom `rdpproxy.ini` for the rdp-gateway pod. See the Kasm documentation for details. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpGateway--resources"><a href="./values.yaml#L1124">components.connectionProxy.rdpGateway.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure the Kasm RDP Gateway container resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpHttpsGateway"><a href="./values.yaml#L1144">components.connectionProxy.rdpHttpsGateway</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
healthCheckTiming:
    livenessProbe: {}
    readinessProbe: {}
image:
    registry: docker.io
    repository: kasmweb/rdp-https-gateway
    tag: ""
resources: {}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm RDP HTTPS Gateway service container running inside the Connection Proxy pod. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpHttpsGateway--enabled"><a href="./values.yaml#L1149">components.connectionProxy.rdpHttpsGateway.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the Kasm RDP HTTPS Gateway service. This service allows users to use native RDP clients via HTTPS connections rather than exposing 3389 - [Kasm RDP HTTPS Gateway](https://docs.kasm.com/docs/latest/guide/connection_proxies#rdp-https-gateway). </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpHttpsGateway--healthCheckTiming"><a href="./values.yaml#L1173">components.connectionProxy.rdpHttpsGateway.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpHttpsGateway--image"><a href="./values.yaml#L1153">components.connectionProxy.rdpHttpsGateway.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/rdp-https-gateway
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpHttpsGateway--image--tag"><a href="./values.yaml#L1157">components.connectionProxy.rdpHttpsGateway.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--rdpHttpsGateway--resources"><a href="./values.yaml#L1159">components.connectionProxy.rdpHttpsGateway.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure the Kasm RDP HTTPS Gateway container resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--connectionProxy--replicas"><a href="./values.yaml#L1023">components.connectionProxy.replicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Override the replica count set by deploymentSize. Set to 0 to use the deploymentSize preset (default).</td>
		</tr>
		<tr>
			<td id="components--manager--annotations"><a href="./values.yaml#L970">components.manager.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the Kasm Manager Deployment</td>
		</tr>
		<tr>
			<td id="components--manager--extraContainers"><a href="./values.yaml#L998">components.manager.extraContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: sidecar-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--manager--extraInitContainers"><a href="./values.yaml#L1004">components.manager.extraInitContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: init-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--manager--extraVolumeMounts"><a href="./values.yaml#L992">components.manager.extraVolumeMounts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes Kasm Manager container Example:    extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="components--manager--extraVolumes"><a href="./values.yaml#L983">components.manager.extraVolumes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm Manager container Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="components--manager--healthCheckTiming"><a href="./values.yaml#L966">components.manager.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="components--manager--image"><a href="./values.yaml#L946">components.manager.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/manager
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--manager--image--tag"><a href="./values.yaml#L950">components.manager.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="components--manager--labels"><a href="./values.yaml#L974">components.manager.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to add to the Kasm Manager Deployment</td>
		</tr>
		<tr>
			<td id="components--manager--replicas"><a href="./values.yaml#L952">components.manager.replicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Override the replica count set by deploymentSize. Set to 0 to use the deploymentSize preset (default).</td>
		</tr>
		<tr>
			<td id="components--manager--resources"><a href="./values.yaml#L972">components.manager.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure the Kasm Manager Deployment resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--manager--supportBundleTimer"><a href="./values.yaml#L1011">components.manager.supportBundleTimer</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
60
</pre>
</div>
			</td>
			<td>Configures the batching interval (in seconds) for generating support bundles.   This value determines how often the system checks for support bundle completion and expiration.  Default value is 60s.</td>
		</tr>
		<tr>
			<td id="components--manager--updateTimer"><a href="./values.yaml#L1007">components.manager.updateTimer</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
86400
</pre>
</div>
			</td>
			<td>Configures the delay (in seconds) between checking for updates, when automatic updates are enabled.  Default value is 86400, which equals 24 hours.</td>
		</tr>
		<tr>
			<td id="components--proxy--annotations"><a href="./values.yaml#L832">components.proxy.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the Kasm Proxy Deployment</td>
		</tr>
		<tr>
			<td id="components--proxy--extraContainers"><a href="./values.yaml#L860">components.proxy.extraContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: sidecar-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--proxy--extraInitContainers"><a href="./values.yaml#L866">components.proxy.extraInitContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: init-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="components--proxy--extraVolumeMounts"><a href="./values.yaml#L854">components.proxy.extraVolumeMounts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes Kasm Proxy container Example:    extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="components--proxy--extraVolumes"><a href="./values.yaml#L845">components.proxy.extraVolumes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm Proxy container Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="components--proxy--healthCheckTiming"><a href="./values.yaml#L828">components.proxy.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="components--proxy--image"><a href="./values.yaml#L808">components.proxy.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/proxy
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--proxy--image--tag"><a href="./values.yaml#L812">components.proxy.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="components--proxy--labels"><a href="./values.yaml#L836">components.proxy.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to add to the Kasm Proxy Deployment</td>
		</tr>
		<tr>
			<td id="components--proxy--replicas"><a href="./values.yaml#L814">components.proxy.replicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Override the replica count set by deploymentSize. Set to 0 to use the deploymentSize preset (default).</td>
		</tr>
		<tr>
			<td id="components--proxy--resources"><a href="./values.yaml#L834">components.proxy.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure the Kasm Proxy Deployment resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="database--annotations"><a href="./values.yaml#L664">database.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the Kasm DB StatefulSet</td>
		</tr>
		<tr>
			<td id="database--extraContainers"><a href="./values.yaml#L708">database.extraContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: sidecar-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="database--extraInitContainers"><a href="./values.yaml#L714">database.extraInitContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in the pod Example  - name: init-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="database--extraVolumeMounts"><a href="./values.yaml#L702">database.extraVolumeMounts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes Kasm Database container Example:    extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="database--extraVolumes"><a href="./values.yaml#L693">database.extraVolumes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm Database container Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="database--healthCheckTiming"><a href="./values.yaml#L680">database.healthCheckTiming</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
livenessProbe: {}
readinessProbe: {}
</pre>
</div>
			</td>
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes.  Values provided individually override their respective timing value, e.g. livenessProbe.timeoutSeconds: 10 will override only  the timeoutSeconds value of the livenessProbe.  Example:    healthCheckTiming:      livenessProbe:        timeoutSeconds: 10        initialDelaySeconds: 20        periodSeconds: 60        failureThreshold: 5      readinessProbe:        periodSeconds: 60        successThreshold: 3</td>
		</tr>
		<tr>
			<td id="database--hostname"><a href="./values.yaml#L603">database.hostname</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The hostname of the external PostgreSQL server. Only used when database.standalone is true.</td>
		</tr>
		<tr>
			<td id="database--image"><a href="./values.yaml#L642">database.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/postgres
tag: ""
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="database--image--tag"><a href="./values.yaml#L646">database.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag for this component's image. Leave empty to fall back to the chart-wide `useImageTags`.</td>
		</tr>
		<tr>
			<td id="database--kasmDbName"><a href="./values.yaml#L613">database.kasmDbName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasm
</pre>
</div>
			</td>
			<td>The name of the database where Kasm is to be initialized and that Kasm services are to connect </td>
		</tr>
		<tr>
			<td id="database--kasmDbSecret"><a href="./values.yaml#L623">database.kasmDbSecret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>The name of the Kasm database password secret to use for a user-created, custom Database password secret value.  NOTE: Leave this empty to use the password created by this Helm chart. If you create a custom DB secret, define the `kasmDbSecret` object below in the example format. </td>
		</tr>
		<tr>
			<td id="database--kasmDbUser"><a href="./values.yaml#L616">database.kasmDbUser</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmapp
</pre>
</div>
			</td>
			<td>The name of the Kasm database User with READ/WRITE permission to the Kasm database </td>
		</tr>
		<tr>
			<td id="database--labels"><a href="./values.yaml#L684">database.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to add to the Kasm DB StatefulSet</td>
		</tr>
		<tr>
			<td id="database--port"><a href="./values.yaml#L606">database.port</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
5432
</pre>
</div>
			</td>
			<td>The port Kasm will use to connect to the PostgreSQL DB server </td>
		</tr>
		<tr>
			<td id="database--postgresMasterUser"><a href="./values.yaml#L632">database.postgresMasterUser</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>An object defining the PostgreSQL DB Master user and the Kubernetes secret and key values for the Master DB password. These credentials are only used by the `db-init-job` to create the `kasmDbName` database, the `kasmDbUser` user account, set permissions for the user account, and initialize and pre-seed the Kasm Database. </td>
		</tr>
		<tr>
			<td id="database--resources"><a href="./values.yaml#L666">database.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure the Kasm DB StatefulSet resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="database--ssl"><a href="./values.yaml#L610">database.ssl</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Connect to PostgreSQL over TLS. The bundled database serves TLS and most managed services require it; set `false` for an external server that only speaks plain TCP. </td>
		</tr>
		<tr>
			<td id="database--standalone"><a href="./values.yaml#L600">database.standalone</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Setting standalone to true will prevent the deployment of the Kasm DB StatefulSet and requires the user to have a self-hosted PostgreSQL Database v16 server already setup and awaiting connections. Use the below database configuration values to connect to your external DB. see, https://docs.kasm.com/docs/latest/how-to/remote_database#requirements for list of full db requirements.</td>
		</tr>
		<tr>
			<td id="database--storage--pvcSize"><a href="./values.yaml#L657">database.storage.pvcSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Set the size of the PVC to attach to your Kubernetes-hosted Database server. The default size is 8Gi. Just supply the integer value of the PVC size in GB you wish to use. </td>
		</tr>
		<tr>
			<td id="database--storage--retentionPolicy"><a href="./values.yaml#L660">database.storage.retentionPolicy</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
whenDeleted: Delete
whenScaled: Retain
</pre>
</div>
			</td>
			<td>Configure how the DB volume should be retained or deleted throughout the DB's lifecycle </td>
		</tr>
		<tr>
			<td id="database--storage--storageClassName"><a href="./values.yaml#L653">database.storage.storageClassName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Set the storage class to attach to the DB for storage. NOTE: Leaving this blank will use the cluster-default storage class. </td>
		</tr>
		<tr>
			<td id="dbManagement--backupCron--enabled"><a href="./values.yaml#L778">dbManagement.backupCron.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set to true to enable automatic Kasm DB backups </td>
		</tr>
		<tr>
			<td id="dbManagement--backupCron--pvcName"><a href="./values.yaml#L781">dbManagement.backupCron.pvcName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The name of the Persistent Volume Claim to use for DB Backups </td>
		</tr>
		<tr>
			<td id="dbManagement--backupCron--pvcSize"><a href="./values.yaml#L797">dbManagement.backupCron.pvcSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Set the size of the PVC to attach to your Kubernetes-hosted Database backup job. The default size is 5Gi. Just supply the integer value of the PVC size in GB you wish to use. </td>
		</tr>
		<tr>
			<td id="dbManagement--backupCron--schedule"><a href="./values.yaml#L786">dbManagement.backupCron.schedule</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Use a cron-style syntax to schedule how often the backup cron job runs. The default value will run a backup every 24 hours at midnight UTC. Refer to the [Kubernetes CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) documentation for more information. </td>
		</tr>
		<tr>
			<td id="dbManagement--backupCron--storageClass"><a href="./values.yaml#L793">dbManagement.backupCron.storageClass</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The `storageClassName` to attach the DB backup job for storage of regular DB backups. Leave the value empty to use your default Kubernetes storageClass </td>
		</tr>
		<tr>
			<td id="dbManagement--backupCron--timeZone"><a href="./values.yaml#L789">dbManagement.backupCron.timeZone</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The time zone to use for the backup cron job. The default is UTC. </td>
		</tr>
		<tr>
			<td id="dbManagement--dbConnectionTimeout"><a href="./values.yaml#L726">dbManagement.dbConnectionTimeout</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
10
</pre>
</div>
			</td>
			<td>The time in seconds to wait for the DB to respond to initContainer connection attempts.</td>
		</tr>
		<tr>
			<td id="dbManagement--initJobTTLSecondsAfterFinished"><a href="./values.yaml#L724">dbManagement.initJobTTLSecondsAfterFinished</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
300
</pre>
</div>
			</td>
			<td>The time in seconds the DB initialization job remains after successful completion. </td>
		</tr>
		<tr>
			<td id="dbManagement--initialize"><a href="./values.yaml#L721">dbManagement.initialize</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Initialize the DB. This is required for an initial deployment of Kasm to configure the DB for Kasm usage </td>
		</tr>
		<tr>
			<td id="dbManagement--upgrade--backupStorageClass"><a href="./values.yaml#L762">dbManagement.upgrade.backupStorageClass</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The storageClass to use to create PV for the backup PVC. </td>
		</tr>
		<tr>
			<td id="dbManagement--upgrade--enable"><a href="./values.yaml#L735">dbManagement.upgrade.enable</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="dbManagement--upgrade--oldDbBackupFileName"><a href="./values.yaml#L771">dbManagement.upgrade.oldDbBackupFileName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasm_dump.tar
</pre>
</div>
			</td>
			<td>The file name of the database backup to restore and upgrade. </td>
		</tr>
		<tr>
			<td id="dbManagement--upgrade--oldDbHostname"><a href="./values.yaml#L740">dbManagement.upgrade.oldDbHostname</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Hostname of the database from the previous Helm release. Only required if your old deployment used a non-default DB hostname (i.e. not kasm-db). Leave empty if using a standalone DB or to fall back to the default. </td>
		</tr>
		<tr>
			<td id="dbManagement--upgrade--oldDbSecretsName"><a href="./values.yaml#L768">dbManagement.upgrade.oldDbSecretsName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The name of an existing Kubernetes secret to use as the source for credential lookup during upgrades. Leave empty to use the current release's '<release>-secrets' secret. Set to a different secret name only when upgrading from a deployment that stored credentials under a non-default name. </td>
		</tr>
		<tr>
			<td id="dbManagement--upgrade--skipBackupAndRestore"><a href="./values.yaml#L759">dbManagement.upgrade.skipBackupAndRestore</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Skip the chart-included pre-upgrade DB backup AND restore steps. The chart will NOT render the backup PVC + Job, and the upgrade Job will NOT attempt to `pg_restore` from a dump file — it will only run the Kasm schema (alembic) migration against the DB it finds.  ONLY supported with `database.standalone=true`. Setting this to true with the bundled (in-chart) DB will cause the upgrade Job to fail-render with an explanatory error.  When this is true, the operator is responsible for performing the data-plane upgrade manually, in this order, BEFORE running `helm upgrade`:   1. pg_dump the existing standalone DB (old Postgres major version).   2. Stand up the new Postgres major version server.   3. pg_restore the dump into the new Postgres server.   4. Run `helm upgrade` with this flag set to true — the chart's upgrade Job then runs only      the Kasm schema migration (alembic) against the already-restored DB.  When this is true, `oldDbHostname` and `oldDbBackupFileName` are ignored. </td>
		</tr>
		<tr>
			<td id="deploymentSize"><a href="./values.yaml#L7">deploymentSize</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
small
</pre>
</div>
			</td>
			<td>Define the estimated size of the Kasm deployment in expected session load.  small  = Up to 10-15 sessions  medium = Up to 25-30 sessions  large  = Up to 50+ sessions </td>
		</tr>
		<tr>
			<td id="directRdpService"><a href="./values.yaml#L130">directRdpService</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
enabled: false
labels: {}
loadBalancerPort: 3389
perServiceSettings: []
rdpAccessURL: ""
type: LoadBalancer
</pre>
</div>
			</td>
			<td>Configure the direct RDP Service for the Kasm RDP Gateway. Only applicable when `components.connectionProxy.rdpGateway.enabled` is true.  One Service is created per connection-proxy replica. See [Direct RDP Service](./README.md#direct-rdp-service) for load balancer requirements, per-replica settings, and cost. </td>
		</tr>
		<tr>
			<td id="directRdpService--annotations"><a href="./values.yaml#L152">directRdpService.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Annotations added to every per-replica Service. Values that must be unique per Service (external-dns hostnames, static IP allocations) belong in `perServiceSettings`. </td>
		</tr>
		<tr>
			<td id="directRdpService--enabled"><a href="./values.yaml#L134">directRdpService.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Enable exposure of the RDP Gateway via a separate Service of the type defined in `directRdpService.type`. </td>
		</tr>
		<tr>
			<td id="directRdpService--labels"><a href="./values.yaml#L155">directRdpService.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Labels added to every per-replica Service. </td>
		</tr>
		<tr>
			<td id="directRdpService--loadBalancerPort"><a href="./values.yaml#L148">directRdpService.loadBalancerPort</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
3389
</pre>
</div>
			</td>
			<td>External port exposed when `type` is LoadBalancer. Overridden per Service by `perServiceSettings[i].loadBalancerPort`. No effect when `type` is NodePort. It is also the port the Gateway API `tcpRoute` forwards to, so it applies even when `directRdpService.enabled` is false. </td>
		</tr>
		<tr>
			<td id="directRdpService--perServiceSettings"><a href="./values.yaml#L177">directRdpService.perServiceSettings</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Per-replica Service settings. Required with more than one replica; rendering fails if there are fewer entries than replicas. Entry `annotations`/`labels` override the shared values above. With exactly one primary-region zone (kasmZones), ordinal is the entry's position in this list (`zone` may be omitted). With more than one zone, every entry needs a `zone` field naming which zone it belongs to; ordinal is then the entry's position among that zone's entries. Example (single zone):   perServiceSettings:     - rdpAccessURL: rdp0.kasm.example.com       loadBalancerPort: 3389       annotations:         external-dns.alpha.kubernetes.io/hostname: rdp0.kasm.example.com     - rdpAccessURL: rdp1.kasm.example.com       annotations:         external-dns.alpha.kubernetes.io/hostname: rdp1.kasm.example.com Example (multiple zones):   perServiceSettings:     - zone: zone-a       rdpAccessURL: rdp0.zone-a.kasm.example.com     - zone: zone-b       rdpAccessURL: rdp0.zone-b.kasm.example.com </td>
		</tr>
		<tr>
			<td id="directRdpService--rdpAccessURL"><a href="./values.yaml#L138">directRdpService.rdpAccessURL</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Legacy single access URL. Only honored with 1 replica and an empty `perServiceSettings`. Use `perServiceSettings` instead. </td>
		</tr>
		<tr>
			<td id="directRdpService--type"><a href="./values.yaml#L142">directRdpService.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
LoadBalancer
</pre>
</div>
			</td>
			<td>Service type to use. Allowed values: LoadBalancer, NodePort. RDP is raw TCP, so a LoadBalancer must be a layer 4 / network load balancer, not an HTTP one. </td>
		</tr>
		<tr>
			<td id="extraAnnotations--configMap"><a href="./values.yaml#L1282">extraAnnotations.configMap</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional configMap annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--cronJob"><a href="./values.yaml#L1284">extraAnnotations.cronJob</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional cronJob annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--cronPod"><a href="./values.yaml#L1286">extraAnnotations.cronPod</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional annotations to apply to the pod template inside CronJobs created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--deployment"><a href="./values.yaml#L1288">extraAnnotations.deployment</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional deployment annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--job"><a href="./values.yaml#L1290">extraAnnotations.job</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional job annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--pod"><a href="./values.yaml#L1292">extraAnnotations.pod</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional pod annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--pvc"><a href="./values.yaml#L1294">extraAnnotations.pvc</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional PersistentVolumeClaim annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--secret"><a href="./values.yaml#L1298">extraAnnotations.secret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional secret annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--service"><a href="./values.yaml#L1296">extraAnnotations.service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional service annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--statefulSet"><a href="./values.yaml#L1300">extraAnnotations.statefulSet</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional statefulSet annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraContainerVolumeMounts"><a href="./values.yaml#L1346">extraContainerVolumeMounts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to all Kasm containers Example:    extraContainerVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="extraContainers"><a href="./values.yaml#L1363">extraContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional sidecar containers to run in every pod Example  - name: init-example    image: busybox    command: [/bin/sh, -c, 'echo "Hello world"']</td>
		</tr>
		<tr>
			<td id="extraInitContainers"><a href="./values.yaml#L1370">extraInitContainers</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="extraInitVolumeMounts"><a href="./values.yaml#L1356">extraInitVolumeMounts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to all Kasm Service Init containers Example:    extraInitVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="extraLabels--configMap"><a href="./values.yaml#L1308">extraLabels.configMap</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional configMap labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--cronJob"><a href="./values.yaml#L1320">extraLabels.cronJob</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional cronJob labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--cronPod"><a href="./values.yaml#L1322">extraLabels.cronPod</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional labels to apply to the pod template inside CronJobs created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--deployment"><a href="./values.yaml#L1310">extraLabels.deployment</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional deployment labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--job"><a href="./values.yaml#L1318">extraLabels.job</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional job labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--pod"><a href="./values.yaml#L1312">extraLabels.pod</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional pod labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--pvc"><a href="./values.yaml#L1324">extraLabels.pvc</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional PersistentVolumeClaim labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--secret"><a href="./values.yaml#L1314">extraLabels.secret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional secret labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--service"><a href="./values.yaml#L1316">extraLabels.service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional service labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--statefulSet"><a href="./values.yaml#L1326">extraLabels.statefulSet</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional statefulSet labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraObjects"><a href="./values.yaml#L1375">extraObjects</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Deploy additional Kubernetes manifests. This field is expected to be either a multi-line string, a list of strings, or a list of objects. </td>
		</tr>
		<tr>
			<td id="extraVolumes"><a href="./values.yaml#L1336">extraVolumes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="global"><a href="./values.yaml#L11">global</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
cattle:
    systemDefaultRegistry: ""
</pre>
</div>
			</td>
			<td>Values Helm shares with every chart in a release. Rancher fills in `global.cattle.*` on every install from its catalog; nothing here needs to be set by hand.</td>
		</tr>
		<tr>
			<td id="global--cattle--systemDefaultRegistry"><a href="./values.yaml#L17">global.cattle.systemDefaultRegistry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The registry Rancher configured as the cluster's system default registry (air-gapped and mirrored clusters). When set, it replaces the registry part of every image this chart renders and the per-image `image.registry` values are ignored, following Rancher's convention. Rancher sets it on install from its catalog; leave it empty everywhere else.</td>
		</tr>
		<tr>
			<td id="httpRoute--annotations"><a href="./values.yaml#L271">httpRoute.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="httpRoute--backendProtocol"><a href="./values.yaml#L270">httpRoute.backendProtocol</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
http
</pre>
</div>
			</td>
			<td>The protocol the Gateway uses to reach the Kasm proxy Service. Valid values: http or https </td>
		</tr>
		<tr>
			<td id="httpRoute--enabled"><a href="./values.yaml#L256">httpRoute.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set to `true` to publish the Kasm proxy through a Gateway API HTTPRoute. Requires the Gateway API CRDs and a Gateway in the cluster. </td>
		</tr>
		<tr>
			<td id="httpRoute--labels"><a href="./values.yaml#L272">httpRoute.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="httpRoute--parentRefs"><a href="./values.yaml#L266">httpRoute.parentRefs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Gateways to attach the route to, passed through verbatim, so any field of a Gateway API `ParentReference` is accepted - `name`, `namespace`, `sectionName`, `port`, `kind`. The route attaches to nothing, and the proxy stays unreachable, if this is left empty. The Gateway's listener must also admit routes from this namespace (its `allowedRoutes`). Example:   parentRefs:     - name: kasm-gateway       namespace: kube-system </td>
		</tr>
		<tr>
			<td id="imagePullPolicy"><a href="./values.yaml#L1214">imagePullPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
Always
</pre>
</div>
			</td>
			<td>Configure global image pull policy </td>
		</tr>
		<tr>
			<td id="imagePullSecrets--annotations"><a href="./values.yaml#L1237">imagePullSecrets.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional annotations for this secret</td>
		</tr>
		<tr>
			<td id="imagePullSecrets--email"><a href="./values.yaml#L1233">imagePullSecrets.email</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The email address used to authenticate (optional, used by some registries).</td>
		</tr>
		<tr>
			<td id="imagePullSecrets--enabled"><a href="./values.yaml#L1220">imagePullSecrets.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Enable/disable image pull secrets</td>
		</tr>
		<tr>
			<td id="imagePullSecrets--labels"><a href="./values.yaml#L1235">imagePullSecrets.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional labels for this secret</td>
		</tr>
		<tr>
			<td id="imagePullSecrets--name"><a href="./values.yaml#L1225">imagePullSecrets.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Secret name to use. If left blank, will be dynamically generated. To use an existing Image pull secret, or one you manually created, set `imagePullSecrets.enabled`, and provide the name of the Image Pull Secret you created, making sure to leave all other values below empty. </td>
		</tr>
		<tr>
			<td id="imagePullSecrets--password"><a href="./values.yaml#L1231">imagePullSecrets.password</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The password used to authenticate agaisnt your Registry.</td>
		</tr>
		<tr>
			<td id="imagePullSecrets--registry"><a href="./values.yaml#L1227">imagePullSecrets.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The Registry to use when pulling images (e.g. index.docker.io, myprivateregistry.com)</td>
		</tr>
		<tr>
			<td id="imagePullSecrets--username"><a href="./values.yaml#L1229">imagePullSecrets.username</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The username used to authenticate agaisnt your Registry.</td>
		</tr>
		<tr>
			<td id="ingress--annotations"><a href="./values.yaml#L195">ingress.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="ingress--backendProtocol"><a href="./values.yaml#L191">ingress.backendProtocol</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
http
</pre>
</div>
			</td>
			<td>The backend protocol to for the Ingress to communicate with the Kasm proxy service. Valid values: http or https </td>
		</tr>
		<tr>
			<td id="ingress--enabled"><a href="./values.yaml#L184">ingress.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set the enabled value to `true` to use a pre-defined Ingress service to expose Kasm </td>
		</tr>
		<tr>
			<td id="ingress--ingressClassName"><a href="./values.yaml#L194">ingress.ingressClassName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Define the ingress Class to use for your Kasm ingress </td>
		</tr>
		<tr>
			<td id="ingress--labels"><a href="./values.yaml#L196">ingress.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="ingress--tls"><a href="./values.yaml#L187">ingress.tls</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Set tls value to `true` to eanble TLS configuration for the hostname defined at `publicAddr` parameter </td>
		</tr>
		<tr>
			<td id="isOpenshift"><a href="./values.yaml#L73">isOpenshift</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Use this flag to remove Pod and Container security ID values and allow OpenShift to dynamically set them in accordance with [OpenShift UIDs](https://www.redhat.com/en/blog/a-guide-to-openshift-and-uids) documentation.</td>
		</tr>
		<tr>
			<td id="kasmConfig"><a href="./values.yaml#L1383">kasmConfig</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
adminUsername: admin@kasm.local
authDomain: ""
autoEnableAgents: null
config: {}
defaultApiUsers: false
defaultUsers: false
existingDefaultPropertiesSecret:
    key: default_properties.yaml
    name: ""
generatePreseed: null
</pre>
</div>
			</td>
			<td>Use fields in the `kasmConfig` section to apply customization to a Kasm deployment during database initialization.  NOTE: This data is only used during DB initialization and does not have any effect on live Kasm configuration settings.  </td>
		</tr>
		<tr>
			<td id="kasmConfig--adminUsername"><a href="./values.yaml#L1416">kasmConfig.adminUsername</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
admin@kasm.local
</pre>
</div>
			</td>
			<td>Change the username seeded on the admin-group member. Default: `admin@kasm.local`, the only true built-in admin account. Setting this to any other value seeds that account with generated (non-built-in) credentials stored under a `<local-part>-password`/`<local-part>-salt` key pair in the passwords/salts Secrets (e.g. `system@kasm.local` -> `system-password`) instead of the built-in admin-password-Secret-backed credentials. The chart will not create an `admin-password` key at all in that case, and the db-init Job will not be given a DEFAULT_ADMIN_PASSWORD env var. See docs/default-users.md. </td>
		</tr>
		<tr>
			<td id="kasmConfig--authDomain"><a href="./values.yaml#L1436">kasmConfig.authDomain</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Set the `kasm_auth_domain` global setting, which scopes the Kasm session cookie. Defaults to `""`, leaving Kasm's own `$request_host$` default in place (cookie scoped to whichever hostname served the page).  Applies at DATABASE INITIALIZATION, so it takes effect on FRESH INSTALLS ONLY. On an existing database the db-init Job no longer seeds anything; change the value in the admin UI under Settings -> Auth, or through the admin API (`POST /api/admin/get_settings` for the `setting_id`, then `POST /api/admin/update_setting`).  Why it exists: with a Kubernetes agent, browsers connect to the agent's session-proxy hostname directly, which is a different hostname from `publicAddr`. A cookie scoped to `publicAddr` is never sent to the agent and every session connection fails with a 401. Set this to the common parent domain of both hostnames — for `kasm.example.com` and `sessions.example.com`, that is `example.com`. Pick the two hostnames as siblings under one parent from the start; there is no fixing this later without renaming one.  Unlike `kasmConfig.config.settings`, this is applied last against the finished seed file, so it wins over both `existingDefaultPropertiesSecret` and the `kasmConfig.config` merge. It does not require `generatePreseed`. See the "Running alongside the kasm-helm control plane" section of [charts/kasm-agent/README.md](../kasm-agent/README.md) for the full agent pairing. </td>
		</tr>
		<tr>
			<td id="kasmConfig--autoEnableAgents"><a href="./values.yaml#L1398">kasmConfig.autoEnableAgents</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="">
`null`: on under Rancher, else off
</pre>
</div>
			</td>
			<td>Seed the manager setting "Automatically Enable Agents" (`auto_agent`), so agents come up enabled as they register instead of waiting for a click under Infrastructure -> Agents. Takes effect at database initialization only, through the generated preseed. Unset (null), it is on for a release installed through Rancher's catalog and off everywhere else; an `auto_agent` entry in `kasmConfig.config.settings` wins over it as written.</td>
		</tr>
		<tr>
			<td id="kasmConfig--config"><a href="./values.yaml#L1453">kasmConfig.config</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Kasm DB pre-seed configuration settings in YAML format. Refer to the [Preseed Documentation](../../docs/reference/preseed.md) and to the [Kasm Slip-Stream Install](https://docs.kasm.com/docs/1.19.0/how-to/administration/import-export/slipstream-install) documentation for additional details. </td>
		</tr>
		<tr>
			<td id="kasmConfig--defaultApiUsers"><a href="./values.yaml#L1408">kasmConfig.defaultApiUsers</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Creates two predefined sets of API credentials with permissions accommodating most standard deployment scenarios. Refer to the [Default API Users](../../docs/reference/default-api-users.md) for additional information about what this flag creates. </td>
		</tr>
		<tr>
			<td id="kasmConfig--defaultUsers"><a href="./values.yaml#L1403">kasmConfig.defaultUsers</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Creates a series of 4 users and 5 groups with a standard set of permissions accommodating most standard deployment scenarios. Refer to the [Default Users](../../docs/reference/default-users.md) for additional information about what this flag creates. </td>
		</tr>
		<tr>
			<td id="kasmConfig--existingDefaultPropertiesSecret"><a href="./values.yaml#L1446">kasmConfig.existingDefaultPropertiesSecret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
key: default_properties.yaml
name: ""
</pre>
</div>
			</td>
			<td>Reference a customer-managed Secret containing a complete `default_properties.yaml` seed file, for infrastructure-as-code workflows that manage the seed file directly as a Kubernetes Secret rather than expressing it through kasmConfig.config values.  When `name` is set, its contents (at `key`) replace the image's baked-in default_properties.yaml as the base seed file. This works independently of generatePreseed: set generatePreseed=true as well to additionally merge kasmConfig.config-generated values on top of the customer-provided file, or leave it false to use the customer-provided file as-is with no chart-side merge. </td>
		</tr>
		<tr>
			<td id="kasmConfig--generatePreseed"><a href="./values.yaml#L1391">kasmConfig.generatePreseed</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="">
`null`: on under Rancher, else off
</pre>
</div>
			</td>
			<td>Generate a custom DB initialization configuration (`kasmConfig.config`, plus what the chart seeds on its own: the default zone's `proxy_port` for a NodePort proxy, and `auto_agent` from `kasmConfig.autoEnableAgents`) and merge it into Kasm's default seed data at database initialization. Unset (null), it is on for a release installed through Rancher's catalog, which has both of those to seed, and off everywhere else; `true`/`false` decides explicitly.</td>
		</tr>
		<tr>
			<td id="kasmSecrets"><a href="./values.yaml#L551">kasmSecrets</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
create: true
labels: {}
name: ""
passwords:
    admin-password: ""
    db-password: ""
    manager-token: ""
    service-token: ""
    user-password: ""
</pre>
</div>
			</td>
			<td>Use this to create custom Kasm Password secret, or to reference an existing one. If this is left blank then Helm will automatically generate random passwords and store them as `<Release-Name>-secrets` in your deployment namespace.  To reference a secret you already created yourself, set `create: false` and `name: "<existing secret name>"`, leaving `passwords` at its defaults; the chart will not manage that secret and will read the credentials from it.  To have the chart create the secret but pin one or more specific credential values (leaving the rest randomly generated), keep `create: true`, optionally set `name`, and set the desired key(s) under `passwords`. </td>
		</tr>
		<tr>
			<td id="kasmSecrets--annotations"><a href="./values.yaml#L580">kasmSecrets.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the Kasm Password secret</td>
		</tr>
		<tr>
			<td id="kasmSecrets--create"><a href="./values.yaml#L554">kasmSecrets.create</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Set to false to use an existing Kasm Password secret. Default = `true`. </td>
		</tr>
		<tr>
			<td id="kasmSecrets--labels"><a href="./values.yaml#L582">kasmSecrets.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to add to the Kasm Kasm Password secret</td>
		</tr>
		<tr>
			<td id="kasmSecrets--name"><a href="./values.yaml#L559">kasmSecrets.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The name of the Kasm Password secret to create. If a value is provided here and `create=true`, Helm will use that as the secret name. If `create=false` then you MUST provide the name of an existing Kasm Password secret in your deployment namespace. </td>
		</tr>
		<tr>
			<td id="kasmSecrets--passwords"><a href="./values.yaml#L571">kasmSecrets.passwords</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
admin-password: ""
db-password: ""
manager-token: ""
service-token: ""
user-password: ""
</pre>
</div>
			</td>
			<td>Set any of the five well-known keys below to a non-empty value to pin that credential to a specific value instead of letting the chart generate (or preserve, on upgrade) a random one. An explicitly set value here always wins, even if a Secret with that key already exists in the namespace.  This object also accepts additional, arbitrary keys beyond the five below. Any extra key you add is written into the generated Secret's `data` as a literal base64-encoded value (no random generation, since the chart has no other source of truth for a custom key) - useful for seeding extra application secrets alongside the standard Kasm credentials.  NOTE: Only used when `kasmSecrets.create` is `true`. Has no effect when referencing an existing secret. </td>
		</tr>
		<tr>
			<td id="kasmZones"><a href="./values.yaml#L60">kasmZones</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>This is a list of objects defining different Kasm Zone configurations for your deployment. This configuration is typically used for multi-region, large, or custom deployments where the customer requires a high degree of configurability and has multiple resources in disparate areas.  NOTE: If you configure custom zones below, you MUST use a valid `ingress` configuration due to the increased deployment complexity of a multi-zone Kasm deployment. Refer to the Kasm [Deployment Zones](https://docs.kasm.com/docs/latest/guide/deployment_zones) documentation for more information on Kasm Zones.  The zone marked `primary: true` is treated as the primary zone. A single configured zone is implicitly primary; with more than one zone configured, exactly one must be marked `primary: true` (there is no first-zone fallback). Traffic to the configured `publicAddr` in the ingress rule will be routed to this primary zone.  Each zone requires a `name` (or the `zone_name` alias, if `name` is not set; `name` wins if both are set).  Each zone's `proxy_hostname` is added to the chart-minted certificate's SANs and written to the zone's preseed `proxy_hostname` value. It gets NO ingress/route rule from this chart: the hostname is associated with a different backend, usually behind a different ingress or load balancer entirely, and only `publicAddr` is published here. `proxyAddress` is a deprecated alias for `proxy_hostname`, kept for backwards compatibility; if both are set, `proxy_hostname` wins.  A zone marked `seedOnly: true` is written to the database preseed (when `kasmConfig.generatePreseed` is true) but deploys no workloads, Services, routing rules or certificate hostnames in this cluster. Use it for multi-cluster deployments: the cluster that initializes the database lists every zone, marking the zones hosted by other clusters `seedOnly: true`, and each of those clusters installs this chart with a values file listing only its own zone(s), `dbManagement.initialize: false` and the shared external database. The primary zone cannot be `seedOnly`, at least one zone must deploy, and a `seedOnly` zone must not share a `region_name` with a deployed zone (zones in one region deploy to one cluster). </td>
		</tr>
		<tr>
			<td id="labels"><a href="./values.yaml#L1270">labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to apply to all deployed resources </td>
		</tr>
		<tr>
			<td id="logFormat"><a href="./values.yaml#L77">logFormat</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
log
</pre>
</div>
			</td>
			<td>Kasm Log format to write to console. Valid options are: json, log </td>
		</tr>
		<tr>
			<td id="nginxResolver"><a href="./values.yaml#L91">nginxResolver</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The IP address used by the `resolver` directive in the Kasm nginx configs (proxy and connection-proxy) for dynamic upstream DNS resolution.  Leave empty (the default) to auto-detect the cluster's kube-dns Service ClusterIP at install/upgrade time. Auto-detection requires a live cluster and read access to Services in the kube-system namespace; it silently falls back to the historical hardcoded value, 127.0.0.11, when running `helm template`/`--dry-run`, when RBAC denies the lookup, or when the cluster's DNS Service isn't named `kube-dns` in `kube-system` (uncommon, but some distros differ).  Set this explicitly to skip auto-detection and pin a specific resolver IP, such as a known CoreDNS/kube-dns ClusterIP, or 127.0.0.11 to restore the previous unconditional default. </td>
		</tr>
		<tr>
			<td id="nodeSelector"><a href="./values.yaml#L1246">nodeSelector</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Configure node selector settings for your Kasm pods - [Kubernetes Node Selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector). </td>
		</tr>
		<tr>
			<td id="proxyService"><a href="./values.yaml#L103">proxyService</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
labels: {}
nodePort: ""
type: ""
</pre>
</div>
			</td>
			<td>Configure the external-facing service type to use. Allowed service types: ClusterIP, LoadBalancer, or NodePort.   The proxyService.annotations defined here only apply to the `proxy` service (`proxy-service-external.yaml` file). If you wish to apply annotations to all services, use the annotations.service value at the bottom of this chart.  NOTE: If ingress.enabled or route.enabled set to `true` service.type MUST be set to `ClusterIP`. Also, if you wish to deploy a multi-zone Kasm (see [Deployment Zones](https://docs.kasm.com/docs/latest/guide/deployment_zones) documentation for reference), you MUST use either a Route or an Ingress and set the `proxyService.type` to `ClusterIP`. </td>
		</tr>
		<tr>
			<td id="proxyService--nodePort"><a href="./values.yaml#L120">proxyService.nodePort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="">
`""`, or `30443` when the chart chose NodePort under Rancher
</pre>
</div>
			</td>
			<td>Pin the node port when the proxy Service is a NodePort. Leave empty to let Kubernetes assign one from the cluster's service-node-port-range (30000-32767 by default), except when the chart chose NodePort on its own (`proxyService.type` empty, installed through Rancher): then it pins 30443, so the port is known at render time.  Kasm builds session URLs from the zone's `proxy_port`, not from this Service. A generated preseed advertises the pinned port in the default zone by itself; with no preseed, or with a Kubernetes- assigned port, set `kasmZones[].proxy_port` to match - otherwise the browser is sent to a port nothing is listening on. Ignored for any other service type.</td>
		</tr>
		<tr>
			<td id="proxyService--type"><a href="./values.yaml#L109">proxyService.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="">
`""`: LoadBalancer, or NodePort under Rancher
</pre>
</div>
			</td>
			<td>ClusterIP, LoadBalancer or NodePort. Leave empty for the automatic default: LoadBalancer, or NodePort when the release is installed through Rancher's catalog (Rancher sets `global.cattle.clusterId` on every install from it), because RKE2 ships no LoadBalancer implementation and the Service would otherwise stay pending forever. An explicit value always wins.</td>
		</tr>
		<tr>
			<td id="publicAddr"><a href="./values.yaml#L27">publicAddr</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Set the access URL to be used for the Kasm deployment. This is the URL you will use to access your Kasm deployment. This URL can be a private address, it just needs to be resolvable by systems you use to interface with Kasm.  If you create a self-signed or custom certificate, this is the value you should assign as the Common Name associated with the certificate. If `certificate.certManager.enabled` is set to true, this is the name used to generate the certificate. </td>
		</tr>
		<tr>
			<td id="restartPolicy"><a href="./values.yaml#L1266">restartPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
Always
</pre>
</div>
			</td>
			<td>Configure global Pod restart policy for Kasm resources </td>
		</tr>
		<tr>
			<td id="route"><a href="./values.yaml#L203">route</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
backendProtocol: http
enabled: false
labels: {}
tls: {}
wildcardPolicy: None
</pre>
</div>
			</td>
			<td>Configure an OpenShift Route for your Kasm deployment.  One Route is rendered, for publicAddr, targeting the primary zone's proxy Service. Zone proxy_hostnames belong to a different backend and get no Route. </td>
		</tr>
		<tr>
			<td id="route--backendProtocol"><a href="./values.yaml#L209">route.backendProtocol</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
http
</pre>
</div>
			</td>
			<td>The backend protocol to for the OpenShift Route to communicate with the Kasm proxy service. Valid values: http or https </td>
		</tr>
		<tr>
			<td id="route--enabled"><a href="./values.yaml#L205">route.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set the enabled value to `true` to use a pre-defined Route service to expose Kasm</td>
		</tr>
		<tr>
			<td id="route--tls"><a href="./values.yaml#L217">route.tls</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Object to define the TLS configuration for your OpenShift Route -  [Configuring Secure Routes](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/networking/configuring-routes#configuring-default-certificate). </td>
		</tr>
		<tr>
			<td id="route--wildcardPolicy"><a href="./values.yaml#L213">route.wildcardPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
None
</pre>
</div>
			</td>
			<td>Set the wildcard policy for the OpenShift Route. Valid values: None, Subdomain </td>
		</tr>
		<tr>
			<td id="tcpRoute--annotations"><a href="./values.yaml#L346">tcpRoute.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="tcpRoute--apiVersion"><a href="./values.yaml#L317">tcpRoute.apiVersion</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
gateway.networking.k8s.io/v1
</pre>
</div>
			</td>
			<td>API version to render the TCPRoute at. TCPRoute has been standard-channel `v1` since Gateway API 1.6; set `gateway.networking.k8s.io/v1alpha2` for older, experimental-channel CRD bundles, where it is deprecated as of 1.6. </td>
		</tr>
		<tr>
			<td id="tcpRoute--enabled"><a href="./values.yaml#L312">tcpRoute.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set to `true` to publish the RDP Gateway through a Gateway API TCPRoute. </td>
		</tr>
		<tr>
			<td id="tcpRoute--labels"><a href="./values.yaml#L347">tcpRoute.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="tcpRoute--parentRefs"><a href="./values.yaml#L327">tcpRoute.parentRefs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Gateways to attach the route to, in the same shape as `httpRoute.parentRefs`. Single-zone shorthand; with multiple zones use `tcpRoute.zones` instead, since each zone needs its own listener. </td>
		</tr>
		<tr>
			<td id="tcpRoute--rdpAccessURL"><a href="./values.yaml#L322">tcpRoute.rdpAccessURL</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The hostname Kasm advertises to RDP clients, and the name the RDP Gateway serves under. Required when `tcpRoute.enabled` is true: a TCPRoute carries no hostname, so the gateway cannot infer it the way an HTTP route's backend can. </td>
		</tr>
		<tr>
			<td id="tcpRoute--zones"><a href="./values.yaml#L345">tcpRoute.zones</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Per-zone Gateway attachment, required when `kasmZones` defines more than one zone in the primary region. A TCPRoute matches on neither hostname nor SNI, so zones cannot share a listener the way they share one for `httpRoute`: give each zone its own listener and select it with `sectionName`. Example:   zones:     - name: zonea       parentRefs:         - name: kasm-gateway           namespace: kube-system           sectionName: rdp-zonea     - name: zoneb       parentRefs:         - name: kasm-gateway           namespace: kube-system           sectionName: rdp-zoneb </td>
		</tr>
		<tr>
			<td id="tlsRoute--annotations"><a href="./values.yaml#L295">tlsRoute.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="tlsRoute--apiVersion"><a href="./values.yaml#L291">tlsRoute.apiVersion</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
gateway.networking.k8s.io/v1
</pre>
</div>
			</td>
			<td>API version to render the TLSRoute at. TLSRoute has been standard-channel `v1` since Gateway API 1.5; set `gateway.networking.k8s.io/v1alpha2` for older, experimental-channel CRD bundles. </td>
		</tr>
		<tr>
			<td id="tlsRoute--enabled"><a href="./values.yaml#L286">tlsRoute.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set to `true` to publish the Kasm proxy by SNI passthrough through a Gateway API TLSRoute. `ingress`, `route`, `httpRoute` and `tlsRoute` are alternatives - enable at most one. </td>
		</tr>
		<tr>
			<td id="tlsRoute--labels"><a href="./values.yaml#L296">tlsRoute.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="tlsRoute--parentRefs"><a href="./values.yaml#L294">tlsRoute.parentRefs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Gateways to attach the route to, in the same shape as `httpRoute.parentRefs`. </td>
		</tr>
		<tr>
			<td id="trustedCaBundle--caCerts"><a href="./values.yaml#L525">trustedCaBundle.caCerts</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>The CA certificates to be stored in the configmap. This is an object where you can paste your PEM-formatted CA certificates in a key-value format where the key is the file name and the value is the PEM-formatted certificate data. All keys MUST end with a `.crt` extension. </td>
		</tr>
		<tr>
			<td id="trustedCaBundle--configMapName"><a href="./values.yaml#L520">trustedCaBundle.configMapName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="trustedCaBundle--enabled"><a href="./values.yaml#L515">trustedCaBundle.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set to true to enable the trusted CA bundle configuration </td>
		</tr>
		<tr>
			<td id="trustedCaBundle--resources"><a href="./values.yaml#L530">trustedCaBundle.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Manually configure resources for the `trusted-ca-init` initContainer that is injected into every Kasm workload while this feature is enabled. Leave empty to use the chart default (the `api` `small` preset); the container only runs `update-ca-certificates` once at startup. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--hostname"><a href="./values.yaml#L378">upstreamAuth.hostname</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The upstream auth hostname for the primary (or implicit default) zone, e.g. kasm-mgmt.example.com. Zones with `kasmZones[].upstream_auth_address` set keep their own value. Required by the ingress/route/httpRoute/tlsRoute publishers below; the service publisher works without it (the preseed then keeps `$request_host$`, and you set the address in the admin UI once the load balancer has one). </td>
		</tr>
		<tr>
			<td id="upstreamAuth--httpRoute"><a href="./values.yaml#L446">upstreamAuth.httpRoute</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
backendProtocol: http
enabled: false
labels: {}
parentRefs: []
zones: []
</pre>
</div>
			</td>
			<td>Publish the upstream auth endpoint through Gateway API HTTPRoutes, one per deployed zone. Same shape as `httpRoute`, including per-zone `zones[].parentRefs` overrides for zones that need their own listener. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--ingress"><a href="./values.yaml#L409">upstreamAuth.ingress</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
backendProtocol: http
enabled: false
ingressClassName: ""
labels: {}
secretName: ""
tls: true
</pre>
</div>
			</td>
			<td>Publish the upstream auth endpoint through an Ingress, one host rule per deployed zone. Point `ingressClassName` at an internal controller class to keep the endpoint private while the front-door Ingress stays public. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--ingress--backendProtocol"><a href="./values.yaml#L428">upstreamAuth.ingress.backendProtocol</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
http
</pre>
</div>
			</td>
			<td>Protocol the Ingress uses to reach the Kasm proxy Service. Valid values: http or https </td>
		</tr>
		<tr>
			<td id="upstreamAuth--ingress--secretName"><a href="./values.yaml#L424">upstreamAuth.ingress.secretName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Certificate Secret for the upstream auth Ingress. Empty (the default) uses the front door's chain: `certificate.secretName`, else the chart-minted Secret. The chart-minted certificates do NOT cover the upstream auth hostnames (they usually live in a private DNS zone), so set this to a Secret that does when the front end must present a matching certificate: controllers like ingress-nginx and Traefik do not reject a non-matching Secret, but they serve their default certificate for the host instead. Kasm agents do not validate the certificate, so this is hygiene, not a functional requirement. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--ingress--tls"><a href="./values.yaml#L414">upstreamAuth.ingress.tls</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Set to `true` to add a TLS section covering every zone's upstream auth hostname, using the certificate Secret below. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--route"><a href="./values.yaml#L435">upstreamAuth.route</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
backendProtocol: http
enabled: false
labels: {}
tls: {}
wildcardPolicy: None
</pre>
</div>
			</td>
			<td>Publish the upstream auth endpoint through OpenShift Routes, one per deployed zone. Same shape as `route`. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--service"><a href="./values.yaml#L383">upstreamAuth.service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
enabled: false
labels: {}
nodePort: ""
type: LoadBalancer
</pre>
</div>
			</td>
			<td>Publish the upstream auth endpoint with one Service per deployed zone (`<release>-upstream-auth-<zone>`), port 443 to the proxy's HTTPS port. This is raw L4: it cannot route by hostname, so multi-zone deployments get one load balancer per zone. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--service--annotations"><a href="./values.yaml#L403">upstreamAuth.service.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Annotations for the per-zone Services. This is where a private/internal load balancer scheme is selected, e.g.   service.beta.kubernetes.io/aws-load-balancer-scheme: internal </td>
		</tr>
		<tr>
			<td id="upstreamAuth--service--enabled"><a href="./values.yaml#L387">upstreamAuth.service.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Set to `true` to publish the upstream auth endpoint through a Service of the type below. </td>
		</tr>
		<tr>
			<td id="upstreamAuth--service--nodePort"><a href="./values.yaml#L398">upstreamAuth.service.nodePort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Pin the node port when `type` is NodePort. Leave empty to let Kubernetes assign one. Only valid with a single deployed zone, since every zone's Service would otherwise claim the same port. Agents reach the endpoint on this port, so include it in the zone's `upstream_auth_address` (host:port). </td>
		</tr>
		<tr>
			<td id="upstreamAuth--service--type"><a href="./values.yaml#L392">upstreamAuth.service.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
LoadBalancer
</pre>
</div>
			</td>
			<td>Service type. Allowed values: LoadBalancer, NodePort. (ClusterIP needs no extra Service - the per-zone proxy Service already exists; its in-cluster DNS name is printed by NOTES as the KubeVirt Upstream Auth Address.) </td>
		</tr>
		<tr>
			<td id="upstreamAuth--tlsRoute"><a href="./values.yaml#L457">upstreamAuth.tlsRoute</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
apiVersion: gateway.networking.k8s.io/v1
enabled: false
labels: {}
parentRefs: []
zones: []
</pre>
</div>
			</td>
			<td>Publish the upstream auth endpoint by SNI passthrough through Gateway API TLSRoutes, one per deployed zone; the Kasm proxy terminates TLS itself. Same shape as `tlsRoute`, plus per-zone `zones[].parentRefs` overrides. </td>
		</tr>
		<tr>
			<td id="useImageTags"><a href="./values.yaml#L591">useImageTags</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
develop
</pre>
</div>
			</td>
			<td>Chart-wide image tag used when a component's `image.tag` is empty. Per-component tag wins if set. To override the tag for a single component, see `components.<x>.image.tag` (or `database.image.tag`). Examples:   "1.19.0-rolling"             rolling tag, receives ongoing bug-fix updates within 1.19.x   "1.19.0"                     frozen point-in-time tag   "1.19.0-rolling-2026-06-02"  date-locked rolling tag, pins a specific rolling build </td>
		</tr>
	</tbody>
</table>

