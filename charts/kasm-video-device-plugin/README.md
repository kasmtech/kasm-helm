# Kasm Video Device Plugin

![Version: 1.1200.0-develop](https://img.shields.io/badge/Version-1.1200.0--develop-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Kubelet device plugin DaemonSet that advertises the v4l2loopback video devices on each node as the extended resource kasm.com/video, so Kasm Workspaces sessions with webcam support can request kasm.com/video and have kubelet assign them a dedicated /dev/video* device.

**Homepage:** <https://kasm.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## What this chart does

Kubernetes will not schedule a pod onto a node because of a device file; it schedules on resources. This
chart deploys Kasm's own video-device-plugin as a DaemonSet that implements the kubelet Device Plugin API
(v1beta1) and turns the node's video devices into a countable, allocatable extended resource:

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
This page is the chart reference; the [documentation index](../../docs/README.md) has the tutorial and the how-to guides.

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
			<td id="allocateEnvVar"><a href="./values.yaml#L66">allocateEnvVar</a></td>
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
			<td id="deviceKind"><a href="./values.yaml#L76">deviceKind</a></td>
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
			<td>What the plugin advertises. Empty (the default) is the webcam plugin described above. `dri` advertises the node's GPU render nodes (`/dev/dri/renderD*`) instead: a session allocated one gets the render node and its matching card node, with `allocateEnvVar` set to the render node. Kubernetes only lets an unprivileged container open a device a device plugin handed it, so this is how a session gets hardware-accelerated rendering without running privileged. A `dri` instance also needs `devicePrefix: renderD`, its own `resourceName` (e.g. `kasm.com/dri`) and `allocateEnvVar: DRINODE`; the `kasm-agent` umbrella's `driDevicePlugin` sets all of them. </td>
		</tr>
		<tr>
			<td id="devicePrefix"><a href="./values.yaml#L49">devicePrefix</a></td>
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
			<td id="deviceShares"><a href="./values.yaml#L82">deviceShares</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>How many sessions may share each device: the plugin advertises every device this many times. `1` (the default) gives each session a device of its own, as webcams need. A GPU render node can be shared; with more than one share the plugin places each session on the device with the most shares free. </td>
		</tr>
		<tr>
			<td id="driDrivers"><a href="./values.yaml#L88">driDrivers</a></td>
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
			<td>`dri` only: comma-separated kernel drivers whose render nodes to advertise (e.g. `i915,xe,amdgpu`), matched against the node's `/sys/class/drm/renderD*/device/driver`. Empty advertises every render node. </td>
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
			<td id="global"><a href="./values.yaml#L13">global</a></td>
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
			<td id="global--cattle--systemDefaultRegistry"><a href="./values.yaml#L19">global.cattle.systemDefaultRegistry</a></td>
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
			<td>The registry Rancher configured as the cluster's system default registry (air-gapped and mirrored clusters). When set, it replaces the registry part of every image this chart renders and `image.registry` is ignored, following Rancher's convention. Rancher sets it on install from its catalog; leave it empty everywhere else.</td>
		</tr>
		<tr>
			<td id="image--pullPolicy"><a href="./values.yaml#L38">image.pullPolicy</a></td>
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
			<td id="image--registry"><a href="./values.yaml#L29">image.registry</a></td>
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
			<td id="image--repository"><a href="./values.yaml#L32">image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmweb/video-device-plugin
</pre>
</div>
			</td>
			<td>Repository of the device plugin image within `image.registry`. </td>
		</tr>
		<tr>
			<td id="image--tag"><a href="./values.yaml#L35">image.tag</a></td>
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
			<td id="imagePullSecrets"><a href="./values.yaml#L43">imagePullSecrets</a></td>
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
			<td id="maxDevices"><a href="./values.yaml#L54">maxDevices</a></td>
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
			<td id="nodeSelector"><a href="./values.yaml#L94">nodeSelector</a></td>
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
			<td id="openshift"><a href="./values.yaml#L168">openshift</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
scc:
    enabled: false
    name: privileged
</pre>
</div>
			</td>
			<td>OpenShift-only objects. Leave every switch here off on any other distribution: the kinds involved exist only on OpenShift and the release would fail to install. </td>
		</tr>
		<tr>
			<td id="openshift--scc--enabled"><a href="./values.yaml#L176">openshift.scc.enabled</a></td>
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
			<td>Grant the DaemonSet's ServiceAccount the right to use the SecurityContextConstraint named by `openshift.scc.name`, through a ClusterRole holding `use` on that one SCC and a RoleBinding in the release namespace. OpenShift's default `restricted-v2` SCC rejects this privileged, hostPath-mounting DaemonSet regardless of the namespace's Pod Security labels; this is the grant that admits it. Requires cluster-admin at install time, as any ClusterRole does. </td>
		</tr>
		<tr>
			<td id="openshift--scc--name"><a href="./values.yaml#L180">openshift.scc.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
privileged
</pre>
</div>
			</td>
			<td>The SecurityContextConstraint to grant. The built-in `privileged` SCC is the only one that admits `privileged: true` with hostPath mounts of `/dev` and the kubelet's device-plugin directory. </td>
		</tr>
		<tr>
			<td id="podAnnotations"><a href="./values.yaml#L141">podAnnotations</a></td>
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
			<td id="podLabels"><a href="./values.yaml#L145">podLabels</a></td>
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
			<td id="priorityClassName"><a href="./values.yaml#L137">priorityClassName</a></td>
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
			<td id="resourceName"><a href="./values.yaml#L60">resourceName</a></td>
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
			<td id="resources"><a href="./values.yaml#L109">resources</a></td>
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
			<td id="resources--limits--cpu"><a href="./values.yaml#L126">resources.limits.cpu</a></td>
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
			<td id="resources--limits--memory"><a href="./values.yaml#L131">resources.limits.memory</a></td>
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
			<td id="resources--requests--cpu"><a href="./values.yaml#L115">resources.requests.cpu</a></td>
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
			<td id="resources--requests--memory"><a href="./values.yaml#L120">resources.requests.memory</a></td>
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
			<td id="serviceAccount"><a href="./values.yaml#L152">serviceAccount</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
create: true
name: ""
</pre>
</div>
			</td>
			<td>The ServiceAccount the DaemonSet pods run under. The chart creates one by default so that cluster policy - an OpenShift SecurityContextConstraint, a Kyverno `PolicyException` - can be granted to this DaemonSet alone instead of to every pod that uses the namespace's `default` account. The account holds no RBAC and mounts no token; the plugin talks to the kubelet over its socket, not to the API server. </td>
		</tr>
		<tr>
			<td id="serviceAccount--annotations"><a href="./values.yaml#L163">serviceAccount.annotations</a></td>
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
			<td>Annotations to add to the created ServiceAccount. </td>
		</tr>
		<tr>
			<td id="serviceAccount--create"><a href="./values.yaml#L156">serviceAccount.create</a></td>
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
			<td>Create the ServiceAccount. Set to `false` to run under an existing one named by `serviceAccount.name`, or under the namespace `default` account when that is empty. </td>
		</tr>
		<tr>
			<td id="serviceAccount--name"><a href="./values.yaml#L160">serviceAccount.name</a></td>
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
			<td>Name of the ServiceAccount to create or to use. Leave empty to derive it from the release name (`<release>-kasm-video-device-plugin`). </td>
		</tr>
		<tr>
			<td id="tolerations"><a href="./values.yaml#L99">tolerations</a></td>
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
			<td id="updateStrategy"><a href="./values.yaml#L104">updateStrategy</a></td>
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

