> **Applies to:** both halves · **Charts/values:** `kasm-helm.applySecurity`, `kasm-helm.isOpenshift`, `nodePrep.*`, `egressInstaller.*`, `networkPolicies.*`

# Security

Each of these is a decision with a blast radius, not a switch to flip late.

| Decision | What it costs | Where |
| -------- | ------------- | ----- |
| **`privileged` PSS scope** | `nodePrep`, `videoDevicePlugin` and `egressInstaller` cannot be made unprivileged. The namespace label covers **everything** in that namespace — including the control plane, in a shared-namespace layout. Keeping the two halves apart is the main argument for the two-namespace topology. | [Privileged workloads and policies](nodes/privileged-workloads.md) |
| **Host namespaces for the egress installer** | `egressInstaller` runs with `hostPID: true` *and* `hostNetwork: true` on top of a privileged container, so a blanket `disallow-host-namespaces` rule rejects it even in a `privileged` namespace. Its shim hard-fails CNI ADD when it cannot reach the daemon — which fails **every** pod sandbox on that node, not just Kasm's. Decide this deliberately or leave it off. | [Egress installer node prerequisites](networking/egress.md) |
| **Operator RBAC** | The operator is a cluster singleton owning cluster-scoped CRDs and fixed-name ClusterRoles. The chart owns that RBAC, so a `helm upgrade` **re-applies** it — which is how a hand-edited role silently reverts, and also how a missing rule (for example the TLSRoute rule behind `GatewayRouteAccepted`) gets fixed. | [architecture → Cluster singletons](../overview/architecture.md#cluster-singletons) |
| **NetworkPolicy enforcement** | Objects are inert unless the CNI enforces them — the worst failure mode, because it looks like it worked. Verify enforcement before treating default-deny as isolation. In the two-namespace layout with an in-cluster manager reached through a hostPort ingress, `networkPolicies.manager.ports` must carry the ingress controller's **backend** port (Traefik: 8443) — the policy sees the post-DNAT port, not 443. | [NetworkPolicy enforcement](networking/network-policies.md) |
| **Image provenance and airgap** | Every chart installs with no internet access, but three flows need separate handling: the chart archive (`make package-agent`), the component images (`make images-agent`, then a registry override block), and **workspace images**, which come from the manager's registry and must be re-pointed there. `nodePrep` in `method: build` fetches at runtime — use a pre-baked builder image or KMM with prebuilt per-kernel images. | [kasm-agent → Airgapped installation](../../charts/kasm-agent/README.md#airgapped-installation) |
| **Secure Boot** | Only where it is on — mostly bare metal and private cloud. MOK enrolment is a **firmware** step per node; on a managed node image you generally cannot reach the firmware. KMM signing is the cleaner path where you have the choice. | [Secure Boot](nodes/secure-boot.md) |
| **Private registries** | `agent.workspaceImagePullSecrets` (what the agent injects into session pods) and `agent.imagePullSecrets` (what pulls the agent's own images) are genuinely different settings. ECR tokens expire every 12h. | [Private registries and image pulling](registries.md) |

Multi-tenancy sits on top of all of it and is `Partial` by design: the operator isolates each
session pod from its neighbours and denies sessions any API access, but a namespace per tenant needs
provisioning automation this repository does not ship — and the same namespace that permits
`privileged` weakens the story for everything else in it. See
[multi-tenancy](../reference/feature-matrix.md#security-and-isolation).

**Decisions**

- [ ] Namespace layout chosen with the `privileged` PSS blast radius in mind.
- [ ] `egressInstaller` explicitly in or out, with the no-daemon failure window accepted if in.
- [ ] Understood that `helm upgrade` re-applies the operator's cluster RBAC.
- [ ] CNI enforcement **proven**, not assumed, before `networkPolicies.enabled=true`.
- [ ] `networkPolicies.manager.ports` set to the post-DNAT backend port where an in-cluster ingress fronts the manager.
- [ ] Airgap decided; if yes, chart archive, component images, workspace images and node-prep inputs all planned.
- [ ] Secure Boot state of the node image known.
- [ ] Pull secrets planned for both flows, with a refresh story for expiring tokens.

---
