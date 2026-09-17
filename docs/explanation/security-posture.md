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
SecurityContextConstraints gate privileged pods in addition to Pod Security admission, and the
label alone is not enough. Procedure:
[Privileged workloads and cluster policy](../how-to/nodes/privileged-workloads.md).

The control plane runs as ordinary workloads on any node and creates no cluster-scoped objects at
all: no CRDs, no ClusterRoles. `kasm-helm.applySecurity` and `kasm-helm.isOpenshift` control the
security contexts it renders.

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
| Host namespaces for the egress installer | `hostPID` and `hostNetwork` on a privileged container; its shim fails **every** pod sandbox on a node while no daemon runs | [Egress installer: node prerequisites](../how-to/networking/egress.md) |
| Operator RBAC | Re-applied on every `helm upgrade` | [Architecture, cluster singletons](architecture.md#cluster-singletons) |
| NetworkPolicy enforcement | Inert without an enforcing CNI; the manager allow needs the post-DNAT port behind a hostPort ingress | [NetworkPolicy enforcement](../how-to/networking/network-policies.md) |
| Image provenance and airgap | Four things to mirror, from four places, by four mechanisms | [Registries and airgap](../how-to/registries-and-airgap.md) |
| Secure Boot | MOK enrolment is a firmware step per node | [Secure Boot](../how-to/nodes/secure-boot.md) |
| Private registries | Workspace images authenticate from per-image credentials in the manager (separate from the charts' own `imagePullSecrets`); ECR tokens expire every 12 hours | [Registries and airgap](../how-to/registries-and-airgap.md) |
