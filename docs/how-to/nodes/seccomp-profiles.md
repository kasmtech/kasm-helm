# Workspace seccomp profiles

> **Applies to:** agent · honouring a Docker workspace image's inline seccomp profile under Kubernetes, which can only reference a profile already present on the node's disk · **Charts/values:** `agent.seccomp.enabled`, `agent.seccomp.backend`, `agent.seccomp.installer.image.*`, `agent.seccomp.installer.imagePullPolicy`, `agent.seccomp.installer.kubeletSeccompDir`, `agent.seccomp.installer.resources`, `agent.workspacesNodeSelector`, `agent.workspacesTolerations`

## Why this is needed

A Docker workspace image can ship an **inline seccomp profile** — `security_opt: seccomp=<json>`, the shape the Nix bubblewrap images carry. Docker applies that JSON straight to the container. Kubernetes cannot: a pod's `securityContext.seccompProfile` can only be `RuntimeDefault`, `Unconfined`, or `Localhost` pointing at a profile file **already on the node's disk** under the kubelet's seccomp directory. There is no inline option.

The agent bridges the gap: it canonicalizes and content-hashes each inline profile, hands it to a **backend** that gets the profile onto the nodes, and sets the session pod's `securityContext.seccompProfile` to `Localhost`. With seccomp **off** (the default), an inline profile falls back to `Unconfined` — the workspace still runs, just without the profile.

Two backends, selected by `agent.seccomp.backend`:

| Backend | How | Needs |
| ------- | --- | ----- |
| **`installer`** (default) | A DaemonSet bundled with the operator writes profiles under the kubelet's seccomp directory on each session node | A `privileged` namespace + hostPath nodes (it runs as root with a hostPath mount) |
| **`spo`** | The agent creates cluster-scoped `SeccompProfile` resources for the external [Security Profiles Operator](https://github.com/kubernetes-sigs/security-profiles-operator) to install | **SPO 1.0+ already running in the cluster** (this chart does not install it); no hostPath or privileged namespace |

## The installer backend (default)

The installer writes under the kubelet's root-owned seccomp directory, so it runs **as root with a hostPath mount** (all Linux capabilities dropped, no privilege escalation). That imposes two requirements:

- **A `privileged` Pod Security namespace.** Label the agent's namespace `pod-security.kubernetes.io/enforce=privileged` (or run it in a namespace that already permits privileged workloads, as node-prep and egress need too). Under `restricted`/`baseline` the installer pod is rejected.
- **Nodes that allow hostPath.** Serverless node pools that forbid hostPath or DaemonSets (e.g. GKE Autopilot, Fargate) cannot run it — there, use the `spo` backend or accept `Unconfined`.

It follows `agent.workspacesNodeSelector` / `agent.workspacesTolerations`, so it stages profiles on exactly the nodes sessions run on — nothing extra to place.

```yaml
kasm-agent:
  agent:
    seccomp:
      enabled: true
      backend: installer          # the default
      installer:
        image:
          registry: docker.io
          repository: kasmweb/kasm-seccomp-installer
          # tag: ""               # falls back to the chart appVersion
```

Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `agent:`.

Override the kubelet seccomp directory where your distro relocates it (`agent.seccomp.installer.kubeletSeccompDir`):

| Distro | `kubeletSeccompDir` |
| ------ | ------------------- |
| stock kubelet (kubeadm, most managed clusters) | `/var/lib/kubelet/seccomp` (default) |
| k3s | `/var/lib/rancher/k3s/agent/kubelet/seccomp` |
| microk8s | `/var/snap/microk8s/common/var/lib/kubelet/seccomp` |

### Verify (installer)

```console
kubectl -n <ns> get ds k8s-agent-seccomp-installer
kubectl -n <ns> get configmap <agent>-seccomp-profiles -o jsonpath='{.data}' | jq 'keys'
```

The DaemonSet has a pod on every session node; the ConfigMap lists one key (a bare content digest) per distinct inline profile the catalog carries. Launch a session from a workspace whose image sets an inline `security_opt: seccomp=…`: the pod reaches `Running`, and its container `securityContext.seccompProfile` is `type: Localhost` with a `localhostProfile` under `kasm/<ns>/<agent>/<digest>.json`. A pod stuck in `CreateContainerError` with a missing-profile message means the installer hasn't written the file yet, or `kubeletSeccompDir` is wrong for that node — check the installer pod's logs there.

## The spo backend

Set `agent.seccomp.backend: spo`. The agent then creates one cluster-scoped `SeccompProfile` (`security-profiles-operator.x-k8s.io/v1`) per profile, and SPO installs it on the nodes and reports back the Localhost path. **No `installer` block is needed or used.** No hostPath, no privileged namespace.

```yaml
kasm-agent:
  agent:
    seccomp:
      enabled: true
      backend: spo
```

- **SPO must already be installed** (1.0 or later) — this chart does not install it; deploy it from [kubernetes-sigs/security-profiles-operator](https://github.com/kubernetes-sigs/security-profiles-operator). While SPO is missing, the Agent reports `Degraded` and launches of inline-profile workspaces fail.
- The operator ships a `kasm-agent-seccomp-spo` ClusterRole and binds it to the agent so it can create/delete those `SeccompProfile` resources; nothing to configure.
- **Profile expressibility:** SPO's schema can't represent every Docker profile — one whose `defaultErrnoRet` is not `EPERM`, or that compares a syscall argument against a value above 2^63−1, fails the launch on `spo` (the `installer` backend has no such limit). Such profiles are rare.

## Decisions

- [ ] Backend chosen: `installer` (privileged namespace + hostPath) or `spo` (SPO pre-installed)
- [ ] installer: namespace admits `privileged` Pod Security, nodes allow hostPath, `kubeletSeccompDir` matches the distro
- [ ] spo: the Security Profiles Operator (1.0+) is running in the cluster
- [ ] Accepted the fallback: with seccomp off, inline profiles run `Unconfined`

> **Note**
> Turning `agent.seccomp.enabled` back off (or deleting the `Agent`) tears the backend down — the installer DaemonSet, or the cluster-scoped `SeccompProfile` resources — and cleans up its RBAC. Profiles already written to a node by the installer are left in place for sessions still referencing them.
