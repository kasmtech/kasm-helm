> **Applies to:** both halves · **See also:** each networking page carries its own "Most likely failures"

# Troubleshooting

Symptoms first, because that is what you have. Most Kasm-on-Kubernetes failures look identical from
a browser — a 404, a 401, or a session that dies about a minute in — and are told apart only by
which command you run next.

## Login works, sessions never start

| Symptom | Likely cause | Check |
| ------- | ------------ | ----- |
| Session request returns 401, or the browser silently loses the session | `kasmConfig.authDomain` does not cover both hostnames, so the login cookie is never sent to the agent | `kubectl -n kasm exec deploy/kasm-api -- env \| grep -i auth_domain` |
| Session starts, then dies after ~60s | Websocket idle timeout on whatever fronts the session proxy | The controller's timeout annotation, or the LB's L4 idle timeout — [Idle timeouts](../planning/networking/loadbalancer-nodeport.md#idle-timeouts) |
| Session spins on "connecting" forever; console shows WebSocket close `1006` | `1006` only means the socket closed without a close frame — it does **not** identify the layer. Check whether the handshake reached the session proxy's access log: if it did, something answered with a non-101 status; if it did not, look at whatever sits in front (ingress controller, load balancer) | Compare `kubectl -n <ns> logs <session-proxy-pod> -c session-proxy` against the ingress controller's log for the same second |
| Session URL is `https://` on an HTTP-only deployment | Expected: container/KasmVNC sessions hard-code the `https` scheme. There is no HTTP-only mode | [TLS is not optional](../planning/networking/certificates.md#tls-is-not-optional-for-container-sessions) |
| Every session fails to launch, control plane healthy | Workspace images unreachable — they come from the **manager's** registry, not from chart values | [Airgap → workspace images](../planning/airgap.md#3-workspace-images) |
| Sessions launch only in one zone | `agent.zone` does not match a `kasmZones` name | `kubectl -n <agent-ns> get agent -o jsonpath='{.items[*].status.zone}'` |

## A session will not start

Three distinct causes present almost identically — a session that spins on "connecting". The pod
state and the session proxy's **error** log tell them apart in one look:

| What you see | Cause | Confirm with |
| ------------ | ----- | ------------ |
| Session proxy error log: `open() "/etc/nginx/html/container/<id>/..." failed` | The per-session nginx config does not exist **yet**. The sidecar writes it only once the workspace Service resolves, so there is a window after launch where requests 404. Transient — it self-heals. | `kubectl -n <ns> logs <session-proxy-pod> -c kasm-nginx-sidecar` — wait for `reloaded nginx` / `session ready` |
| Browser sent to a URL whose **port** nothing serves | Kasm builds session URLs from the zone's `proxy_port`, not from the Service you reached it on. Publishing on a node port or a non-443 mapping without matching the zone sends users nowhere. | Compare the session URL's port against `select proxy_port from zones;` |
| Workspace pod `ImagePullBackOff` / `NotFound` | Architecture. Workspace images are amd64-only — see [Supported platforms](../planning/support.md#node-architecture) | `kubectl -n <ns> describe pod <kws-pod>` |

A WebSocket close code of **`1006`** does not identify which of these you have — it only means the
socket closed without a close frame. It is **not** evidence of a certificate problem: a
clicked-through self-signed certificate does complete `wss://` handshakes (verified on Chrome 152).

## The agent never becomes ready

```console
$ kubectl -n kasm-agent get agent -o wide
NAME        PHASE   ZONE    AGE
k8s-agent   Ready   zonea   6m
```

A phase short of `Ready` is one of: the manager token Secret missing or wrong, the manager
unreachable from the cluster, or the operator lacking a permission it needs. The operator's
conditions say which:

```console
$ kubectl -n kasm-agent get agent k8s-agent \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{.reason}{"\n"}{end}'
Available=True   AgentRegistered
Degraded=False   AsExpected
```

`Degraded=True` with a `TLSRoute*` reason is the Gateway API path, not the agent itself — see
[Gateway API](../planning/networking/gateway-api.md).

## Pods will not start

| Status | Cause | Check |
| ------ | ----- | ----- |
| `ImagePullBackOff` | A registry override missed one component, or a pull secret is absent | `kubectl -n kasm get pods --field-selector=status.phase!=Running` |
| `CreateContainerConfigError` | A referenced Secret or ConfigMap does not exist | `kubectl -n kasm describe pod <pod> \| tail -20` |
| `Pending`, no events about resources | No node matches the selector — often `agent.workspacesNodeSelector` against unlabelled nodes | `kubectl get nodes --show-labels` |
| Privileged pods rejected outright | Pod Security admission on the namespace | [Privileged workloads](../planning/nodes/privileged-workloads.md) |

## The database

```console
$ kubectl -n kasm get job -l app.kubernetes.io/component=db-init
NAME           STATUS     COMPLETIONS   DURATION   AGE
kasm-db-init   Complete   1/1           47s        8m
```

Stuck at `0/1` with `could not translate host name` is DNS or NetworkPolicy reaching an external
database — not credentials. Stuck with an authentication error is credentials. A completed job on a
database that already had a schema does nothing, which is correct: preseeding only applies at
initialization ([Database](../planning/database.md#seeding-at-initialization)).

## External access

Each mechanism page ends with its own failure table, because the diagnosis differs:

* [Ingress](../planning/networking/ingress.md) — an empty `ADDRESS` means no controller claimed it.
* [Gateway API](../planning/networking/gateway-api.md) — `Accepted=False` is the listener refusing
  the namespace; `ResolvedRefs=False` is a backend that does not exist.
* [LoadBalancer and NodePort](../planning/networking/loadbalancer-nodeport.md) — `<pending>` means
  no load-balancer controller.
* [OpenShift Route](../planning/networking/openshift-route.md) — an empty TLS column means the
  Route was rendered with no TLS stanza.

Certificates are the cross-cutting one: [Certificates](../planning/networking/certificates.md) has
the command that prints what was actually issued, which is often not what was asked for.

## Rendering fails before anything is created

The charts refuse contradictory values at render time rather than in the cluster. The message names
the values:

```console
$ helm upgrade --install kasm oci://registry-1.docker.io/kasmweb/kasm-platform -f values.yaml
Error: execution error at (kasm-helm/templates/validation.yaml:8:4): Only one proxy exposure
method may be enabled, but ingress.enabled and httpRoute.enabled are set. ...
```

These are working as intended — fix the values, do not work around them.
