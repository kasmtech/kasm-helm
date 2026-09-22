# What works on Kubernetes

> **Applies to:** both halves

Sessions run as pods here instead of as Docker containers. Most of what you configure in the Kasm
admin UI does not notice the difference. This page lists the features that do: the ones that need
a value switched on, the ones that need something prepared in the cluster first, and the handful
that come with a limit worth knowing before you promise them to users.

✅ Works out of the box · 🔧 Needs cluster setup · ⚠️ Works with limits · ❌ Not on Kubernetes yet

Every row's *What you need* cell links to the how-to that installs it. Agent values are written
as they sit on the `kasm-agent` umbrella (`agent.*`, `nodePrep.*`); under
[kasm-platform](../../charts/kasm-platform/README.md) prefix them with `kasm-agent.`. Control-plane
values carry their `kasm-helm.` prefix. On a managed service, read
[Managed providers](../explanation/managed-providers.md) alongside this page: EKS, AKS, GKE and
OpenShift decide some of the rows for you.

[Sessions & workspaces](#sessions-and-workspaces) ·
[Storage & profiles](#storage-and-profiles) ·
[Networking & access](#networking-and-access) ·
[Devices](#devices-gpu-webcam-audio) ·
[Security & isolation](#security-and-isolation) ·
[Observability & operations](#observability-and-operations) ·
[Everything else](#everything-else-works-unchanged) ·
[Not on Kubernetes yet](#not-on-kubernetes-yet)

## Sessions and workspaces

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Desktop, browser and app sessions** | ✅ | Any conformant cluster with containerd or CRI-O · [how-to](../how-to/install/one-cluster.md) | `operator.enabled=true`<br>`agent.enabled=true`<br>`agent.manager.hostname`<br>`agent.publicHostname`<br>(both derived under `kasm-platform`; the no-values install sets neither) |
| **CPU and memory limits** | ⚠️ | Nothing | Set per workspace in the Kasm UI |
| **Session CPU-request density** | ✅ | Nothing · [capacity](../explanation/capacity.md#shrinking-the-cpu-request-without-changing-the-image) | `agent.workspaceCPURequestPercent` (1-100, default 100) |
| **Wait for autoscaled capacity** | 🔧 | A cluster autoscaler watching the workspace nodes · [capacity](../explanation/capacity.md#growing-capacity-autoscaling-and-standby) | `agent.workspacesAutoscaling.enabled=true`<br>`agent.workspacesAutoscaling.maxNodes`<br>`agent.workspacesAutoscaling.schedulingTimeoutSeconds` |
| **Standby session headroom** | 🔧 | Nothing — the chart creates a negative-value `PriorityClass` (or reference an admin-managed one) · [capacity](../explanation/capacity.md#growing-capacity-autoscaling-and-standby) | `agent.workspacesAutoscaling.standby.enabled=true`<br>`agent.workspacesAutoscaling.standby.priorityClassName` (optional; derived `<name>-standby`)<br>`agent.workspacesAutoscaling.standby.priorityClass.create` (default true) / `value`<br>`agent.workspacesAutoscaling.standby.replicas` / `externallyScaled`<br>`agent.workspacesAutoscaling.standby.resources` |
| **Session proxy scaling** | 🔧 | For external scaling, KEDA or an HPA against the proxy Deployment · [capacity](../explanation/capacity.md#scaling-the-session-proxy) | `agent.sessionProxy.autoscaling.enabled=true` (`sessionsPerReplica`, `min`/`maxReplicas`)<br>or `agent.sessionProxy.externallyScaled=true`<br>`agent.sessionProxy.nginx` (per-pod capacity)<br>`agent.sessionProxy.drainTimeoutSeconds` |
| **Docker run and exec config overrides** | ⚠️ | Nothing | Set per workspace in the Kasm UI |
| **Session recording** | ⚠️ | A Kasm license that includes recording, and session pods able to reach the Kasm API service · [how-to](../how-to/storage/README.md) | Turn recording on in the Kasm UI |
| **Printing** | ✅ | A workspace image with CUPS - the stock Kasm images have it | Nothing |
| **Startup and stop scripts** | ✅ | Nothing | Nothing |
| **Session sharing and casting** | ✅ | Nothing | Nothing |
| **Zone pinning** | ✅ | A `kasm-helm.kasmZones` entry per zone (each renders a manager), and the agent registering through that zone's hostname · [how-to](../how-to/multi-zone.md) | `kasm-helm.kasmZones[]`<br>`agent.manager.hostname` = the zone's `proxy_hostname`<br>`agent.zone` = the zone name |
| **RDP and RemoteApp workspaces** | ✅ | RDP target hosts outside the cluster, reachable on TCP 3389 · [how-to](../how-to/networking/rdp-gateway.md) | `kasm-helm.components.connectionProxy.rdpGateway.enabled`<br>`kasm-helm.components.connectionProxy.rdpHttpsGateway.enabled` |

**CPU and memory.** Kasm's **Shares** allocation (and *Inherit* under the default) gives a session
a CPU request with no ceiling; **Quotas** gives it a request and an equal limit. Memory always sets
both. Kubernetes has no share weighting, so there is no third mode. Size memory honestly - each
session's `/dev/shm` is memory-backed and counts against the pod's limit. Because a request is a hard
reservation, an image's `cores` fills a node's CPU while sessions sit idle; `agent.workspaceCPURequestPercent`
shrinks the request (not the limit) to bin-pack more sessions per node - see
[Capacity](../explanation/capacity.md#shrinking-the-cpu-request-without-changing-the-image).

**Docker run and exec config.** The pod-shaped parts survive: shared-memory size, devices,
capabilities, command and arguments, environment, labels and annotations, stop timeout, health
check, image mounts (Kubernetes 1.35+ only) and init containers, plus a pod-spec escape hatch for
the rest. Host-runtime keys have no effect - see
[Not on Kubernetes yet](#not-on-kubernetes-yet).

**Session recording.** Capture works and needs no values, but it is a **licensed** Kasm feature:
without it sessions start with the recorder off even when the upload location and the group setting
are both configured, and the API logs *"Session recording is configured but not licensed"*. Once
licensed, the recording buffers on the session pod's own disk in a sized scratch volume, so it
survives a container restart but not the loss of the pod: an evicted or OOM-killed session loses
what it had not yet uploaded. The pod is held open for the upload for the workspace's stop timeout
plus 30 seconds.

**Zone pinning.** One agent release serves one zone, and an agent joins the zone of the manager it
registers with, so `agent.manager.hostname` has to be that zone's hostname (`kasmZones[].proxy_hostname`,
or the in-cluster `<release>-proxy-<zone>` Service). `agent.zone` labels what the agent reports and
must match the same name; on its own it moves nothing. A zone created only in the admin UI has no
manager in a Kubernetes control plane and cannot take a Kubernetes agent. Several zones means several
agent releases, each with its own `agent.publicHostname`.

**RDP.** Both gateways are on by default. The targets are Windows or Linux hosts **outside** the
cluster - the gateway brokers to them, nothing here schedules a pod for them.
`kasm-helm.directRdpService.enabled=true` adds native-client access.

## Storage and profiles

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Persistent profiles** | 🔧 | A StorageClass with dynamic provisioning. **Shared** profiles need `ReadWriteMany` - NFS, EFS, Azure Files, CephFS · [how-to](../how-to/storage/rwx-profiles.md) | `agent.persistentProfiles.storageClass`, `accessModes`, `capacity` (empty: the cluster default class, `ReadWriteOnce`, `10Gi`)<br>with an RWX class you already have, or<br>`nfs-server-provisioner.enabled=true`<br>`nfs-server-provisioner.persistence.enabled=true` and `storageClass: kasm-rwx` |
| **Cloud storage mappings (rclone, S3, Drive)** | 🔧 | FUSE on every node that runs sessions, and outbound access to the remote · [how-to](../how-to/storage/cloud-mappings.md) | `csiRclone.enabled=true`<br>`agent.storageMappings.enabled=true` |
| **Volume mappings (host paths)** | ⚠️ | A namespace whose Pod Security Standard permits `hostPath` · [how-to](../how-to/nodes/privileged-workloads.md) | `agent.workspacesNodeSelector` |
| **File mappings** | ✅ | Nothing | Nothing |
| **SSH key injection** | ✅ | Nothing | Nothing |
| **Uploads and downloads** | ✅ | Nothing | Nothing |

**Persistent profiles.** `ReadWriteOnce` covers most provisioners (EBS, PD, Azure Disk, Longhorn,
local-path) and pins a session to the node holding its volume. A profile marked persistent outlives
the session. No value names the class: the profile PVC is created without a `storageClassName`, so
the cluster's default StorageClass provisions it, at 10Gi. The bundled NFS provisioner is a
convenience for clusters with no RWX driver, not a production storage recommendation - and without
`nfs-server-provisioner.persistence.enabled=true` every profile is lost when its pod restarts.

**Cloud storage mappings.** Both values, always: the driver alone mounts nothing, and the agent
flag alone points at a driver that is not there. The operator binds a static PersistentVolume and
claim per session and mapping, with the rclone configuration in a per-session Secret; the same
configuration, credentials included, is also carried in the `KasmWorkspace` spec today. Where more
than one installation shares a cluster, scope the generated names with
`agent.storageMappings.installationID`.

**Volume mappings.** The mapping itself works; scheduling is the limit. Docker mounts a path on the
one host it runs on, while an unpinned pod can land on a node where the path does not exist and
fail to start. Pin sessions to the nodes that actually have the path.

**File mappings** arrive as one ConfigMap each, text or binary, placed at the destination with the configured permission bits (executable becomes 0755); a mapping marked *writable* is copied in at start so the session user can edit it. Files cap at 1 MiB.

**Uploads and downloads** need no setup, but without a persistent profile or a storage mapping the
files live on the session's own disk and go when the session does.

## Networking and access

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **External access to sessions** | 🔧 | Nothing on the relayed default beyond publishing the control plane. Direct-connect: an ingress controller, a Gateway API implementation, or a cloud load balancer / MetalLB, with an idle timeout of at least 3600s, DNS, and the session proxy able to reach the control plane's hostname from inside the cluster (on its post-DNAT backend port under the baseline policies). Every listed front streams: the session proxy serves its own sessions locally, so SNI-routed and `Host`-routed fronts serve alike; [Switch sessions to direct-connect](../how-to/networking/direct-connect.md#why-this-is-needed) · [how-to](../how-to/networking/README.md) | Exactly one of<br>`agent.ingress.enabled=true`<br>`agent.httpRoute.enabled=true`<br>`agent.route.enabled=true`<br>`agent.sessionProxy.service.type=NodePort`<br>`agent.sessionProxy.service.type=LoadBalancer` with `agent.sessionProxy.service.httpsPort=443`<br>`agent.gatewayRoute.enabled=true`<br>`agent.tlsRoute.enabled=true`<br>Control plane: `kasm-helm.ingress.enabled=true` or `kasm-helm.route.enabled=true` |
| **TLS** | 🔧 | cert-manager, or a TLS Secret you create · [how-to](../how-to/networking/README.md) | Control plane: `kasm-helm.certificate.secretName`<br>Agent: `agent.sessionProxy.certificate.enabled=true`<br>or `agent.sessionProxy.certSecretName` |
| **The login cookie reaching sessions** | ✅ | Nothing on the relayed default. Direct-connect only: a domain that covers both hostnames · [how-to](../how-to/networking/direct-connect.md) | Relayed: nothing<br>Direct-connect: `kasm-helm.kasmConfig.authDomain` |
| **Real client IP addresses** | 🔧 | A load balancer that preserves the source address, or one that sends PROXY protocol on every connection · [how-to](../how-to/networking/loadbalancer-nodeport.md#preserving-real-client-ips) | `agent.sessionProxy.service.externalTrafficPolicy=Local`<br>or `agent.sessionProxy.proxyProtocol.enabled=true` with `agent.sessionProxy.proxyProtocol.trustedCIDRs` |
| **Web filtering** | ✅ | Session pods able to reach the session proxy | Nothing |
| **Network isolation (restrict to network)** | 🔧 | A CNI that **enforces** NetworkPolicy - Calico, Cilium, Antrea, Weave, Kube-router, GKE Dataplane V2, or AWS VPC CNI with Calico policy · [how-to](../how-to/networking/network-policies.md) | Nothing for per-session isolation.<br>`networkPolicies.enabled=true` adds the agent's own namespace baseline; on Cilium also `networkPolicies.manager.inCluster.namespace` (in-cluster manager) and `networkPolicies.cilium.enabled=true` (node-hosted API server) |
| **Egress gateways (per-session VPN)** | 🔧 | A namespace that permits `privileged` **and** host namespaces, and a runtime that honours chained CNI plugins · [how-to](../how-to/networking/egress.md) · [Kasm docs](https://www.kasmweb.com/docs/latest/guide/egress.html) | `egressInstaller.enabled=true`<br>`egressInstaller.distro`<br>or<br>`egressInstaller.cniBinDir` |

**External access.** The two halves are exposed independently. On the relayed default only the
control plane is published and its proxy reaches the session proxy in-cluster; on direct-connect
the session proxy is published too, on its own hostname. Every listed front works there, because
the session proxy serves its own sessions locally and never loops back through the public
address; `agent.route` is the OpenShift path, unexercised on OpenShift itself; `agent.httpRoute`
also needs `agent.httpRoute.parentRefs`. On a `LoadBalancer`, `agent.sessionProxy.service.httpsPort=443`
maps the Service's 443 onto the session proxy's 4444 listener, so `agent.publicPort` and the zone's
port stay at 443; on a `NodePort` set `agent.publicPort` to the node port instead. Behind
an ingress, leave the control plane's `kasm-helm.proxyService.type` as `ClusterIP`.
[Deployment topologies](../explanation/topologies.md).

**The login cookie.** On the relayed default the browser only ever talks to the control plane, so nothing changes. On direct-connect the session proxy is a *different hostname* from the control plane, so Kasm's
Authorization Domain has to cover both or the browser drops the cookie the moment streaming starts.
The value above applies at database initialisation, so it is a fresh-install setting; on an existing
database set it in the admin UI under Settings → Auth ([Kasm docs: Settings](https://www.kasmweb.com/docs/latest/guide/settings.html)).

**Real client IPs.** `externalTrafficPolicy=Local` only routes traffic through nodes running a
session-proxy pod. `proxyProtocol.enabled` puts `proxy_protocol` on both session-proxy listeners
and rolls the Deployment; the client address becomes the real one only for sources listed in
`trustedCIDRs`, and a connection that arrives without a PROXY header is refused, so the front must
send it on every connection.

**Web filtering** needs nothing set - the agent points the in-session filter at the session proxy
for you. Enforcement is application-layer and happens inside the session pod, so a user with root
in the workspace can interfere with it.

**Network isolation.** The operator writes a policy for every session on its own: default-deny,
then ingress from the session proxy and egress limited to DNS, the manager, and the internet minus
the cloud metadata address. It works in every topology with no namespace labels, including a
manager in another cluster. Under standalone Flannel or canal alone, though, every policy in the
cluster is a no-op that silently succeeds (k3s's bundled flannel enforces through its embedded
policy controller). `networkPolicies.*` is the *agent's own* namespace baseline and a separate
decision, settled by the layout ([Deployment topologies](../explanation/topologies.md#one-release-or-two-namespaces)),
and extended with `networkPolicies.extraPolicies`. On Cilium an `ipBlock` never matches a pod or a
node, so the baseline needs the two Cilium values in the how-to.

**Egress gateways.** Read the how-to before enabling this in production. A graceful shutdown
restores every node's CNI configuration and removes the shim; a hard crash does not, and while no
daemon is running the shim fails **every** pod sandbox on that node, not only Kasm's. An older
per-session VPN sidecar remains available on the workspace resource and needs no chart at all.

## Devices (GPU, webcam, audio)

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **GPU workspaces (CUDA / compute)** | 🔧 | GPU hardware, and nodes labelled - usually tainted - for GPU workloads · [how-to](../how-to/nodes/gpu.md) | `gpuOperator.enabled=true`<br>`agent.gpu.enabled=true` |
| **GPU graphics acceleration (EGL / DRI)** | 🔧 | GPU drivers in the node image, with `/dev/dri/card0` and `/dev/dri/renderD128` present · [how-to](../how-to/nodes/gpu.md) | `agent.gpu.enabled=true`<br>`agent.workspacesNodeSelector` |
| **Webcam passthrough** | 🔧 | Loadable kernel modules on nodes, a `privileged` namespace, and either kernel headers and a toolchain or the KMM operator and a registry · [how-to](../how-to/nodes/webcam-kernel-modules.md) | `nodePrep.enabled=true`<br>`nodePrep.modules.v4l2loopback.enabled=true`<br>`videoDevicePlugin.enabled=true` |
| **Microphone** | ✅ | A workspace image with PulseAudio - the stock Kasm images have it | Nothing |
| **Audio playback** | ✅ | Nothing | Nothing |
| **Gamepad** | ❌ | Not supported by the Kubernetes agent: passthrough relies on host `/dev/input` and `/run/udev/data` mounts (and udev) that the agent does not wire into session pods | — |

**GPU.** Both values, always: the GPU Operator on its own advertises GPUs that nothing asks for.
The GPU Operator is cluster-scoped - install it once per cluster, not once per agent release, and
leave `gpuOperator.enabled=false` if you already run NVIDIA's device plugin. Allocation moves to
kubelet, which is sturdier than the Docker agent's own bookkeeping but drops the Kasm-level GPU
metadata, and on a multi-GPU node a session gets the first available graphics device rather than a
topology-aware one. Hardware video encoding (NVENC) additionally needs the driver stack in the
workspace image.

**Webcam.** Both halves are required: one chart loads the kernel module and reloads it after every
node reboot, the other advertises the resulting devices to the scheduler. At fleet scale, on Secure
Boot nodes, or on node images with no compiler, set `nodePrep.modules.v4l2loopback.method=kmm` to
build the module once per kernel into an image instead. Devices per node:
`nodePrep.modules.v4l2loopback.videoDevices`.

**Audio and gamepad** ride the session connection, so no node needs a sound device or a controller
attached.

## Security and isolation

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Private image registries** | ✅ | For workspace images: registry credentials on the image in the Kasm admin UI, which the agent turns into a per-registry pull Secret on every session pod. For the charts' own images: a `kubernetes.io/dockerconfigjson` Secret in the namespace · [how-to](../how-to/registries-and-airgap.md) | `agent.imagePullSecrets` (the agent's own images)<br>`agent.imagePuller.extraImages[].imagePullSecrets` (pre-seeded workspace images)<br>`kasm-helm.imagePullSecrets.enabled=true` |
| **Per-workspace registry credentials** | ⚠️ | Nothing | Set on the workspace in the Kasm UI |
| **Trusted CA certificates** | ✅ | Your CA certificates in PEM · [how-to](../how-to/networking/certificates.md) | `kasm-helm.trustedCaBundle.enabled=true`<br>`kasm-helm.trustedCaBundle.caCerts` |
| **Secure Boot nodes** | 🔧 | MOK signing keys enrolled in each node's UEFI, and the key pair in a Secret · [how-to](../how-to/nodes/secure-boot.md) | `nodePrep.secureBoot.existingMokSecret`<br>or<br>`nodePrep.modules.v4l2loopback.kmm.sign.enabled=true` |
| **WireGuard on kernels older than 5.6** | 🔧 | Kernel headers, `/lib/modules` and `/usr/src` on the node, and a `privileged` namespace · [how-to](../how-to/nodes/webcam-kernel-modules.md) | `nodePrep.enabled=true`<br>`nodePrep.modules.wireguard.enabled=true` |
| **Workspace seccomp profiles** | 🔧 | Two backends: `installer` (default) needs a `privileged` namespace and hostPath nodes; `spo` needs the [Security Profiles Operator](https://github.com/kubernetes-sigs/security-profiles-operator) pre-installed (no hostPath) · [how-to](../how-to/nodes/seccomp-profiles.md) | `agent.seccomp.enabled=true`<br>`agent.seccomp.backend` (`installer`\|`spo`)<br>`agent.seccomp.installer.image.*`, `agent.seccomp.installer.kubeletSeccompDir` (k3s/microk8s) |
| **Multi-tenancy / namespace isolation** | ⚠️ | NetworkPolicy enforcement, Pod Security Standards, ResourceQuota and LimitRange · [how-to](../how-to/networking/network-policies.md) | `networkPolicies.enabled=true`, one agent release per tenant |

**Anything that touches a node needs a privileged namespace.** Webcam, WireGuard, Secure Boot and
egress gateways all run privileged pods:

```console
kubectl label namespace kasm-agent pod-security.kubernetes.io/enforce=privileged
```

Egress gateways need one thing more - host namespaces (`hostPID`, `hostNetwork`) - which a blanket
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

**Secure Boot** only matters where Secure Boot is actually on - mostly bare metal and private
cloud. EKS, GKE and AKS do not enable it by default.

**WireGuard** is in-tree from kernel 5.6, and the installer detects that and exits early, so
leaving this on across a mixed fleet is safe. Most managed Kubernetes is already past 5.6.

**Multi-tenancy.** What ships is real but basic: each session is isolated from every other pod in
its namespace, sessions get no Kubernetes API access, and file ownership is normalised. A namespace
per user or per group needs provisioning automation on top, and the same namespace that permits
`privileged` for node prep or egress weakens the baseline for everything else in it. Separate
releases per tenant, and the two-namespace layout in
[Deployment topologies](../explanation/topologies.md), are the recommended starting point.

## Observability and operations

| Feature | Status | What you need | Turn it on |
| ------- | ------ | ------------- | ---------- |
| **Telemetry (traces, metrics, logs, events)** | 🔧 | An OTLP-speaking backend and/or a ClickHouse instance · [values](../../charts/kasm-otel-collector/README.md) | `otelCollector.enabled=true`<br>`otelCollector.exporters.otlp.enabled=true`<br>`otelCollector.exporters.otlp.endpoint`<br>and/or<br>`otelCollector.exporters.clickhouse.enabled=true`<br>`otelCollector.exporters.clickhouse.endpoint`<br>`otelCollector.receivers.k8sEvents.enabled=true` |
| **Image pre-pulling** | ✅ | Registry access or a mirror reachable from every session node · [how-to](../how-to/registries-and-airgap.md) | On by default (`agent.imagePuller.enabled`).<br>`agent.imagePuller.extraImages` to pre-seed<br>`agent.imagePuller.refreshIntervalSeconds` to refresh mutable tags<br>`agent.imageAvailabilityPolicy` |
| **Node targeting and pools** | ✅ | A consistent node-labelling strategy · [how-to](../how-to/nodes/scope-workspaces-to-nodes.md) | Nothing per workspace.<br>`agent.workspacesNodeSelector` sets a fleet-wide default |
| **Node tuning and swap** | 🔧 | The node's kubelet configured for swap **first** · [how-to](../how-to/nodes/tuning-and-swap.md) | `nodePrep.tuning.swap.enabled=true`<br>`nodePrep.tuning.sysctls.enabled=true` |
| **Autoscaling** | 🔧 | Cluster Autoscaler or Karpenter, against node groups that match workspace pod requests · [capacity](../explanation/capacity.md#growing-capacity-autoscaling-and-standby) | `agent.workspacesAutoscaling.enabled=true` (wait for a node)<br>`agent.workspacesAutoscaling.standby.enabled=true` (pre-warmed headroom) |
| **Airgapped installation** | ✅ | A registry you mirror the images into · [how-to](../how-to/registries-and-airgap.md) | Nothing |

**Telemetry.** `otelCollector.exporters.debug.enabled=true` is the quickest way to confirm data is
arriving before you point it anywhere real. With `networkPolicies.enabled=true`, open the path out
with `networkPolicies.otelBackend.cidr`.

**Image pre-pulling.** On by default: the agent maintains one puller that stages the manager's
advertised catalog on the session nodes, and `agent.imagePuller.extraImages` adds images you want
staged regardless. It is an ordinary DaemonSet that holds each image with an idle container (the
kubelet does the pull) — no container-runtime socket or privileges. The default
`imageAvailabilityPolicy: pulled` depends on it, so disable it only alongside
`imageAvailabilityPolicy: all` (see the how-to).

**Node targeting** needs no value per workspace: the agent turns the manager's own workspace labels
into a node selector for you. `agent.nodeSelector` targets the agent's own pods, not sessions.

**Autoscaling.** Node-level autoscaling works normally, and the agent now cooperates with it.
`agent.workspacesAutoscaling` lets a session wait for the autoscaler to add a node instead of the
launch failing on a full pool (the agent advertises the growable capacity and holds the workspace
`WaitingForCapacity`), and `agent.workspacesAutoscaling.standby` keeps a pool of low-priority placeholder pods so a session
takes reserved room instantly while the evicted placeholder triggers the scale-up - demand-driven when
`workspacesAutoscaling.standby.externallyScaled` hands the replica count to a KEDA `ScaledObject` or HPA. Both are covered in
[Capacity](../explanation/capacity.md#growing-capacity-autoscaling-and-standby). Note that this is
chart-managed: you configure and observe it through Helm and `kubectl`, not the Kasm admin UI, which has
no controls over it and sees only the capacity the agent reports. Warm session *instances* (the
`warmpools.pools.kasm.ai` CRD, which pre-starts whole sessions) remain a bare custom resource with no
chart value.

**Airgap.** Every chart installs with no internet access. `make images-agent` lists every image to
mirror and `make package-agent` builds the self-contained archive. The one thing that needs
planning is building kernel modules on nodes that cannot reach the internet: use
`nodePrep.modules.v4l2loopback.method=kmm` with an image you built into your own registry. Details
in the [kasm-agent README](../../charts/kasm-agent/README.md).

## Everything else works unchanged

Most of the Kasm admin UI is control-plane state, or a conversation between the browser, the
streaming server inside the workspace image, and the manager. None of it changes when the session
becomes a pod, and none of it needs anything from the cluster:

- The workspace catalogue - names, descriptions, icons, categories, visibility, notes, image
  sizes, session banners and links.
- Clipboard direction, seamless clipboard, and the streaming mode and image-quality settings.
- Session time limits, keepalive and idle-disconnect timers, usage limits, and per-user session
  caps.
- Users, groups and permissions; 2FA, SSO, LDAP and SAML; password policy and subscriptions.
- UI preferences - control-panel visibility, language, dashboard redirects, default workspace,
  error display.
- Web filter policies, cast configurations, and recording parameters (bitrate, framerate,
  resolution, retention, upload location).
- Kasm's own log forwarding to Splunk or a syslog/HTTP endpoint, and object-storage credentials.
- Licensing, and the rest of the global settings.

On a fresh install most of these can be seeded from Helm values at database initialisation with
`kasm-helm.kasmConfig.generatePreseed=true` and `kasm-helm.kasmConfig.config` - see the
[preseed reference](preseed.md).

## Not on Kubernetes yet

- **Pause and resume a session.** Kubernetes has no container pause. The manager will report the
  session as paused, but the workspace keeps running - disable pause for groups that use a
  Kubernetes agent.
- **Choosing a named network at launch.** A pod gets one network attachment and has no list of
  names to offer. Network isolation is a filter, not a network, so it cannot stand in for this.
- **A per-workspace egress IP address.** Kubernetes network policy filters addresses and ports; it
  assigns no source address of its own, the way a Docker network plugin does.
- **Container logs in the Kasm UI.** The agent has no route to a session's logs. They are still
  there as ordinary pod logs and in the cluster's log pipeline, not in the Kasm UI.
- **Docker-only run options.** `network_mode`, `ulimits`, `hostname`, `dns`, restart policy and
  `pid_mode` describe a Docker host. The pod sandbox owns those concerns, so the settings are
  ignored rather than translated.
- **Cloud-VM session autoscaling.** Kasm's own autoscaler provisions VMs from a cloud provider; there
  is no equivalent here. The Kubernetes-side substitutes are node autoscaling with
  `agent.workspacesAutoscaling`, standby placeholder headroom with `agent.workspacesAutoscaling.standby` (see
  [Capacity](../explanation/capacity.md#growing-capacity-autoscaling-and-standby)), and the
  `warmpools.pools.kasm.ai` CRD for pre-started sessions.

What the operator adds to a session's environment, compared with a Docker agent, is in
[Sessions: Docker agent vs Kubernetes](../explanation/sessions-docker-vs-kubernetes.md).
