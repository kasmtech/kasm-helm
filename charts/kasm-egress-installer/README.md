# Kasm Egress Installer

![Version: 1.1190.8-agent.1](https://img.shields.io/badge/Version-1.1190.8--agent.1-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Privileged DaemonSet that chains a CNI shim into every node's active CNI conflist and, on request, brings up an OpenVPN, WireGuard, or Ziti tunnel inside a Kasm Workspaces session's network namespace for per-session egress routing.

**Homepage:** <https://kasm.com>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## Requirements

Kubernetes: `>= 1.26.0-0`

## Read this before installing

This chart has been validated in a live k3s cluster (install, pod scheduling through the chained shim,
crash restart, and graceful uninstall). Two findings from its security review matter enough to state
here:

1. **Graceful shutdown cleans up after itself; a crash does not (until the next start).** This
   DaemonSet chains a CNI plugin (`kasm-egress-cni`) into every node's active CNI conflist. On a graceful
   termination — disabling it in a `helm upgrade`, `helm uninstall`, a rolling update, or a plain pod
   delete — the daemon restores each patched `.conflist` from the `.kasm-egress.bak` backup it wrote on
   first modification and removes the shim binary, leaving the node's CNI chain exactly as it found it.
   The default 30s termination grace
   period is ample; the cleanup takes well under a second. A **hard crash** skips that path: the chain
   stays patched, and the replacement pod re-installs and re-verifies it on start.

   The residual risk is the window with **no daemon running**. The shim hard-fails (`os.Exit(1)`) on CNI
   ADD/CHECK when it can't reach the daemon's socket, and a failing chained CNI plugin fails the *entire*
   pod sandbox creation — not just Kasm workspace pods, **every pod scheduled on that node**. Normally
   that window is just the DaemonSet restart, but a sustained crash-loop, or losing the pod without a
   graceful termination (a node reboot mid-uninstall, an evicted-and-not-rescheduled DaemonSet), blocks
   new pod scheduling on that node until a daemon comes back — or until the `.conflist` is restored by
   hand from its `.kasm-egress.bak`. Decide how you want to handle that failure mode before installing
   this anywhere that matters.
2. **This chart requires `hostNetwork: true` and `hostPID: true`** (see Security posture below), which
   conflicts with any cluster policy that blanket-disallows host namespaces (for example, a Kyverno
   `ClusterPolicy` with an unconditional `disallow-host-namespaces` rule and no exception mechanism). That
   is a genuine, unresolved policy conflict, not a chart bug — it needs an explicit decision (a scoped
   policy exception, or accepting this workload sits outside the baseline policy set), not a silent bypass.
This page is the chart reference; the [documentation index](../../docs/README.md) has the tutorial and the how-to guides.

## What this chart does

The control-plane side of egress (providers, gateways, credentials, assignment) is configured as on
any Kasm and documented in [Egress in the Kasm documentation](https://www.kasmweb.com/docs/latest/guide/egress.html). This chart is the
Kubernetes node-side piece only.

1. The daemon starts, installs its bundled `kasm-egress-cni` binary onto the host's CNI bin directory, and
   patches every `.conflist` file it finds in `cniConfDirs` to chain that shim into the plugin list —
   idempotently: reapplying is safe, and each conflist is checked (and re-verified after a settle delay) for
   the entry rather than blindly re-added.
2. From then on, every pod's CNI `ADD` on that node is proxied through the shim to the daemon. For an
   ordinary pod that never asked for an egress tunnel, the daemon just passes the previous CNI result
   through unchanged.
3. When a workspace session's pod annotations request a tunnel (OpenVPN, WireGuard, or Ziti — configured
   via the Kasm agent, not this chart), the daemon uses `nsenter` to enter that pod's network namespace,
   brings the tunnel up there, and injects the tunnel's DNS servers into the CNI result. `CHECK` and `DEL`
   verify and tear the tunnel down the same way.

## Security posture

Read this before installing. **This chart is aggressively privileged by necessity** — it manipulates other
pods' network namespaces and the node's own CNI configuration.

* The DaemonSet container runs with `securityContext.privileged: true`. It calls `nsenter` into arbitrary
  other pods' network *and* mount namespaces (found by scanning `/proc/<pid>/ns/*` across every process on
  the node, not just the namespace path the CNI request itself provides), runs `mknod` for `/dev/net/tun`,
  manipulates `iptables` and routes, and `unshare -m`s a new mount namespace to give the Ziti tunnel process
  its own bind mount for DNS. None of that fits inside a narrower capability set reliably.
* `hostPID: true` — required for the `/proc` scan above.
* `hostNetwork: true` — required so this pod isn't itself waiting on the CNI chain it exists to patch.
* It mounts several host paths: the CNI bin directory (write, to install the shim), every directory in
  `cniConfDirs` (write, to patch conflists), the containerd config directories for k3s and RKE2 (read-only,
  to detect a non-default `conf_dir`), and its own socket directory (write — must be a host path, since the
  shim that connects to it runs directly on the host, outside any pod).
* RBAC is minimal: a `ClusterRole` with `get` (never list or watch) on `pods` alone,
  used only for optional annotation-based config discovery and looking up a sibling container's env vars.
* The namespace this is installed into must allow privileged, host-namespace pods. With
  [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) that means
  labelling the namespace `pod-security.kubernetes.io/enforce: privileged` — this cannot satisfy `baseline`
  or `restricted` and will be rejected outright by an enforcing namespace.

## Ziti version support

The image bundles three pinned Ziti CLI versions (2.0.6, 1.6.21, 1.5.18). The daemon queries a
session's Ziti identity for its controller version and picks the installed binary whose major.minor matches
— a controller running a newer minor version than all three bundled here will fail with "no installed ziti
binary matches controller major.minor version". Keep this list current with whatever Ziti controller
versions your fleet actually runs.

## Usage

Pin the daemon to the same nodes that run Kasm Workspaces sessions:

```yaml
nodeSelector:
  kasm.com/workspaces: "true"
tolerations:
  - key: kasm.com/workspaces
    operator: Exists
    effect: NoSchedule
```

Check the daemon's own view of CNI chaining status once it's up:

```bash
kubectl exec -n <namespace> <pod> -- wget -qO- --unix-socket /var/run/kasm-egress/daemon.sock http://unix/status
```

### Point the shim at the right CNI plugin directory

The CNI plugin bin dir is this chart's one silent-failure knob. The daemon installs its
`kasm-egress-cni` binary into that directory; if it is not the directory your container runtime
actually loads plugins from, the runtime never invokes the shim. Nothing errors — the DaemonSet
stays `Running`, the conflists still look patched — sessions just get no egress tunnel.

`distro` picks the directory, and `cniBinDir` overrides it:

| `distro` | Bin dir it derives | Use for |
| -------- | ------------------ | ------- |
| `k3s` (the default) | `/var/lib/rancher/k3s/data/cni` | k3s |
| `vanilla` | `/opt/cni/bin` | kubeadm, and most managed distributions |
| anything else | none — you must set `cniBinDir` | RKE2 (its bin dir varies by version) and everything else |

An unrecognized `distro` with no `cniBinDir` **fails template rendering** rather than guessing a
path: a wrong directory here is silent at runtime, so the chart would rather not install than
install something that quietly does nothing.

```yaml
distro: vanilla            # /opt/cni/bin — kubeadm and most managed distros
# distro: k3s              # the default: /var/lib/rancher/k3s/data/cni
# cniBinDir: /opt/cni/bin  # explicit override; required for any other distro
```

This preset governs the install directory and nothing else. The conflist directories
(`cniConfDirs`) and the containerd config paths (`containerdConfigPaths`) are scanned as a *union*
that already covers the k3s, RKE2, and vanilla layouts, and entries that do not exist on a given
node are skipped rather than treated as an error — so there is no matching `distro` choice to make
for those.

## Installing from Rancher

The chart carries what Rancher's Apps catalog reads: `catalog.cattle.io/*` annotations,
`app-readme.md` and a `questions.yaml` form for the CNI plugin directory and the socket directory.
On RKE2 set `cniBinDir` explicitly, and with the CIS profile exempt the namespace from Pod Security
admission before installing. A system default registry configured on the cluster is honoured
(`global.cattle.systemDefaultRegistry`). Procedure:
[Install from the Rancher catalog](../../docs/how-to/install/rancher.md).

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
			<td id="cniBinDir"><a href="./values.yaml#L86">cniBinDir</a></td>
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
			<td>Host path the kasm-egress-cni shim binary is installed into; must match the CNI bin dir your container runtime actually reads plugins from. Leave empty to derive it from `distro` (recommended); set it to override the preset (required when `distro` is not a recognized value). </td>
		</tr>
		<tr>
			<td id="cniConfDirs"><a href="./values.yaml#L94">cniConfDirs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
- /etc/cni/net.d
- /var/lib/rancher/k3s/agent/etc/cni/net.d
- /var/lib/rancher/rke2/agent/etc/cni/net.d
</pre>
</div>
			</td>
			<td>Host paths scanned for active `.conflist` files. Every conflist found in each of these directories is patched to chain kasm-egress-cni into its plugin list (idempotently — safe to reapply, and the original file is backed up once, on first modification, to a sibling `.kasm-egress.bak`). Include every path your container runtime might read chained CNI config from; unused paths in this list are skipped silently, not treated as an error. </td>
		</tr>
		<tr>
			<td id="containerdConfigDirs"><a href="./values.yaml#L120">containerdConfigDirs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
- /var/lib/rancher/k3s/agent/etc/containerd
- /var/lib/rancher/rke2/agent/etc/containerd
- /etc/containerd
</pre>
</div>
			</td>
			<td>Host directories containing the files listed in containerdConfigPaths above, mounted read-only so the daemon can read whichever of those files exist on a given node. Only one of these two (k3s vs. RKE2) exists on any given node; DirectoryOrCreate is used so a missing one does not wedge the pod in ContainerCreating (mirrors the same k3s-vs-RKE2 handling in the kasm-node-prep chart). </td>
		</tr>
		<tr>
			<td id="containerdConfigPaths"><a href="./values.yaml#L106">containerdConfigPaths</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
- /var/lib/rancher/k3s/agent/etc/containerd/config.toml
- /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl
- /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
- /var/lib/rancher/rke2/agent/etc/containerd/config.toml
- /var/lib/rancher/rke2/agent/etc/containerd/config-v3.toml.tmpl
- /var/lib/rancher/rke2/agent/etc/containerd/config.toml.tmpl
- /etc/containerd/config.toml
</pre>
</div>
			</td>
			<td>Host file paths inspected for a containerd `conf_dir` setting, so the daemon can detect when containerd is already configured to read chained CNI config from a directory not listed above (and merge it in). Paths that don't exist on a given node's distro are skipped, not an error — the six defaults below cover every k3s/RKE2 config file layout across config.toml, config-v3.toml.tmpl, and config.toml.tmpl. This is a separate list from containerdConfigDirs below because the daemon reads each of these as an exact file, but volumes can only be mounted per-directory. </td>
		</tr>
		<tr>
			<td id="distro"><a href="./values.yaml#L61">distro</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
vanilla
</pre>
</div>
			</td>
			<td>Kubernetes distribution preset used to derive the CNI plugin bin dir (`cniBinDir`) and the CNI mode (`mode`) when those are left empty. Distributions read CNI plugin binaries from different host paths, and installing the shim to the wrong one means the container runtime never invokes it — pods get no egress tunnel, with no error. Recognized values: `vanilla` (/opt/cni/bin — kubeadm and most managed distros, the default), `k3s` (/var/lib/rancher/k3s/data/cni) and `openshift` (/var/lib/cni/bin, where Multus finds its plugins, and `mode: attachment`). For any other distribution (including RKE2, whose bin dir varies by version) set `cniBinDir` explicitly. In chain mode the conflist and containerd paths scanned below already cover k3s/RKE2/vanilla as a union. </td>
		</tr>
		<tr>
			<td id="excludedCIDRs"><a href="./values.yaml#L128">excludedCIDRs</a></td>
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
			<td>CIDRs excluded from egress tunneling and routed through the pod's original default gateway instead of the tunnel, once one is established. Empty by default (nothing bypassed). </td>
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
			<td id="image--pullPolicy"><a href="./values.yaml#L39">image.pullPolicy</a></td>
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
			<td>Image pull policy for the egress daemon container. </td>
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
			<td>Container registry that hosts the egress daemon image. Point this at a private registry or a pull-through mirror for air-gapped clusters. </td>
		</tr>
		<tr>
			<td id="image--repository"><a href="./values.yaml#L32">image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmweb/egress-daemon
</pre>
</div>
			</td>
			<td>Repository of the egress daemon image within `image.registry`. </td>
		</tr>
		<tr>
			<td id="image--tag"><a href="./values.yaml#L36">image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1.1190.8-agent.1
</pre>
</div>
			</td>
			<td>Tag of the egress daemon image. Pinned to the agent build this chart version ships; empty uses the chart's `appVersion`. </td>
		</tr>
		<tr>
			<td id="imagePullSecrets"><a href="./values.yaml#L44">imagePullSecrets</a></td>
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
			<td>Names of existing `kubernetes.io/dockerconfigjson` Secrets in the release namespace, used to pull the egress daemon image from a private registry. </td>
		</tr>
		<tr>
			<td id="mode"><a href="./values.yaml#L71">mode</a></td>
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
			<td>How sessions reach the shim. `chain` chains kasm-egress-cni into every conflist the runtime reads (`cniConfDirs`), so the runtime calls it for every pod. `attachment` touches no CNI configuration: the chart renders a Multus NetworkAttachmentDefinition (`networkAttachment`) that runs the shim, and only the sessions with egress are attached to it — set the agent's `agent.egress.networkAttachment` to the same name. Use `attachment` where the primary CNI configuration belongs to someone else, as OpenShift's belongs to the Cluster Network Operator; it needs Multus. Empty derives it from `distro`: `attachment` for `openshift`, `chain` otherwise. </td>
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
			<td>Override the chart name used when building resource names and the `app.kubernetes.io/name` label. Leave empty to use the chart name (`kasm-egress-installer`). </td>
		</tr>
		<tr>
			<td id="networkAttachment--name"><a href="./values.yaml#L80">networkAttachment.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasm-egress
</pre>
</div>
			</td>
			<td>Name of the NetworkAttachmentDefinition. The agent's `agent.egress.networkAttachment` must name it. </td>
		</tr>
		<tr>
			<td id="nodeSelector"><a href="./values.yaml#L140">nodeSelector</a></td>
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
			<td>Node labels that select which nodes run the egress daemon. Every pod scheduled on a selected node depends on this daemon once installed — see the security notice in this chart's README before narrowing or widening this. </td>
		</tr>
		<tr>
			<td id="openshift"><a href="./values.yaml#L194">openshift</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
scc:
    enabled: false
</pre>
</div>
			</td>
			<td>OpenShift-only objects. Leave off on any other distribution: the kinds involved exist only on OpenShift and the release would fail to install. </td>
		</tr>
		<tr>
			<td id="openshift--scc--enabled"><a href="./values.yaml#L200">openshift.scc.enabled</a></td>
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
			<td>Grant the daemon's ServiceAccount the built-in `privileged` SCC, through a ClusterRole holding `use` on it and a RoleBinding in the release namespace. The daemon is privileged, uses the host's PID and network namespaces and mounts host paths; `restricted-v2` admits none of that. </td>
		</tr>
		<tr>
			<td id="openvpnBinary"><a href="./values.yaml#L134">openvpnBinary</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
/usr/sbin/openvpn
</pre>
</div>
			</td>
			<td>Path to the openvpn binary inside the egress daemon container. The image bundles OpenVPN, WireGuard tools, iproute2, iptables, and three pinned Ziti CLI versions; this only needs to change if you build a custom image with openvpn installed somewhere else. </td>
		</tr>
		<tr>
			<td id="podAnnotations"><a href="./values.yaml#L189">podAnnotations</a></td>
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
			<td id="podLabels"><a href="./values.yaml#L204">podLabels</a></td>
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
			<td id="priorityClassName"><a href="./values.yaml#L185">priorityClassName</a></td>
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
			<td>Priority class for the DaemonSet pods. If this pod is evicted, kasm-egress-cni starts failing every pod ADD on that node (see this chart's README) — set to an empty string to use the namespace default instead. </td>
		</tr>
		<tr>
			<td id="resources"><a href="./values.yaml#L155">resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
limits:
    cpu: 500m
    memory: 256Mi
requests:
    cpu: 50m
    memory: 64Mi
</pre>
</div>
			</td>
			<td>CPU and memory requests and limits for the egress daemon container. </td>
		</tr>
		<tr>
			<td id="resources--limits--cpu"><a href="./values.yaml#L173">resources.limits.cpu</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
500m
</pre>
</div>
			</td>
			<td>CPU limit for the egress daemon container. Tunnel setup and the userspace data path (OpenVPN and Ziti both encrypt in userspace) are the expensive parts, and throttling them shows up as slow session starts and a throughput ceiling rather than as an error — raise this before suspecting the tunnel provider. </td>
		</tr>
		<tr>
			<td id="resources--limits--memory"><a href="./values.yaml#L179">resources.limits.memory</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
256Mi
</pre>
</div>
			</td>
			<td>Memory limit for the egress daemon container. Consumption scales with the number of concurrent egress sessions, since each one adds another tunnel process to this cgroup, so raise it on nodes that host many egress-enabled sessions. An OOMKill here tears down every tunnel on the node at once, and the restart has the node-wide effect described in this chart's README. </td>
		</tr>
		<tr>
			<td id="resources--requests--cpu"><a href="./values.yaml#L161">resources.requests.cpu</a></td>
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
			<td>CPU request for the egress daemon container. Between session setup and teardown the daemon is idle, so the request only has to cover the reconcile work and the socket server; the bursty tunnel negotiation is what `resources.limits.cpu` sizes for. </td>
		</tr>
		<tr>
			<td id="resources--requests--memory"><a href="./values.yaml#L166">resources.requests.memory</a></td>
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
			<td>Memory request for the egress daemon container. The daemon forks one tunnel process (OpenVPN, WireGuard, or Ziti) per egress session and every one of them lives in this container's cgroup, so the floor here should cover the daemon itself plus the sessions a node routinely runs. </td>
		</tr>
		<tr>
			<td id="socketDir"><a href="./values.yaml#L50">socketDir</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
/var/run/kasm-egress
</pre>
</div>
			</td>
			<td>Host path for the egress daemon's Unix socket and per-session state. Must be a host path (not an emptyDir): the kasm-egress-cni shim it installs runs directly on the host, invoked by the container runtime outside of any pod, and has to reach this same path from outside the container. </td>
		</tr>
		<tr>
			<td id="tolerations"><a href="./values.yaml#L145">tolerations</a></td>
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
			<td>Tolerations for the DaemonSet pods, so nodes carrying taints (for example dedicated workspace nodes) still get the egress daemon. </td>
		</tr>
		<tr>
			<td id="updateStrategy"><a href="./values.yaml#L151">updateStrategy</a></td>
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
			<td>DaemonSet update strategy type. `RollingUpdate` restarts the daemon gradually (see this chart's README for why a restart briefly affects node-wide pod scheduling, not just egress sessions). `OnDelete` leaves running pods untouched until deleted manually. </td>
		</tr>
	</tbody>
</table>

