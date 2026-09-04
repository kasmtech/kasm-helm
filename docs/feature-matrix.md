# What works on Kubernetes

Sessions run as pods here instead of as Docker containers. Most of what you configure in the Kasm
admin UI does not notice the difference. This page lists the features that do: the ones that need
a value switched on, the ones that need something prepared in the cluster first, and the handful
that come with a limit worth knowing before you promise them to users.

✅ Works out of the box · 🔧 Needs cluster setup · ⚠️ Works with limits · ❌ Not on Kubernetes yet

Values are written as you set them on the **`kasm-agent`** umbrella; under
[kasm-platform](../charts/kasm-platform/README.md) prefix them with `kasm-agent.`. Values shown
with a `kasm-helm.` prefix belong to the control plane — drop the prefix when you install
[kasm-helm](../charts/kasm-helm/README.md) on its own. On a managed service, read
[Managed Kubernetes providers: what changes](howto/managed-kubernetes-providers.md) alongside this
page: EKS, AKS, GKE and OpenShift decide some of the rows below for you.

[Sessions & workspaces](#sessions--workspaces) ·
[Storage & profiles](#storage--profiles) ·
[Networking & access](#networking--access) ·
[Devices](#devices-gpu-webcam-audio) ·
[Security & isolation](#security--isolation) ·
[Observability & operations](#observability--operations) ·
[Everything else](#everything-else-works-unchanged) ·
[Not on Kubernetes yet](#not-on-kubernetes-yet)

---

## Sessions & workspaces

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Desktop, browser and app sessions** | ✅ | Any conformant cluster with containerd or CRI-O | `operator.enabled=true`<br>`agent.enabled=true`<br>`agent.manager.hostname`<br>`agent.publicHostname` |
| **CPU and memory limits** | ⚠️ | Nothing | Set per workspace in the Kasm UI |
| **Docker run and exec config overrides** | ⚠️ | Nothing | Set per workspace in the Kasm UI |
| **Session recording** | ⚠️ | A Kasm license that includes recording, and session pods able to reach the Kasm API service | Turn recording on in the Kasm UI |
| **Printing** | ✅ | A workspace image with CUPS — the stock Kasm images have it | Nothing |
| **Startup and stop scripts** | ✅ | Nothing | Nothing |
| **Session sharing and casting** | ✅ | Nothing | Nothing |
| **Zone pinning** | ✅ | Nothing | `agent.zone`<br>`kasm-helm.kasmZones` |
| **RDP and RemoteApp workspaces** | ✅ | RDP target hosts outside the cluster, reachable on TCP 3389 | `kasm-helm.components.rdpGateway.enabled`<br>`kasm-helm.components.rdpHttpsGateway.enabled` |

**CPU and memory.** Kasm's **Shares** allocation (and *Inherit* under the default) gives a session
a CPU request with no ceiling; **Quotas** gives it a request and an equal limit. Memory always sets
both. Kubernetes has no share weighting, so there is no third mode. Size memory honestly — each
session's `/dev/shm` is memory-backed and counts against the pod's limit.

**Docker run and exec config.** The pod-shaped parts survive: shared-memory size, devices,
capabilities, command and arguments, environment, labels and annotations, stop timeout, health
check, image mounts (Kubernetes 1.35+ only) and init containers, plus a pod-spec escape hatch for
the rest. Host-runtime keys have no effect — see
[Not on Kubernetes yet](#not-on-kubernetes-yet).

**Session recording.** Capture works and needs no values, but it is a **licensed** Kasm feature:
without it sessions start with the recorder off even when the upload location and the group setting
are both configured, and the API logs *"Session recording is configured but not licensed"*. Once
licensed, the recording buffers on the session pod's own disk in a sized scratch volume, so it
survives a container restart but not the loss of the pod: an evicted or OOM-killed session loses
what it had not yet uploaded. The pod is held open for the upload for the workspace's stop timeout
plus 30 seconds.

**Zone pinning.** One agent release serves one zone. `agent.zone` has to name a zone that exists on
the control plane; several zones means several agent releases, each with its own
`agent.publicHostname`.

**RDP.** Both gateways are on by default. The targets are Windows or Linux hosts **outside** the
cluster — the gateway brokers to them, nothing here schedules a pod for them.
`kasm-helm.directRdpService.enabled=true` adds native-client access.

## Storage & profiles

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Persistent profiles** | 🔧 | A StorageClass with dynamic provisioning. **Shared** profiles need `ReadWriteMany` — NFS, EFS, Azure Files, CephFS | Point Kasm at an RWX StorageClass you already have<br>or<br>`nfs-server-provisioner.enabled=true`<br>`nfs-server-provisioner.persistence.enabled=true`<br>· [how-to](howto/rwx-storage-for-profiles.md) |
| **Cloud storage mappings (rclone, S3, Drive)** | 🔧 | FUSE on every node that runs sessions, and outbound access to the remote | `csiRclone.enabled=true`<br>`agent.storageMappings.enabled=true`<br>· [how-to](howto/cloud-storage-rclone-csi.md) |
| **Volume mappings (host paths)** | ⚠️ | A namespace whose Pod Security Standard permits `hostPath` | `agent.workspacesNodeSelector`<br>· [how-to](howto/privileged-workloads-and-policies.md) |
| **File mappings** | ✅ | Nothing | Nothing |
| **SSH key injection** | ✅ | Nothing | Nothing |
| **Uploads and downloads** | ✅ | Nothing | Nothing |

**Persistent profiles.** `ReadWriteOnce` covers most provisioners (EBS, PD, Azure Disk, Longhorn,
local-path) and pins a session to the node holding its volume. A profile marked persistent outlives
the session. The bundled NFS provisioner is a convenience for clusters with no RWX driver, not a
production storage recommendation — and without `nfs-server-provisioner.persistence.enabled=true`
every profile is lost when its pod restarts.

**Cloud storage mappings.** Both values, always: the driver alone mounts nothing, and the agent
flag alone points at a driver that is not there. Credentials stay in a Secret. Where more than one
installation shares a cluster, scope the generated names with `agent.storageMappings.installationID`.

**Volume mappings.** The mapping itself works; scheduling is the limit. Docker mounts a path on the
one host it runs on, while an unpinned pod can land on a node where the path does not exist and
fail to start. Pin sessions to the nodes that actually have the path.

**File mappings** arrive as one ConfigMap each, text or binary, placed at the destination with the configured permission bits (executable becomes 0755); a mapping marked *writable* is copied in at start so the session user can edit it. Files cap at 1 MiB.

**Uploads and downloads** need no setup, but without a persistent profile or a storage mapping the
files live on the session's own disk and go when the session does.

## Networking & access

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **External access to sessions** | 🔧 | A Gateway API implementation, an ingress controller, or a cloud load balancer / MetalLB — with a WebSocket idle timeout of at least 3600s. DNS pointing at it | Exactly one of<br>`agent.gatewayRoute.enabled=true`<br>`agent.tlsRoute.enabled=true`<br>`agent.httpRoute.enabled=true`<br>`agent.ingress.enabled=true`<br>`agent.route.enabled=true`<br>`agent.sessionProxy.service.type=NodePort`<br>`agent.sessionProxy.service.type=LoadBalancer`<br>Control plane: `kasm-helm.ingress.enabled=true` or `kasm-helm.route.enabled=true`<br>· [how-to](howto/external-access-and-tls.md) |
| **TLS** | 🔧 | cert-manager, or a TLS Secret you create | Control plane: `kasm-helm.certificate.secretName`<br>Agent: `agent.sessionProxy.certificate.enabled=true`<br>or `agent.sessionProxy.certSecretName`<br>· [how-to](howto/external-access-and-tls.md) |
| **The login cookie reaching sessions** | ✅ | A domain that covers both hostnames | `kasm-helm.kasmConfig.generatePreseed=true`<br>`kasm-helm.kasmConfig.authDomain` |
| **Real client IP addresses** | 🔧 | A load balancer that preserves the source address, or one that sends PROXY protocol | `agent.sessionProxy.service.externalTrafficPolicy=Local`<br>or<br>`agent.sessionProxy.proxyProtocol.enabled=true`<br>`agent.sessionProxy.proxyProtocol.trustedCIDRs` |
| **Web filtering** | ✅ | Session pods able to reach the session proxy | Nothing |
| **Network isolation (restrict to network)** | 🔧 | A CNI that **enforces** NetworkPolicy — Calico, Cilium, Antrea, Weave, Kube-router, GKE Dataplane V2, or AWS VPC CNI with Calico policy | Nothing for per-session isolation.<br>`networkPolicies.enabled=true` adds the agent's own namespace baseline<br>· [how-to](howto/network-policy-enforcement.md) |
| **Egress gateways (per-session VPN)** | 🔧 | A namespace that permits `privileged` **and** host namespaces, and a runtime that honours chained CNI plugins | `egressInstaller.enabled=true`<br>`egressInstaller.distro`<br>or<br>`egressInstaller.cniBinDir`<br>· [how-to](howto/egress-installer-node-prerequisites.md) |

**External access.** The two halves are exposed independently: the control plane is what users log
in to, the session proxy is what their browser streams from. `agent.gatewayRoute` is the preferred
route (Gateway API TLS passthrough); `agent.route` is the OpenShift path; `agent.httpRoute` also
needs `agent.httpRoute.parentRefs` and `agent.httpRoute.hostnames`. Behind an ingress, leave the
control plane's `kasm-helm.proxyService.type` as `ClusterIP`.

**The login cookie.** The session proxy is a *different hostname* from the control plane, so Kasm's
Authorization Domain has to cover both or the browser drops the cookie the moment streaming starts.
The value above applies at database initialisation, so it is a fresh-install setting; on an existing
database set it in the admin UI under Settings → Auth.

**Real client IPs.** `externalTrafficPolicy=Local` only routes traffic through nodes running a
session-proxy pod. With PROXY protocol the proxy in front **must** actually send it, or every
connection breaks.

**Web filtering** needs nothing set — the agent points the in-session filter at the session proxy
for you. Enforcement is application-layer and happens inside the session pod, so a user with root
in the workspace can interfere with it.

**Network isolation.** The operator writes a policy for every session on its own: default-deny,
then ingress from the session proxy and egress limited to DNS, the manager, and the internet minus
the cloud metadata address. It works in every topology with no namespace labels, including a
manager in another cluster. Under Flannel or canal alone, though, every policy in the cluster is a
no-op that silently succeeds. `networkPolicies.*` is the *agent's own* namespace baseline and is a
separate decision — leave it off in a namespace shared with the control plane, and extend it with
`networkPolicies.extraPolicies`.

**Egress gateways.** Read the how-to before enabling this in production. A graceful shutdown
restores every node's CNI configuration and removes the shim; a hard crash does not, and while no
daemon is running the shim fails **every** pod sandbox on that node, not only Kasm's. An older
per-session VPN sidecar remains available on the workspace resource and needs no chart at all.

## Devices (GPU, webcam, audio)

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **GPU workspaces (CUDA / compute)** | 🔧 | GPU hardware, and nodes labelled — usually tainted — for GPU workloads | `gpuOperator.enabled=true`<br>`agent.gpu.enabled=true`<br>· [how-to](howto/gpu-nodes.md) |
| **GPU graphics acceleration (EGL / DRI)** | 🔧 | GPU drivers in the node image, with `/dev/dri/card0` and `/dev/dri/renderD128` present | `agent.gpu.enabled=true`<br>`agent.workspacesNodeSelector`<br>· [how-to](howto/gpu-nodes.md) |
| **Webcam passthrough** | 🔧 | Loadable kernel modules on nodes, a `privileged` namespace, and either kernel headers and a toolchain or the KMM operator and a registry | `nodePrep.enabled=true`<br>`nodePrep.modules.v4l2loopback.enabled=true`<br>`videoDevicePlugin.enabled=true`<br>· [how-to](howto/kernel-modules-and-webcam.md) |
| **Microphone** | ✅ | A workspace image with PulseAudio — the stock Kasm images have it | Nothing |
| **Audio playback** | ✅ | Nothing | Nothing |
| **Gamepad** | ✅ | Nothing | Nothing |

**GPU.** Both values, always: the GPU Operator on its own advertises GPUs that nothing asks for.
The GPU Operator is cluster-scoped — install it once per cluster, not once per agent release, and
leave `gpuOperator.enabled=false` if you already run NVIDIA's device plugin. Allocation moves to
kubelet, which is sturdier than the Docker agent's own bookkeeping but drops the Kasm-level GPU
metadata, and on a multi-GPU node a session gets the first available graphics device rather than a
topology-aware one. Hardware video encoding (NVENC) additionally needs the driver stack in the
workspace image; it is untested here, in a lab with no GPU nodes.

**Webcam.** Both halves are required: one chart loads the kernel module and reloads it after every
node reboot, the other advertises the resulting devices to the scheduler. At fleet scale, on Secure
Boot nodes, or on node images with no compiler, set `nodePrep.modules.v4l2loopback.method=kmm` to
build the module once per kernel into an image instead. Devices per node:
`nodePrep.modules.v4l2loopback.videoDevices`.

**Audio and gamepad** ride the session connection, so no node needs a sound device or a controller
attached.

## Security & isolation

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Private image registries** | 🔧 | A `kubernetes.io/dockerconfigjson` Secret in the namespace | `agent.workspaceImagePullSecrets` (workspace images)<br>`agent.imagePullSecrets` (the agent's own images)<br>`kasm-helm.imagePullSecrets.enabled=true`<br>· [how-to](howto/private-registries-and-image-pulling.md) |
| **Per-workspace registry credentials** | ⚠️ | Nothing | Set on the workspace in the Kasm UI |
| **Trusted CA certificates** | ✅ | Your CA certificates in PEM | `kasm-helm.trustedCaBundle.enabled=true`<br>`kasm-helm.trustedCaBundle.caCerts` |
| **Secure Boot nodes** | 🔧 | MOK signing keys enrolled in each node's UEFI, and the key pair in a Secret | `nodePrep.secureBoot.existingMokSecret`<br>or<br>`nodePrep.modules.v4l2loopback.kmm.sign.enabled=true`<br>· [how-to](howto/secure-boot.md) |
| **WireGuard on kernels older than 5.6** | 🔧 | Kernel headers, `/lib/modules` and `/usr/src` on the node, and a `privileged` namespace | `nodePrep.enabled=true`<br>`nodePrep.modules.wireguard.enabled=true`<br>· [how-to](howto/kernel-modules-and-webcam.md) |
| **Multi-tenancy / namespace isolation** | ⚠️ | NetworkPolicy enforcement, Pod Security Standards, ResourceQuota and LimitRange | `networkPolicies.enabled=true`, one agent release per tenant<br>· [how-to](howto/network-policy-enforcement.md) |

**Anything that touches a node needs a privileged namespace.** Webcam, WireGuard, Secure Boot and
egress gateways all run privileged pods:

```console
kubectl label namespace kasm-agent pod-security.kubernetes.io/enforce=privileged
```

Egress gateways need one thing more — host namespaces (`hostPID`, `hostNetwork`) — which a blanket
`disallow-host-namespaces` admission rule rejects even in a privileged namespace, and which has to
be scoped or excepted deliberately.

**Per-workspace registry credentials.** Credentials set on a single workspace are turned into a
pull Secret for you and kept in step when they change. Two gaps: an image name that carries no
registry host is pulled from Docker Hub whatever the workspace's registry field says, so a
registry-scoped private image would fail; and the generated Secrets are not cleaned up when they
stop being used.

**Trusted CA certificates.** The values above put your CA into the Kasm services. Getting the same
CA trusted *inside a session* is a different mechanism: add the certificate as a file mapping under
`/usr/local/share/ca-certificates/` and have a start script run `update-ca-certificates`.

**Secure Boot** only matters where Secure Boot is actually on — mostly bare metal and private
cloud. EKS, GKE and AKS do not enable it by default.

**WireGuard** is in-tree from kernel 5.6, and the installer detects that and exits early, so
leaving this on across a mixed fleet is safe. Most managed Kubernetes is already past 5.6.

**Multi-tenancy.** What ships is real but basic: each session is isolated from every other pod in
its namespace, sessions get no Kubernetes API access, and file ownership is normalised. A namespace
per user or per group needs provisioning automation on top, and the same namespace that permits
`privileged` for node prep or egress weakens the baseline for everything else in it. Separate
releases per tenant, and the two-namespace layout in
[architecture](architecture.md#deployment-topologies), are the recommended starting point.

## Observability & operations

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Telemetry (traces, metrics, logs, events)** | 🔧 | An OTLP-speaking backend and/or a ClickHouse instance | `otelCollector.enabled=true`<br>`otelCollector.exporters.otlp.enabled=true`<br>`otelCollector.exporters.otlp.endpoint`<br>and/or<br>`otelCollector.exporters.clickhouse.enabled=true`<br>`otelCollector.exporters.clickhouse.endpoint`<br>`otelCollector.receivers.k8sEvents.enabled=true` |
| **Image pre-pulling** | 🔧 | The container runtime socket reachable from DaemonSet pods, and registry access or a mirror from every node | `agent.imagePuller.enabled=true`<br>`agent.imagePuller.images`<br>`agent.imageAvailabilityPolicy`<br>· [how-to](howto/private-registries-and-image-pulling.md) |
| **Node targeting and pools** | ✅ | A consistent node-labelling strategy | Nothing per workspace.<br>`agent.workspacesNodeSelector` sets a fleet-wide default<br>· [how-to](howto/gpu-nodes.md) |
| **Node tuning and swap** | 🔧 | The node's kubelet configured for swap **first** | `nodePrep.tuning.swap.enabled=true`<br>`nodePrep.tuning.sysctls.enabled=true`<br>· [how-to](howto/node-tuning-and-swap.md) |
| **Autoscaling** | ⚠️ | Cluster Autoscaler or Karpenter, against node groups that match workspace pod requests | `operator.enabled=true` |
| **Airgapped installation** | ✅ | A registry you mirror the images into | Nothing |

**Telemetry.** `otelCollector.exporters.debug.enabled=true` is the quickest way to confirm data is
arriving before you point it anywhere real. With `networkPolicies.enabled=true`, open the path out
with `networkPolicies.otelBackend.cidr`.

**Image pre-pulling.** The operator already stages the manager's own image list without being
asked; the values above add images you want staged regardless. Either way it is a DaemonSet talking
to each node's container runtime, which is broad node access — worth a deliberate decision on a
cluster with tight node policy.

**Node targeting** needs no value per workspace: the agent turns the manager's own workspace labels
into a node selector for you. `agent.nodeSelector` targets the agent's own pods, not sessions.

**Autoscaling.** Node-level autoscaling works normally. What is missing is the Kasm-specific half —
nothing scales on session density. Pre-warmed pools are available as a custom resource and cut
cold-start latency, but that is pre-warming, not demand-driven scaling, and no chart value creates
one.

**Airgap.** Every chart installs with no internet access. `make images-agent` lists every image to
mirror and `make package-agent` builds the self-contained archive. The one thing that needs
planning is building kernel modules on nodes that cannot reach the internet: use
`nodePrep.modules.v4l2loopback.method=kmm` with an image you built into your own registry. Details
in the [kasm-agent README](../charts/kasm-agent/README.md).

## Everything else works unchanged

Most of the Kasm admin UI is control-plane state, or a conversation between the browser, the
streaming server inside the workspace image, and the manager. None of it changes when the session
becomes a pod, and none of it needs anything from the cluster:

- The workspace catalogue — names, descriptions, icons, categories, visibility, notes, image
  sizes, session banners and links.
- Clipboard direction, seamless clipboard, and the streaming mode and image-quality settings.
- Session time limits, keepalive and idle-disconnect timers, usage limits, and per-user session
  caps.
- Users, groups and permissions; 2FA, SSO, LDAP and SAML; password policy and subscriptions.
- UI preferences — control-panel visibility, language, dashboard redirects, default workspace,
  error display.
- Web filter policies, cast configurations, and recording parameters (bitrate, framerate,
  resolution, retention, upload location).
- Kasm's own log forwarding to Splunk or a syslog/HTTP endpoint, and object-storage credentials.
- Licensing, and the rest of the global settings.

On a fresh install most of these can be seeded from Helm values at database initialisation with
`kasm-helm.kasmConfig.generatePreseed=true` and `kasm-helm.kasmConfig.config` — see the
[preseed reference](../charts/kasm-helm/docs/preseed.md).

## Not on Kubernetes yet

- **Pause and resume a session.** Kubernetes has no container pause. The manager will report the
  session as paused, but the workspace keeps running — disable pause for groups that use a
  Kubernetes agent.
- **Choosing a named network at launch.** A pod gets one network attachment and has no list of
  names to offer. Network isolation is a filter, not a network, so it cannot stand in for this.
- **A per-workspace egress IP address.** Kubernetes network policy filters addresses and ports; it
  assigns no source address of its own, the way a Docker network plugin does.
- **Container logs in the Kasm UI.** The agent has no route to a session's logs. They are still
  there as ordinary pod logs and in the cluster's log pipeline — just not in the Kasm UI.
- **Docker-only run options.** `network_mode`, `ulimits`, `hostname`, `dns`, restart policy and
  `pid_mode` describe a Docker host. The pod sandbox owns those concerns, so the settings are
  ignored rather than translated.
- **Session-density autoscaling.** Kasm's own autoscaler provisions VMs from a cloud provider;
  nothing here scales session capacity on demand. Node autoscaling and pre-warmed pools are the
  Kubernetes-side substitutes.

---

Looking for which Kasm setting maps to which custom-resource field? See
[**Reference: Kasm settings → agent custom resource fields**](reference/settings-to-crd.md).
