# Kasm on Kubernetes

![Version: 1.1190.4](https://img.shields.io/badge/Version-1.1190.4-informational?style=flat-square) ![AppVersion: 1.19.0](https://img.shields.io/badge/AppVersion-1.19.0-informational?style=flat-square)

Kasm is a platform specializing in providing secure browser-based workspaces for a wide range of applications and industries. Its main goal is to provide isolated and secure environments that can be accessed via web browsers, ensuring that users can perform tasks without risking the security of their local systems.

**Homepage:** <https://kasm.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

<!-- This README.md.gotmpl is used by helm-docs to generate README.md which in turn generates the information on https://artifacthub.io/packages/helm/nautobot/nautobot so there are parts of this which are duplicated from `docs` -->
## Documentation

Please see our [official documentation site](https://docs.kasm.com) for more information.

> **Note:** Make sure to select the correct Kasm Workspaces version in the top-right version selector on the documentation site to ensure the guides match your deployment.

<!-- This section is a duplicate of docs/installation/prerequisites.md -->
## Prerequisites

* Kubernetes 1.24 or newer (older versions of Kubernetes may work, however, we try to keep this chart updated to [supported versions of Kubernetes](https://kubernetes.io/releases/))
* Helm 3.18.x or newer ([installation](https://helm.sh/docs/helm/helm_install/))

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
			<td id="affinity"><a href="./values.yaml#L974">affinity</a></td>
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
			<td id="annotations"><a href="./values.yaml#L994">annotations</a></td>
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
			<td id="applyHealthChecks"><a href="./values.yaml#L982">applyHealthChecks</a></td>
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
			<td id="applySecurity"><a href="./values.yaml#L978">applySecurity</a></td>
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
			<td id="certificate--certManager"><a href="./values.yaml#L173">certificate.certManager</a></td>
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
			<td id="certificate--secretName"><a href="./values.yaml#L162">certificate.secretName</a></td>
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
			<td id="clusterDomain"><a href="./values.yaml#L961">clusterDomain</a></td>
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
			<td id="components--api--annotations"><a href="./values.yaml#L515">components.api.annotations</a></td>
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
			<td id="components--api--extraContainers"><a href="./values.yaml#L543">components.api.extraContainers</a></td>
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
			<td id="components--api--extraInitContainers"><a href="./values.yaml#L549">components.api.extraInitContainers</a></td>
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
			<td id="components--api--extraVolumeMounts"><a href="./values.yaml#L537">components.api.extraVolumeMounts</a></td>
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
			<td id="components--api--extraVolumes"><a href="./values.yaml#L528">components.api.extraVolumes</a></td>
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
			<td id="components--api--healthCheckTiming"><a href="./values.yaml#L511">components.api.healthCheckTiming</a></td>
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
			<td id="components--api--image"><a href="./values.yaml#L491">components.api.image</a></td>
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
			<td id="components--api--image--tag"><a href="./values.yaml#L495">components.api.image.tag</a></td>
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
			<td id="components--api--labels"><a href="./values.yaml#L519">components.api.labels</a></td>
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
			<td id="components--api--replicas"><a href="./values.yaml#L497">components.api.replicas</a></td>
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
			<td id="components--api--resources"><a href="./values.yaml#L517">components.api.resources</a></td>
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
			<td id="components--api--threadPool"><a href="./values.yaml#L552">components.api.threadPool</a></td>
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
			<td id="components--api--threadPoolLogInterval"><a href="./values.yaml#L555">components.api.threadPoolLogInterval</a></td>
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
			<td id="components--guac--annotations"><a href="./values.yaml#L667">components.guac.annotations</a></td>
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
			<td>Custom annotations to add to the Kasm Guac Deployment</td>
		</tr>
		<tr>
			<td id="components--guac--enabled"><a href="./values.yaml#L644">components.guac.enabled</a></td>
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
			<td>Use this setting to enable/disable deployment of the Kasm Guacamole web RDP service -  [Kasm Guac Service](https://docs.kasm.com/docs/latest/guide/connection_proxies#guacamole-guac). </td>
		</tr>
		<tr>
			<td id="components--guac--extraContainers"><a href="./values.yaml#L715">components.guac.extraContainers</a></td>
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
			<td id="components--guac--extraInitContainers"><a href="./values.yaml#L721">components.guac.extraInitContainers</a></td>
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
			<td id="components--guac--extraVolumeMounts"><a href="./values.yaml#L709">components.guac.extraVolumeMounts</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes Kasm Guac container Example:    extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="components--guac--extraVolumes"><a href="./values.yaml#L700">components.guac.extraVolumes</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm Guac container Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="components--guac--guacClusterSize"><a href="./values.yaml#L647">components.guac.guacClusterSize</a></td>
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
			<td id="components--guac--healthCheckTiming"><a href="./values.yaml#L663">components.guac.healthCheckTiming</a></td>
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
			<td id="components--guac--image"><a href="./values.yaml#L636">components.guac.image</a></td>
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
			<td id="components--guac--image--tag"><a href="./values.yaml#L640">components.guac.image.tag</a></td>
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
			<td id="components--guac--labels"><a href="./values.yaml#L691">components.guac.labels</a></td>
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
			<td>Custom labels to add to the Kasm Guac Deployment</td>
		</tr>
		<tr>
			<td id="components--guac--nginxSidecar"><a href="./values.yaml#L671">components.guac.nginxSidecar</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
healthCheckTiming:
    livenessProbe: {}
    readinessProbe: {}
resources: {}
</pre>
</div>
			</td>
			<td>Configuration for the nginx sidecar container.</td>
		</tr>
		<tr>
			<td id="components--guac--nginxSidecar--healthCheckTiming"><a href="./values.yaml#L687">components.guac.nginxSidecar.healthCheckTiming</a></td>
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
			<td id="components--guac--nginxSidecar--resources"><a href="./values.yaml#L673">components.guac.nginxSidecar.resources</a></td>
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
			<td>Manually configure resources for the nginx sidecar container. Leave empty to use the chart default.</td>
		</tr>
		<tr>
			<td id="components--guac--recordingData"><a href="./values.yaml#L724">components.guac.recordingData</a></td>
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
			<td id="components--guac--recordingData--pvcSize"><a href="./values.yaml#L726">components.guac.recordingData.pvcSize</a></td>
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
			<td id="components--guac--recordingData--storageClassName"><a href="./values.yaml#L728">components.guac.recordingData.storageClassName</a></td>
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
			<td id="components--guac--replicas"><a href="./values.yaml#L649">components.guac.replicas</a></td>
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
			<td id="components--guac--resources"><a href="./values.yaml#L669">components.guac.resources</a></td>
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
			<td>Manually configure the Kasm Guac Deployment resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--manager--annotations"><a href="./values.yaml#L587">components.manager.annotations</a></td>
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
			<td id="components--manager--extraContainers"><a href="./values.yaml#L615">components.manager.extraContainers</a></td>
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
			<td id="components--manager--extraInitContainers"><a href="./values.yaml#L621">components.manager.extraInitContainers</a></td>
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
			<td id="components--manager--extraVolumeMounts"><a href="./values.yaml#L609">components.manager.extraVolumeMounts</a></td>
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
			<td id="components--manager--extraVolumes"><a href="./values.yaml#L600">components.manager.extraVolumes</a></td>
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
			<td id="components--manager--healthCheckTiming"><a href="./values.yaml#L583">components.manager.healthCheckTiming</a></td>
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
			<td id="components--manager--image"><a href="./values.yaml#L563">components.manager.image</a></td>
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
			<td id="components--manager--image--tag"><a href="./values.yaml#L567">components.manager.image.tag</a></td>
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
			<td id="components--manager--labels"><a href="./values.yaml#L591">components.manager.labels</a></td>
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
			<td id="components--manager--replicas"><a href="./values.yaml#L569">components.manager.replicas</a></td>
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
			<td id="components--manager--resources"><a href="./values.yaml#L589">components.manager.resources</a></td>
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
			<td id="components--manager--supportBundleTimer"><a href="./values.yaml#L628">components.manager.supportBundleTimer</a></td>
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
			<td id="components--manager--updateTimer"><a href="./values.yaml#L624">components.manager.updateTimer</a></td>
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
			<td id="components--proxy--annotations"><a href="./values.yaml#L449">components.proxy.annotations</a></td>
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
			<td id="components--proxy--extraContainers"><a href="./values.yaml#L477">components.proxy.extraContainers</a></td>
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
			<td id="components--proxy--extraInitContainers"><a href="./values.yaml#L483">components.proxy.extraInitContainers</a></td>
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
			<td id="components--proxy--extraVolumeMounts"><a href="./values.yaml#L471">components.proxy.extraVolumeMounts</a></td>
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
			<td id="components--proxy--extraVolumes"><a href="./values.yaml#L462">components.proxy.extraVolumes</a></td>
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
			<td id="components--proxy--healthCheckTiming"><a href="./values.yaml#L445">components.proxy.healthCheckTiming</a></td>
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
			<td id="components--proxy--image"><a href="./values.yaml#L425">components.proxy.image</a></td>
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
			<td id="components--proxy--image--tag"><a href="./values.yaml#L429">components.proxy.image.tag</a></td>
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
			<td id="components--proxy--labels"><a href="./values.yaml#L453">components.proxy.labels</a></td>
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
			<td id="components--proxy--replicas"><a href="./values.yaml#L431">components.proxy.replicas</a></td>
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
			<td id="components--proxy--resources"><a href="./values.yaml#L451">components.proxy.resources</a></td>
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
			<td id="components--rdpGateway--annotations"><a href="./values.yaml#L767">components.rdpGateway.annotations</a></td>
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
			<td>Custom annotations to add to the Kasm RDP Gateway Deployment</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--enabled"><a href="./values.yaml#L744">components.rdpGateway.enabled</a></td>
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
			<td>Use this setting to enable/disable deployment of the Kasm RDP Gateway service -  [Kasm RDP Gateway](https://docs.kasm.com/docs/latest/guide/connection_proxies#rdp-gateway). </td>
		</tr>
		<tr>
			<td id="components--rdpGateway--extraContainers"><a href="./values.yaml#L815">components.rdpGateway.extraContainers</a></td>
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
			<td id="components--rdpGateway--extraInitContainers"><a href="./values.yaml#L821">components.rdpGateway.extraInitContainers</a></td>
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
			<td id="components--rdpGateway--extraVolumeMounts"><a href="./values.yaml#L809">components.rdpGateway.extraVolumeMounts</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes Kasm RDP Gateway container Example:    extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--extraVolumes"><a href="./values.yaml#L800">components.rdpGateway.extraVolumes</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm RDP Gateway container Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--healthCheckTiming"><a href="./values.yaml#L763">components.rdpGateway.healthCheckTiming</a></td>
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
			<td id="components--rdpGateway--image"><a href="./values.yaml#L736">components.rdpGateway.image</a></td>
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
			<td id="components--rdpGateway--image--tag"><a href="./values.yaml#L740">components.rdpGateway.image.tag</a></td>
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
			<td id="components--rdpGateway--iniConfigMapName"><a href="./values.yaml#L826">components.rdpGateway.iniConfigMapName</a></td>
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
			<td id="components--rdpGateway--labels"><a href="./values.yaml#L791">components.rdpGateway.labels</a></td>
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
			<td>Custom labels to add to the Kasm RDP Gateway Deployment</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--nginxSidecar"><a href="./values.yaml#L771">components.rdpGateway.nginxSidecar</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
healthCheckTiming:
    livenessProbe: {}
    readinessProbe: {}
resources: {}
</pre>
</div>
			</td>
			<td>Configuration for the nginx sidecar container.</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--nginxSidecar--healthCheckTiming"><a href="./values.yaml#L787">components.rdpGateway.nginxSidecar.healthCheckTiming</a></td>
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
			<td id="components--rdpGateway--nginxSidecar--resources"><a href="./values.yaml#L773">components.rdpGateway.nginxSidecar.resources</a></td>
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
			<td>Manually configure resources for the nginx sidecar container. Leave empty to use the chart default.</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--replicas"><a href="./values.yaml#L749">components.rdpGateway.replicas</a></td>
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
			<td>Override the replica count set by deploymentSize. Set to 0 to use the deploymentSize preset (default).  NOTE: must be 0 (preset) or 1. Multi-replica rdp-gateway is not supported in this release.</td>
		</tr>
		<tr>
			<td id="components--rdpGateway--resources"><a href="./values.yaml#L769">components.rdpGateway.resources</a></td>
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
			<td>Manually configure the Kasm RDP Gateway Deployment resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--annotations"><a href="./values.yaml#L863">components.rdpHttpsGateway.annotations</a></td>
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
			<td>Custom annotations to add to the Kasm RDP HTTPS Gateway Deployment</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--enabled"><a href="./values.yaml#L843">components.rdpHttpsGateway.enabled</a></td>
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
			<td>Use this setting to enable/disable deployment of the Kasm RDP HTTPS Gateway service. This service allows users to use native RDP clients via HTTPS connections rather than exposing 3389 -  [Kasm RDP HTTPS Gateway](https://docs.kasm.com/docs/latest/guide/connection_proxies#rdp-https-gateway). </td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--extraContainers"><a href="./values.yaml#L911">components.rdpHttpsGateway.extraContainers</a></td>
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
			<td id="components--rdpHttpsGateway--extraInitContainers"><a href="./values.yaml#L917">components.rdpHttpsGateway.extraInitContainers</a></td>
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
			<td id="components--rdpHttpsGateway--extraVolumeMounts"><a href="./values.yaml#L905">components.rdpHttpsGateway.extraVolumeMounts</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes Kasm RDP HTTPS Gateway container Example:    extraVolumeMounts:     - mountPath: /etc/ssl/certs/ca-certificates.crt       name: pkichain       readOnly: true       subPath: ca.crt</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--extraVolumes"><a href="./values.yaml#L896">components.rdpHttpsGateway.extraVolumes</a></td>
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
			<td>A list of objects for additional secrets, configmaps, or volume mounts. Useful for adding things  like custom SSL certificates, config files, or data volumes to the Kasm RDP HTTPS Gateway container Example:   extraVolumes:     - secret:         defaultMode: 420         secretName: kasm-custom-tls       name: pkichain</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--healthCheckTiming"><a href="./values.yaml#L859">components.rdpHttpsGateway.healthCheckTiming</a></td>
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
			<td id="components--rdpHttpsGateway--image"><a href="./values.yaml#L834">components.rdpHttpsGateway.image</a></td>
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
			<td id="components--rdpHttpsGateway--image--tag"><a href="./values.yaml#L838">components.rdpHttpsGateway.image.tag</a></td>
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
			<td id="components--rdpHttpsGateway--labels"><a href="./values.yaml#L887">components.rdpHttpsGateway.labels</a></td>
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
			<td>Custom labels to add to the Kasm RDP HTTPS Gateway Deployment</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--nginxSidecar"><a href="./values.yaml#L867">components.rdpHttpsGateway.nginxSidecar</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
healthCheckTiming:
    livenessProbe: {}
    readinessProbe: {}
resources: {}
</pre>
</div>
			</td>
			<td>Configuration for the nginx sidecar container.</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--nginxSidecar--healthCheckTiming"><a href="./values.yaml#L883">components.rdpHttpsGateway.nginxSidecar.healthCheckTiming</a></td>
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
			<td id="components--rdpHttpsGateway--nginxSidecar--resources"><a href="./values.yaml#L869">components.rdpHttpsGateway.nginxSidecar.resources</a></td>
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
			<td>Manually configure resources for the nginx sidecar container. Leave empty to use the chart default.</td>
		</tr>
		<tr>
			<td id="components--rdpHttpsGateway--replicas"><a href="./values.yaml#L845">components.rdpHttpsGateway.replicas</a></td>
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
			<td id="components--rdpHttpsGateway--resources"><a href="./values.yaml#L865">components.rdpHttpsGateway.resources</a></td>
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
			<td>Manually configure the Kasm RDP HTTPS Gateway Deployment resources. This overrides the pre-defined `deploymentSize` values.</td>
		</tr>
		<tr>
			<td id="database--annotations"><a href="./values.yaml#L281">database.annotations</a></td>
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
			<td id="database--extraContainers"><a href="./values.yaml#L325">database.extraContainers</a></td>
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
			<td id="database--extraInitContainers"><a href="./values.yaml#L331">database.extraInitContainers</a></td>
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
			<td id="database--extraVolumeMounts"><a href="./values.yaml#L319">database.extraVolumeMounts</a></td>
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
			<td id="database--extraVolumes"><a href="./values.yaml#L310">database.extraVolumes</a></td>
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
			<td id="database--healthCheckTiming"><a href="./values.yaml#L297">database.healthCheckTiming</a></td>
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
			<td id="database--hostname"><a href="./values.yaml#L224">database.hostname</a></td>
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
			<td id="database--image"><a href="./values.yaml#L259">database.image</a></td>
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
			<td id="database--image--tag"><a href="./values.yaml#L263">database.image.tag</a></td>
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
			<td id="database--kasmDbName"><a href="./values.yaml#L230">database.kasmDbName</a></td>
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
			<td id="database--kasmDbSecret"><a href="./values.yaml#L240">database.kasmDbSecret</a></td>
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
			<td id="database--kasmDbUser"><a href="./values.yaml#L233">database.kasmDbUser</a></td>
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
			<td id="database--labels"><a href="./values.yaml#L301">database.labels</a></td>
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
			<td id="database--port"><a href="./values.yaml#L227">database.port</a></td>
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
			<td id="database--postgresMasterUser"><a href="./values.yaml#L249">database.postgresMasterUser</a></td>
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
			<td id="database--resources"><a href="./values.yaml#L283">database.resources</a></td>
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
			<td id="database--standalone"><a href="./values.yaml#L221">database.standalone</a></td>
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
			<td id="database--storage--pvcSize"><a href="./values.yaml#L274">database.storage.pvcSize</a></td>
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
			<td id="database--storage--retentionPolicy"><a href="./values.yaml#L277">database.storage.retentionPolicy</a></td>
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
			<td id="database--storage--storageClassName"><a href="./values.yaml#L270">database.storage.storageClassName</a></td>
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
			<td id="dbManagement--backupCron--enabled"><a href="./values.yaml#L395">dbManagement.backupCron.enabled</a></td>
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
			<td id="dbManagement--backupCron--pvcName"><a href="./values.yaml#L398">dbManagement.backupCron.pvcName</a></td>
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
			<td id="dbManagement--backupCron--pvcSize"><a href="./values.yaml#L414">dbManagement.backupCron.pvcSize</a></td>
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
			<td id="dbManagement--backupCron--schedule"><a href="./values.yaml#L403">dbManagement.backupCron.schedule</a></td>
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
			<td id="dbManagement--backupCron--storageClass"><a href="./values.yaml#L410">dbManagement.backupCron.storageClass</a></td>
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
			<td id="dbManagement--backupCron--timeZone"><a href="./values.yaml#L406">dbManagement.backupCron.timeZone</a></td>
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
			<td id="dbManagement--dbConnectionTimeout"><a href="./values.yaml#L343">dbManagement.dbConnectionTimeout</a></td>
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
			<td id="dbManagement--initJobTTLSecondsAfterFinished"><a href="./values.yaml#L341">dbManagement.initJobTTLSecondsAfterFinished</a></td>
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
			<td id="dbManagement--initialize"><a href="./values.yaml#L338">dbManagement.initialize</a></td>
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
			<td id="dbManagement--upgrade--backupStorageClass"><a href="./values.yaml#L379">dbManagement.upgrade.backupStorageClass</a></td>
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
			<td id="dbManagement--upgrade--enable"><a href="./values.yaml#L352">dbManagement.upgrade.enable</a></td>
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
			<td id="dbManagement--upgrade--oldDbBackupFileName"><a href="./values.yaml#L388">dbManagement.upgrade.oldDbBackupFileName</a></td>
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
			<td id="dbManagement--upgrade--oldDbHostname"><a href="./values.yaml#L357">dbManagement.upgrade.oldDbHostname</a></td>
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
			<td id="dbManagement--upgrade--oldDbSecretsName"><a href="./values.yaml#L385">dbManagement.upgrade.oldDbSecretsName</a></td>
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
			<td id="dbManagement--upgrade--skipBackupAndRestore"><a href="./values.yaml#L376">dbManagement.upgrade.skipBackupAndRestore</a></td>
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
			<td id="directRdpService"><a href="./values.yaml#L67">directRdpService</a></td>
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
rdpAccessURL: ""
type: LoadBalancer
</pre>
</div>
			</td>
			<td>Configure the directRdpService settings and service type to use for the Kasm RDP Gateway service. This is only applicable if you have enabled the Kasm RDP Gateway component in `components.rdpGateway.enabled`. </td>
		</tr>
		<tr>
			<td id="directRdpService--annotations"><a href="./values.yaml#L91">directRdpService.annotations</a></td>
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
			<td>Custom annotations to add to the RDP Gateway Service. This only applies if `directRdpService.enabled` is set to true. If you use the annotations below to deploy a load balancer in your cloud provider, you must ensure the load balancer type supports RDP. This typically requires using a Network Load Balancer type that supports TCP load balancing, and not a HTTP/HTTPS load balancer type. </td>
		</tr>
		<tr>
			<td id="directRdpService--enabled"><a href="./values.yaml#L71">directRdpService.enabled</a></td>
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
			<td>Enable the exposure of the RDP Gateway service via a separate Service of the type defined in `directRdpService.type`. This is only applicable if you have enabled the Kasm RDP Gateway component in `components.rdpGateway.enabled`. </td>
		</tr>
		<tr>
			<td id="directRdpService--loadBalancerPort"><a href="./values.yaml#L85">directRdpService.loadBalancerPort</a></td>
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
			<td>The external port exposed by the directRdpService Service when `directRdpService.type` is LoadBalancer. Defaults to 3389. Has no effect when `directRdpService.type` is NodePort. </td>
		</tr>
		<tr>
			<td id="directRdpService--rdpAccessURL"><a href="./values.yaml#L76">directRdpService.rdpAccessURL</a></td>
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
			<td>If you are exposing the RDP Gateway service via a separate Service, set the access URL to be used for the RDP Gateway. This is the URL you will use to access the RDP Gateway service and must be resolvable by your users' systems. </td>
		</tr>
		<tr>
			<td id="directRdpService--type"><a href="./values.yaml#L81">directRdpService.type</a></td>
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
			<td>The service type to use for the RDP Gateway service if `directRdpService.enabled` is set to true. Allowed values are LoadBalancer or NodePort. The RDP Gateway speaks raw TCP, so any cloud load balancer backing this Service must be a Layer 4 / TCP type (e.g. NLB on AWS, not ALB). </td>
		</tr>
		<tr>
			<td id="extraAnnotations--configMap"><a href="./values.yaml#L1002">extraAnnotations.configMap</a></td>
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
			<td id="extraAnnotations--cronJob"><a href="./values.yaml#L1004">extraAnnotations.cronJob</a></td>
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
			<td id="extraAnnotations--cronPod"><a href="./values.yaml#L1006">extraAnnotations.cronPod</a></td>
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
			<td id="extraAnnotations--deployment"><a href="./values.yaml#L1008">extraAnnotations.deployment</a></td>
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
			<td id="extraAnnotations--job"><a href="./values.yaml#L1010">extraAnnotations.job</a></td>
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
			<td id="extraAnnotations--pod"><a href="./values.yaml#L1012">extraAnnotations.pod</a></td>
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
			<td id="extraAnnotations--pvc"><a href="./values.yaml#L1014">extraAnnotations.pvc</a></td>
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
			<td id="extraAnnotations--secret"><a href="./values.yaml#L1018">extraAnnotations.secret</a></td>
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
			<td id="extraAnnotations--service"><a href="./values.yaml#L1016">extraAnnotations.service</a></td>
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
			<td id="extraAnnotations--statefulSet"><a href="./values.yaml#L1020">extraAnnotations.statefulSet</a></td>
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
			<td id="extraContainerVolumeMounts"><a href="./values.yaml#L1066">extraContainerVolumeMounts</a></td>
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
			<td id="extraContainers"><a href="./values.yaml#L1083">extraContainers</a></td>
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
			<td id="extraInitContainers"><a href="./values.yaml#L1090">extraInitContainers</a></td>
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
			<td id="extraInitVolumeMounts"><a href="./values.yaml#L1076">extraInitVolumeMounts</a></td>
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
			<td id="extraLabels--configMap"><a href="./values.yaml#L1028">extraLabels.configMap</a></td>
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
			<td id="extraLabels--cronJob"><a href="./values.yaml#L1040">extraLabels.cronJob</a></td>
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
			<td id="extraLabels--cronPod"><a href="./values.yaml#L1042">extraLabels.cronPod</a></td>
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
			<td id="extraLabels--deployment"><a href="./values.yaml#L1030">extraLabels.deployment</a></td>
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
			<td id="extraLabels--job"><a href="./values.yaml#L1038">extraLabels.job</a></td>
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
			<td id="extraLabels--pod"><a href="./values.yaml#L1032">extraLabels.pod</a></td>
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
			<td id="extraLabels--pvc"><a href="./values.yaml#L1044">extraLabels.pvc</a></td>
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
			<td id="extraLabels--secret"><a href="./values.yaml#L1034">extraLabels.secret</a></td>
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
			<td id="extraLabels--service"><a href="./values.yaml#L1036">extraLabels.service</a></td>
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
			<td id="extraLabels--statefulSet"><a href="./values.yaml#L1046">extraLabels.statefulSet</a></td>
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
			<td id="extraObjects"><a href="./values.yaml#L1095">extraObjects</a></td>
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
			<td id="extraVolumes"><a href="./values.yaml#L1056">extraVolumes</a></td>
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
			<td id="imagePullPolicy"><a href="./values.yaml#L934">imagePullPolicy</a></td>
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
			<td id="imagePullSecrets--annotations"><a href="./values.yaml#L957">imagePullSecrets.annotations</a></td>
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
			<td id="imagePullSecrets--email"><a href="./values.yaml#L953">imagePullSecrets.email</a></td>
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
			<td id="imagePullSecrets--enabled"><a href="./values.yaml#L940">imagePullSecrets.enabled</a></td>
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
			<td id="imagePullSecrets--labels"><a href="./values.yaml#L955">imagePullSecrets.labels</a></td>
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
			<td id="imagePullSecrets--name"><a href="./values.yaml#L945">imagePullSecrets.name</a></td>
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
			<td id="imagePullSecrets--password"><a href="./values.yaml#L951">imagePullSecrets.password</a></td>
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
			<td id="imagePullSecrets--registry"><a href="./values.yaml#L947">imagePullSecrets.registry</a></td>
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
			<td id="imagePullSecrets--username"><a href="./values.yaml#L949">imagePullSecrets.username</a></td>
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
			<td id="ingress--annotations"><a href="./values.yaml#L110">ingress.annotations</a></td>
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
			<td id="ingress--backendProtocol"><a href="./values.yaml#L106">ingress.backendProtocol</a></td>
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
			<td id="ingress--enabled"><a href="./values.yaml#L99">ingress.enabled</a></td>
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
			<td id="ingress--ingressClassName"><a href="./values.yaml#L109">ingress.ingressClassName</a></td>
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
			<td id="ingress--labels"><a href="./values.yaml#L111">ingress.labels</a></td>
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
			<td id="ingress--tls"><a href="./values.yaml#L102">ingress.tls</a></td>
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
			<td id="kasmConfig"><a href="./values.yaml#L1103">kasmConfig</a></td>
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
			<td id="kasmConfig--adminUsername"><a href="./values.yaml#L1125">kasmConfig.adminUsername</a></td>
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
			<td id="kasmConfig--config"><a href="./values.yaml#L1142">kasmConfig.config</a></td>
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
			<td id="kasmConfig--defaultApiUsers"><a href="./values.yaml#L1117">kasmConfig.defaultApiUsers</a></td>
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
			<td id="kasmConfig--defaultUsers"><a href="./values.yaml#L1112">kasmConfig.defaultUsers</a></td>
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
			<td id="kasmConfig--existingDefaultPropertiesSecret"><a href="./values.yaml#L1135">kasmConfig.existingDefaultPropertiesSecret</a></td>
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
			<td id="kasmConfig--generatePreseed"><a href="./values.yaml#L1107">kasmConfig.generatePreseed</a></td>
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
			<td id="labels"><a href="./values.yaml#L990">labels</a></td>
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
			<td id="logFormat"><a href="./values.yaml#L212">logFormat</a></td>
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
			<td id="nodeSelector"><a href="./values.yaml#L966">nodeSelector</a></td>
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
			<td id="proxyService"><a href="./values.yaml#L59">proxyService</a></td>
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
			<td>Configure the external-facing service type to use.  Allowed service types: ClusterIP, LoadBalancer, or NodePort.   The proxyService.annotations defined here only apply to the `proxy` service (`proxy-service-external.yaml` file). If you wish to apply annotations to all services, use the annotations.service value at the bottom of this chart.  NOTE: If ingress.enabled or route.enabled set to `true` service.type MUST be set to `ClusterIP`. Also, if you wish to deploy a multi-zone Kasm (see [Deployment Zones](https://docs.kasm.com/docs/latest/guide/deployment_zones) documentation for reference), you MUST use either a Route or an Ingress and set the `proxyService.type` to `ClusterIP`. </td>
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
			<td id="restartPolicy"><a href="./values.yaml#L986">restartPolicy</a></td>
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
			<td id="route"><a href="./values.yaml#L119">route</a></td>
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
			<td id="route--backendProtocol"><a href="./values.yaml#L125">route.backendProtocol</a></td>
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
			<td id="route--enabled"><a href="./values.yaml#L121">route.enabled</a></td>
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
			<td id="route--tls"><a href="./values.yaml#L133">route.tls</a></td>
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
			<td id="route--wildcardPolicy"><a href="./values.yaml#L129">route.wildcardPolicy</a></td>
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
			<td id="trustedCaBundle--caCerts"><a href="./values.yaml#L199">trustedCaBundle.caCerts</a></td>
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
			<td id="trustedCaBundle--configMapName"><a href="./values.yaml#L194">trustedCaBundle.configMapName</a></td>
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
			<td id="trustedCaBundle--enabled"><a href="./values.yaml#L189">trustedCaBundle.enabled</a></td>
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
			<td id="useImageTags"><a href="./values.yaml#L930">useImageTags</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1.19.0-rolling
</pre>
</div>
			</td>
			<td>Chart-wide image tag used when a component's `image.tag` is empty. Per-component tag wins if set. To override the tag for a single component, see `components.<x>.image.tag` (or `database.image.tag`). Examples:   "1.19.0-rolling"             rolling tag, receives ongoing bug-fix updates within 1.19.x   "1.19.0"                     frozen point-in-time tag   "1.19.0-rolling-2026-06-02"  date-locked rolling tag, pins a specific rolling build </td>
		</tr>
	</tbody>
</table>

