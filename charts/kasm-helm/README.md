# Kasm on Kubernetes

![Version: 1.1200.0-develop](https://img.shields.io/badge/Version-1.1200.0--develop-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Kasm is a platform specializing in providing secure browser-based workspaces for a wide range of applications and industries. Its main goal is to provide isolated and secure environments that can be accessed via web browsers, ensuring that users can perform tasks without risking the security of their local systems.

**Homepage:** <https://kasm.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://../kasm-common | kasm-common | 0.1.0 |

<!-- This README.md.gotmpl is used by helm-docs to generate README.md which in turn generates the information on https://artifacthub.io/packages/helm/nautobot/nautobot so there are parts of this which are duplicated from `docs` -->
## Documentation

Please see our [official documentation site](https://docs.kasm.com) for more information.

> **Note:** Make sure to select the correct Kasm Workspaces version in the top-right version selector on the documentation site to ensure the guides match your deployment.

<!-- This section is a duplicate of docs/installation/prerequisites.md -->
## Prerequisites

* Kubernetes 1.24 or newer (older versions of Kubernetes may work, however, we try to keep this chart updated to [supported versions of Kubernetes](https://kubernetes.io/releases/))
* Helm 3.18.x or newer ([installation](https://helm.sh/docs/helm/helm_install/))

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
			<td id="affinity"><a href="./values.yaml#L1236">affinity</a></td>
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
			<td id="annotations"><a href="./values.yaml#L1256">annotations</a></td>
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
			<td id="applyHealthChecks"><a href="./values.yaml#L1244">applyHealthChecks</a></td>
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
			<td id="applySecurity"><a href="./values.yaml#L1240">applySecurity</a></td>
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
			<td id="certificate--certManager"><a href="./values.yaml#L210">certificate.certManager</a></td>
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
			<td id="certificate--secretName"><a href="./values.yaml#L199">certificate.secretName</a></td>
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
			<td id="clusterDomain"><a href="./values.yaml#L1223">clusterDomain</a></td>
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
			<td id="components--api--annotations"><a href="./values.yaml#L603">components.api.annotations</a></td>
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
			<td id="components--api--extraContainers"><a href="./values.yaml#L631">components.api.extraContainers</a></td>
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
			<td id="components--api--extraInitContainers"><a href="./values.yaml#L637">components.api.extraInitContainers</a></td>
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
			<td id="components--api--extraVolumeMounts"><a href="./values.yaml#L625">components.api.extraVolumeMounts</a></td>
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
			<td id="components--api--extraVolumes"><a href="./values.yaml#L616">components.api.extraVolumes</a></td>
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
			<td id="components--api--healthCheckTiming"><a href="./values.yaml#L599">components.api.healthCheckTiming</a></td>
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
			<td id="components--api--image"><a href="./values.yaml#L579">components.api.image</a></td>
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
			<td id="components--api--image--tag"><a href="./values.yaml#L583">components.api.image.tag</a></td>
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
			<td id="components--api--labels"><a href="./values.yaml#L607">components.api.labels</a></td>
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
			<td id="components--api--replicas"><a href="./values.yaml#L585">components.api.replicas</a></td>
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
			<td id="components--api--resources"><a href="./values.yaml#L605">components.api.resources</a></td>
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
			<td id="components--api--threadPool"><a href="./values.yaml#L640">components.api.threadPool</a></td>
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
			<td id="components--api--threadPoolLogInterval"><a href="./values.yaml#L643">components.api.threadPoolLogInterval</a></td>
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
			<td id="components--clickhouse--annotations"><a href="./values.yaml#L991">components.clickhouse.annotations</a></td>
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
			<td>Custom annotations to add to the ClickHouse StatefulSet</td>
		</tr>
		<tr>
			<td id="components--clickhouse--extraContainers"><a href="./values.yaml#L1026">components.clickhouse.extraContainers</a></td>
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
			<td>Additional sidecar containers to run in the pod</td>
		</tr>
		<tr>
			<td id="components--clickhouse--extraInitContainers"><a href="./values.yaml#L1028">components.clickhouse.extraInitContainers</a></td>
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
			<td>Additional init containers to run in the pod</td>
		</tr>
		<tr>
			<td id="components--clickhouse--extraVolumeMounts"><a href="./values.yaml#L1024">components.clickhouse.extraVolumeMounts</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the ClickHouse container</td>
		</tr>
		<tr>
			<td id="components--clickhouse--extraVolumes"><a href="./values.yaml#L1021">components.clickhouse.extraVolumes</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the ClickHouse container</td>
		</tr>
		<tr>
			<td id="components--clickhouse--healthCheckTiming"><a href="./values.yaml#L998">components.clickhouse.healthCheckTiming</a></td>
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
			<td>Override the pod's default healthcheck timing values for liveness and/or readiness probes. Values provided individually override their respective timing value.</td>
		</tr>
		<tr>
			<td id="components--clickhouse--image"><a href="./values.yaml#L984">components.clickhouse.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: clickhouse/clickhouse-server
tag: 24.12-alpine
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--clickhouse--image--tag"><a href="./values.yaml#L989">components.clickhouse.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
24.12-alpine
</pre>
</div>
			</td>
			<td>Tag for this component's image. Pinned by the chart rather than falling back to the chart-wide `useImageTags`, because ClickHouse is versioned independently of Kasm.</td>
		</tr>
		<tr>
			<td id="components--clickhouse--labels"><a href="./values.yaml#L995">components.clickhouse.labels</a></td>
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
			<td>Custom labels to add to the ClickHouse StatefulSet</td>
		</tr>
		<tr>
			<td id="components--clickhouse--resources"><a href="./values.yaml#L993">components.clickhouse.resources</a></td>
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
			<td>Manually configure the ClickHouse StatefulSet resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--clickhouse--storage--pvcSize"><a href="./values.yaml#L1011">components.clickhouse.storage.pvcSize</a></td>
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
			<td>Size of the PVC backing ClickHouse, in GiB. Telemetry volume scales with session count and retention; see the observability documentation for sizing guidance. </td>
		</tr>
		<tr>
			<td id="components--clickhouse--storage--retentionPolicy"><a href="./values.yaml#L1016">components.clickhouse.storage.retentionPolicy</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
whenDeleted: Retain
whenScaled: Retain
</pre>
</div>
			</td>
			<td>Configure how the ClickHouse volume should be retained or deleted throughout the StatefulSet's lifecycle. Defaults to Retain so telemetry history survives an uninstall. </td>
		</tr>
		<tr>
			<td id="components--clickhouse--storage--storageClassName"><a href="./values.yaml#L1007">components.clickhouse.storage.storageClassName</a></td>
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
			<td>Set the storage class to attach to ClickHouse for storage. Leaving this blank will use the cluster-default storage class. </td>
		</tr>
		<tr>
			<td id="components--connectionProxy--annotations"><a href="./values.yaml#L730">components.connectionProxy.annotations</a></td>
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
			<td id="components--connectionProxy--enabled"><a href="./values.yaml#L726">components.connectionProxy.enabled</a></td>
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
			<td id="components--connectionProxy--extraContainers"><a href="./values.yaml#L905">components.connectionProxy.extraContainers</a></td>
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
			<td id="components--connectionProxy--extraInitContainers"><a href="./values.yaml#L911">components.connectionProxy.extraInitContainers</a></td>
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
			<td id="components--connectionProxy--extraVolumeMounts"><a href="./values.yaml#L899">components.connectionProxy.extraVolumeMounts</a></td>
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
			<td id="components--connectionProxy--extraVolumes"><a href="./values.yaml#L890">components.connectionProxy.extraVolumes</a></td>
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
			<td id="components--connectionProxy--guac"><a href="./values.yaml#L766">components.connectionProxy.guac</a></td>
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
			<td id="components--connectionProxy--guac--enabled"><a href="./values.yaml#L770">components.connectionProxy.guac.enabled</a></td>
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
			<td id="components--connectionProxy--guac--guacClusterSize"><a href="./values.yaml#L781">components.connectionProxy.guac.guacClusterSize</a></td>
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
			<td id="components--connectionProxy--guac--healthCheckTiming"><a href="./values.yaml#L797">components.connectionProxy.guac.healthCheckTiming</a></td>
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
			<td id="components--connectionProxy--guac--image"><a href="./values.yaml#L774">components.connectionProxy.guac.image</a></td>
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
			<td id="components--connectionProxy--guac--image--tag"><a href="./values.yaml#L778">components.connectionProxy.guac.image.tag</a></td>
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
			<td id="components--connectionProxy--guac--recordingData"><a href="./values.yaml#L802">components.connectionProxy.guac.recordingData</a></td>
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
			<td id="components--connectionProxy--guac--recordingData--pvcSize"><a href="./values.yaml#L804">components.connectionProxy.guac.recordingData.pvcSize</a></td>
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
			<td id="components--connectionProxy--guac--recordingData--storageClassName"><a href="./values.yaml#L806">components.connectionProxy.guac.recordingData.storageClassName</a></td>
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
			<td id="components--connectionProxy--guac--resources"><a href="./values.yaml#L783">components.connectionProxy.guac.resources</a></td>
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
			<td id="components--connectionProxy--labels"><a href="./values.yaml#L732">components.connectionProxy.labels</a></td>
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
			<td id="components--connectionProxy--nginx"><a href="./values.yaml#L736">components.connectionProxy.nginx</a></td>
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
			<td id="components--connectionProxy--nginx--healthCheckTiming"><a href="./values.yaml#L760">components.connectionProxy.nginx.healthCheckTiming</a></td>
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
			<td id="components--connectionProxy--nginx--image"><a href="./values.yaml#L740">components.connectionProxy.nginx.image</a></td>
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
			<td id="components--connectionProxy--nginx--image--tag"><a href="./values.yaml#L744">components.connectionProxy.nginx.image.tag</a></td>
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
			<td id="components--connectionProxy--nginx--resources"><a href="./values.yaml#L746">components.connectionProxy.nginx.resources</a></td>
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
			<td id="components--connectionProxy--rdpGateway"><a href="./values.yaml#L810">components.connectionProxy.rdpGateway</a></td>
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
			<td id="components--connectionProxy--rdpGateway--enabled"><a href="./values.yaml#L814">components.connectionProxy.rdpGateway.enabled</a></td>
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
			<td id="components--connectionProxy--rdpGateway--healthCheckTiming"><a href="./values.yaml#L843">components.connectionProxy.rdpGateway.healthCheckTiming</a></td>
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
			<td id="components--connectionProxy--rdpGateway--image"><a href="./values.yaml#L818">components.connectionProxy.rdpGateway.image</a></td>
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
			<td id="components--connectionProxy--rdpGateway--image--tag"><a href="./values.yaml#L822">components.connectionProxy.rdpGateway.image.tag</a></td>
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
			<td id="components--connectionProxy--rdpGateway--iniConfigMapName"><a href="./values.yaml#L827">components.connectionProxy.rdpGateway.iniConfigMapName</a></td>
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
			<td id="components--connectionProxy--rdpGateway--resources"><a href="./values.yaml#L829">components.connectionProxy.rdpGateway.resources</a></td>
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
			<td id="components--connectionProxy--rdpHttpsGateway"><a href="./values.yaml#L849">components.connectionProxy.rdpHttpsGateway</a></td>
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
			<td id="components--connectionProxy--rdpHttpsGateway--enabled"><a href="./values.yaml#L854">components.connectionProxy.rdpHttpsGateway.enabled</a></td>
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
			<td id="components--connectionProxy--rdpHttpsGateway--healthCheckTiming"><a href="./values.yaml#L878">components.connectionProxy.rdpHttpsGateway.healthCheckTiming</a></td>
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
			<td id="components--connectionProxy--rdpHttpsGateway--image"><a href="./values.yaml#L858">components.connectionProxy.rdpHttpsGateway.image</a></td>
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
			<td id="components--connectionProxy--rdpHttpsGateway--image--tag"><a href="./values.yaml#L862">components.connectionProxy.rdpHttpsGateway.image.tag</a></td>
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
			<td id="components--connectionProxy--rdpHttpsGateway--resources"><a href="./values.yaml#L864">components.connectionProxy.rdpHttpsGateway.resources</a></td>
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
			<td id="components--connectionProxy--replicas"><a href="./values.yaml#L728">components.connectionProxy.replicas</a></td>
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
			<td id="components--manager--annotations"><a href="./values.yaml#L675">components.manager.annotations</a></td>
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
			<td id="components--manager--extraContainers"><a href="./values.yaml#L703">components.manager.extraContainers</a></td>
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
			<td id="components--manager--extraInitContainers"><a href="./values.yaml#L709">components.manager.extraInitContainers</a></td>
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
			<td id="components--manager--extraVolumeMounts"><a href="./values.yaml#L697">components.manager.extraVolumeMounts</a></td>
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
			<td id="components--manager--extraVolumes"><a href="./values.yaml#L688">components.manager.extraVolumes</a></td>
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
			<td id="components--manager--healthCheckTiming"><a href="./values.yaml#L671">components.manager.healthCheckTiming</a></td>
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
			<td id="components--manager--image"><a href="./values.yaml#L651">components.manager.image</a></td>
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
			<td id="components--manager--image--tag"><a href="./values.yaml#L655">components.manager.image.tag</a></td>
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
			<td id="components--manager--labels"><a href="./values.yaml#L679">components.manager.labels</a></td>
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
			<td id="components--manager--replicas"><a href="./values.yaml#L657">components.manager.replicas</a></td>
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
			<td id="components--manager--resources"><a href="./values.yaml#L677">components.manager.resources</a></td>
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
			<td id="components--manager--supportBundleTimer"><a href="./values.yaml#L716">components.manager.supportBundleTimer</a></td>
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
			<td id="components--manager--updateTimer"><a href="./values.yaml#L712">components.manager.updateTimer</a></td>
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
			<td id="components--otelGateway--annotations"><a href="./values.yaml#L936">components.otelGateway.annotations</a></td>
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
			<td>Custom annotations to add to the gateway Collector Deployment</td>
		</tr>
		<tr>
			<td id="components--otelGateway--extraContainers"><a href="./values.yaml#L951">components.otelGateway.extraContainers</a></td>
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
			<td>Additional sidecar containers to run in the pod</td>
		</tr>
		<tr>
			<td id="components--otelGateway--extraInitContainers"><a href="./values.yaml#L953">components.otelGateway.extraInitContainers</a></td>
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
			<td>Additional init containers to run in the pod</td>
		</tr>
		<tr>
			<td id="components--otelGateway--extraVolumeMounts"><a href="./values.yaml#L949">components.otelGateway.extraVolumeMounts</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the gateway Collector container</td>
		</tr>
		<tr>
			<td id="components--otelGateway--extraVolumes"><a href="./values.yaml#L946">components.otelGateway.extraVolumes</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the gateway Collector container</td>
		</tr>
		<tr>
			<td id="components--otelGateway--image"><a href="./values.yaml#L922">components.otelGateway.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: otel/opentelemetry-collector-contrib
tag: 0.156.0
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--otelGateway--image--tag"><a href="./values.yaml#L927">components.otelGateway.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0.156.0
</pre>
</div>
			</td>
			<td>Tag for this component's image. Pinned by the chart rather than falling back to the chart-wide `useImageTags`, because the Collector is versioned independently of Kasm.</td>
		</tr>
		<tr>
			<td id="components--otelGateway--labels"><a href="./values.yaml#L943">components.otelGateway.labels</a></td>
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
			<td>Custom labels to add to the gateway Collector Deployment</td>
		</tr>
		<tr>
			<td id="components--otelGateway--replicas"><a href="./values.yaml#L934">components.otelGateway.replicas</a></td>
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
			<td>Override the replica count set by deploymentSize. Set to 0 to use the deploymentSize preset (default, which is 1 at every size).  Pinned to 1: every sender exports straight to the gateway, and nothing in front of it partitions traces by ID, so a second replica would make tail_sampling decide on partial traces and silently drop spans. The chart fails at render time if this is set above 1.</td>
		</tr>
		<tr>
			<td id="components--otelGateway--resources"><a href="./values.yaml#L941">components.otelGateway.resources</a></td>
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
			<td>Manually configure the gateway Collector Deployment resources. This overrides the pre-defined `deploymentSize` values. The memory_limiter and num_traces settings baked into the gateway config are sized from the deploymentSize preset, not from this value, so a manual memory limit set below the preset can let the container OOM before memory_limiter has a chance to shed load.</td>
		</tr>
		<tr>
			<td id="components--otelSidecar--image"><a href="./values.yaml#L965">components.otelSidecar.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: otel/opentelemetry-collector-contrib
tag: 0.156.0
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one. </td>
		</tr>
		<tr>
			<td id="components--otelSidecar--image--tag"><a href="./values.yaml#L970">components.otelSidecar.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0.156.0
</pre>
</div>
			</td>
			<td>Tag for this component's image. Pinned by the chart rather than falling back to the chart-wide `useImageTags`, because the Collector is versioned independently of Kasm.</td>
		</tr>
		<tr>
			<td id="components--otelSidecar--resources"><a href="./values.yaml#L974">components.otelSidecar.resources</a></td>
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
			<td>Manually configure the Collector sidecar resources. This overrides the pre-defined `deploymentSize` values. Applied to every sidecar; note that a large deployment runs one per Proxy replica, one per Connection Proxy replica, and one in the DB pod.</td>
		</tr>
		<tr>
			<td id="components--proxy--annotations"><a href="./values.yaml#L537">components.proxy.annotations</a></td>
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
			<td id="components--proxy--extraContainers"><a href="./values.yaml#L565">components.proxy.extraContainers</a></td>
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
			<td id="components--proxy--extraInitContainers"><a href="./values.yaml#L571">components.proxy.extraInitContainers</a></td>
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
			<td id="components--proxy--extraVolumeMounts"><a href="./values.yaml#L559">components.proxy.extraVolumeMounts</a></td>
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
			<td id="components--proxy--extraVolumes"><a href="./values.yaml#L550">components.proxy.extraVolumes</a></td>
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
			<td id="components--proxy--healthCheckTiming"><a href="./values.yaml#L533">components.proxy.healthCheckTiming</a></td>
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
			<td id="components--proxy--image"><a href="./values.yaml#L513">components.proxy.image</a></td>
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
			<td id="components--proxy--image--tag"><a href="./values.yaml#L517">components.proxy.image.tag</a></td>
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
			<td id="components--proxy--labels"><a href="./values.yaml#L541">components.proxy.labels</a></td>
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
			<td id="components--proxy--replicas"><a href="./values.yaml#L519">components.proxy.replicas</a></td>
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
			<td id="components--proxy--resources"><a href="./values.yaml#L539">components.proxy.resources</a></td>
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
			<td id="database--annotations"><a href="./values.yaml#L369">database.annotations</a></td>
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
			<td id="database--extraContainers"><a href="./values.yaml#L413">database.extraContainers</a></td>
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
			<td id="database--extraInitContainers"><a href="./values.yaml#L419">database.extraInitContainers</a></td>
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
			<td id="database--extraVolumeMounts"><a href="./values.yaml#L407">database.extraVolumeMounts</a></td>
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
			<td id="database--extraVolumes"><a href="./values.yaml#L398">database.extraVolumes</a></td>
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
			<td id="database--healthCheckTiming"><a href="./values.yaml#L385">database.healthCheckTiming</a></td>
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
			<td id="database--hostname"><a href="./values.yaml#L312">database.hostname</a></td>
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
			<td id="database--image"><a href="./values.yaml#L347">database.image</a></td>
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
			<td id="database--image--tag"><a href="./values.yaml#L351">database.image.tag</a></td>
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
			<td id="database--kasmDbName"><a href="./values.yaml#L318">database.kasmDbName</a></td>
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
			<td id="database--kasmDbSecret"><a href="./values.yaml#L328">database.kasmDbSecret</a></td>
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
			<td id="database--kasmDbUser"><a href="./values.yaml#L321">database.kasmDbUser</a></td>
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
			<td id="database--labels"><a href="./values.yaml#L389">database.labels</a></td>
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
			<td id="database--port"><a href="./values.yaml#L315">database.port</a></td>
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
			<td id="database--postgresMasterUser"><a href="./values.yaml#L337">database.postgresMasterUser</a></td>
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
			<td id="database--resources"><a href="./values.yaml#L371">database.resources</a></td>
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
			<td id="database--standalone"><a href="./values.yaml#L309">database.standalone</a></td>
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
			<td id="database--storage--pvcSize"><a href="./values.yaml#L362">database.storage.pvcSize</a></td>
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
			<td id="database--storage--retentionPolicy"><a href="./values.yaml#L365">database.storage.retentionPolicy</a></td>
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
			<td id="database--storage--storageClassName"><a href="./values.yaml#L358">database.storage.storageClassName</a></td>
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
			<td id="dbManagement--backupCron--enabled"><a href="./values.yaml#L483">dbManagement.backupCron.enabled</a></td>
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
			<td id="dbManagement--backupCron--pvcName"><a href="./values.yaml#L486">dbManagement.backupCron.pvcName</a></td>
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
			<td id="dbManagement--backupCron--pvcSize"><a href="./values.yaml#L502">dbManagement.backupCron.pvcSize</a></td>
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
			<td id="dbManagement--backupCron--schedule"><a href="./values.yaml#L491">dbManagement.backupCron.schedule</a></td>
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
			<td id="dbManagement--backupCron--storageClass"><a href="./values.yaml#L498">dbManagement.backupCron.storageClass</a></td>
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
			<td id="dbManagement--backupCron--timeZone"><a href="./values.yaml#L494">dbManagement.backupCron.timeZone</a></td>
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
			<td id="dbManagement--dbConnectionTimeout"><a href="./values.yaml#L431">dbManagement.dbConnectionTimeout</a></td>
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
			<td id="dbManagement--initJobTTLSecondsAfterFinished"><a href="./values.yaml#L429">dbManagement.initJobTTLSecondsAfterFinished</a></td>
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
			<td id="dbManagement--initialize"><a href="./values.yaml#L426">dbManagement.initialize</a></td>
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
			<td id="dbManagement--upgrade--backupStorageClass"><a href="./values.yaml#L467">dbManagement.upgrade.backupStorageClass</a></td>
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
			<td id="dbManagement--upgrade--enable"><a href="./values.yaml#L440">dbManagement.upgrade.enable</a></td>
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
			<td id="dbManagement--upgrade--oldDbBackupFileName"><a href="./values.yaml#L476">dbManagement.upgrade.oldDbBackupFileName</a></td>
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
			<td id="dbManagement--upgrade--oldDbHostname"><a href="./values.yaml#L445">dbManagement.upgrade.oldDbHostname</a></td>
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
			<td id="dbManagement--upgrade--oldDbSecretsName"><a href="./values.yaml#L473">dbManagement.upgrade.oldDbSecretsName</a></td>
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
			<td id="dbManagement--upgrade--skipBackupAndRestore"><a href="./values.yaml#L464">dbManagement.upgrade.skipBackupAndRestore</a></td>
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
			<td id="directRdpService"><a href="./values.yaml#L84">directRdpService</a></td>
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
			<td id="directRdpService--annotations"><a href="./values.yaml#L104">directRdpService.annotations</a></td>
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
			<td id="directRdpService--enabled"><a href="./values.yaml#L88">directRdpService.enabled</a></td>
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
			<td id="directRdpService--labels"><a href="./values.yaml#L107">directRdpService.labels</a></td>
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
			<td id="directRdpService--loadBalancerPort"><a href="./values.yaml#L100">directRdpService.loadBalancerPort</a></td>
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
			<td>External port exposed when `type` is LoadBalancer. Overridden per Service by `perServiceSettings[i].loadBalancerPort`. No effect when `type` is NodePort. </td>
		</tr>
		<tr>
			<td id="directRdpService--perServiceSettings"><a href="./values.yaml#L129">directRdpService.perServiceSettings</a></td>
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
			<td id="directRdpService--rdpAccessURL"><a href="./values.yaml#L92">directRdpService.rdpAccessURL</a></td>
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
			<td id="directRdpService--type"><a href="./values.yaml#L96">directRdpService.type</a></td>
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
			<td id="extraAnnotations--configMap"><a href="./values.yaml#L1264">extraAnnotations.configMap</a></td>
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
			<td id="extraAnnotations--cronJob"><a href="./values.yaml#L1266">extraAnnotations.cronJob</a></td>
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
			<td id="extraAnnotations--cronPod"><a href="./values.yaml#L1268">extraAnnotations.cronPod</a></td>
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
			<td id="extraAnnotations--daemonSet"><a href="./values.yaml#L1270">extraAnnotations.daemonSet</a></td>
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
			<td>Additional daemonSet annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraAnnotations--deployment"><a href="./values.yaml#L1272">extraAnnotations.deployment</a></td>
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
			<td id="extraAnnotations--job"><a href="./values.yaml#L1274">extraAnnotations.job</a></td>
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
			<td id="extraAnnotations--pod"><a href="./values.yaml#L1276">extraAnnotations.pod</a></td>
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
			<td id="extraAnnotations--pvc"><a href="./values.yaml#L1278">extraAnnotations.pvc</a></td>
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
			<td id="extraAnnotations--secret"><a href="./values.yaml#L1282">extraAnnotations.secret</a></td>
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
			<td id="extraAnnotations--service"><a href="./values.yaml#L1280">extraAnnotations.service</a></td>
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
			<td id="extraAnnotations--statefulSet"><a href="./values.yaml#L1284">extraAnnotations.statefulSet</a></td>
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
			<td id="extraContainerVolumeMounts"><a href="./values.yaml#L1332">extraContainerVolumeMounts</a></td>
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
			<td id="extraContainers"><a href="./values.yaml#L1349">extraContainers</a></td>
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
			<td id="extraInitContainers"><a href="./values.yaml#L1356">extraInitContainers</a></td>
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
			<td id="extraInitVolumeMounts"><a href="./values.yaml#L1342">extraInitVolumeMounts</a></td>
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
			<td id="extraLabels--configMap"><a href="./values.yaml#L1292">extraLabels.configMap</a></td>
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
			<td id="extraLabels--cronJob"><a href="./values.yaml#L1306">extraLabels.cronJob</a></td>
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
			<td id="extraLabels--cronPod"><a href="./values.yaml#L1308">extraLabels.cronPod</a></td>
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
			<td id="extraLabels--daemonSet"><a href="./values.yaml#L1294">extraLabels.daemonSet</a></td>
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
			<td>Additional daemonSet labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--deployment"><a href="./values.yaml#L1296">extraLabels.deployment</a></td>
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
			<td id="extraLabels--job"><a href="./values.yaml#L1304">extraLabels.job</a></td>
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
			<td id="extraLabels--pod"><a href="./values.yaml#L1298">extraLabels.pod</a></td>
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
			<td id="extraLabels--pvc"><a href="./values.yaml#L1310">extraLabels.pvc</a></td>
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
			<td id="extraLabels--secret"><a href="./values.yaml#L1300">extraLabels.secret</a></td>
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
			<td id="extraLabels--service"><a href="./values.yaml#L1302">extraLabels.service</a></td>
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
			<td id="extraLabels--statefulSet"><a href="./values.yaml#L1312">extraLabels.statefulSet</a></td>
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
			<td id="extraObjects"><a href="./values.yaml#L1361">extraObjects</a></td>
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
			<td id="extraVolumes"><a href="./values.yaml#L1322">extraVolumes</a></td>
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
			<td id="imagePullPolicy"><a href="./values.yaml#L1196">imagePullPolicy</a></td>
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
			<td id="imagePullSecrets--annotations"><a href="./values.yaml#L1219">imagePullSecrets.annotations</a></td>
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
			<td id="imagePullSecrets--email"><a href="./values.yaml#L1215">imagePullSecrets.email</a></td>
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
			<td id="imagePullSecrets--enabled"><a href="./values.yaml#L1202">imagePullSecrets.enabled</a></td>
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
			<td id="imagePullSecrets--labels"><a href="./values.yaml#L1217">imagePullSecrets.labels</a></td>
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
			<td id="imagePullSecrets--name"><a href="./values.yaml#L1207">imagePullSecrets.name</a></td>
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
			<td id="imagePullSecrets--password"><a href="./values.yaml#L1213">imagePullSecrets.password</a></td>
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
			<td id="imagePullSecrets--registry"><a href="./values.yaml#L1209">imagePullSecrets.registry</a></td>
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
			<td id="imagePullSecrets--username"><a href="./values.yaml#L1211">imagePullSecrets.username</a></td>
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
			<td id="ingress--annotations"><a href="./values.yaml#L147">ingress.annotations</a></td>
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
			<td id="ingress--backendProtocol"><a href="./values.yaml#L143">ingress.backendProtocol</a></td>
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
			<td id="ingress--enabled"><a href="./values.yaml#L136">ingress.enabled</a></td>
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
			<td id="ingress--ingressClassName"><a href="./values.yaml#L146">ingress.ingressClassName</a></td>
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
			<td id="ingress--labels"><a href="./values.yaml#L148">ingress.labels</a></td>
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
			<td id="ingress--tls"><a href="./values.yaml#L139">ingress.tls</a></td>
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
			<td id="isOpenshift"><a href="./values.yaml#L47">isOpenshift</a></td>
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
			<td id="kasmConfig"><a href="./values.yaml#L1369">kasmConfig</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
adminUsername: admin@kasm.local
config: {}
defaultApiUsers: false
defaultUsers: false
existingDefaultPropertiesSecret:
    key: default_properties.yaml
    name: ""
generatePreseed: false
</pre>
</div>
			</td>
			<td>Use fields in the `kasmConfig` section to apply customization to a Kasm deployment during database initialization.  NOTE: This data is only used during DB initialization and does not have any effect on live Kasm configuration settings.  </td>
		</tr>
		<tr>
			<td id="kasmConfig--adminUsername"><a href="./values.yaml#L1391">kasmConfig.adminUsername</a></td>
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
			<td id="kasmConfig--config"><a href="./values.yaml#L1408">kasmConfig.config</a></td>
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
			<td>Kasm DB pre-seed configuration settings in YAML format. Refer to the [Preseed Documentation](./docs/preseed.md) and to the [Kasm Slip-Stream Install](https://docs.kasm.com/docs/1.19.0/how-to/administration/import-export/slipstream-install) documentation for additional details. </td>
		</tr>
		<tr>
			<td id="kasmConfig--defaultApiUsers"><a href="./values.yaml#L1383">kasmConfig.defaultApiUsers</a></td>
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
			<td>Creates two predefined sets of API credentials with permissions accommodating most standard deployment scenarios. Refer to the [Default API Users](./docs/default-api-users.md) for additional information about what this flag creates. </td>
		</tr>
		<tr>
			<td id="kasmConfig--defaultUsers"><a href="./values.yaml#L1378">kasmConfig.defaultUsers</a></td>
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
			<td>Creates a series of 4 users and 5 groups with a standard set of permissions accommodating most standard deployment scenarios. Refer to the [Default Users](./docs/default-users.md) for additional information about what this flag creates. </td>
		</tr>
		<tr>
			<td id="kasmConfig--existingDefaultPropertiesSecret"><a href="./values.yaml#L1401">kasmConfig.existingDefaultPropertiesSecret</a></td>
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
			<td id="kasmConfig--generatePreseed"><a href="./values.yaml#L1373">kasmConfig.generatePreseed</a></td>
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
			<td>Enable generation of a custom DB initialization configuration to pre-configure Kasm during installation. </td>
		</tr>
		<tr>
			<td id="kasmSecrets"><a href="./values.yaml#L257">kasmSecrets</a></td>
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
    clickhouse-password: ""
    clickhouse-ro-password: ""
    db-password: ""
    manager-token: ""
    otel-bearer-token: ""
    service-token: ""
    user-password: ""
</pre>
</div>
			</td>
			<td>Use this to create custom Kasm Password secret, or to reference an existing one. If this is left blank then Helm will automatically generate random passwords and store them as `<Release-Name>-secrets` in your deployment namespace.  To reference a secret you already created yourself, set `create: false` and `name: "<existing secret name>"`, leaving `passwords` at its defaults; the chart will not manage that secret and will read the credentials from it.  To have the chart create the secret but pin one or more specific credential values (leaving the rest randomly generated), keep `create: true`, optionally set `name`, and set the desired key(s) under `passwords`. </td>
		</tr>
		<tr>
			<td id="kasmSecrets--annotations"><a href="./values.yaml#L289">kasmSecrets.annotations</a></td>
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
			<td id="kasmSecrets--create"><a href="./values.yaml#L260">kasmSecrets.create</a></td>
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
			<td id="kasmSecrets--labels"><a href="./values.yaml#L291">kasmSecrets.labels</a></td>
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
			<td id="kasmSecrets--name"><a href="./values.yaml#L265">kasmSecrets.name</a></td>
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
			<td id="kasmSecrets--passwords"><a href="./values.yaml#L277">kasmSecrets.passwords</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
admin-password: ""
clickhouse-password: ""
clickhouse-ro-password: ""
db-password: ""
manager-token: ""
otel-bearer-token: ""
service-token: ""
user-password: ""
</pre>
</div>
			</td>
			<td>Set any of the five well-known keys below to a non-empty value to pin that credential to a specific value instead of letting the chart generate (or preserve, on upgrade) a random one. An explicitly set value here always wins, even if a Secret with that key already exists in the namespace.  This object also accepts additional, arbitrary keys beyond the five below. Any extra key you add is written into the generated Secret's `data` as a literal base64-encoded value (no random generation, since the chart has no other source of truth for a custom key) - useful for seeding extra application secrets alongside the standard Kasm credentials.  NOTE: Only used when `kasmSecrets.create` is `true`. Has no effect when referencing an existing secret. </td>
		</tr>
		<tr>
			<td id="kasmZones"><a href="./values.yaml#L38">kasmZones</a></td>
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
			<td>This is a list of objects defining different Kasm Zone configurations for your deployment. This configuration is typically used for multi-region, large, or custom deployments where the customer requires a high degree of configurability and has multiple resources in disparate areas.  NOTE: If you configure custom zones below, you MUST use a valid `ingress` configuration due to the increased deployment complexity of a multi-zone Kasm deployment. Refer to the Kasm [Deployment Zones](https://docs.kasm.com/docs/latest/guide/deployment_zones) documentation for more information on Kasm Zones.  The zone marked `primary: true` is treated as the primary zone; if no zone is marked primary, the first zone in the list is used instead. At most one zone may be marked `primary: true`. Traffic to the configured `publicAddr` in the ingress rule will be routed to this primary zone.  Each zone requires a `name` (or the `zone_name` alias, if `name` is not set; `name` wins if both are set).  Each zone's `proxy_hostname` is used to build the ingress/route/certificate hostnames for that zone, as well as the zone's preseed `proxy_hostname` value. `proxyAddress` is a deprecated alias for `proxy_hostname`, kept for backwards compatibility; if both are set, `proxy_hostname` wins. </td>
		</tr>
		<tr>
			<td id="labels"><a href="./values.yaml#L1252">labels</a></td>
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
			<td id="nginxResolver"><a href="./values.yaml#L61">nginxResolver</a></td>
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
			<td id="nodeSelector"><a href="./values.yaml#L1228">nodeSelector</a></td>
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
			<td id="observability--browser"><a href="./values.yaml#L1184">observability.browser</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
</pre>
</div>
			</td>
			<td>Collect real-user telemetry from the Kasm web UI in the user's browser. </td>
		</tr>
		<tr>
			<td id="observability--browser--enabled"><a href="./values.yaml#L1188">observability.browser.enabled</a></td>
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
			<td>Serve the browser telemetry runtime configuration so the Kasm web UI reports page loads and user interactions. When false (the default), a stub is served that disables the browser SDK without producing console errors.</td>
		</tr>
		<tr>
			<td id="observability--clickhouse--caCert"><a href="./values.yaml#L1156">observability.clickhouse.caCert</a></td>
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
			<td>PEM-encoded CA certificate trusted when connecting to a *standalone* ClickHouse over TLS (e.g. `httpEndpoint: https://...` behind a private or self-signed CA). Ignored for the bundled ClickHouse, which already uses the shared Kasm certificate. `clickhouse_connect` (the Python client Kasm's api/manager use) requires an explicit CA file — it does not consult `SSL_CERT_FILE`/`REQUESTS_CA_BUNDLE` or this chart's `trustedCaBundle` mechanism — so setting this renders a dedicated ConfigMap and mounts it into the api/manager containers. Leave empty to use the system trust store, or set `tlsVerify: false` to skip verification instead. Mutually exclusive with `caCertConfigMap`. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--caCertConfigMap"><a href="./values.yaml#L1161">observability.clickhouse.caCertConfigMap</a></td>
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
			<td>Name of an existing ConfigMap containing the CA certificate for a standalone ClickHouse, under the key `ca.crt`. Use this instead of `caCert` if you already manage the certificate as a ConfigMap. Ignored for the bundled ClickHouse. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--database"><a href="./values.yaml#L1120">observability.clickhouse.database</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasm_otel
</pre>
</div>
			</td>
			<td>Name of the ClickHouse database holding Kasm telemetry.  Changing this on an existing deployment requires starting from an empty ClickHouse volume. The audit-log retention tier depends on a column created by the initial schema, which only runs when the data directory is empty; pointing an existing volume at a new database name silently drops audit logs to the shorter `retention.logsDays` window. See [Observability](./docs/observability.md) for the procedure and a way to check an existing deployment. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--enabled"><a href="./values.yaml#L1094">observability.clickhouse.enabled</a></td>
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
			<td>Deploy a ClickHouse StatefulSet to store telemetry. To use a ClickHouse you already run, leave this true and set `standalone` instead. Setting this to false is only valid when the gateway has somewhere else to send telemetry: set `observability.collector.gateway.forward.endpoint` to an external OTLP/HTTP backend, or the render fails rather than deploying a Collector that would discard every signal. Kasm reporting features read from ClickHouse, so they return empty results whenever no ClickHouse is configured. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--existingSecret"><a href="./values.yaml#L1138">observability.clickhouse.existingSecret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
key: ""
name: ""
readKey: ""
</pre>
</div>
			</td>
			<td>Read the ClickHouse password(s) from an existing Secret instead of the chart-generated `clickhouse-password`/`clickhouse-ro-password` keys. `name` and `key` (for `username`) are required together when used; `readKey` (for `readUsername`) is optional and falls back to `key` when unset, matching `readUsername`'s own fallback to `username`. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--httpEndpoint"><a href="./values.yaml#L1110">observability.clickhouse.httpEndpoint</a></td>
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
			<td>URL for ClickHouse's HTTP interface, used by Kasm to read reports and logs (e.g. `https://clickhouse.example.com:8443`). Only used when `standalone` is true, and required together with `nativeEndpoint`. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--nativeEndpoint"><a href="./values.yaml#L1105">observability.clickhouse.nativeEndpoint</a></td>
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
			<td>DSN for ClickHouse's native interface, used by the Collector to write telemetry (e.g. `tcp://clickhouse.example.com:9440?secure=true&skip_verify=true`). A bare `host:port` is wrapped with the chart's defaults. Only used when `standalone` is true, and required together with `httpEndpoint`. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--readUsername"><a href="./values.yaml#L1132">observability.clickhouse.readUsername</a></td>
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
			<td>ClickHouse user api/manager use to read reports, holding only GRANT SELECT ON <db>.* instead of `username`'s full access. When the chart manages ClickHouse (`enabled: true`, `standalone: false`), leaving this empty still gets you a read-only user: it defaults to `kasm_otel_ro`. For a `standalone` external ClickHouse, leaving this empty instead keeps api/manager on `username` (no read-only user is rendered) unless you set this to a read-only user you have provisioned there yourself. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--retention"><a href="./values.yaml#L1171">observability.clickhouse.retention</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
auditLogsDays: 365
logsDays: 30
metricsDays: 90
tracesDays: 7
</pre>
</div>
			</td>
			<td>How long each class of telemetry is kept before ClickHouse deletes it. Applied to the schema at install time and re-applied by a post-upgrade Job when these values change. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--retention--auditLogsDays"><a href="./values.yaml#L1176">observability.clickhouse.retention.auditLogsDays</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
365
</pre>
</div>
			</td>
			<td>Retention in days for security-relevant audit logs (login and logout events). Usually longer than general logs to satisfy audit requirements.</td>
		</tr>
		<tr>
			<td id="observability--clickhouse--retention--logsDays"><a href="./values.yaml#L1173">observability.clickhouse.retention.logsDays</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
30
</pre>
</div>
			</td>
			<td>Retention in days for general application logs.</td>
		</tr>
		<tr>
			<td id="observability--clickhouse--retention--metricsDays"><a href="./values.yaml#L1180">observability.clickhouse.retention.metricsDays</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
90
</pre>
</div>
			</td>
			<td>Retention in days for metrics.</td>
		</tr>
		<tr>
			<td id="observability--clickhouse--retention--tracesDays"><a href="./values.yaml#L1178">observability.clickhouse.retention.tracesDays</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
7
</pre>
</div>
			</td>
			<td>Retention in days for distributed traces.</td>
		</tr>
		<tr>
			<td id="observability--clickhouse--standalone"><a href="./values.yaml#L1099">observability.clickhouse.standalone</a></td>
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
			<td>Setting standalone to true will prevent the deployment of the ClickHouse StatefulSet and requires you to have a ClickHouse server already set up and awaiting connections. Use the endpoint values below to connect to your external instance. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--tls"><a href="./values.yaml#L1146">observability.clickhouse.tls</a></td>
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
			<td>Enable TLS on the bundled ClickHouse's 8443 (HTTPS) and 9440 (native) ports using the same certificate as the rest of Kasm, mirroring how the bundled Kasm DB is configured. Requires `certificate.secretName` or cert-manager. Has no effect when `standalone` is true. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--tlsVerify"><a href="./values.yaml#L1167">observability.clickhouse.tlsVerify</a></td>
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
			<td>Whether the api/manager containers verify a standalone ClickHouse's TLS certificate at all. Set to false to skip verification (not recommended). Ignored when `caCert` or `caCertConfigMap` is set (an explicit CA always wins), and for the bundled ClickHouse, whose certificate is always verified. </td>
		</tr>
		<tr>
			<td id="observability--clickhouse--username"><a href="./values.yaml#L1124">observability.clickhouse.username</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasm_otel
</pre>
</div>
			</td>
			<td>ClickHouse user Kasm connects as. Also the writer credential used by the gateway Collector and the retention Job. </td>
		</tr>
		<tr>
			<td id="observability--collector--gateway"><a href="./values.yaml#L1054">observability.collector.gateway</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
existingConfigMap: ""
forward:
    endpoint: ""
    existingSecret:
        key: ""
        name: ""
    token: ""
tailSamplePercentage: 10
</pre>
</div>
			</td>
			<td>Configure the single cluster-wide gateway Collector, which makes the trace-sampling decision and is the only writer to ClickHouse. </td>
		</tr>
		<tr>
			<td id="observability--collector--gateway--existingConfigMap"><a href="./values.yaml#L1061">observability.collector.gateway.existingConfigMap</a></td>
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
			<td>Name of a user-created ConfigMap holding a complete configuration for the gateway Collector, under the key `config.yaml`. Set this to take full ownership of the gateway config: the chart renders none of its own, and the sibling values that only shape that config (`tailSamplePercentage` and `forward`, plus `clickhouse.retention`) are ignored. </td>
		</tr>
		<tr>
			<td id="observability--collector--gateway--forward"><a href="./values.yaml#L1071">observability.collector.gateway.forward</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
endpoint: ""
existingSecret:
    key: ""
    name: ""
token: ""
</pre>
</div>
			</td>
			<td>Forward a copy of all telemetry to an external OTLP/HTTP endpoint in addition to storing it in ClickHouse. Useful for shipping to a vendor or a central Collector. Applied at the gateway, so a forwarded copy reflects the sampling decision. </td>
		</tr>
		<tr>
			<td id="observability--collector--gateway--forward--endpoint"><a href="./values.yaml#L1074">observability.collector.gateway.forward.endpoint</a></td>
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
			<td>OTLP/HTTP endpoint to forward to (e.g. `https://otlp-gateway.example.com/otlp`). Leave empty to disable forwarding.</td>
		</tr>
		<tr>
			<td id="observability--collector--gateway--forward--existingSecret"><a href="./values.yaml#L1080">observability.collector.gateway.forward.existingSecret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
key: ""
name: ""
</pre>
</div>
			</td>
			<td>Read the forwarding bearer token from an existing Secret instead of `token`. Both `name` and `key` are required when used.</td>
		</tr>
		<tr>
			<td id="observability--collector--gateway--forward--token"><a href="./values.yaml#L1077">observability.collector.gateway.forward.token</a></td>
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
			<td>Bearer token for the forwarding endpoint. Prefer `existingSecret` over putting a credential in values.</td>
		</tr>
		<tr>
			<td id="observability--collector--gateway--tailSamplePercentage"><a href="./values.yaml#L1066">observability.collector.gateway.tailSamplePercentage</a></td>
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
			<td>Percentage (0-100) of traces to keep after the always-keep rules. Traces containing an error, and traces slower than one second, are always kept regardless of this value. Applied at the gateway, which is the only tier that sees a whole trace. </td>
		</tr>
		<tr>
			<td id="observability--enabled"><a href="./values.yaml#L1039">observability.enabled</a></td>
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
			<td>Master switch for the whole observability stack. Set to false to deploy no Collector and no ClickHouse, disable the OpenTelemetry SDKs in every Kasm service, and serve a disabled browser-telemetry stub. Reporting features that read telemetry will return empty results. </td>
		</tr>
		<tr>
			<td id="proxyService"><a href="./values.yaml#L73">proxyService</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
labels: {}
type: LoadBalancer
</pre>
</div>
			</td>
			<td>Configure the external-facing service type to use. Allowed service types: ClusterIP, LoadBalancer, or NodePort.   The proxyService.annotations defined here only apply to the `proxy` service (`proxy-service-external.yaml` file). If you wish to apply annotations to all services, use the annotations.service value at the bottom of this chart.  NOTE: If ingress.enabled or route.enabled set to `true` service.type MUST be set to `ClusterIP`. Also, if you wish to deploy a multi-zone Kasm (see [Deployment Zones](https://docs.kasm.com/docs/latest/guide/deployment_zones) documentation for reference), you MUST use either a Route or an Ingress and set the `proxyService.type` to `ClusterIP`. </td>
		</tr>
		<tr>
			<td id="publicAddr"><a href="./values.yaml#L17">publicAddr</a></td>
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
			<td id="restartPolicy"><a href="./values.yaml#L1248">restartPolicy</a></td>
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
			<td id="route"><a href="./values.yaml#L156">route</a></td>
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
			<td>Configure an OpenShift Route for your Kasm deployment.  With kasmZones set, one Route is rendered per zone (plus a primary Route for publicAddr). The TLS cert must cover publicAddr and every zone's proxyAddress; route.* settings apply to all Routes. </td>
		</tr>
		<tr>
			<td id="route--backendProtocol"><a href="./values.yaml#L162">route.backendProtocol</a></td>
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
			<td id="route--enabled"><a href="./values.yaml#L158">route.enabled</a></td>
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
			<td id="route--tls"><a href="./values.yaml#L170">route.tls</a></td>
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
			<td id="route--wildcardPolicy"><a href="./values.yaml#L166">route.wildcardPolicy</a></td>
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
			<td id="trustedCaBundle--caCerts"><a href="./values.yaml#L236">trustedCaBundle.caCerts</a></td>
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
			<td id="trustedCaBundle--configMapName"><a href="./values.yaml#L231">trustedCaBundle.configMapName</a></td>
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
			<td id="trustedCaBundle--enabled"><a href="./values.yaml#L226">trustedCaBundle.enabled</a></td>
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
			<td id="useImageTags"><a href="./values.yaml#L300">useImageTags</a></td>
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

