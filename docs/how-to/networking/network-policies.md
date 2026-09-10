# NetworkPolicy enforcement

> **Applies to:** agent · **Charts/values:** `networkPolicies.enabled`, `networkPolicies.apiServer.cidr`, `networkPolicies.apiServer.ports`, `networkPolicies.manager.cidr`, `networkPolicies.manager.ports`, `networkPolicies.manager.inCluster.namespace`, `networkPolicies.manager.inCluster.podSelector`, `networkPolicies.cilium.enabled`, `networkPolicies.sessionProxy.ports`, `networkPolicies.sessionProxy.from`, `networkPolicies.otelBackend.cidr`, `networkPolicies.otelBackend.ports`, `networkPolicies.extraPolicies`

## Why this is needed

A `NetworkPolicy` object is **inert unless the CNI enforces it**. Applying a default-deny policy on
a cluster whose CNI ignores policy succeeds silently and isolates nothing - the worst possible
failure mode, because it looks like it worked. Enforcement is a cluster property you have to
establish before the chart's baseline means anything.

Two separate mechanisms exist here, and they are often confused:

* **The operator's per-workspace policies.** Stamped automatically for every session pod, no
  configuration. Nothing in this page turns them on or off.
* **`networkPolicies.*` - the agent's own namespace baseline.** Seven policies: default-deny plus
  narrow allows for DNS, intra-namespace traffic, the API server, the Kasm manager, session-proxy
  ingress, and the telemetry backend. Off by default.

## Before you start

* Know your CNI, and whether it enforces policy:

  | Platform | Enforcement |
  | -------- | ----------- |
  | k3s (default) | **Yes** - the embedded network-policy controller enforces alongside flannel. Verified live. |
  | Plain flannel, standalone | **No.** Policies are accepted and ignored. |
  | Cilium | **Yes, with two extra values.** On Cilium an `ipBlock` matches world traffic only, never a pod and never the node that hosts the API server (unless Cilium runs with `policyCIDRMatchMode: nodes`). The baseline's manager and API-server allows are `ipBlock` rules, so an in-cluster manager needs `networkPolicies.manager.inCluster.namespace` and a node-hosted API server (kubeadm, RKE2, k3s with Cilium) needs `networkPolicies.cilium.enabled`; step 4. Verified on Cilium 1.20 on kubeadm 1.34. |
  | Calico, Antrea, kube-router, Weave | Yes |
  | EKS | VPC CNI alone does **not** enforce - add Calico policy, or run Cilium |
  | AKS | Enable a network policy engine (Azure NPM or Calico) at cluster creation |
  | GKE | Dataplane V2, or the legacy network-policy add-on |
  | OpenShift | OVN-Kubernetes enforces |

* The agent has a namespace to itself. The rule and its reason are in
  [Deployment topologies](../../explanation/topologies.md#one-release-or-two-namespaces).
* Know how the agent reaches the manager, including **which port the connection actually lands on**
  after DNAT. This is the one non-obvious prerequisite; see step 3.

## Steps

1. **Prove the CNI enforces policy - before you rely on it.**

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

   # Give the CNI a moment to program the policy, then this must FAIL
   sleep 5
   kubectl -n netpol-probe exec probe -- curl -sS -m 5 -o /dev/null -w '%{http_code}\n' https://example.com
   ```

   Expected: the second `curl` hangs until its 5-second timeout and exits 28. A `200` within a
   second of the `apply` is propagation, not a non-enforcing CNI (Cilium programs the endpoint 1
   to 3 seconds later); repeat it after a few seconds before drawing a conclusion. Clean up with
   `kubectl delete namespace netpol-probe`.

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
       ports: [443, 80, 8080, 8443]     # 8443 = Traefik's websecure backend port
   ```

   The default list is `[443, 80, 8080]`; 8080 is the in-cluster control-plane proxy's HTTP
   listener. Find the real backend port for your controller:

   ```console
   kubectl -n kube-system get pod -l app.kubernetes.io/name=traefik \
     -o jsonpath='{.items[0].spec.containers[0].ports[*].containerPort}{"\n"}'
   ```

   Drop 8443 when the manager is behind an external load balancer that terminates before the node.
   The same post-DNAT rule applies to a Gateway: a public hostname whose address DNATs to the
   Gateway's data-plane pod lands on that pod's listener port (Envoy Gateway: 10443), which the
   direct-connect session proxy also has to reach for its upstream-auth hop; `manager.inCluster`
   covers only the control plane's own proxy pods.

4. **On Cilium, add the selector-based allows.** A Cilium `ipBlock` never matches a pod or the
   node hosting the API server, so the two `0.0.0.0/0` allows below do nothing for those
   destinations. With an in-cluster manager (the two-namespace layout), name the control plane's
   namespace; the chart adds an egress peer to its proxy pods on `manager.ports`:

   ```yaml
   networkPolicies:
     manager:
       inCluster:
         namespace: kasm                      # the control plane's namespace
         # podSelector defaults to app.kubernetes.io/component: proxy
     cilium:
       enabled: true                          # CiliumNetworkPolicy: egress toEntities [kube-apiserver] on apiServer.ports
   ```

   `cilium.enabled` renders a `CiliumNetworkPolicy` allowing egress to the `kube-apiserver` entity
   on `networkPolicies.apiServer.ports`; without it, on a cluster whose API server runs on a node,
   the operator loses leader election and crash-loops the moment the policies land. The
   cluster-wide alternative is running Cilium with `policyCIDRMatchMode: nodes`, which makes the
   `ipBlock` match nodes; then `cilium.enabled` is not needed. Neither value applies on other
   CNIs, where an `ipBlock` matches any destination.

5. **Tighten the wildcard CIDRs** once the real addresses are known. All four default to
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

6. **Restrict session-proxy ingress** if the fronting proxy has a predictable source:

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

7. **Add anything else** through `networkPolicies.extraPolicies` - each entry is a complete
   manifest, rendered through `tpl`.

## Verify

```console
kubectl get netpol -n kasm-agent
kubectl get agents.agent.kasm.com -n kasm-agent
```

Expected indicators:

* **Seven** policies: `*-default-deny`, `*-allow-dns`, `*-allow-intra-namespace`,
  `*-allow-apiserver-egress`, `*-allow-manager-egress`, `*-allow-session-ingress`,
  `*-allow-otlp-backend-egress`; with `cilium.enabled`, one `CiliumNetworkPolicy` beside them
  (`kubectl get cnp -n kasm-agent`).
* The `Agent` resource reports **Ready**, which means it registered and its heartbeats reach the
  manager through the policies. An agent the policies cut off drops to `Progressing` with
  `Available=False WorkloadsUnavailable` (`waiting for workloads (agent=false, sessionProxy=true)`)
  within about a minute. To confirm the allow:
  `kubectl -n kasm-agent logs deploy/k8s-agent | grep heartbeat` shows no `heartbeat failed` lines
  after the policies landed, and under **Infrastructure → Agents** the agent is listed (by its
  session-proxy hostname) with its last-reported time advancing, or `get_servers` on the API shows
  `last_reported` advancing.
* The step-1 deny test times out rather than connecting. A blocked destination must **hang until the
  curl timeout**, not return a response.
* A browser session still connects (session-proxy ingress and web filtering are unaffected).

## Chart values

Under the `kasm-platform` umbrella, in a release whose `kasm-helm.enabled` is `false`
([Install in two namespaces](../install/two-namespaces.md)):

```yaml
kasm-agent:
  networkPolicies:
    enabled: true
    manager:
      ports: [443, 80, 8080, 8443]
      inCluster:
        namespace: kasm            # Cilium with an in-cluster manager; leave empty otherwise
    cilium:
      enabled: true                # Cilium with a node-hosted API server; false otherwise
    otelBackend:
      cidr: 10.42.0.0/16
```

Installing `kasm-agent` directly? Drop the `kasm-agent:` key and start at `networkPolicies:`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Agent heartbeats fail with `connection refused`; manager reports "No Agent slots available" | Policy is evaluated post-DNAT; the allow list has 443 but the traffic lands on the ingress controller's backend port | Add the backend port to `networkPolicies.manager.ports` (Traefik: `8443`) |
| Policies applied, nothing is actually blocked | The CNI does not enforce NetworkPolicy | Run the step-1 deny test; switch to Calico/Cilium/Antrea or enable your platform's policy engine |
| Telemetry stops arriving at the backend | Backend outside `networkPolicies.otelBackend.cidr`/`ports` | Widen the CIDR or add the port (OTLP 4317/4318, ClickHouse 9000) |
| Sessions launch but the browser cannot connect | Session-proxy ingress restricted by `networkPolicies.sessionProxy.from`, or the ports do not match the proxy's listeners | Keep `from: []`, and keep `sessionProxy.ports` at `[4444, 4445]` |
| Operator/agent pods log API-server timeouts | `networkPolicies.apiServer.cidr` tightened past the real endpoint | Check `kubectl get endpoints kubernetes -n default` and widen |
| Operator crash-loops the moment the policies land: `leaderelection ... context deadline exceeded`, `leader election lost`, exit 1; `cilium-dbg monitor --type drop` on the node shows `drop (Policy denied)` from the operator pod to the API server address on 6443 | Cilium: the `ipBlock` allow never matches the node that hosts the API server | `networkPolicies.cilium.enabled=true`, or Cilium's `policyCIDRMatchMode: nodes` |
| Agent logs `heartbeat failed ... context deadline exceeded` every 30 s, the `Agent` stays `Progressing` (`WorkloadsUnavailable`), the manager never lists it; `cilium-dbg monitor --type drop` shows `Policy denied` from the agent pod to the control-plane proxy pod on 8080 | Cilium: the `ipBlock` allow never matches a pod | `networkPolicies.manager.inCluster.namespace` set to the control plane's namespace |

## Decisions

- [ ] CNI enforcement proven with a default-deny probe namespace
- [ ] Agent has a namespace to itself
- [ ] `networkPolicies.enabled=true`
- [ ] `networkPolicies.manager.ports` includes the real post-DNAT backend port
- [ ] On Cilium: `manager.inCluster.namespace` for an in-cluster manager, `cilium.enabled` for a node-hosted API server
- [ ] Seven policies present in the namespace
- [ ] The `Agent` is `Ready` and its log shows no `heartbeat failed`; the manager lists the agent with its last-reported time advancing
- [ ] `apiServer`, `manager`, `otelBackend` CIDRs tightened from `0.0.0.0/0`
- [ ] A browser session still connects end to end
