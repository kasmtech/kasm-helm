# Security posture

> **Applies to:** both halves

What the charts ask of the cluster, and what they do to keep sessions apart. Each item is a
decision with a blast radius, not a switch to flip late.

## Pod Security

Three charts ship DaemonSets that cannot be made unprivileged:

| Workload | Why it is privileged | Beyond `privileged` |
| -------- | -------------------- | ------------------- |
| `kasm-node-prep` | `CAP_SYS_MODULE` to `insmod`, writes `/proc/sys`, calls `swapon` | nothing |
| `kasm-video-device-plugin` | opens node device nodes, writes the kubelet device-plugin socket dir | nothing |
| `kasm-egress-installer` | `nsenter` into other pods' netns, `mknod /dev/net/tun`, `iptables` | `hostPID` and `hostNetwork` |
| KMM worker, build and sign pods | `modprobe` on the node | nothing |

None satisfies the `baseline` or `restricted` Pod Security Standard. The namespace that runs them
must be labelled `pod-security.kubernetes.io/enforce=privileged`, and that label covers every pod
in the namespace, which is the main reason for the two-namespace layout
([Deployment topologies](topologies.md)). Host namespaces are beyond what the label grants: a
blanket `disallow-host-namespaces` Kyverno or Gatekeeper rule rejects the egress installer even in a
`privileged` namespace, so it needs a scoped exception or a recorded accepted risk. On OpenShift,
SecurityContextConstraints admit pods instead of the label, which the SCC label syncer sets on the
namespace for you; each privileged chart grants the `privileged` SCC to its own ServiceAccount, and
sessions get an SCC of their own
([Admit the agent on OpenShift](../how-to/nodes/openshift.md)). On RKE2 with the CIS profile, Pod Security admission enforces
`restricted` on every namespace from the API server's admission configuration, and a namespace
label cannot loosen it: the exemption is an entry in that configuration. Procedure:
[Privileged workloads and cluster policy](../how-to/nodes/privileged-workloads.md).

The control plane runs as ordinary workloads on any node and creates no cluster-scoped objects at
all: no CRDs, no ClusterRoles. `kasm-helm.applySecurity` and `kasm-helm.isOpenshift` control the
security contexts it renders.

## Session run identity

Sessions run as `kasm-user`, uid and gid 1000, the user every stock Kasm image is built for:
`runAsNonRoot`, `allowPrivilegeEscalation: false`, every capability dropped, and back only what the
profile adds (`SYS_CHROOT` for the browser sandbox under the default `baseline`, nothing but
`NET_BIND_SERVICE` under `restricted`). That is the Docker agent's user too; what the Docker agent
has and a pod does not is `docker exec -u root`, so the images and features that relied on it
(a `user: root` run config, root `exec_configs`, session recording) now need a root session of
their own. `agent.workspaceSecurity.rootMode` says where that comes from. The default is the one
that works everywhere, and the other two lock root down:

- `host` (the default) runs it as host uid 0, the way every session ran before. It works on any
  node, runtime and volume, only images that need root run this way, and a container escape from
  such a session is root on the node.
- `userns` runs the container as uid 0 inside a Linux user namespace (`hostUsers: false`). Root in
  the pod maps to an unprivileged, per-pod uid range on the node, so a container escape lands as
  nobody in particular. It needs Kubernetes 1.33 or newer (user namespaces on by default; GA in
  1.36), containerd 2.0 or CRI-O 1.25, a 6.3+ kernel on the session nodes, no NFS-backed volume on
  the pod (the NFS client cannot idmap-mount, and the container fails to create;
  [Storage](../how-to/storage/README.md)), and no OCI image volume (a Nix image's `imageMounts`) on
  a runc node, since runc idmaps bind mounts only. Device passthrough into it is limited, since
  device ownership is not remapped ([GPU workspaces](../how-to/nodes/gpu.md)).
- `forbid` refuses root: such an image fails to launch.

The feature-by-feature consequences of each mode are in [Session run modes](session-run-modes.md).

`rootFeatures` decides what an otherwise uid-1000 image gets when it asks for root through its
commands or recording: promoted to `rootMode`, kept at uid 1000 with the feature downgraded, or
refused. `userNamespaces: always` puts uid-1000 sessions in a user namespace as well, and `sudo`
turns privilege escalation back on for images whose sudoers entry has to work. Every session pod is
labelled `kasm.com/run-mode` (`nonroot`, `userns-root`, `host-root`), so Kyverno exceptions and
dashboards can tell the three apart without reading the security context.

The Pod Security Standard a session pod satisfies follows from its run mode:

| Run mode | Pod shape | Highest level it satisfies |
| -------- | --------- | -------------------------- |
| `nonroot`, `profile: restricted` | uid 1000, no escalation, `NET_BIND_SERVICE` at most, `RuntimeDefault` or `Localhost` seccomp | `restricted` |
| `nonroot`, `profile: baseline` (default) | as above plus `SYS_CHROOT` and the image's own `cap_add`s | `baseline`, since `restricted` admits no add but `NET_BIND_SERVICE`; `sudo` (escalation, `SETUID`/`SETGID`) also stays at `baseline` |
| `userns-root` | uid 0 in a user namespace, escalation allowed, the eight root capabilities | `baseline`. `restricted` stays out of reach even behind the alpha `UserNamespacesPodSecurityStandards` API-server gate, which relaxes only the non-root checks for user-namespace pods, not the capability or escalation ones |
| `host-root` | host uid 0, escalation allowed, the eight root capabilities | `baseline` on paper, since no Pod Security control looks at the uid; treat it as needing a `privileged` namespace, because that is what it amounts to on escape |

`profile` (with `userNamespaces` and `sudo`) shapes uid-1000 sessions and `rootMode` shapes root
sessions, and the two are independent: `profile: restricted` with the default `rootMode: host` is a
coherent pair, restricted-shaped desktops while root-needing images still run as host root. In a
namespace that enforces `restricted`, only `profile: restricted` sessions are admitted; every root
session, `userns-root` or `host-root`, is refused at admission. `rootMode: forbid` is the companion
knob for such a namespace, so a root-needing image fails at launch with a clear reason instead of
leaving a pod-less Deployment, but it is not a requirement.

Whatever the mode, an image with an inline seccomp profile and no `seccomp` backend falls back to
`Unconfined` under the `baseline` profile, which no Pod Security level admits; turn the backend on
([Workspace seccomp profiles](../how-to/nodes/seccomp-profiles.md)).

On OpenShift the built-in SCCs do not fit even the uid-1000 shape: `nonroot-v2` admits
`MustRunAsNonRoot` pods but no capability add beyond `NET_BIND_SERVICE` and no `Localhost` seccomp,
so it would carry only `restricted`-profile sessions from images with no inline profile; and
`restricted-v3`/`nested-container` (OpenShift 4.20's user-namespace SCCs) admit `SETUID`/`SETGID`
at most. The agent chart therefore ships its own SCCs, one per run shape
([Admit the agent on OpenShift](../how-to/nodes/openshift.md#root-sessions-the-three-root-modes)).

## RBAC

The operator is a cluster singleton. It owns the five cluster-scoped CRDs and fixed-name
ClusterRoles, so only one release per cluster may set `operator.enabled: true`. The chart owns that
RBAC, and a `helm upgrade` **re-applies** it: a hand-edited role reverts silently, and a missing rule
(the TLSRoute rule behind `GatewayRouteAccepted`, for example) is repaired the same way. Its Secret
access is per namespace, not cluster-wide: each `kasm-agent-instance` release stamps a Role in its
own namespace granting the operator's ServiceAccount what it needs there, which is why the
two-namespace layout tells the agent where the operator runs
(`agent.operatorRBAC.serviceAccount.namespace`).

The agent's ClusterRole grants `pods` get, list and watch but no `pods/log`, which is why container
logs do not appear in the Kasm UI on Kubernetes. Sessions themselves get no API access:
`automountServiceAccountToken: false` on every workspace pod.

## Isolation

The operator writes a NetworkPolicy for every session on its own: default-deny, ingress only from
the session proxy (by `podSelector`, so no namespace label is needed), egress limited to DNS, the
manager and the internet minus the cloud metadata addresses. It works in every layout, including a
manager in another cluster. A policy is inert unless the CNI enforces it; under standalone Flannel
or canal alone every policy in the cluster succeeds silently and isolates nothing (k3s's bundled
flannel enforces through its embedded policy controller). Prove enforcement before
treating default-deny as isolation: [NetworkPolicy enforcement](../how-to/networking/network-policies.md).

`networkPolicies.*` is a different thing: the agent's own namespace baseline, off by default, and
safe only in a namespace the agent has to itself. The rule and its reason are in
[Deployment topologies](topologies.md#one-release-or-two-namespaces).

Multi-tenancy is partial by design. Each session is isolated from every other pod in its namespace,
sessions get no API access, and file ownership is normalised with `fsGroup: 1000`. A namespace per
tenant needs provisioning automation this repository does not ship, and the same namespace that
permits `privileged` for node prep or egress weakens the story for everything else in it. One agent
release per tenant, in the two-namespace layout, is the starting point.

## Certificates and secrets

Both halves generate self-signed TLS Secrets when nothing else is configured: `<release>-cert-manager`
on the control plane and `kasm-session-proxy-tls` on the agent. They are reused across upgrades,
regenerated on a hostname change, and never overwrite a Secret somebody else created. On the relayed
default a browser never sees the agent's; on direct-connect it does, and it must be replaced. The
control plane's is shown to browsers on every topology. [Certificates](../how-to/networking/certificates.md).

Passwords and tokens live in `<release>-secrets` (`admin-password`, `user-password`, `db-password`,
`service-token`, `manager-token`), generated once by a pre-install hook, reused on every upgrade,
and never printed by the release notes. The manager token is the shared secret both halves check;
prefer `agent.manager.existingTokenSecret` over an inline `agent.manager.token`, which would land in
the Helm release history.

## Where each decision is made

| Decision | What it costs | Procedure |
| -------- | ------------- | --------- |
| `privileged` PSS scope | The label covers everything in the namespace, the control plane included in a shared one | [Privileged workloads and cluster policy](../how-to/nodes/privileged-workloads.md) |
| Root sessions (`agent.workspaceSecurity.rootMode`) | `host`, the default, makes a container escape from a root session root on the node; `userns` needs Kubernetes 1.33+, containerd 2.0 / CRI-O 1.25, a 6.3+ kernel, and neither an NFS-backed volume nor, on runc, an image volume on a root session | [Session run identity](#session-run-identity) |
| Host namespaces for the egress installer | `hostPID` and `hostNetwork` on a privileged container; its shim fails **every** pod sandbox on a node while no daemon runs | [Egress installer: node prerequisites](../how-to/networking/egress.md) |
| Operator RBAC | Re-applied on every `helm upgrade` | [Architecture, cluster singletons](architecture.md#cluster-singletons) |
| NetworkPolicy enforcement | Inert without an enforcing CNI; the manager allow needs the post-DNAT port behind a hostPort ingress | [NetworkPolicy enforcement](../how-to/networking/network-policies.md) |
| Image provenance and airgap | Four things to mirror, from four places, by four mechanisms | [Registries and airgap](../how-to/registries-and-airgap.md) |
| Secure Boot | MOK enrolment is a firmware step per node | [Secure Boot](../how-to/nodes/secure-boot.md) |
| Private registries | Workspace images authenticate from per-image credentials in the manager (separate from the charts' own `imagePullSecrets`); ECR tokens expire every 12 hours | [Registries and airgap](../how-to/registries-and-airgap.md) |
