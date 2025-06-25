# Kasm on Kubernetes

# kasm-single-zone

![Version: 1.17.0](https://img.shields.io/badge/Version-1.17.0-informational?style=flat-square) ![AppVersion: 1.17.0](https://img.shields.io/badge/AppVersion-1.17.0-informational?style=flat-square)

Kasm is a platform specializing in providing secure browser-based workspaces for a wide range of applications and industries. Its main goal is to provide isolated and secure environments that can be accessed via web browsers, ensuring that users can perform tasks without risking the security of their local systems.

**Homepage:** <https://kasmweb.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

**Non-Release branches are not intended for production**

Kasm has been modified to run inside Kubernetes. The service containers will automatically detect they are running in Kubernetes and they will talk directly to each other rather than assume they are talking through an NGINX server as is the case for a normal Kasm deployment. Additionally, components need to talk to the name of the service defined, not to individual containers. A Kubernetes service has a resolvable DNS name that all containers should be able to talk with. API containers will not talk to an individual rdp gateway or guac container, but rather be load balanced to all existing respective containers. The reverse is also true. The API servers have been modified to only return a single entry when guac or rdp gateways call to get a list of API servers.

## Branches

This project will contain a branch that matches the release version of the corresponding Kasm Workspaces release. For example, Kasm Workspaces 1.16.0 will have a branch `release/1.16.0` within this project. **Non-release branches should not be used for production.** Be sure to checkout the branch on this project that matches the version of Kasm Workspaces you intend to deploy. Use the default `develop` branch to deploy the [developer preview](https://kasmweb.com/docs/latest/developers/builds.html#developer-preview-builds) build of Kasm Workspaces.

## Installing the Chart

To install the chart with the release name `kasm-helm`:

```console
$ helm repo add kasm https://helm.kasmweb.com
$ helm install kasm-helm kasm/kasm-single-zone --namespace kasm-namespace
```

## Values

<table height="400px" >
	<thead>
		<th>Key</th>
		<th>Type</th>
		<th>Default</th>
		<th>Description</th>
	</thead>
	<tbody>
		<tr>
			<td id="annotations--certSecret"><a href="./values.yaml#L219">annotations.certSecret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional certSecret annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="annotations--configMap"><a href="./values.yaml#L221">annotations.configMap</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional configMap annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="annotations--deployment"><a href="./values.yaml#L223">annotations.deployment</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional deployment annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="annotations--ingress"><a href="./values.yaml#L231">annotations.ingress</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional ingress annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="annotations--pod"><a href="./values.yaml#L225">annotations.pod</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional pod annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="annotations--secret"><a href="./values.yaml#L229">annotations.secret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional secret annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="annotations--service"><a href="./values.yaml#L227">annotations.service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional service annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="annotations--statefulSet"><a href="./values.yaml#L233">annotations.statefulSet</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional statefulSet annotations to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="applyHealthChecks"><a href="./values.yaml#L208">applyHealthChecks</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Add Pod/Container healthchecks settings for Kasm resources</td>
		</tr>
		<tr>
			<td id="applySecurity"><a href="./values.yaml#L205">applySecurity</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Apply Pod/Container security settings for Kasm resources</td>
		</tr>
		<tr>
			<td id="certificate--certManager--addWildCard"><a href="./values.yaml#L52">certificate.certManager.addWildCard</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Setting addWildCard to true will automatically add *.<publicAddr> as a hostname served by the Ingress, as well as adding it to the list of domains to generate a certificate for.</td>
		</tr>
		<tr>
			<td id="certificate--certManager--enabled"><a href="./values.yaml#L49">certificate.certManager.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="certificate--certManager--issuerGroup"><a href="./values.yaml#L61">certificate.certManager.issuerGroup</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Provide the group of Issuer that cert-manager should use, defaults to 'cert-manager.io' which is the default Issuer group.</td>
		</tr>
		<tr>
			<td id="certificate--certManager--issuerKind"><a href="./values.yaml#L58">certificate.certManager.issuerKind</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Provide the kind of certificate to use, defaults to `Issuer` for security to scope the certificate to the Kasm namespace.</td>
		</tr>
		<tr>
			<td id="certificate--certManager--issuerName"><a href="./values.yaml#L55">certificate.certManager.issuerName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"some-issuer"
</pre>
</div>
			</td>
			<td>Name of the Issuer/ClusterIssuer to use for certs NOTE: You will always need to create this yourself when `certManager.enabled` is true.</td>
		</tr>
		<tr>
			<td id="certificate--secretName"><a href="./values.yaml#L41">certificate.secretName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Set the secret name where the certificate is stored This secret name will store a certificate created by `cert-manager` if you set `cert-manager.enabled` to true </td>
		</tr>
		<tr>
			<td id="clusterDomain"><a href="./values.yaml#L198">clusterDomain</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"cluster.local"
</pre>
</div>
			</td>
			<td>Cluster-wide Kubernetes DNS domain name</td>
		</tr>
		<tr>
			<td id="components--api--annotations"><a href="./values.yaml#L107">components.api.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--api--image--repository"><a href="./values.yaml#L105">components.api.image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"kasmweb/api"
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--api--image--tag"><a href="./values.yaml#L106">components.api.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"1.17.0"
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--api--labels"><a href="./values.yaml#L109">components.api.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--api--resources"><a href="./values.yaml#L108">components.api.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--guac--annotations"><a href="./values.yaml#L130">components.guac.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--guac--enabled"><a href="./values.yaml#L129">components.guac.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the Kasm Guacamole web RDP service https://kasmweb.com/docs/latest/guide/connection_proxies.html#guacamole-guac</td>
		</tr>
		<tr>
			<td id="components--guac--image"><a href="./values.yaml#L124">components.guac.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "repository": "kasmweb/kasm-guac",
  "tag": "1.17.0"
}
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--guac--labels"><a href="./values.yaml#L132">components.guac.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--guac--resources"><a href="./values.yaml#L131">components.guac.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--manager--annotations"><a href="./values.yaml#L117">components.manager.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--manager--image--repository"><a href="./values.yaml#L115">components.manager.image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"kasmweb/manager"
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--manager--image--tag"><a href="./values.yaml#L116">components.manager.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"1.17.0"
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--manager--labels"><a href="./values.yaml#L119">components.manager.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--manager--resources"><a href="./values.yaml#L118">components.manager.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--proxy--annotations"><a href="./values.yaml#L97">components.proxy.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--proxy--image"><a href="./values.yaml#L94">components.proxy.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "repository": "kasmweb/proxy",
  "tag": "1.17.0"
}
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--proxy--labels"><a href="./values.yaml#L99">components.proxy.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--proxy--resources"><a href="./values.yaml#L98">components.proxy.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--rdpGateway--annotations"><a href="./values.yaml#L143">components.rdpGateway.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--rdpGateway--enabled"><a href="./values.yaml#L142">components.rdpGateway.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the Kasm RDP Gateway service https://kasmweb.com/docs/latest/guide/connection_proxies.html#rdp-gateway</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--image"><a href="./values.yaml#L137">components.rdpGateway.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "repository": "kasmweb/rdp-gateway",
  "tag": "1.17.0"
}
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--labels"><a href="./values.yaml#L145">components.rdpGateway.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--rdpGateway--resources"><a href="./values.yaml#L144">components.rdpGateway.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--annotations"><a href="./values.yaml#L157">components.rdpHttpsGateway.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--enabled"><a href="./values.yaml#L156">components.rdpHttpsGateway.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the Kasm RDP HTTPS Gateway service. This service allows users to use native RDP clients via HTTPS connections rather than exposing 3389. https://kasmweb.com/docs/latest/guide/connection_proxies.html#rdp-https-gateway</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--image"><a href="./values.yaml#L150">components.rdpHttpsGateway.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "repository": "kasmweb/rdp-https-gateway",
  "tag": "1.17.0"
}
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--labels"><a href="./values.yaml#L159">components.rdpHttpsGateway.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--resources"><a href="./values.yaml#L158">components.rdpHttpsGateway.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--redis--annotations"><a href="./values.yaml#L180">components.redis.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--redis--image"><a href="./values.yaml#L177">components.redis.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "repository": "redis",
  "tag": "5-alpine"
}
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--redis--labels"><a href="./values.yaml#L182">components.redis.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--redis--resources"><a href="./values.yaml#L181">components.redis.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--share--annotations"><a href="./values.yaml#L170">components.share.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--share--enabled"><a href="./values.yaml#L169">components.share.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Use this setting to enable/disable deployment of the Kasm Share and associated Redis services https://kasmweb.com/docs/latest/guide/session_sharing.html</td>
		</tr>
		<tr>
			<td id="components--share--image"><a href="./values.yaml#L164">components.share.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "repository": "kasmweb/share",
  "tag": "1.17.0"
}
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="components--share--labels"><a href="./values.yaml#L172">components.share.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="components--share--resources"><a href="./values.yaml#L171">components.share.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="database--annotations"><a href="./values.yaml#L83">database.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="database--image"><a href="./values.yaml#L72">database.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "repository": "kasmweb/postgres",
  "tag": "1.17.0"
}
</pre>
</div>
			</td>
			<td>Configure the image repository where the image is stored. Use this to point to an private hosted container registry instead of our public DockerHub hosted one.</td>
		</tr>
		<tr>
			<td id="database--initialize_db"><a href="./values.yaml#L69">database.initialize_db</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Setting `initialize_db` to true assumes you want a newly initialized Kasm deployment. Setting this to false is useful for deployment testing where you don't want to wait for DB initialization before using Kasm, or if running Kasm upgrades.</td>
		</tr>
		<tr>
			<td id="database--labels"><a href="./values.yaml#L85">database.labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="database--resources"><a href="./values.yaml#L84">database.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td></td>
		</tr>
		<tr>
			<td id="database--storage--retentionPolicy"><a href="./values.yaml#L80">database.storage.retentionPolicy</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "whenDeleted": "Delete",
  "whenScaled": "Retain"
}
</pre>
</div>
			</td>
			<td>Configure how the DB volume should be retained or deleted throughout the DB's lifecycle</td>
		</tr>
		<tr>
			<td id="database--storage--storageClassName"><a href="./values.yaml#L78">database.storage.storageClassName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Set the storage class to attach to the DB for storage. NOTE: Leaving this blank will use the cluster-default storage class</td>
		</tr>
		<tr>
			<td id="deploymentSize"><a href="./values.yaml#L5">deploymentSize</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"small"
</pre>
</div>
			</td>
			<td>Define the estimated size of the Kasm deployment in expected session load.      small  = Up to 10-15 sessions      medium = Up to 25-30 sessions      large  = Up to 50+ sessions</td>
		</tr>
		<tr>
			<td id="extraLabels--certSecret"><a href="./values.yaml#L240">extraLabels.certSecret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional statefulSet labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--configMap"><a href="./values.yaml#L242">extraLabels.configMap</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional configMap labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--deployment"><a href="./values.yaml#L244">extraLabels.deployment</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional deployment labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--ingress"><a href="./values.yaml#L252">extraLabels.ingress</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional ingress labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--job"><a href="./values.yaml#L254">extraLabels.job</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional job labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--jobPod"><a href="./values.yaml#L256">extraLabels.jobPod</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional jobPod labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--pod"><a href="./values.yaml#L246">extraLabels.pod</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional pod labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--secret"><a href="./values.yaml#L248">extraLabels.secret</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional secret labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--service"><a href="./values.yaml#L250">extraLabels.service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional service labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="extraLabels--statefulSet"><a href="./values.yaml#L258">extraLabels.statefulSet</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Additional statefulSet labels to apply to resources created by this chart</td>
		</tr>
		<tr>
			<td id="imagePullCredentials"><a href="./values.yaml#L195">imagePullCredentials</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Create a dockerconfigjson secret as an image pull credential. Useful for offline or self-hosted repos, or dev builds.</td>
		</tr>
		<tr>
			<td id="imagePullPolicy"><a href="./values.yaml#L189">imagePullPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"IfNotPresent"
</pre>
</div>
			</td>
			<td>Configure global image pull policy</td>
		</tr>
		<tr>
			<td id="imagePullSecrets"><a href="./values.yaml#L192">imagePullSecrets</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Use credentials for custom images or image repositories. Useful for offline or self-hosted repos, or dev builds.</td>
		</tr>
		<tr>
			<td id="ingress"><a href="./values.yaml#L14">ingress</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "enabled": true,
  "ingressClassName": "",
  "labels": {}
}
</pre>
</div>
			</td>
			<td>Configure Ingress for your Kasm deployment.  </td>
		</tr>
		<tr>
			<td id="labels"><a href="./values.yaml#L214">labels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to apply to all deployed resources</td>
		</tr>
		<tr>
			<td id="nodeSelector"><a href="./values.yaml#L202">nodeSelector</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>nodeSelector to apply for pod assignment https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector</td>
		</tr>
		<tr>
			<td id="publicAddr"><a href="./values.yaml#L10">publicAddr</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Set the access URL to be used for the Kasm deployment. This is the value that should be used when generating a certificate and that this chart uses when the `certificate.certManager.enabled` is set to true.</td>
		</tr>
		<tr>
			<td id="restartPolicy"><a href="./values.yaml#L211">restartPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"Always"
</pre>
</div>
			</td>
			<td>Configure global Pod restart policy for Kasm resources</td>
		</tr>
		<tr>
			<td id="service"><a href="./values.yaml#L28">service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "type": "ClusterIP"
}
</pre>
</div>
			</td>
			<td>Configure the external-facing service type to use. Allowed service types: ClusterIP or LoadBalancer  The service.annotations defined here only apply to the `proxy` service. If you wish to apply annotations to all services, use the annotations.service value at the bottom of this chart.  NOTE: If ingress.enabled set to `true` service.type value MUST be set to `ClusterIP`. </td>
		</tr>
	</tbody>
</table>

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)