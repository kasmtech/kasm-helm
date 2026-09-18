# Workspace seccomp profiles

> **Applies to:** agent · honouring a Docker workspace image's inline seccomp profile under Kubernetes, which can only reference a profile already present on the node's disk · **Charts/values:** `agent.seccompInstaller.enabled`, `agent.seccompInstaller.image.*`, `agent.seccompInstaller.imagePullPolicy`, `agent.seccompInstaller.kubeletSeccompDir`, `agent.seccompInstaller.resources`, `agent.workspacesNodeSelector`, `agent.workspacesTolerations`

## Why this is needed

A Docker workspace image can ship an **inline seccomp profile** — `security_opt: seccomp=<json>`, the shape the Nix bubblewrap images carry. Docker applies that JSON straight to the container. Kubernetes cannot: a pod's `securityContext.seccompProfile` can only be `RuntimeDefault`, `Unconfined`, or `Localhost` pointing at a profile file **already on the node's disk** under the kubelet's seccomp directory. There is no inline option.

The seccomp installer bridges the gap:

1. The agent canonicalizes and SHA-256-hashes each inline profile, stages it (`digest → JSON`) into a per-agent `seccomp-profiles` ConfigMap, and sets the session pod's `securityContext.seccompProfile` to `Localhost` at `<prefix>/<digest>.json`.
2. The **installer** — a DaemonSet the operator deploys on the session nodes — watches that ConfigMap and mirrors every profile onto each node under the kubelet's seccomp directory, pruning anything the ConfigMap no longer lists.

With the installer **off** (the default), an inline profile falls back to `Unconfined` — the workspace still runs, just without the profile.

## Before you start

The installer writes under the kubelet's root-owned seccomp directory, so it runs **as root with a hostPath mount** (all Linux capabilities dropped, no privilege escalation, read-only root filesystem otherwise). That imposes two requirements:

- **A `privileged` Pod Security namespace.** The agent's namespace must admit the pod — label it `pod-security.kubernetes.io/enforce=privileged` (or run the agent in a namespace that already permits privileged workloads, as the node-prep and egress DaemonSets need too). Under `restricted`/`baseline` the installer pod is rejected.
- **Nodes that allow hostPath.** Managed serverless node pools that forbid hostPath or DaemonSets (e.g. GKE Autopilot, Fargate) cannot run it — there, leave it off and accept `Unconfined`.

The installer follows `agent.workspacesNodeSelector` / `agent.workspacesTolerations`, so it stages profiles on exactly the nodes sessions run on — nothing extra to place.

## Steps

1. **Enable it and point it at the image.**

   ```yaml
   kasm-agent:
     agent:
       seccompInstaller:
         enabled: true
         image:
           registry: docker.io
           repository: kasmweb/kasm-seccomp-installer
           # tag: ""   # falls back to the chart appVersion
   ```

   Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `agent:`.

2. **Override the kubelet seccomp directory where your distro relocates it.** The default `/var/lib/kubelet/seccomp` suits a stock kubelet. Common overrides:

   | Distro | `agent.seccompInstaller.kubeletSeccompDir` |
   | ------ | ------------------------------------------ |
   | stock kubelet (kubeadm, most managed clusters) | `/var/lib/kubelet/seccomp` (default) |
   | k3s | `/var/lib/rancher/k3s/agent/kubelet/seccomp` |
   | microk8s | `/var/snap/microk8s/common/var/lib/kubelet/seccomp` |

3. **Admit the namespace.** Ensure the agent's namespace enforces the `privileged` Pod Security level (see [Privileged workloads and policies](privileged-workloads.md)).

## Verify

```console
kubectl -n <ns> get ds -l app.kubernetes.io/name=kasm-seccomp-installer
kubectl -n <ns> get configmap <agent>-seccomp-profiles -o jsonpath='{.data}' | jq 'keys'
```

Expected: the DaemonSet has a pod on every session node; the ConfigMap lists one `<digest>.json` key per distinct inline profile the catalog carries. Then launch a session from a workspace whose image sets an inline `security_opt: seccomp=…`: the pod reaches `Running`, and `kubectl get pod <session> -o jsonpath='{.spec.securityContext.seccompProfile}'` shows `type: Localhost` with a `localhostProfile` under `kasm/<ns>/<agent>/`.

If the session pod stays `CreateContainerError` with a missing-profile message, the installer has not written the file yet (or `kubeletSeccompDir` is wrong for this node) — check the installer pod's logs on that node.

## Decisions

- [ ] Namespace admits `privileged` Pod Security, and the nodes allow hostPath
- [ ] `agent.seccompInstaller.kubeletSeccompDir` matches the distro's kubelet root
- [ ] Accepted the fallback: with the installer off, inline profiles run `Unconfined`

> **Note**
> Turning `seccompInstaller.enabled` back off removes only the DaemonSet; the staged ConfigMap and the profiles already on the nodes are left in place so sessions still referencing them keep resolving. They are garbage-collected with the `Agent`.
