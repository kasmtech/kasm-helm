# NetworkPolicy enforcement

> **Applies to:** [Network isolation and web filtering](../../reference/feature-matrix.md#networking-and-access), [multi-tenancy](../../reference/feature-matrix.md#security-and-isolation) and [telemetry](../../reference/feature-matrix.md#observability-and-operations) · **Charts/values:** `networkPolicies.enabled`, `networkPolicies.apiServer.cidr`, `networkPolicies.apiServer.ports`, `networkPolicies.manager.cidr`, `networkPolicies.manager.ports`, `networkPolicies.sessionProxy.ports`, `networkPolicies.sessionProxy.from`, `networkPolicies.otelBackend.cidr`, `networkPolicies.otelBackend.ports`, `networkPolicies.extraPolicies`

## Why this is needed

A `NetworkPolicy` object is **inert unless the CNI enforces it**. Applying a default-deny policy on
a cluster whose CNI ignores policy succeeds silently and isolates nothing — the worst possible
failure mode, because it looks like it worked. Enforcement is a cluster property you have to
establish before the chart's baseline means anything.

Two separate mechanisms exist here, and they are often confused:

* **The operator's per-workspace policies.** Stamped automatically for every session pod, no
  configuration. Nothing in this page turns them on or off.
* **`networkPolicies.*` — the agent's own namespace baseline.** Seven policies: default-deny plus
  narrow allows for DNS, intra-namespace traffic, the API server, the Kasm manager, session-proxy
  ingress, and the telemetry backend. Off by default.

## Before you start

* Know your CNI, and whether it enforces policy:

  | Platform | Enforcement |
  | -------- | ----------- |
  | k3s (default) | **Yes** — the embedded network-policy controller enforces alongside flannel. Verified live. |
  | Plain flannel, standalone | **No.** Policies are accepted and ignored. |
  | Calico, Cilium, Antrea, kube-router, Weave | Yes |
  | EKS | VPC CNI alone does **not** enforce — add Calico policy, or run Cilium |
  | AKS | Enable a network policy engine (Azure NPM or Calico) at cluster creation |
  | GKE | Dataplane V2, or the legacy network-policy add-on |
  | OpenShift | OVN-Kubernetes enforces |

* **The baseline models the two-namespace layout only.** In a namespace shared with the `kasm-helm`
  control plane, leave `networkPolicies.enabled=false` — the baseline does not model the control
  plane's flows and will cut it off. See
  [Running alongside the kasm-helm control plane](../../../charts/kasm-agent/README.md#running-alongside-the-kasm-helm-control-plane).
* Know how the agent reaches the manager, including **which port the connection actually lands on**
  after DNAT. This is the one non-obvious prerequisite; see step 3.

## Steps

1. **Prove the CNI enforces policy — before you rely on it.**

   ```console
   kubectl create namespace netpol-probe
   kubectl -n netpol-probe run probe --image=curlimages/curl:8.9.1 \
     --restart=Never --command -- sleep 3600
   kubectl -n netpol-probe wait --for=condition=Ready pod/probe --timeout=60s

   # Baseline: this must succeed
   kubectl -n netpol-probe exec probe -- curl -sS -m 5 -o /dev/null -w '%{http_code}\n' https://example.com

   kubectl -n netpol-probe apply -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny
   spec:
     podSelector: {}
     policyTypes: [Ingress, Egress]
   EOF

   # Now this must FAIL
   kubectl -n netpol-probe exec probe -- curl -sS -m 5 -o /dev/null -w '%{http_code}\n' https://example.com
   ```

   Clean up with `kubectl delete namespace netpol-probe`.

2. **Enable the baseline** in a dedicated agent namespace:

   ```yaml
   networkPolicies:
     enabled: true
   ```

3. **Fix manager egress for the post-DNAT port.** Policy is evaluated **after** destination NAT.
   When the manager is an in-cluster control plane reached through its public hostname, and that
   hostname resolves to a node running a hostPort/ServiceLB-style ingress (k3s + Traefik), the
   connection's effective destination is the *ingress controller's backend port*, not 443:

   ```yaml
   networkPolicies:
     manager:
       ports: [443, 80, 8443]     # 8443 = Traefik's websecure backend port
   ```

   Find the real backend port for your controller:

   ```console
   kubectl -n kube-system get pod -l app.kubernetes.io/name=traefik \
     -o jsonpath='{.items[0].spec.containers[0].ports[*].containerPort}{"\n"}'
   ```

   Drop 8443 when the manager is behind an external load balancer that terminates before the node.

4. **Tighten the wildcard CIDRs** once the real addresses are known. All four default to
   `0.0.0.0/0` on specific ports:

   ```yaml
   networkPolicies:
     apiServer:
       cidr: 10.0.0.0/16
       ports: [6443, 443]
     manager:
       cidr: 10.0.0.0/16
     otelBackend:
       cidr: 10.42.0.0/16
       ports: [4317, 4318, 9000]
   ```

   `kubectl get endpoints kubernetes -n default` shows the API server address.

5. **Restrict session-proxy ingress** if the fronting proxy has a predictable source:

   ```yaml
   networkPolicies:
     sessionProxy:
       ports: [4444, 4445]
       from:
         - namespaceSelector:
             matchLabels:
               kubernetes.io/metadata.name: ingress-nginx
   ```

   Leave `from: []` (anywhere) when a cloud load balancer's source addresses are not predictable.

6. **Add anything else** through `networkPolicies.extraPolicies` — each entry is a complete
   manifest, rendered through `tpl`.

## Verify

```console
kubectl get netpol -n kasm-agent
kubectl get agents.agent.kasm.com -n kasm-agent
```

Expected indicators:

* **Seven** policies: `*-default-deny`, `*-allow-dns`, `*-allow-intra-namespace`,
  `*-allow-apiserver-egress`, `*-allow-manager-egress`, `*-allow-session-ingress`,
  `*-allow-otlp-backend-egress`.
* The `Agent` resource reports **Ready**, and the manager's Infrastructure page shows the agent with
  available slots — that is the heartbeat surviving the default-deny.
* The step-1 deny test times out rather than connecting. A blocked destination must **hang until the
  curl timeout**, not return a response.
* A browser session still connects (session-proxy ingress and web filtering are unaffected).

## Chart values

Under the `kasm-platform` umbrella — but note that `kasm-platform`'s single-namespace layout is
exactly the case where the baseline must stay **off**. Enable it only when the agent has its own
namespace:

```yaml
kasm-agent:
  networkPolicies:
    enabled: true
    manager:
      ports: [443, 80, 8443]
    otelBackend:
      cidr: 10.42.0.0/16
```

Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `networkPolicies:`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Agent heartbeats fail with `connection refused`; manager reports "No Agent slots available" | Policy is evaluated post-DNAT; the allow list has 443 but the traffic lands on the ingress controller's backend port | Add the backend port to `networkPolicies.manager.ports` (Traefik: `8443`) |
| Policies applied, nothing is actually blocked | The CNI does not enforce NetworkPolicy | Run the step-1 deny test; switch to Calico/Cilium/Antrea or enable your platform's policy engine |
| Control plane breaks right after enabling the baseline | Baseline enabled in a namespace shared with `kasm-helm` | Set `networkPolicies.enabled=false` there, or split into two namespaces |
| Telemetry stops arriving at the backend | Backend outside `networkPolicies.otelBackend.cidr`/`ports` | Widen the CIDR or add the port (OTLP 4317/4318, ClickHouse 9000) |
| Sessions launch but the browser cannot connect | Session-proxy ingress restricted by `networkPolicies.sessionProxy.from`, or the ports do not match the proxy's listeners | Keep `from: []`, and keep `sessionProxy.ports` at `[4444, 4445]` |
| Operator/agent pods log API-server timeouts | `networkPolicies.apiServer.cidr` tightened past the real endpoint | Check `kubectl get endpoints kubernetes -n default` and widen |

## Checklist

- [ ] CNI enforcement proven with a default-deny probe namespace
- [ ] Agent has its own namespace (not shared with the control plane)
- [ ] `networkPolicies.enabled=true`
- [ ] `networkPolicies.manager.ports` includes the real post-DNAT backend port
- [ ] Seven policies present in the namespace
- [ ] `Agent` reports Ready and the manager shows agent slots
- [ ] `apiServer`, `manager`, `otelBackend` CIDRs tightened from `0.0.0.0/0`
- [ ] A browser session still connects end to end
