# Troubleshooting

> **Applies to:** both halves

Symptoms first, because that is what you have. Most failures look identical from a browser (a 404,
a 401, a session that dies about a minute in) and are told apart only by the next command. This is
the one failures table; the how-to pages link here rather than carrying their own.

## Login works, sessions never start

| Symptom | Cause | Command or fix |
| ------- | ----- | -------------- |
| "No resources are available" | The agent is not enabled, or was enabled less than 15 seconds ago | Infrastructure → Agents → Enable; or seed `auto_agent` ([Enable agents automatically](../how-to/enable-agents-automatically.md)) |
| "Image Not Authorized" | The workspace is not assigned to the user's group | Workspaces → the image → assign the group ([Kasm docs: Workspaces](https://www.kasmweb.com/docs/latest/guide/workspaces.html), [Groups](https://www.kasmweb.com/docs/latest/guide/groups.html)) |
| Session connect returns **401** (direct-connect) | The Kasm Authorization Domain does not cover both hostnames, so the cookie is never sent to the agent | `kasm-helm.kasmConfig.authDomain` on a fresh install, Settings → Auth on an existing one; then a fresh private window ([Switch sessions to direct-connect](../how-to/networking/direct-connect.md)) |
| Session connect returns **401** (relayed) | A stale cookie from an earlier install on the same address | A fresh private window |
| Session connect returns **404** from the ingress (direct-connect) | The zone still relays: *Proxy Connections* is on, so the request carries the control plane's `Host` header and matches no route on the agent side | Infrastructure → Zones: *Proxy Connections* off, *Upstream Auth Address* = the control plane |
| Login returns 500 on a fresh install | `kasm_auth_domain` was preseeded through `config.settings` | Use `kasm-helm.kasmConfig.authDomain` instead |
| Session dies after ~60s (ingress-nginx), ~30s (OpenShift router), ~350s (AWS NLB) | The idle timeout on whatever fronts the session proxy | [Idle timeouts](../how-to/networking/loadbalancer-nodeport.md#idle-timeouts) |
| Relayed session dies at 30 minutes idle | The control-plane proxy's fixed `proxy_read_timeout 1800s` | Not a value; switch to direct-connect |
| Session spins on "connecting"; console shows WebSocket close `1006` | `1006` only means the socket closed without a close frame; it identifies no layer, and it is not evidence of a certificate problem | Check whether the handshake reached the session proxy's access log: `kubectl -n <ns> logs <session-proxy-pod> -c session-proxy` against the front end's log for the same second |
| Session proxy error log: `open() "/etc/nginx/html/container/<id>/..." failed` | The per-session nginx config does not exist yet; the sidecar writes it once the workspace Service resolves | Transient. `kubectl -n <ns> logs <session-proxy-pod> -c kasm-nginx-sidecar` shows `reloaded nginx` |
| Browser sent to a URL whose **port** nothing serves | Kasm builds session URLs from the zone's `proxy_port`, not from the Service you reached it on | Match `kasmZones[].proxy_port` (preseed) or *Proxy Port* under Infrastructure → Zones to the published port |
| Session URL is `https://` on an HTTP-only deployment | Container sessions hard-code the `https` scheme; there is no HTTP-only mode | [Certificates](../how-to/networking/certificates.md) |
| Workspace pod `ImagePullBackOff` / `NotFound` on arm64 | Workspace images are amd64 only | [Supported platforms](../explanation/supported-platforms.md#node-architecture) |
| Every session fails to launch, control plane healthy | Workspace images unreachable; they come from the **manager's** registry, not from values | [Registries and airgap](../how-to/registries-and-airgap.md) |
| Session pods `ImagePullBackOff`, agent pods fine | Only `imagePullSecrets` was set; sessions use `agent.workspaceImagePullSecrets` | [Registries and airgap](../how-to/registries-and-airgap.md) |
| Sessions launch only in one zone | `agent.zone` matches no `kasmZones` name | `kubectl -n <agent-ns> get agent -o jsonpath='{.items[*].status.zone}'` |

## The agent never becomes Ready

```console
kubectl -n kasm-agent get agent k8s-agent \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{.reason}{"\n"}{end}'
```

Expected on a healthy agent: `Available=True AgentRegistered` and `Degraded=False AsExpected`. A
phase short of `Ready` is one of:

| Cause | Check |
| ----- | ----- |
| The manager token Secret is missing or wrong | `kubectl -n <ns> get secret <existingTokenSecret>`; the two-namespace layout needs the copy |
| The manager is unreachable from the cluster | `kubectl -n <ns> logs deploy/<agent>`; with NetworkPolicies on, `networkPolicies.manager.ports` must carry the post-DNAT port (Traefik 8443, or 8080 for the in-cluster proxy) |
| The agent image tag is out of step with the control plane's `manager/agent_version` | A registration failure in the agent log; align the versions ([Day 2](../how-to/day-2.md)) |
| `Degraded=True` with `TLSRouteForbidden` or `TLSRouteUnavailable` | The operator cannot manage TLSRoutes: its `manager-role` lacks the rule, or the CRD is not served. Sessions keep working; only `agent.gatewayRoute` is unfulfilled | Upgrade the operator chart (a `helm upgrade` re-applies its RBAC) or install Gateway API 1.5+ |

## External access

| Symptom | Cause | Command or fix |
| ------- | ----- | -------------- |
| `EXTERNAL-IP` stays `<pending>` | No load-balancer controller; or, on k3s, ServiceLB cannot bind 443 because Traefik holds it | `kubectl get svc -A \| grep LoadBalancer`; use `NodePort` or an Ingress on k3s |
| Control-plane install rejected with a port conflict | `kasm-helm.proxyService.type=LoadBalancer` or `NodePort` alongside an Ingress, Route or Gateway route | Set it to `ClusterIP` |
| Ingress has no `ADDRESS` | No controller claimed it: wrong class name, or no controller running | `kubectl get ingressclass` |
| `HTTPRoute`/`TLSRoute` shows `Accepted=False` (`NotAllowedByListeners`) | The Gateway listener does not admit the namespace, or the hostname does not match | Fix the listener's `allowedRoutes` and `hostname`; with two namespaces admit both |
| `ResolvedRefs=False` | A backend that does not exist, usually a zone-name mismatch | Compare the route's `backendRefs` with `kubectl get svc` |
| Gateway shows `Accepted`/`Programmed`, connections hang | Observed on the host-network Cilium Gateway (Cilium 1.20 / kubeadm 1.34): correct config, no traffic | Prove with `curl`, not status; the Traefik chart on host ports worked on the same cluster |
| `TLSRoute` not recognised, or `no matches for kind "TLSRoute" in version …/v1alpha2` | Gateway API older than 1.5, or an old version rendered | Install 1.5+; the chart selects `v1` automatically, else set `agent.tlsRoute.apiVersion` |
| `TCPRoute` `Accepted=True`, no traffic | The implementation does not serve TCPRoute | Use `directRdpService` ([Publish the RDP gateway](../how-to/networking/rdp-gateway.md)) |
| Browser certificate warning on the session hostname | Passthrough serves the session proxy's certificate, which does not cover the hostname, or the self-signed default is still in place | Add the hostname and `*.<hostname>` to `agent.sessionProxy.certificate.dnsNames`, or pre-create `kasm-session-proxy-tls` |
| cert-manager Certificate stuck at `READY False` | Almost always the ACME challenge | `kubectl -n <ns> describe certificate <name>` |
| Route rendered with no TLS column | `route.tls` left empty | Set at least `termination` |
| NodePort answers in-cluster, refused from a LAN client | The environment does not route 30000 to 32767 to the nodes | Open the range, or front the proxy with an ingress or load balancer |
| Everything breaks the moment PROXY protocol is enabled | The fronting proxy is not sending a PROXY header | Enable it on the load balancer too, or turn `agent.sessionProxy.proxyProtocol.enabled` off |
| Some clients time out with `externalTrafficPolicy: Local` | Traffic routed via a node with no session-proxy pod | Raise `agent.sessionProxy.replicas`, pin with `nodeSelector`, or use a load balancer that honours the health check |

## Pods will not start

| Status | Cause | Check |
| ------ | ----- | ----- |
| `ImagePullBackOff` | A registry override missed one component, or a pull secret is absent | `kubectl -n kasm get pods --field-selector=status.phase!=Running` |
| `CreateContainerConfigError` | A referenced Secret or ConfigMap does not exist | `kubectl -n kasm describe pod <pod> \| tail -20` |
| `Pending`, no events about resources | No node matches the selector; often `agent.workspacesNodeSelector` against unlabelled nodes | `kubectl get nodes --show-labels` |
| DaemonSet `DESIRED 3 / CURRENT 0`, `FailedCreate … violates PodSecurity` | Pod Security admission on the namespace | [Privileged workloads and cluster policy](../how-to/nodes/privileged-workloads.md) |
| Only the egress installer is rejected, with a host-namespaces message | A `disallow-host-namespaces` policy-engine rule, beyond the `privileged` label | A scoped exception, or accept the workload outside the baseline |
| Control plane loses connectivity right after enabling `networkPolicies` | The baseline was enabled in a namespace shared with the control plane | Turn it off there ([Deployment topologies](../explanation/topologies.md#one-release-or-two-namespaces)) |
| Agent heartbeats `connection refused` after enabling `networkPolicies`; "No Agent slots available" | Policy is evaluated after DNAT; the allow list lacks the backend port | Add it to `networkPolicies.manager.ports` |

## The database

```console
kubectl -n kasm get job -l app.kubernetes.io/component=db-init
```

Expected: `kasm-db-init   Complete   1/1`. Stuck at `0/1` with `could not translate host name` is
DNS or NetworkPolicy reaching an external database, not credentials; stuck with an authentication
error is credentials. A completed Job on a database that already had a schema does nothing, which
is correct: preseeding applies only at initialization ([Database](../how-to/database.md)).

## Uninstall and upgrade

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `Agent` or `KasmWorkspace` deletion hangs after `helm uninstall` | The operator that clears the finalizer is gone | Reinstall the operator chart to reap it; next time delete the custom resources first ([Day 2](../how-to/day-2.md#uninstall)) |
| `rendered manifests contain a resource that already exists … invalid ownership metadata` installing `kasm-agent-crds` | The CRDs came from a `crds/` install with no Helm metadata | Adopt them first ([Install the CRDs as their own release](../how-to/install/crds.md)) |
| Fields vanish from custom resources after a rollback | `helm rollback` of the CRD release reinstated an older schema | Never roll that release back; roll forward |

## Rendering fails before anything is created

The charts refuse contradictory values at render time rather than in the cluster, and the message
names the values:

```console
$ helm upgrade --install kasm oci://registry-1.docker.io/kasmweb/kasm-platform -f values.yaml
Error: execution error at (kasm-helm/templates/validation.yaml:8:4): Only one proxy exposure
method may be enabled, but ingress.enabled and httpRoute.enabled are set. ...
```

Two exposure mechanisms on one half, `LoadBalancer` beside a front end, `directRdpService` beside
`tcpRoute`, `httpRoute` or `tlsRoute` with empty `parentRefs`, an egress `distro` the chart does not
know with no `cniBinDir`, `sourcePath` with `method: kmm`, and KMM signing with a missing Secret
all fail this way. These are working as intended: fix the values.
