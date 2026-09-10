# Install in two namespaces

> **Applies to:** both halves

## Why this is needed

Two releases on one cluster, a namespace each: the control plane (`kasm-helm`) in `kasm`, the agent
(`kasm-agent`) in `kasm-agent`. The `privileged` Pod Security label then covers only the agent
namespace, and the agent's baseline NetworkPolicies can be turned on.
[Deployment topologies](../../explanation/topologies.md) explains what each of those fixes.

## Before you start

- Everything in [Install on one cluster](one-cluster.md) § Before you start.
- Permission to create two namespaces and to copy a Secret between them.
- If NetworkPolicies are wanted, a CNI that enforces them:
  [NetworkPolicy enforcement](../networking/network-policies.md).

## Steps

1. **Install the control plane.** Either chart works; `kasm-platform` with the agent half off keeps
   one artifact for both releases.

   ```yaml
   # cp-values.yaml
   kasm-helm:
     publicAddr: kasm.example.com
     certificate:
       secretName: kasm-tls
     proxyService:
       type: ClusterIP
     ingress:
       enabled: true
       ingressClassName: nginx
   kasm-agent:
     enabled: false
   ```

   ```console
   helm install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
     -n kasm --create-namespace -f cp-values.yaml --timeout 20m
   ```

2. **Copy the manager token across.** The control plane generated it into `kasm-secrets`; the agent
   namespace needs its own copy, because Secrets do not cross namespaces. This copy is the entire
   coupling between the two releases.

   ```console
   kubectl create namespace kasm-agent
   kubectl create secret generic kasm-manager-token -n kasm-agent \
     --from-literal=token="$(kubectl get secret kasm-secrets -n kasm -o jsonpath='{.data.manager-token}' | base64 -d)"
   ```

3. **Label the agent namespace** if any privileged chart will be on:

   ```console
   kubectl label namespace kasm-agent pod-security.kubernetes.io/enforce=privileged
   ```

4. **Install the agent.** The manager is reached at the control plane's in-cluster proxy Service,
   so the agent never leaves the cluster to heartbeat, and the session hostname is the in-cluster
   session-proxy Service, which is all the relayed topology needs. The port, scheme and
   `publicPort` are spelled out because the chart derives 8080/http and 4444 only while the
   hostnames are left empty; setting a hostname switches the defaults to 443/https and 443.

   ```yaml
   # agent-values.yaml
   kasm-helm:
     enabled: false
   kasm-agent:
     agent:
       manager:
         hostname: kasm-proxy-default.kasm.svc.cluster.local
         port: 8080
         scheme: http
         existingTokenSecret: kasm-manager-token
       publicHostname: k8s-agent-session-proxy.kasm-agent.svc.cluster.local
       publicPort: 4444
     networkPolicies:
       enabled: true
       manager:
         ports: [8080]                # the in-cluster proxy's HTTP listener
   ```

   ```console
   helm install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-platform \
     -n kasm-agent -f agent-values.yaml --timeout 10m
   ```

   On **Cilium**, an `ipBlock` never matches a pod or the node hosting the API server, so add to
   the same block: `networkPolicies.manager.inCluster.namespace: kasm` (an egress peer to the
   control plane's proxy pods) and, when the API server runs on a node, `networkPolicies.cilium.enabled: true`.
   Without them the operator crash-loops and every heartbeat is dropped, so the agent pod goes
   unready. [NetworkPolicy enforcement](../networking/network-policies.md) has the detail.

5. **Enable the agent and authorize a workspace**, as in [Get started](../../tutorials/get-started.md),
   or seed `auto_agent` on the control plane first with
   [Enable agents automatically](../enable-agents-automatically.md).

## Verify

```console
kubectl get pods -n kasm
kubectl get pods -n kasm-agent
kubectl get agents.agent.kasm.com -n kasm-agent
kubectl get netpol -n kasm-agent
```

Expected: every pod in both namespaces `Running`; the agent `PHASE` is `Ready`; seven
NetworkPolicies in `kasm-agent` when the baseline is on. `Ready` means the agent registered through
the copied token and the manager address, and its heartbeats are arriving; an agent stuck in
`Progressing` with `waiting for workloads (agent=false, ...)` has one of those wrong. Then open
**Infrastructure → Agents** on the control plane: the agent is listed as
`k8s-agent-session-proxy.kasm-agent.svc.cluster.local` and shows **Enabled** (step 5, or
`auto_agent`). Log in at `https://kasm.example.com` and launch a session; the address bar stays on
the control plane.

> **Note.** An agent that moved from the control plane's namespace (a one-release install turned
> into this layout) registers as a **new** server record, because its session-proxy hostname
> changed. The manager keeps the old record, enabled and reporting until its pods are gone; delete
> it under Infrastructure → Agents so launches are not placed on it.

## Chart values

The two files above, side by side. Under plain `kasm-helm` and `kasm-agent` releases instead of
`kasm-platform`, drop the outer `kasm-helm:` / `kasm-agent:` keys.

```yaml
# cp-values.yaml (kasm-platform)
kasm-helm:
  publicAddr: kasm.example.com
  certificate:
    secretName: kasm-tls
  proxyService:
    type: ClusterIP
  ingress:
    enabled: true
    ingressClassName: nginx
kasm-agent:
  enabled: false
```

```yaml
# agent-values.yaml (kasm-platform)
kasm-helm:
  enabled: false
kasm-agent:
  agent:
    manager:
      hostname: kasm-proxy-default.kasm.svc.cluster.local
      port: 8080
      scheme: http
      existingTokenSecret: kasm-manager-token
    publicHostname: k8s-agent-session-proxy.kasm-agent.svc.cluster.local
    publicPort: 4444
  networkPolicies:
    enabled: true
    manager:
      ports: [8080]
```

Reaching the manager through its public hostname instead (`kasm.example.com`, port 443, `https`)
also works; then `port` and `scheme` can be dropped (443 and `https` are the defaults once a
hostname is set), and `networkPolicies.manager.ports` has to carry the port the connection lands on
after DNAT, which behind a hostPort ingress such as k3s Traefik is the controller's backend port
(8443). [NetworkPolicy enforcement](../networking/network-policies.md) has the check, and the two
Cilium values.

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md). The failures specific to this layout: an
agent that never reaches `Ready` (the token copy, or the manager address: `Progressing` with
`waiting for workloads (agent=false, ...)` and `heartbeat failed` in its log), heartbeats refused
after enabling the baseline (the post-DNAT port), and on Cilium heartbeats timing out and the
operator crash-looping after enabling the baseline (the two Cilium values).

## Decisions

- [ ] Control plane in `kasm`, agent in `kasm-agent`; only `kasm-agent` labelled `privileged`.
- [ ] Manager token copied into `kasm-agent` as `kasm-manager-token`.
- [ ] Manager address chosen: in-cluster Service (8080, http) or the public hostname (443, https).
- [ ] `networkPolicies.enabled=true` only after the CNI is proven to enforce; `manager.ports` matches the address chosen; on Cilium, `manager.inCluster.namespace` and `cilium.enabled` set.
- [ ] `PHASE Ready`, and the agent enabled under Infrastructure → Agents (or `auto_agent` on).
- [ ] Relayed sessions accepted (the in-cluster session hostname), or [direct-connect](../networking/direct-connect.md) scheduled.
- [ ] Gateway or Ingress listeners admit both namespaces if both halves are published through one.
