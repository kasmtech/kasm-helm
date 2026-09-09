# Privileged workloads and cluster policy

> **Applies to:** every feature that needs a `privileged` namespace — [egress gateways](../../reference/feature-matrix.md#networking-and-access), and [webcam passthrough](../../reference/feature-matrix.md#devices-gpu-webcam-audio), [WireGuard, Secure Boot and multi-tenancy](../../reference/feature-matrix.md#security-and-isolation) — plus the host namespaces (`hostPID`, `hostNetwork`) that egress gateways need on top · **Charts/values:** `nodePrep.enabled`, `videoDevicePlugin.enabled`, `egressInstaller.enabled`, `networkPolicies.enabled`

## Why this is needed

Three charts in this repo ship DaemonSets that cannot be made unprivileged:

| Workload | Why it is privileged | Extra namespaces |
| -------- | -------------------- | ---------------- |
| `kasm-node-prep` | `CAP_SYS_MODULE` to `insmod`, writes `/proc/sys`, calls `swapon` | — |
| `kasm-video-device-plugin` | opens node device nodes, writes the kubelet device-plugin socket dir | — |
| `kasm-egress-installer` | `nsenter` into other pods' netns, `mknod /dev/net/tun`, `iptables` | `hostPID`, `hostNetwork` |
| KMM worker / build / sign pods (`method=kmm`) | KMM's own workers `modprobe` on the node | — |

None of them satisfies the `baseline` or `restricted` [Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-admission/). A namespace that enforces either rejects them at admission — the DaemonSet exists, the pods never do. This page is the one-time namespace and policy preparation that has to happen before egress gateways, webcam passthrough, WireGuard or Secure Boot will work.

See [kasm-node-prep § Security posture](../../../charts/kasm-node-prep/README.md#security-posture), [kasm-video-device-plugin § Security posture](../../../charts/kasm-video-device-plugin/README.md#security-posture) and [kasm-egress-installer § Security posture](../../../charts/kasm-egress-installer/README.md#security-posture) for the full mount-by-mount breakdown.

## Before you start

- Decide the namespace topology **first**. In a single-namespace install the `privileged` label covers the control plane too; the two-namespace layout in [architecture.md § Deployment topologies](../../overview/architecture.md#deployment-topologies) is how you keep the control plane under normal enforcement. Changing your mind later means moving a release.
- Know which admission controllers the cluster actually runs: built-in PSA, and/or Kyverno / OPA Gatekeeper / a cloud policy add-on. They are enforced independently — satisfying PSA does not satisfy Kyverno.
- Distro variants:
  - **k3s** — ships **no** `PodSecurity` admission configuration by default, so the label is a no-op here. Apply it anyway: it is free, and it makes the same values file portable to a cluster that does enforce.
  - **kubeadm / vanilla** — PSA is compiled in and commonly configured to enforce `baseline` cluster-wide via an `AdmissionConfiguration` file. Those clusters reject the DaemonSet pods outright.
  - **Managed (EKS / AKS / GKE)** — PSA is available and often pre-configured (GKE Autopilot forbids privileged pods altogether and cannot run these charts). Cloud policy add-ons (GKE Policy Controller, AKS Azure Policy) apply on top.
  - **OpenShift** — SecurityContextConstraints gate privileged pods in addition to PSA, so the namespace label alone is not sufficient there. These DaemonSets have not been validated on OpenShift in this repo; treat SCC binding as unverified work you own.
- `kubectl` with permission to label namespaces, and to read your policy engine's `ClusterPolicy` / `ConstraintTemplate` objects.

## Steps

1. **Create (or pick) the namespace.** Two-namespace layout, control plane elsewhere:

   ```console
   kubectl create namespace kasm-agent
   ```

2. **Label it for the `privileged` profile.** This is the single line every one of those features depends on:

   ```console
   kubectl label namespace kasm-agent pod-security.kubernetes.io/enforce=privileged
   ```

   Optionally silence the audit/warn channels too, so `kubectl` stops printing violation warnings on every apply:

   ```console
   kubectl label namespace kasm-agent \
     pod-security.kubernetes.io/audit=privileged \
     pod-security.kubernetes.io/warn=privileged
   ```

   *k3s:* this succeeds and changes nothing — there is no PSA enforcement configured. *kubeadm / managed:* this is the step that turns rejection into admission.

3. **Only if you are enabling `egressInstaller`: clear the host-namespace policy.** Its DaemonSet sets `hostPID: true` and `hostNetwork: true`, which a `privileged` PSS label permits but a blanket `disallow-host-namespaces` Kyverno `ClusterPolicy` (or the Gatekeeper equivalent) still rejects. Find it:

   ```console
   kubectl get clusterpolicies.kyverno.io -o custom-columns='NAME:.metadata.name,ACTION:.spec.validationFailureAction'
   kubectl get constrainttemplates 2>/dev/null
   ```

   This is a deliberate policy decision, not a chart bug — take one of two routes, and record which:
   - scope a `PolicyException` (Kyverno) / constraint `excludedNamespaces` (Gatekeeper) to this namespace and this DaemonSet's ServiceAccount; or
   - accept that this workload sits outside the baseline policy set and say so in your policy inventory.

   This repo does the second thing for its own CI: the `infra` and `kmm` scenarios in `tests/values-agent/` render to `.rendered-infra/` instead of `.rendered/`, and only `.rendered/` is swept by the Kyverno PSS gate (see `AGENT_SCENARIOS` and `render-agent` in the `Makefile`). The exclusion is by design and documented in `tests/values-agent/infra.yaml`.

4. **Do not label the manager namespace `kasm.com/role=manager`.** It is *not* required for sessions: the operator's per-workspace NetworkPolicy admits the session proxy **by podSelector** (verified against the stamped policy on a live deployment), and all session and manager traffic flows through that proxy. Add it only where something genuinely needs *direct* ingress to workspace pods. See [kasm-agent § Running alongside the kasm-helm control plane](../../../charts/kasm-agent/README.md#running-alongside-the-kasm-helm-control-plane).

5. **Keep `networkPolicies.enabled=false` in any namespace shared with the control plane.** The agent umbrella's baseline models only the agent's own flows and would cut the control plane off. See [kasm-agent § Baseline network policies](../../../charts/kasm-agent/README.md#baseline-network-policies).

6. **Install the release**, then confirm the pods were admitted (next section).

## Verify

Namespace label is in place:

```console
kubectl get namespace kasm-agent \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}'
```

Expected output: `privileged`.

Every privileged DaemonSet has as many ready pods as it has eligible nodes — `DESIRED == READY`, no zeros:

```console
kubectl -n kasm-agent get daemonset
```

```text
NAME                                  DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
kasm-agent-kasm-node-prep             3         3         3       3            3
kasm-agent-kasm-video-device-plugin   3         3         3       3            3
kasm-agent-kasm-egress-installer      3         3         3       3            3
```

`DESIRED` non-zero with `CURRENT 0` is the admission-rejection signature. The reason is on the DaemonSet, not on any pod (no pod was ever created):

```console
kubectl -n kasm-agent describe daemonset kasm-agent-kasm-node-prep | sed -n '/Events/,$p'
```

A healthy namespace shows `SuccessfulCreate`; a rejecting one shows `FailedCreate` naming the violated profile.

## Chart values

Umbrella (`kasm-agent`) form — the label above is a `kubectl` step, not a chart value; these are the workloads it unblocks:

```yaml
# values.yaml for the kasm-agent umbrella
nodePrep:
  enabled: true
videoDevicePlugin:
  enabled: true
egressInstaller:
  enabled: true

# Leave this off in any namespace shared with the control plane.
networkPolicies:
  enabled: false
```

Installed via [kasm-platform](../../../charts/kasm-platform/README.md), nest the same block one level down under `kasm-agent:`:

```yaml
kasm-agent:
  nodePrep:
    enabled: true
  videoDevicePlugin:
    enabled: true
  egressInstaller:
    enabled: true
```

Installing a subchart standalone (`helm install ... oci://registry-1.docker.io/kasmweb/kasm-node-prep`) drops the alias prefix entirely: the keys are `modules.*`, `tuning.*`, `distro`, and so on at the top level.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| DaemonSet shows `DESIRED 3 / CURRENT 0`; `describe daemonset` events say `FailedCreate ... violates PodSecurity "baseline:latest"` | The namespace enforces `baseline` (or `restricted`) — kubeadm and most managed clusters | `kubectl label namespace <ns> pod-security.kubernetes.io/enforce=privileged --overwrite` |
| `nodePrep` and `videoDevicePlugin` pods run, but only `egressInstaller` pods are rejected — with a policy message about host namespaces | A blanket `disallow-host-namespaces` Kyverno/OPA rule. `hostPID` + `hostNetwork` are beyond `privileged` PSS and are enforced by a separate engine | Scope a `PolicyException` to this namespace/ServiceAccount, or accept the workload outside the baseline set. Not a chart bug — decide explicitly |
| The `privileged` label appears to do nothing on k3s — pods were already running before it was applied | k3s configures no PSA admission plugin by default, so the label is inert there | Expected. Keep the label for portability to clusters that do enforce |
| Labelling the shared namespace `privileged` also relaxes enforcement on the control-plane pods | Single-namespace topology: PSS is a namespace-level control and cannot be scoped to one workload | Split into the two-namespace layout ([architecture.md § Deployment topologies](../../overview/architecture.md#deployment-topologies)) so only the agent namespace is `privileged` |
| The repo's Kyverno gate fails after adding `nodePrep`/`egressInstaller` to a test scenario | The gate sweeps `.rendered/`; privileged cluster-infra scenarios belong in `.rendered-infra/` | Add the scenario to the `infra`/`kmm` filter in `AGENT_SCENARIOS` so it renders to `.rendered-infra/`, as `tests/values-agent/infra.yaml` does |
| Control plane loses connectivity after enabling `networkPolicies.enabled=true` in a shared namespace | The agent's baseline policy set models only agent flows | Set `networkPolicies.enabled=false` in shared-namespace topologies |

## Checklist

- [ ] Namespace topology chosen (two-namespace unless there is a reason not to).
- [ ] `kubectl label namespace <ns> pod-security.kubernetes.io/enforce=privileged` applied (a no-op on k3s; required on kubeadm/managed).
- [ ] `audit`/`warn` labels set too, if you want quiet applies.
- [ ] Cluster policy engine inventoried (`kubectl get clusterpolicies.kyverno.io`, `kubectl get constrainttemplates`).
- [ ] For `egressInstaller`: host-namespace policy resolved by a scoped exception or a recorded accepted risk.
- [ ] `networkPolicies.enabled=false` in any namespace shared with the control plane.
- [ ] `kasm.com/role=manager` **not** applied unless direct manager→workspace ingress is genuinely needed.
- [ ] `kubectl -n <ns> get daemonset` shows `DESIRED == READY` for every privileged DaemonSet.
- [ ] OpenShift only: SCC binding handled separately (unvalidated in this repo).
