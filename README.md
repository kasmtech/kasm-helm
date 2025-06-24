# kasm-single-zone

![Version: 1.17.0](https://img.shields.io/badge/Version-1.17.0-informational?style=flat-square) ![AppVersion: 1.17.0](https://img.shields.io/badge/AppVersion-1.17.0-informational?style=flat-square)

Kasm is a platform specializing in providing secure browser-based workspaces for a wide range of applications and industries. Its main goal is to provide isolated and secure environments that can be accessed via web browsers, ensuring that users can perform tasks without risking the security of their local systems.

**Homepage:** <https://kasmweb.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## Installing the Chart

To install the chart with the release name `my-release`:

```console
$ helm repo add foo-bar http://charts.foo-bar.com
$ helm install my-release foo-bar/kasm-single-zone
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
			<td id="annotations--certSecret"><a href="./values.yaml#L182">annotations.certSecret</a></td>
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
			<td id="annotations--configMap"><a href="./values.yaml#L184">annotations.configMap</a></td>
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
			<td id="annotations--deployment"><a href="./values.yaml#L186">annotations.deployment</a></td>
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
			<td id="annotations--ingress"><a href="./values.yaml#L194">annotations.ingress</a></td>
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
			<td id="annotations--pod"><a href="./values.yaml#L188">annotations.pod</a></td>
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
			<td id="annotations--secret"><a href="./values.yaml#L192">annotations.secret</a></td>
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
			<td id="annotations--service"><a href="./values.yaml#L190">annotations.service</a></td>
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
			<td id="annotations--statefulSet"><a href="./values.yaml#L196">annotations.statefulSet</a></td>
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
			<td id="applyHealthChecks"><a href="./values.yaml#L171">applyHealthChecks</a></td>
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
			<td id="applySecurity"><a href="./values.yaml#L168">applySecurity</a></td>
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
			<td id="certificate"><a href="./values.yaml#L29">certificate</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "certManager": {
    "addWildCard": true,
    "enabled": true,
    "issuerGroup": "",
    "issuerKind": "",
    "issuerName": ""
  },
  "secretName": ""
}
</pre>
</div>
			</td>
			<td>Configure certificate settings. You can create your own certificate and upload it to the `secretName` supplied below, or if you have an existing cert-manager configured and you wish to use that, set the `secretName` and configure the associated cert-manager settings. </td>
		</tr>
		<tr>
			<td id="certificate--certManager"><a href="./values.yaml#L38">certificate.certManager</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "addWildCard": true,
  "enabled": true,
  "issuerGroup": "",
  "issuerKind": "",
  "issuerName": ""
}
</pre>
</div>
			</td>
			<td>For additional cert-manager configuration/deployment information refer to the online documentation https://cert-manager.io/v1.1-docs/installation/kubernetes/  NOTE: If you do not enable `cert-manager`, you must generate your own certificates and add them to Kubernetes</td>
		</tr>
		<tr>
			<td id="certificate--certManager--addWildCard"><a href="./values.yaml#L42">certificate.certManager.addWildCard</a></td>
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
			<td id="certificate--certManager--issuerGroup"><a href="./values.yaml#L51">certificate.certManager.issuerGroup</a></td>
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
			<td id="certificate--certManager--issuerKind"><a href="./values.yaml#L48">certificate.certManager.issuerKind</a></td>
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
			<td id="certificate--certManager--issuerName"><a href="./values.yaml#L45">certificate.certManager.issuerName</a></td>
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
			<td>Name of the Issuer/ClusterIssuer to use for certs NOTE: You will always need to create this yourself when `certManager.enabled` is true.</td>
		</tr>
		<tr>
			<td id="certificate--secretName"><a href="./values.yaml#L32">certificate.secretName</a></td>
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
			<td>Set the secret name where the certificate is stored This secret name will store a certificate created by `cert-manager` if you set `cert-manager.enabled` to true</td>
		</tr>
		<tr>
			<td id="clusterDomain"><a href="./values.yaml#L161">clusterDomain</a></td>
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
			<td id="components--api"><a href="./values.yaml#L87">components.api</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "image": {
    "repository": "kasmweb/api",
    "tag": "1.17.0"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm API service</td>
		</tr>
		<tr>
			<td id="components--guac"><a href="./values.yaml#L103">components.guac</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "enabled": true,
  "image": {
    "repository": "kasmweb/kasm-guac",
    "tag": "1.17.0"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm Guac RDP service</td>
		</tr>
		<tr>
			<td id="components--manager"><a href="./values.yaml#L95">components.manager</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "image": {
    "repository": "kasmweb/manager",
    "tag": "1.17.0"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm Manager service</td>
		</tr>
		<tr>
			<td id="components--proxy"><a href="./values.yaml#L79">components.proxy</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "image": {
    "repository": "kasmweb/proxy",
    "tag": "1.17.0"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm Nginx Proxy service</td>
		</tr>
		<tr>
			<td id="components--rdpGateway"><a href="./values.yaml#L112">components.rdpGateway</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "enabled": true,
  "image": {
    "repository": "kasmweb/rdp-gateway",
    "tag": "1.17.0"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm RDP Gateway service</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway"><a href="./values.yaml#L121">components.rdpHttpsGateway</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "enabled": true,
  "image": {
    "repository": "kasmweb/rdp-https-gateway",
    "tag": "1.17.0"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm RDP HTTPS Gateway service</td>
		</tr>
		<tr>
			<td id="components--redis"><a href="./values.yaml#L139">components.redis</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "image": {
    "repository": "redis",
    "tag": "5-alpine"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm Share Redis backend service</td>
		</tr>
		<tr>
			<td id="components--share"><a href="./values.yaml#L130">components.share</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "enabled": true,
  "image": {
    "repository": "kasmweb/share",
    "tag": "1.17.0"
  },
  "labels": {},
  "resources": {}
}
</pre>
</div>
			</td>
			<td>Configuration settings for the Kasm Share service</td>
		</tr>
		<tr>
			<td id="database"><a href="./values.yaml#L55">database</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
{
  "annotations": {},
  "image": {
    "repository": "kasmweb/postgres",
    "tag": "1.17.0"
  },
  "initialize_db": true,
  "labels": {},
  "resources": {},
  "storage": {
    "retentionPolicy": {
      "whenDeleted": "Delete",
      "whenScaled": "Retain"
    },
    "storageClassName": ""
  }
}
</pre>
</div>
			</td>
			<td>Kasm DB settings and configuration options </td>
		</tr>
		<tr>
			<td id="database--initialize_db"><a href="./values.yaml#L59">database.initialize_db</a></td>
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
			<td id="database--storage--retentionPolicy"><a href="./values.yaml#L68">database.storage.retentionPolicy</a></td>
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
			<td id="database--storage--storageClassName"><a href="./values.yaml#L66">database.storage.storageClassName</a></td>
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
			<td id="extraLabels--certSecret"><a href="./values.yaml#L203">extraLabels.certSecret</a></td>
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
			<td id="extraLabels--configMap"><a href="./values.yaml#L205">extraLabels.configMap</a></td>
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
			<td id="extraLabels--deployment"><a href="./values.yaml#L207">extraLabels.deployment</a></td>
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
			<td id="extraLabels--ingress"><a href="./values.yaml#L215">extraLabels.ingress</a></td>
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
			<td id="extraLabels--job"><a href="./values.yaml#L217">extraLabels.job</a></td>
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
			<td id="extraLabels--jobPod"><a href="./values.yaml#L219">extraLabels.jobPod</a></td>
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
			<td id="extraLabels--pod"><a href="./values.yaml#L209">extraLabels.pod</a></td>
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
			<td id="extraLabels--secret"><a href="./values.yaml#L211">extraLabels.secret</a></td>
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
			<td id="extraLabels--service"><a href="./values.yaml#L213">extraLabels.service</a></td>
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
			<td id="extraLabels--statefulSet"><a href="./values.yaml#L221">extraLabels.statefulSet</a></td>
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
			<td id="imageCredentials"><a href="./values.yaml#L158">imageCredentials</a></td>
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
			<td id="imagePullPolicy"><a href="./values.yaml#L152">imagePullPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"IfNotExists"
</pre>
</div>
			</td>
			<td>Configure global image pull policy</td>
		</tr>
		<tr>
			<td id="imagePullSecrets"><a href="./values.yaml#L155">imagePullSecrets</a></td>
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
			<td id="ingress--annotations"><a href="./values.yaml#L16">ingress.annotations</a></td>
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
			<td id="ingress--enabled"><a href="./values.yaml#L14">ingress.enabled</a></td>
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
			<td id="ingress--ingressClassName"><a href="./values.yaml#L15">ingress.ingressClassName</a></td>
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
			<td></td>
		</tr>
		<tr>
			<td id="ingress--labels"><a href="./values.yaml#L17">ingress.labels</a></td>
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
			<td id="labels"><a href="./values.yaml#L177">labels</a></td>
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
			<td id="nodeSelector"><a href="./values.yaml#L165">nodeSelector</a></td>
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
			<td id="restartPolicy"><a href="./values.yaml#L174">restartPolicy</a></td>
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
			<td id="service--annotations"><a href="./values.yaml#L22">service.annotations</a></td>
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
			<td id="service--type"><a href="./values.yaml#L21">service.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 300px;">
<pre lang="json">
"ClusterIP"
</pre>
</div>
			</td>
			<td></td>
		</tr>
	</tbody>
</table>

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)