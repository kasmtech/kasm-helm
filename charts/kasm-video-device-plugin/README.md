# Kasm Video Device Plugin

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![AppVersion: latest](https://img.shields.io/badge/AppVersion-latest-informational?style=flat-square)

Kubelet device plugin DaemonSet that advertises the v4l2loopback video devices on each node as the extended resource kasm.com/video, so Kasm Workspaces sessions with webcam support can request kasm.com/video and have kubelet assign them a dedicated /dev/video* device.

**Homepage:** <https://kasm.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## What this chart does

Kubernetes will not schedule a pod onto a node because of a device file; it schedules on resources. This
chart deploys Kasm's own video-device-plugin (built from `apps/kasm-video-device-plugin` in kasm-monorepo) as
a DaemonSet that implements the kubelet Device Plugin API (v1beta1) and turns the node's video devices into a
countable, allocatable extended resource:

1. The plugin scans `/dev` every 10 seconds for entries starting with `devicePrefix` (default `video`, so
   `video0`, `video1`, ...), sorted numerically by suffix so the advertised order stays stable as devices
   come and go.
2. Every matching device up to `maxDevices` (default 128) is advertised as one unit of `resourceName`
   (default **`kasm.com/video`**).
3. When a workspace pod requests `kasm.com/video: 1`, kubelet picks a specific free device, guarantees no
   other pod gets it, and mounts it into the container. The Kasm agent adds that request to the pod when
   `KASM_SVC_WEBCAM=1`. When a container is allocated exactly one device, the plugin also injects
   `allocateEnvVar` (default `KASM_VIDEO_DEVICE`) set to that device's host path, which the exec job reads to
   discover the assigned device.

The devices themselves come from the **v4l2loopback** kernel module, which this chart does not install — the
companion [`kasm-node-prep`](../kasm-node-prep) chart builds and loads it. Install both, or the plugin will
find no devices and advertise a capacity of zero.

Allocation is entirely kubelet's job here. There is no assignment tracking to configure and no way for two
sessions to end up on the same virtual webcam.

## Security posture

Read this before installing. **This chart is privileged by necessity** — a device plugin has to reach the
node's device files and the kubelet socket.

* The DaemonSet container runs with `securityContext.privileged: true`, because it must stat, open, and hand
  out the node's device nodes.
* It mounts two host paths:
  * `/var/lib/kubelet/device-plugins` — the Device Plugin API socket directory. The plugin creates its own
    socket here and registers with kubelet through `kubelet.sock`. Write access to this directory is
    effectively the ability to advertise arbitrary resources to kubelet.
  * `/dev` — the node device tree matched against `devicePrefix`.
* It does **not** use `hostNetwork`, `hostPID`, `hostIPC`, or a host service account, and it mounts no other
  host path. It needs no RBAC, because it talks to kubelet over the socket rather than to the API server.
* The namespace it is installed into must allow privileged pods. With
  [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) that means
  labelling the namespace `pod-security.kubernetes.io/enforce: privileged`. The pods cannot satisfy the
  `baseline` or `restricted` standards and will be rejected outright by an enforcing namespace.

## Node prerequisites

* **The v4l2loopback module must be loaded**, otherwise no `/dev/video*` device exists and the plugin
  advertises `kasm.com/video: 0`. Install [`kasm-node-prep`](../kasm-node-prep) with
  `modules.v4l2loopback.enabled: true` on the same nodes. That chart's own prerequisites (kernel headers
  available, internet or mirror access for the module source, and MOK enrollment on Secure Boot nodes) apply
  transitively — this plugin is useless on a node where the module could not be built.
* **The kubelet device-plugin directory must be at `/var/lib/kubelet/device-plugins`.** Clusters that
  relocate the kubelet root directory need the `device-plugin` hostPath adjusted to match.
* **`priorityClassName: system-node-critical`** is used by default, which requires the pods to run in a
  namespace permitted to use that system priority class (`kube-system`, or any namespace when no
  `ResourceQuota` restricts it). Set `priorityClassName: ""` if your admission policy forbids it.

## Usage

Pin the plugin to the same nodes the module installer prepares, so `kasm.com/video` is never advertised on a
node without loopback devices:

```yaml
nodeSelector:
  kasm.com/workspaces: "true"
tolerations:
  - key: kasm.com/workspaces
    operator: Exists
    effect: NoSchedule
```

Confirm the resource is registered once the pods are up:

```bash
kubectl get nodes -o custom-columns='NODE:.metadata.name,VIDEO:.status.allocatable.kasm\.com/video'
```

A node showing a capacity of `0` (or no value) has no `/dev/video*` devices; check the `kasm-node-prep` pod
log on that node.

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
			<td id="allocateEnvVar"><a href="./values.yaml#L56">allocateEnvVar</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
KASM_VIDEO_DEVICE
</pre>
</div>
			</td>
			<td>Env var injected into a container that is allocated exactly one device, set to that device's host path (e.g. `KASM_VIDEO_DEVICE=/dev/video3`). The exec job reads this to discover which device kubelet assigned. Not set when a container is allocated more than one device. </td>
		</tr>
		<tr>
			<td id="devicePrefix"><a href="./values.yaml#L39">devicePrefix</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
video
</pre>
</div>
			</td>
			<td>Prefix matched against entries in /dev to decide which host device files to advertise (e.g. "video" matches video0, video1, ...). The plugin re-scans /dev every 10 seconds, so devices created or removed while it runs are picked up without a restart. </td>
		</tr>
		<tr>
			<td id="fullnameOverride"><a href="./values.yaml#L9">fullnameOverride</a></td>
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
			<td>Override the fully qualified name of every resource this chart creates. Leave empty to use the standard `<release name>-<chart name>` naming. </td>
		</tr>
		<tr>
			<td id="image--pullPolicy"><a href="./values.yaml#L28">image.pullPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
IfNotPresent
</pre>
</div>
			</td>
			<td>Image pull policy for the device plugin container. </td>
		</tr>
		<tr>
			<td id="image--registry"><a href="./values.yaml#L19">image.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
docker.io
</pre>
</div>
			</td>
			<td>Container registry that hosts the device plugin image. Point this at a private registry or a pull-through mirror for air-gapped clusters. </td>
		</tr>
		<tr>
			<td id="image--repository"><a href="./values.yaml#L22">image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmweb/kasm-video-device-plugin
</pre>
</div>
			</td>
			<td>Repository of the device plugin image within `image.registry`. </td>
		</tr>
		<tr>
			<td id="image--tag"><a href="./values.yaml#L25">image.tag</a></td>
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
			<td>Tag of the device plugin image. Leave empty to use the chart's `appVersion`. </td>
		</tr>
		<tr>
			<td id="imagePullSecrets"><a href="./values.yaml#L33">imagePullSecrets</a></td>
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
			<td>Names of existing `kubernetes.io/dockerconfigjson` Secrets in the release namespace, used to pull the device plugin image from a private registry. </td>
		</tr>
		<tr>
			<td id="maxDevices"><a href="./values.yaml#L44">maxDevices</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
128
</pre>
</div>
			</td>
			<td>Maximum number of matching devices to advertise. Extra devices beyond this count (sorted numerically by suffix, so video10 is not treated as smaller than video2) are ignored. </td>
		</tr>
		<tr>
			<td id="nameOverride"><a href="./values.yaml#L4">nameOverride</a></td>
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
			<td>Override the chart name used when building resource names and the `app.kubernetes.io/name` label. Leave empty to use the chart name (`kasm-video-device-plugin`). </td>
		</tr>
		<tr>
			<td id="nodeSelector"><a href="./values.yaml#L62">nodeSelector</a></td>
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
			<td>Node labels that select which nodes run the device plugin. Set this to the same selector used by the `kasm-node-prep` chart so `kasm.com/video` is only advertised on nodes where the v4l2loopback module is actually loaded; otherwise the scheduler can place a webcam session on a node with no devices. </td>
		</tr>
		<tr>
			<td id="podAnnotations"><a href="./values.yaml#L109">podAnnotations</a></td>
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
			<td>Extra annotations to add to the DaemonSet pods. </td>
		</tr>
		<tr>
			<td id="podLabels"><a href="./values.yaml#L113">podLabels</a></td>
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
			<td>Extra labels to add to the DaemonSet pods, merged with the chart's standard selector labels. </td>
		</tr>
		<tr>
			<td id="priorityClassName"><a href="./values.yaml#L105">priorityClassName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
system-node-critical
</pre>
</div>
			</td>
			<td>Priority class for the DaemonSet pods. Device plugins should outlive node pressure: if this pod is evicted, kubelet stops advertising `kasm.com/video` and webcam sessions become unschedulable on that node. Set to an empty string to use the namespace default instead. </td>
		</tr>
		<tr>
			<td id="resourceName"><a href="./values.yaml#L50">resourceName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasm.com/video
</pre>
</div>
			</td>
			<td>Kubernetes extended resource name the plugin registers under with kubelet. Must match the resource key in workspace pod limits — this is the resource the Kasm agent requests when `KASM_SVC_WEBCAM=1`. </td>
		</tr>
		<tr>
			<td id="resources"><a href="./values.yaml#L77">resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
limits:
    cpu: 50m
    memory: 64Mi
requests:
    cpu: 10m
    memory: 32Mi
</pre>
</div>
			</td>
			<td>CPU and memory requests and limits for the device plugin container. The plugin only watches device paths and answers kubelet, so it stays small. Both requests and limits are always set. </td>
		</tr>
		<tr>
			<td id="resources--limits--cpu"><a href="./values.yaml#L94">resources.limits.cpu</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
50m
</pre>
</div>
			</td>
			<td>CPU limit for the device plugin container. Headroom over the request for the periodic `/dev` re-scan and for the burst of Allocate calls when several webcam sessions start at once; the plugin is near-idle the rest of the time, so there is little reason to raise this. </td>
		</tr>
		<tr>
			<td id="resources--limits--memory"><a href="./values.yaml#L99">resources.limits.memory</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
64Mi
</pre>
</div>
			</td>
			<td>Memory limit for the device plugin container. Comfortably above what the plugin actually uses — it is here to bound a runaway and to satisfy the repository's Kyverno policies, which reject a container with no memory limit, not because the plugin is expected to approach it. </td>
		</tr>
		<tr>
			<td id="resources--requests--cpu"><a href="./values.yaml#L83">resources.requests.cpu</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
10m
</pre>
</div>
			</td>
			<td>CPU request for the device plugin container. All the plugin does is re-scan `/dev` every 10 seconds and answer kubelet's gRPC calls, so there is no per-session work and the request is effectively an idle reservation. </td>
		</tr>
		<tr>
			<td id="resources--requests--memory"><a href="./values.yaml#L88">resources.requests.memory</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
32Mi
</pre>
</div>
			</td>
			<td>Memory request for the device plugin container. It holds only the list of matching device files (at most `maxDevices` entries) and its gRPC server, so this stays flat no matter how many webcam sessions are running on the node. </td>
		</tr>
		<tr>
			<td id="tolerations"><a href="./values.yaml#L67">tolerations</a></td>
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
			<td>Tolerations for the DaemonSet pods, so nodes carrying taints (for example dedicated workspace nodes) still advertise their video devices. </td>
		</tr>
		<tr>
			<td id="updateStrategy"><a href="./values.yaml#L72">updateStrategy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
RollingUpdate
</pre>
</div>
			</td>
			<td>DaemonSet update strategy type. `RollingUpdate` restarts the plugin pods gradually; `OnDelete` leaves running pods untouched until they are deleted manually. </td>
		</tr>
	</tbody>
</table>

