# Kasm Agent Instance

![Version: 1.1200.0-develop](https://img.shields.io/badge/Version-1.1200.0--develop-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

Creates the Agent custom resource (agent.kasm.com/v1alpha1) that the Kasm agent operator reconciles into a Kubernetes-native Kasm agent and session proxy, plus its satellite objects - the manager token Secret, a cert-manager Certificate, a KasmImagePuller, and a Gateway API HTTPRoute, a classic Ingress or an OpenShift Route. Deployed as a subchart of the kasm-agent umbrella chart under the `agent` alias.

**Homepage:** <https://kasm.com>

> **Part of the [`kasm-agent`](../kasm-agent/README.md) umbrella.** This chart creates the `Agent`
> custom resource and normally ships as the `agent` dependency of the
> [`kasm-agent`](../kasm-agent/README.md) chart (or the full-stack
> [`kasm-platform`](../kasm-platform/README.md) chart), which also installs the operator that
> reconciles it. Install it standalone only to add an agent instance to a cluster whose operator
> already exists.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## Documentation

Please see our [official documentation site](https://docs.kasm.com) for more information.

> **Note:** Make sure to select the correct Kasm Workspaces version in the top-right version selector on the documentation site to ensure the guides match your deployment.

This repository's own documentation starts at the [documentation index](../../docs/README.md); this page is the chart reference.

## Prerequisites

* Kubernetes 1.26 or newer — the shared floor for the whole `kasm-agent` family (older versions of Kubernetes may work, however, we try to keep this chart updated to [supported versions of Kubernetes](https://kubernetes.io/releases/))
* Helm 3.18.x or newer ([installation](https://helm.sh/docs/helm/helm_install/))
* The Kasm agent operator (a build from 2026-09-08 or later, which no longer caches Secrets), and its `agent.kasm.com` CRDs, installed in the cluster. This chart creates custom resources; it does not install the controller that reconciles them. It does stamp the one namespaced permission the operator needs here, a Role letting it read, create and update the per-workspace storage-mapping Secrets (`operatorRBAC.*`); when the operator runs in a different namespace from this agent, set `operatorRBAC.serviceAccount.namespace` to that namespace.
* A reachable Kasm control plane, and the shared manager token for it.
* [cert-manager](https://cert-manager.io/) when `sessionProxy.certificate.enabled` is set, the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs plus a Gateway when `httpRoute.enabled` is set, the Gateway API CRDs at 1.5 or newer (`TLSRoute` is standard-channel `v1` there; older experimental-channel bundles also work) plus a Gateway with a `Passthrough` TLS listener when either `gatewayRoute.enabled` or `tlsRoute.enabled` is set, an ingress controller when `ingress.enabled` is set, and OpenShift (the `route.openshift.io` API) when `route.enabled` is set.

## What this chart deploys

* An `Agent` custom resource. The operator reconciles it into the agent Deployment, the session-proxy Deployment, and a session-proxy Service named `<name>-session-proxy`. None of those are created by this chart.
* A `Secret` holding the manager token, only when the token is supplied inline via `manager.token`. Referencing an existing Secret through `manager.existingTokenSecret` is preferred and takes precedence.
* The session proxy's TLS `Secret`, named by `sessionProxy.certSecretName` (`kasm-session-proxy-tls`), self-signed, whenever `sessionProxy.selfSigned.enabled` is true and `sessionProxy.certificate.enabled` is false. The template looks that Secret up at render time and does one of three things: no Secret of that name exists, so it generates one (also the `helm template` and `--dry-run` path); the Secret exists and this release owns it, so it reuses the bytes, regenerating them only when the `self-signed-for` marker no longer matches `publicHostname`; the Secret exists and someone else created it, so it renders nothing and the proxy mounts that Secret as-is. Pre-create the Secret before the first install to bring your own certificate.
* Optionally, a cert-manager `Certificate` for the session proxy's HTTPS listener, a `KasmImagePuller` that pre-stages workspace images on every node, and - to expose the session proxy at the agent's public hostname - one of a Gateway API `HTTPRoute`, a Gateway API `TLSRoute`, a classic `networking.k8s.io/v1` `Ingress`, or an OpenShift `Route`. The `TLSRoute` can instead be delegated to the operator via `gatewayRoute`, in which case this chart creates no route object of its own. The session-proxy Service can also be published directly, without any of those, through `sessionProxy.service`.

## External access

The session-proxy Service the operator creates is a `ClusterIP` by default, reachable only inside the cluster. This chart offers five mutually exclusive ways to publish it at `publicHostname`:

* `httpRoute.enabled` renders a Gateway API `HTTPRoute` attached to the Gateways in `httpRoute.parentRefs`. The Gateway's listener has to allow routes from this namespace. Only the `parentRefs` cross namespaces, so no `ReferenceGrant` is needed.
* `ingress.enabled` renders a `networking.k8s.io/v1` `Ingress` on `ingress.className`, with one `/` `Prefix` rule per entry in `ingress.hosts`, TLS from `ingress.tls`, and annotations from `ingress.annotations` merged over `commonAnnotations`.
* `route.enabled` renders an OpenShift `route.openshift.io/v1` `Route` for `route.host`, the native option on OpenShift.
* `gatewayRoute.enabled` asks the **operator** to create a Gateway API `TLSRoute` - SNI-based TLS passthrough, the same end-to-end shape as the OpenShift `Route` but on any cluster with the Gateway API.
* `tlsRoute.enabled` renders that same passthrough `TLSRoute` **from this chart** instead.

All five default their hostname to `publicHostname`, and **at most one may be enabled**: all of them front the same Service, so enabling two gives one hostname two owners. The chart fails the render with an explicit message naming the colliding values rather than letting the conflict reach the cluster. `httpRoute` and `tlsRoute` are also refused with an empty `parentRefs`, because the route would attach to no Gateway and the session proxy would stay unreachable.

Or skip the ingress layer entirely and publish the session-proxy Service itself - see below.

### `gatewayRoute` vs `tlsRoute`: who owns the route

Both produce a `TLSRoute` doing SNI-based passthrough to the session proxy, and both need the same things from the cluster: the `TLSRoute` CRD (standard-channel `v1` since Gateway API 1.5, which needs Kubernetes 1.31 or newer; the chart-managed route falls back to `v1alpha2` on older experimental-channel installs, see `tlsRoute.apiVersion`) and a Gateway listener with `protocol: TLS` and `tls.mode: Passthrough` whose `allowedRoutes` admits this namespace. What differs is ownership.

* `gatewayRoute`: the **operator** creates and reconciles the route alongside the session-proxy Service it already owns, so the two cannot drift apart. `gatewayRoute.parentRef` is a **single** reference, and `parentRef.name` is required whenever `gatewayRoute.enabled` is true (templating fails without it). Leave `gatewayRoute.hostnames` empty: the operator defaults it to `[publicHostname]`. Prefer this when the operator supports it.
* `tlsRoute`: the route is a Helm-release object, owned by the release and torn down with it. It takes a list of `parentRefs`, defaults `hostnames` to `publicHostname`, and exposes `backendPort` (4444, the proxy's own HTTPS listener). Reach for it when the operator predates `spec.gatewayRoute`, or when release tooling has to own the route.

```yaml
gatewayRoute:
  enabled: true
  parentRef:
    name: traefik-gateway
    namespace: kube-system
    sectionName: tls-passthrough   # optional: pick one listener on the Gateway
```

### LoadBalancer / NodePort: no ingress layer at all

`sessionProxy.service` is passed through to the `Agent`, and the operator applies it to the session-proxy Service it owns. The whole block is omitted from the resource while it holds nothing but defaults, so leaving it alone keeps the plain `ClusterIP`; any single non-default value pulls it in.

```yaml
sessionProxy:
  service:
    type: NodePort
    externalTrafficPolicy: Local   # real client IPs; routes only through nodes running a proxy pod
    httpsNodePort: 30443           # the proxy's own TLS listener (4444)
    httpNodePort: 30080            # plain HTTP (4445), for TLS terminated in front
```

```yaml
sessionProxy:
  service:
    type: LoadBalancer
    externalTrafficPolicy: Local
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: external
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

`httpsNodePort` and `httpNodePort` must fall inside the cluster's node-port range: the CRD rejects anything outside 30000-32767. They are only worth pinning when a firewall rule or an external load balancer has to be aimed at a fixed port; the operator carries allocated ports across reconciles, so an unpinned NodePort stays stable anyway. `sessionProxy.proxyProtocol.enabled` (with `trustedCIDRs`, the fronting load balancer's source range) turns on PROXY protocol on both nginx listeners; it is all-or-nothing, so anything that connects without a PROXY header then fails on those listeners. Client-IP preservation, NodePort reachability and the NetworkPolicy interaction are in [Publish with a LoadBalancer or NodePort](../../docs/how-to/networking/loadbalancer-nodeport.md).

### Where TLS terminates

The session proxy listens on two ports: 4445 is plain HTTP, and 4444 is its own HTTPS listener, served with the certificate in `sessionProxy.certSecretName`.

`httpRoute` and `ingress` both default to backend port 4445 - TLS for the public hostname terminates at the Gateway or the Ingress. Routing them to 4444 instead means telling the controller to speak TLS upstream (`nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` on ingress-nginx).

The `Route` defaults to `passthrough` termination, matching the Kasm operator's OpenShift example: the router forwards the TLS connection untouched, so browsers see the session proxy's certificate directly. That certificate therefore has to be valid for `route.host` - enable `sessionProxy.certificate` or provision `sessionProxy.certSecretName` out of band before using it. `route.backendPort` follows the termination mode when left empty: 4444 for `passthrough` and `reencrypt`, 4445 for `edge`, which terminates at the router instead. `reencrypt` additionally accepts a `route.tls.destinationCACertificate` for validating the proxy's certificate, and `edge` accepts `route.tls.key`/`certificate` plus an `insecureEdgeTerminationPolicy` of `Redirect`.

Both `TLSRoute` options - operator-managed `gatewayRoute` and chart-managed `tlsRoute` - are passthrough too, and for the same reason browsers end up validating the session proxy's own certificate, but through the Gateway API rather than the OpenShift router. They are what to reach for when you want end-to-end TLS on a cluster that is not OpenShift. The Gateway matches on SNI alone and splices the connection through without decrypting it, which is why `tlsRoute.backendPort` defaults to 4444 (nothing terminates TLS earlier, so the plain-HTTP listener would never work) and why the proxy's certificate has to cover every hostname in force - whether set explicitly or defaulted to `publicHostname`. Both require support on the Gateway side that the `HTTPRoute` path does not: `TLSRoute` is standard-channel `v1` since Gateway API 1.5 (experimental-only, as `v1alpha2`, on older bundles), and the Gateway needs a listener declared with `protocol: TLS` and `tls.mode: Passthrough` - a normal terminating HTTPS listener will not serve it.

Publishing the Service directly through `sessionProxy.service` leaves TLS wherever you put it: point an external load balancer at the HTTPS listener (4444) for end-to-end TLS to the proxy's own certificate, or at the plain-HTTP one (4445) when TLS is terminated in front.

### Websockets and timeouts

Kasm sessions are long-lived VNC websockets, so whatever terminates them must allow websocket upgrades and use timeouts of at least 3600s. Otherwise sessions are dropped mid-use at the default timeout - 60 seconds on ingress-nginx, 30 seconds on the OpenShift router:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  tls:
    - secretName: kasm-agent-public-tls
      hosts:
        - agent.example.com
```

```yaml
route:
  enabled: true
  annotations:
    haproxy.router.openshift.io/timeout: "3600s"
```

The two passthrough routes (`gatewayRoute`, `tlsRoute`) and direct `sessionProxy.service` exposure have no equivalent knob, because nothing on the path speaks HTTP: there is no upgrade to allow and no HTTP read timeout to raise. What bounds a session there is the **layer-4 idle timeout** of the Gateway's data plane or of the load balancer in front of it — an AWS NLB's 350s default, for instance, will still cut idle sessions, so raise it the same way.

## Required values

Three values have no default and must be set, unless `inClusterControlPlane: true` derives them from a `kasm-helm` release of the same name in the same namespace:

* `manager.hostname` - the Kasm manager (or the proxy in front of it) this agent registers with.
* exactly one of `manager.existingTokenSecret` or `manager.token` - the registration token.
* `publicHostname` - the externally reachable address browsers use to connect to this agent's session proxy.

Templating fails with a specific message when any of these is missing. `sessionProxy.certSecretName` is not one of them: the chart generates a self-signed Secret at that name unless one already exists (see [What this chart deploys](#what-this-chart-deploys)).

## Environment variables

`spec.env` on the Agent is assembled in this order:

1. `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE`, when `otel.enabled` is true.
2. `KASM_GPU_OPERATOR_ENABLED`, when `gpu.enabled` is true.
3. Everything in the `env` list, verbatim.

The operator merges environment variables by name, so an entry in `env` that reuses one of the generated names overrides it.

## Chart value settings in `values.yaml`

## Values

<table>
	<thead>
		<th>Key</th>
		<th>Type</th>
		<th>Default</th>
		<th>Description</th>
	</thead>
	<tbody>
		<tr>
			<td id="agentLabels"><a href="./values.yaml#L33">agentLabels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Extra Kubernetes labels the operator stamps onto every workload it creates for this agent: the agent Deployment, the session proxy, and their Services and RBAC. Added to each object's metadata.labels, never to the immutable pod selectors. Distinct from workspaceLabels (the session pods), so the agent's own workloads and its workspaces can be tracked separately. </td>
		</tr>
		<tr>
			<td id="apiServerURL"><a href="./values.yaml#L590">apiServerURL</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Split-horizon override for the base URL the agent uses for manager ADMIN calls (for example file-mapping fetches). Defaults to `manager.scheme://manager.hostname:manager.port` when empty. Set it when agents should reach the manager on an internal address (an in-cluster Service, a private LB) while `manager.hostname` stays the public name — e.g. `https://kasm-proxy.kasm.svc.cluster.local`. Omitted from the Agent resource when empty. </td>
		</tr>
		<tr>
			<td id="commonAnnotations"><a href="./values.yaml#L43">commonAnnotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to apply to every resource created by this chart. </td>
		</tr>
		<tr>
			<td id="commonLabels"><a href="./values.yaml#L26">commonLabels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to apply to every resource created by **this chart** (the Agent custom resource, its RBAC, the session-proxy TLS Secret). These do NOT reach the workloads the operator creates from the Agent CR -- use agentLabels and workspaceLabels for those. </td>
		</tr>
		<tr>
			<td id="env"><a href="./values.yaml#L617">env</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional environment variables appended to the Agent's `spec.env`, as a list of Kubernetes EnvVar objects. The operator merges environment variables by name, so an entry here with the same name as one this chart generates (for example `OTEL_EXPORTER_OTLP_ENDPOINT`) wins. </td>
		</tr>
		<tr>
			<td id="fullnameOverride"><a href="./values.yaml#L10">fullnameOverride</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Fully override the generated name prefix for the satellite objects. When set, those names are derived from this instead of from the release name and the chart name. </td>
		</tr>
		<tr>
			<td id="gatewayRoute"><a href="./values.yaml#L938">gatewayRoute</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
hostnames: []
parentRef:
    name: ""
    namespace: ""
    sectionName: ""
</pre>
</div>
			</td>
			<td>Optionally have the OPERATOR create the Gateway API TLSRoute, rather than rendering one from this chart. Same end result as `tlsRoute` - SNI-based TLS passthrough to the session proxy's own certificate - but the operator owns the route: it creates it, reconciles it, and keeps it aligned with the session-proxy Service it also owns, so the two cannot drift apart. `tlsRoute` is the chart-managed equivalent, for operator builds that predate this field or when the route has to live in the Helm release (owned by it, torn down with it, patched by other release tooling) rather than under the operator's ownership. Prefer this one whenever the operator supports it. The whole block is omitted from the Agent resource when disabled. </td>
		</tr>
		<tr>
			<td id="gatewayRoute--enabled"><a href="./values.yaml#L945">gatewayRoute.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Have the operator create the TLSRoute. Same cluster-side prerequisites as `tlsRoute`: the TLSRoute CRD (standard channel since Gateway API 1.5), and a Gateway with a `protocol: TLS` / `tls.mode: Passthrough` listener whose `allowedRoutes` admits this namespace. `httpRoute`, `ingress`, `route`, `tlsRoute` and `gatewayRoute` are alternatives - enable at most one of the five, since all of them point at the same session-proxy Service. Between the two passthrough options, prefer `gatewayRoute` when the operator supports it and fall back to `tlsRoute` when it does not.</td>
		</tr>
		<tr>
			<td id="gatewayRoute--hostnames"><a href="./values.yaml#L969">gatewayRoute.hostnames</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>SNI hostnames the route matches. Unlike `tlsRoute.hostnames`, which this chart defaults, these are defaulted by the *operator* to `[publicHostname]`, so leaving this empty is the normal case - it is omitted from the Agent resource and the operator fills it in. The session proxy's own certificate (`sessionProxy.certSecretName`) still has to cover whatever names end up in force, since the connection reaches it undecrypted. Example:   hostnames:     - agent.example.com     - alt.example.com</td>
		</tr>
		<tr>
			<td id="gatewayRoute--parentRef"><a href="./values.yaml#L948">gatewayRoute.parentRef</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
name: ""
namespace: ""
sectionName: ""
</pre>
</div>
			</td>
			<td>The single Gateway the operator attaches the TLSRoute to. Note the shape differs from `tlsRoute.parentRefs`: the CRD takes one reference, not a list.</td>
		</tr>
		<tr>
			<td id="gatewayRoute--parentRef--name"><a href="./values.yaml#L951">gatewayRoute.parentRef.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>REQUIRED when `gatewayRoute.enabled` is true. Name of the Gateway resource. Templating fails when it is empty, since the CRD rejects the resource without it.</td>
		</tr>
		<tr>
			<td id="gatewayRoute--parentRef--namespace"><a href="./values.yaml#L954">gatewayRoute.parentRef.namespace</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Namespace of the Gateway. Omitted from the Agent resource when empty, which lets the operator default it to the Agent's own namespace.</td>
		</tr>
		<tr>
			<td id="gatewayRoute--parentRef--sectionName"><a href="./values.yaml#L959">gatewayRoute.parentRef.sectionName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Selects one specific listener on the Gateway, by its `name`, in place of every listener that would otherwise accept the route. Use it when the Gateway carries more than one listener and only one of them is the `Passthrough` TLS listener. Omitted from the Agent resource when empty.</td>
		</tr>
		<tr>
			<td id="global"><a href="./values.yaml#L14">global</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
cattle:
    systemDefaultRegistry: ""
</pre>
</div>
			</td>
			<td>Values Helm shares with every chart in a release. Rancher fills in `global.cattle.*` on every install from its catalog; nothing here needs to be set by hand.</td>
		</tr>
		<tr>
			<td id="global--cattle--systemDefaultRegistry"><a href="./values.yaml#L20">global.cattle.systemDefaultRegistry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The registry Rancher configured as the cluster's system default registry (air-gapped and mirrored clusters). When set, it replaces the registry part of every image this chart renders and `image.registry` is ignored, following Rancher's convention. Rancher sets it on install from its catalog; leave it empty everywhere else.</td>
		</tr>
		<tr>
			<td id="gpu"><a href="./values.yaml#L609">gpu</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
</pre>
</div>
			</td>
			<td>GPU workspace support. </td>
		</tr>
		<tr>
			<td id="gpu--enabled"><a href="./values.yaml#L611">gpu.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Tell the agent that the NVIDIA GPU operator is installed, so it can schedule GPU workspaces.</td>
		</tr>
		<tr>
			<td id="heartbeatIntervalSeconds"><a href="./values.yaml#L410">heartbeatIntervalSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
5
</pre>
</div>
			</td>
			<td>How often the agent heartbeats the manager. </td>
		</tr>
		<tr>
			<td id="httpRoute"><a href="./values.yaml#L772">httpRoute</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
backendPort: 4445
enabled: false
hostnames: []
parentRefs: []
</pre>
</div>
			</td>
			<td>Optionally expose the operator-created session-proxy Service through a Gateway API Gateway. </td>
		</tr>
		<tr>
			<td id="httpRoute--backendPort"><a href="./values.yaml#L790">httpRoute.backendPort</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
4445
</pre>
</div>
			</td>
			<td>Port on the session-proxy Service to forward to. The default, 4445, is the proxy's plain-HTTP listener; TLS for the public hostname is expected to terminate at the Gateway. Use 4444 to forward to the proxy's own HTTPS listener instead.</td>
		</tr>
		<tr>
			<td id="httpRoute--enabled"><a href="./values.yaml#L776">httpRoute.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Render the HTTPRoute. Requires the Gateway API CRDs and a Gateway in the cluster. `httpRoute`, `ingress`, `route`, `tlsRoute` and `gatewayRoute` are alternatives - enable at most one of the five, since all of them point at the same operator-created session-proxy Service.</td>
		</tr>
		<tr>
			<td id="httpRoute--hostnames"><a href="./values.yaml#L786">httpRoute.hostnames</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Hostnames the route matches. Defaults to a single-entry list holding `publicHostname` when empty.</td>
		</tr>
		<tr>
			<td id="httpRoute--parentRefs"><a href="./values.yaml#L783">httpRoute.parentRefs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Gateways to attach the route to, as a list of `{name, namespace}` objects. The route attaches to nothing - and the session proxy stays unreachable through the Gateway - if this is left empty. Example:   parentRefs:     - name: traefik-gateway       namespace: kube-system</td>
		</tr>
		<tr>
			<td id="image"><a href="./values.yaml#L76">image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/kasm-agent-api
tag: ""
</pre>
</div>
			</td>
			<td>The Kasm agent API container image, deployed by the operator as `spec.image`. </td>
		</tr>
		<tr>
			<td id="image--registry"><a href="./values.yaml#L78">image.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
docker.io
</pre>
</div>
			</td>
			<td>Registry that hosts the agent image.</td>
		</tr>
		<tr>
			<td id="image--repository"><a href="./values.yaml#L80">image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmweb/kasm-agent-api
</pre>
</div>
			</td>
			<td>Repository of the agent image, without the registry or tag.</td>
		</tr>
		<tr>
			<td id="image--tag"><a href="./values.yaml#L82">image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag of the agent image. Leave empty to fall back to the chart's `appVersion`.</td>
		</tr>
		<tr>
			<td id="imageAvailabilityPolicy"><a href="./values.yaml#L417">imageAvailabilityPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
pulled
</pre>
</div>
			</td>
			<td>Which workspace images the agent reports to the manager as available, one of `pulled` or `all`. `pulled` (default) reports only images the puller has actually staged on a node, so the manager routes a workspace here only when it can start with no launch-time pull; `all` also reports catalog images not staged yet, for optimistic routing that pulls the image on demand at launch. </td>
		</tr>
		<tr>
			<td id="imagePullPolicy"><a href="./values.yaml#L431">imagePullPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
IfNotPresent
</pre>
</div>
			</td>
			<td>Pull policy applied to the agent and session-proxy containers. </td>
		</tr>
		<tr>
			<td id="imagePullSecrets"><a href="./values.yaml#L440">imagePullSecrets</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Pull secrets for the agent and session-proxy images, as a list of `{name: <secret>}` references. Omitted from the Agent resource entirely when empty. </td>
		</tr>
		<tr>
			<td id="imagePuller"><a href="./values.yaml#L624">imagePuller</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
extraImages: []
refreshIntervalSeconds: 0
resources: {}
storage:
    evictionPercent: ""
    maxConcurrentPulls: ""
    reservedBytes: ""
    reservedPercent: ""
    unpackFactor: ""
</pre>
</div>
			</td>
			<td>Pre-pull workspace images onto the session nodes, so the first session using an image on a node starts without a cold registry pull. The agent maintains one KasmImagePuller for this agent, from the manager's advertised catalog plus any `extraImages`; the operator reconciles it into a DaemonSet on the same nodes workspaces run on (`workspacesNodeSelector`/`workspacesTolerations`). </td>
		</tr>
		<tr>
			<td id="imagePuller--enabled"><a href="./values.yaml#L631">imagePuller.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Pre-pull workspace images. Keep this on (the default): it is what makes session start fast and pull-free, and the default `imageAvailabilityPolicy: pulled` depends on it (the manager only sends a session to a node once the image is staged there, so with the puller off no node ever reports an image and sessions stop scheduling). Turn it off only to run on demand — set `imageAvailabilityPolicy: all` alongside — e.g. to relieve node disk pressure from a large catalog, or when images are already resident on the nodes (a baked node image or a local registry mirror).</td>
		</tr>
		<tr>
			<td id="imagePuller--extraImages"><a href="./values.yaml#L651">imagePuller.extraImages</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Images to stage in addition to the manager's advertised catalog, to pre-seed a custom workspace image the manager has not listed yet. A list of `{image, registry, imagePullSecrets, priority}` objects: `image` is the full reference and is authoritative for the pull; `registry` is informational; `imagePullSecrets` is an optional per-image list of `{name: <secret>}` references; `priority` (integer, default 0 = lowest) orders the pull on each node — higher pulls first, so pre-seeding a catalog image with a high priority pulls it ahead of the rest. Whether they all staged is reported on the Agent's `ExtraImagesStaged` condition. Example:   extraImages:     - image: registry.example.com/team/custom-workspace:1.0       registry: https://registry.example.com       priority: 10       imagePullSecrets:         - name: example-registry</td>
		</tr>
		<tr>
			<td id="imagePuller--refreshIntervalSeconds"><a href="./values.yaml#L636">imagePuller.refreshIntervalSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>Re-pull the staged images on this cadence, so a mutable tag (`:develop`, or a rebuilt `:1.2.3` whose digest changed but tag did not) is refreshed on the nodes. 0 (the default) never re-pulls: an image is fetched only when it first enters the catalog. A refresh rolls the puller DaemonSet, so keep it comfortably longer than a pull takes — 3600 (hourly) is a sensible start.</td>
		</tr>
		<tr>
			<td id="imagePuller--resources"><a href="./values.yaml#L677">imagePuller.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Compute resources for the puller's idle holder containers (kept tiny — they only idle to hold the image resident). Omitted when empty.</td>
		</tr>
		<tr>
			<td id="imagePuller--storage"><a href="./values.yaml#L656">imagePuller.storage</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
evictionPercent: ""
maxConcurrentPulls: ""
reservedBytes: ""
reservedPercent: ""
unpackFactor: ""
</pre>
</div>
			</td>
			<td>Per-node disk budget the puller pulls into. It never pulls an image it cannot fit: on each node the budget is the ephemeral-storage capacity minus the kubelet eviction threshold, minus the reserve kept for workspaces, minus what images and pods already use. Empty leaves the operator's defaults in charge (omitted from the Agent while every field is empty).</td>
		</tr>
		<tr>
			<td id="imagePuller--storage--evictionPercent"><a href="./values.yaml#L666">imagePuller.storage.evictionPercent</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The kubelet's `imagefs.available` hard-eviction threshold as a percentage of capacity (0-90); the budget keeps this much free on top of the reserve so a pull never drives the node into DiskPressure. Default 15 (the kubelet's own default).</td>
		</tr>
		<tr>
			<td id="imagePuller--storage--maxConcurrentPulls"><a href="./values.yaml#L674">imagePuller.storage.maxConcurrentPulls</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>How many pull pods may run on one node at a time (minimum 1, default 1). More than 1 only helps if the node's kubelet raises `maxParallelImagePulls` (it serializes pulls by default).</td>
		</tr>
		<tr>
			<td id="imagePuller--storage--reservedBytes"><a href="./values.yaml#L659">imagePuller.storage.reservedBytes</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Headroom kept free on every node for workspace pods' writable layers and logs, in bytes. Takes precedence over `reservedPercent`. Empty uses `reservedPercent`.</td>
		</tr>
		<tr>
			<td id="imagePuller--storage--reservedPercent"><a href="./values.yaml#L662">imagePuller.storage.reservedPercent</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The reserve as a percentage of the node's ephemeral-storage capacity (0-90). Default 20 when neither this nor `reservedBytes` is set.</td>
		</tr>
		<tr>
			<td id="imagePuller--storage--unpackFactor"><a href="./values.yaml#L670">imagePuller.storage.unpackFactor</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Estimates an image's unpacked on-disk size from its compressed layer sizes, as a decimal string (`"2.5"`). Used until a node holds the image and reports its real size. Default `"2.5"` (conservative for gzip; zstd:chunked layers unpack closer to `"1.5"`).</td>
		</tr>
		<tr>
			<td id="inClusterControlPlane"><a href="./values.yaml#L67">inClusterControlPlane</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
null
</pre>
</div>
			</td>
			<td>Derive the control-plane connection from a `kasm-helm` release installed under the **same release name and namespace** - which is what the `kasm-platform` umbrella does.  When true, three values that otherwise have no default and fail the render are derived instead:  * `manager.hostname` becomes `<release>-proxy-default.<namespace>.svc.cluster.local` * the manager token is read from the `<release>-secrets` Secret the control plane generates,   under its `manager-token` key * `publicHostname` becomes `<name>-session-proxy.<namespace>.svc.cluster.local`  Anything you set explicitly still wins. Unset (null, the default), the `kasm-platform` umbrella's `global.kasm.inClusterControlPlane` decides, and without that it is off. That fallback exists because Rancher's install form can submit an untouched toggle as null, which deletes an umbrella's per-subchart override; an explicit `false` here still wins over the global. The derived `manager.hostname` assumes the default zone; set it yourself when `kasm-helm.kasmZones` names something else.  The derived `publicHostname` is an in-cluster address, so it only works while the control plane relays session traffic (`proxy_connections: true`, Kasm's default). Publishing sessions directly to browsers needs a real external hostname here - see the networking documentation. </td>
		</tr>
		<tr>
			<td id="ingress"><a href="./values.yaml#L795">ingress</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
backendPort: 4445
className: ""
enabled: false
hosts: []
tls: []
</pre>
</div>
			</td>
			<td>Optionally expose the operator-created session-proxy Service through a classic `networking.k8s.io/v1` Ingress, for clusters without the Gateway API. </td>
		</tr>
		<tr>
			<td id="ingress--annotations"><a href="./values.yaml#L811">ingress.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Annotations for the Ingress, merged over `commonAnnotations`. This is where the controller-specific websocket and timeout settings go - without them sessions are cut off at the controller's default read timeout (60s on ingress-nginx). Example (ingress-nginx):   annotations:     nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"     nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"</td>
		</tr>
		<tr>
			<td id="ingress--backendPort"><a href="./values.yaml#L830">ingress.backendPort</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
4445
</pre>
</div>
			</td>
			<td>Port on the session-proxy Service to forward to. The default, 4445, is the proxy's plain-HTTP listener; TLS for the public hostname is expected to terminate at the Ingress. Use 4444 to forward to the proxy's own HTTPS listener instead, which on most controllers also needs a backend-protocol annotation (`nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` on ingress-nginx).</td>
		</tr>
		<tr>
			<td id="ingress--className"><a href="./values.yaml#L803">ingress.className</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>`ingressClassName` of the controller that should serve this Ingress. Omitted from the resource when empty, which leaves the cluster's default IngressClass to claim it.</td>
		</tr>
		<tr>
			<td id="ingress--enabled"><a href="./values.yaml#L800">ingress.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Render the Ingress. `httpRoute`, `ingress`, `route`, `tlsRoute` and `gatewayRoute` are alternatives - enable at most one of the five, since all point at the same operator-created session-proxy Service. Kasm sessions are long-lived VNC websockets, so whichever controller backs this ingress class must allow websocket upgrades and use read and send timeouts of at least 3600s; see `ingress.annotations` below.</td>
		</tr>
		<tr>
			<td id="ingress--hosts"><a href="./values.yaml#L817">ingress.hosts</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Hostnames the Ingress serves, as a list of strings. Each gets one `/` `Prefix` rule to the session-proxy Service. Defaults to a single-entry list holding `publicHostname` when empty. Example:   hosts:     - agent.example.com</td>
		</tr>
		<tr>
			<td id="ingress--tls"><a href="./values.yaml#L825">ingress.tls</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>TLS blocks for the Ingress, as a standard list of `{secretName, hosts}` objects, passed through verbatim. Empty means the Ingress serves plain HTTP. Example:   tls:     - secretName: kasm-agent-public-tls       hosts:         - agent.example.com</td>
		</tr>
		<tr>
			<td id="logLevel"><a href="./values.yaml#L435">logLevel</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
INFO
</pre>
</div>
			</td>
			<td>Log level for the agent container. </td>
		</tr>
		<tr>
			<td id="manager"><a href="./values.yaml#L86">manager</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
existingTokenSecret: ""
hostname: ""
pathPrefix: /manager_api
port: 443
scheme: https
token: ""
tokenSecretKey: token
</pre>
</div>
			</td>
			<td>The Kasm control plane this agent registers and heartbeats with. </td>
		</tr>
		<tr>
			<td id="manager--existingTokenSecret"><a href="./values.yaml#L104">manager.existingTokenSecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of an existing Secret holding the manager token. Takes precedence over `manager.token`; when set, this chart creates no Secret of its own. One of the two must be set.</td>
		</tr>
		<tr>
			<td id="manager--hostname"><a href="./values.yaml#L89">manager.hostname</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>REQUIRED. Hostname of the Kasm manager (or the proxy in front of it) the agent heartbeats to. Templating fails when this is empty - there is no sensible default.</td>
		</tr>
		<tr>
			<td id="manager--pathPrefix"><a href="./values.yaml#L96">manager.pathPrefix</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
/manager_api
</pre>
</div>
			</td>
			<td>Prefix prepended to manager API paths. When reaching the manager through its public proxy this is `/manager_api`; set it empty only for direct manager-Service access.</td>
		</tr>
		<tr>
			<td id="manager--port"><a href="./values.yaml#L91">manager.port</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
443
</pre>
</div>
			</td>
			<td>Port the manager listens on.</td>
		</tr>
		<tr>
			<td id="manager--scheme"><a href="./values.yaml#L93">manager.scheme</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
https
</pre>
</div>
			</td>
			<td>URL scheme used to reach the manager - `https` or `http`.</td>
		</tr>
		<tr>
			<td id="manager--token"><a href="./values.yaml#L101">manager.token</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The shared manager token, in plaintext. When set (and `manager.existingTokenSecret` is not), this chart creates a Secret named `<fullname>-manager-token` holding it and points the Agent at that. Prefer `manager.existingTokenSecret` for anything but a throwaway environment - a value set here lands in the Helm release history.</td>
		</tr>
		<tr>
			<td id="manager--tokenSecretKey"><a href="./values.yaml#L106">manager.tokenSecretKey</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
token
</pre>
</div>
			</td>
			<td>Key inside `manager.existingTokenSecret` that holds the token.</td>
		</tr>
		<tr>
			<td id="name"><a href="./values.yaml#L72">name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
k8s-agent
</pre>
</div>
			</td>
			<td>Name of the Agent custom resource. The operator derives the names of the objects it creates from this, most visibly the session-proxy Service, which it names `<name>-session-proxy`. </td>
		</tr>
		<tr>
			<td id="nameOverride"><a href="./values.yaml#L5">nameOverride</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Override the chart name used to build the names of the satellite objects (token Secret, Certificate, KasmImagePuller, HTTPRoute) and the `app.kubernetes.io/name` label. The Agent custom resource itself is named by `name`, not by this. </td>
		</tr>
		<tr>
			<td id="nodeSelector"><a href="./values.yaml#L464">nodeSelector</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Node selector pinning the agent and session-proxy pods. Omitted from the Agent resource entirely when empty. </td>
		</tr>
		<tr>
			<td id="openshift"><a href="./values.yaml#L983">openshift</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
scc:
    enabled: false
    workspace:
        allowHostPath: false
        allowPrivileged: false
        capabilities: []
        name: ""
        seccompProfiles:
            - runtime/default
            - localhost/*
            - unconfined
        volumes:
            - configMap
            - csi
            - downwardAPI
            - emptyDir
            - ephemeral
            - persistentVolumeClaim
            - projected
            - secret
</pre>
</div>
			</td>
			<td>OpenShift-only objects. Leave every switch here off on any other distribution: the kinds involved exist only on OpenShift and the release would fail to install.  Sessions are ordinary pods, and on OpenShift ordinary pods are admitted by the `restricted-v2` SecurityContextConstraint, which refuses what a Kasm workspace needs even at uid 1000: a fixed uid and `fsGroup: 1000` outside the namespace's range, a capability or two on top of `drop: ALL` (`SYS_CHROOT` for the browser sandbox), and possibly a `Localhost` seccomp profile. A session that needs root adds uid 0 (in a pod user namespace or on the host, per `workspaceSecurity.rootMode`), a wider capability set and privilege escalation. The operator runs each session under a ServiceAccount of its own, `<name>-workspace`, so SCCs that admit exactly that can be granted to sessions alone and to nothing else in the namespace. This block ships those SCCs and the grant, shaped by `workspaceSecurity`. </td>
		</tr>
		<tr>
			<td id="openshift--scc--enabled"><a href="./values.yaml#L995">openshift.scc.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Render the workspace SecurityContextConstraints, a ClusterRole holding `use` on them, and the RoleBinding that grants it to the `<name>-workspace` ServiceAccount the operator creates for this agent. One SCC admits uid-1000 sessions (`MustRunAsNonRoot`); unless `workspaceSecurity.rootMode` is `forbid`, a second admits root sessions: uid 0 in a pod user namespace only (`userNamespaceLevel: RequirePodLevel`, OpenShift 4.20+) for `userns`, uid 0 on the host for `host`. With `seccomp.enabled` and the `installer` backend, also grant the built-in `privileged` SCC to the `<name>-seccomp-installer` ServiceAccount (root with a hostPath mount of the kubelet's seccomp directory, `spc_t`). Requires cluster-admin at install time, as any SCC or ClusterRole does. The agent Deployment, the session proxy, the image puller and the standby placeholders set no UID and stay under `restricted-v2`. </td>
		</tr>
		<tr>
			<td id="openshift--scc--workspace--allowHostPath"><a href="./values.yaml#L1023">openshift.scc.workspace.allowHostPath</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Admit hostPath volumes. The operator renders a workspace's `devices` (`/dev/dri`, `/dev/video*` passed through by path) and its Docker-style `volumeMappings` (host bind mounts from the manager's volume mappings) as hostPath volumes; without this they are refused. Webcam sessions through `videoDevicePlugin` use a device-plugin resource instead and need no hostPath. </td>
		</tr>
		<tr>
			<td id="openshift--scc--workspace--allowPrivileged"><a href="./values.yaml#L1017">openshift.scc.workspace.allowPrivileged</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Admit sessions whose image run config asks for `privileged: true`. Off by default: no stock Kasm image needs it. </td>
		</tr>
		<tr>
			<td id="openshift--scc--workspace--capabilities"><a href="./values.yaml#L1013">openshift.scc.workspace.capabilities</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Capabilities the SCCs let a session add. Leave empty (the default) to derive them from `workspaceSecurity`: the uid-1000 SCC admits `SYS_CHROOT` and `NET_BIND_SERVICE` under profile `baseline` (plus `SETUID`/`SETGID` with `sudo`) and only `NET_BIND_SERVICE` under `restricted`; the root SCC (`rootMode` `userns` or `host`) admits the set the operator adds to every root container on top of `drop: ALL` (`SETUID`, `SETGID`, `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `KILL`, `NET_BIND_SERVICE`, `SYS_CHROOT`). A non-empty list replaces the derived set on every SCC the chart renders; set one when an image `cap_add`s more (the manager passes the image's run config through), or the pod is refused. Example:   capabilities: [SETUID, SETGID, CHOWN, DAC_OVERRIDE, FOWNER, KILL, NET_BIND_SERVICE, SYS_CHROOT, SYS_ADMIN] </td>
		</tr>
		<tr>
			<td id="openshift--scc--workspace--name"><a href="./values.yaml#L1002">openshift.scc.workspace.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of the cluster-scoped uid-1000 SecurityContextConstraint and of the ClusterRole that grants the SCCs. The root SCC, rendered unless `workspaceSecurity.rootMode` is `forbid`, takes the same name with a `-root` suffix. Leave empty to derive one unique to this agent and namespace (`kasm-<namespace>-<name>-workspace`). </td>
		</tr>
		<tr>
			<td id="openshift--scc--workspace--seccompProfiles"><a href="./values.yaml#L1044">openshift.scc.workspace.seccompProfiles</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
- runtime/default
- localhost/*
- unconfined
</pre>
</div>
			</td>
			<td>seccomp profiles the SCC admits. `runtime/default` is what the operator sets when an image carries no profile; `localhost/*` is the `Localhost` profile the agent sets for an image that ships an inline profile (`seccomp.enabled`, either backend); `unconfined` is the fallback for such an image when `seccomp.enabled` is off. </td>
		</tr>
		<tr>
			<td id="openshift--scc--workspace--volumes"><a href="./values.yaml#L1030">openshift.scc.workspace.volumes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
- configMap
- csi
- downwardAPI
- emptyDir
- ephemeral
- persistentVolumeClaim
- projected
- secret
</pre>
</div>
			</td>
			<td>Volume kinds the SCC admits. The default covers everything the operator renders for a session: the startup-script ConfigMaps, the memory-backed `/dev/shm` and `/tmp`, persistent profiles (PersistentVolumeClaim) and cloud storage mappings (CSI). `hostPath` is added by `allowHostPath`. Add `image` for `imageMounts` (OCI image volumes, Kubernetes 1.35+), which this list leaves out because an SCC naming a volume kind the API server does not know is refused outright. </td>
		</tr>
		<tr>
			<td id="operatorRBAC--serviceAccount--name"><a href="./values.yaml#L453">operatorRBAC.serviceAccount.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
controller-manager
</pre>
</div>
			</td>
			<td>Name of the operator's ServiceAccount, the `kasm-agent-operator` chart's `serviceAccount.name`. </td>
		</tr>
		<tr>
			<td id="operatorRBAC--serviceAccount--namespace"><a href="./values.yaml#L459">operatorRBAC.serviceAccount.namespace</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Namespace the operator runs in. Leave empty when the operator is installed in this release's namespace (the `kasm-agent` umbrella with `operator.enabled=true`). Set it whenever this agent lives in a different namespace from the operator; otherwise the RoleBinding points at a ServiceAccount that does not exist and every session with a storage mapping fails with Forbidden. </td>
		</tr>
		<tr>
			<td id="otel"><a href="./values.yaml#L599">otel</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
endpoint: ""
</pre>
</div>
			</td>
			<td>OpenTelemetry export settings, rendered as environment variables on the Agent. </td>
		</tr>
		<tr>
			<td id="otel--enabled"><a href="./values.yaml#L602">otel.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Point the agent at an OTLP endpoint. Enabled by default so the agent reports to the collector deployed alongside it.</td>
		</tr>
		<tr>
			<td id="otel--endpoint"><a href="./values.yaml#L605">otel.endpoint</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>OTLP/HTTP endpoint the agent exports to. Defaults to the in-cluster kasm-otel-collector Service for this release (`http://<release>-kasm-otel-collector:4318`) when empty.</td>
		</tr>
		<tr>
			<td id="persistentProfiles"><a href="./values.yaml#L569">persistentProfiles</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
accessModes: []
capacity: ""
storageClass: ""
</pre>
</div>
			</td>
			<td>Cluster-wide defaults for the PVC behind every persistent profile. The manager sends only the profile path with a launch, never a StorageClass, access mode or size, so those come from here. Leave a field empty to keep the operator's default: the cluster's default StorageClass, `ReadWriteOnce` and `10Gi`. Set an RWX-capable class with `ReadWriteMany` so one user's profile can be mounted by concurrent sessions on different nodes.</td>
		</tr>
		<tr>
			<td id="persistentProfiles--accessModes"><a href="./values.yaml#L574">persistentProfiles.accessModes</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Access modes for persistent-profile PVCs, for example `[ReadWriteMany]`. Empty means `ReadWriteOnce`.</td>
		</tr>
		<tr>
			<td id="persistentProfiles--capacity"><a href="./values.yaml#L576">persistentProfiles.capacity</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Size of each persistent-profile PVC, for example `20Gi`. Empty means `10Gi`.</td>
		</tr>
		<tr>
			<td id="persistentProfiles--storageClass"><a href="./values.yaml#L571">persistentProfiles.storageClass</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>StorageClass for persistent-profile PVCs. Empty means the cluster default.</td>
		</tr>
		<tr>
			<td id="publicHostname"><a href="./values.yaml#L111">publicHostname</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>REQUIRED. This agent's externally reachable address, advertised to the manager as where browsers should connect. Templating fails when this is empty. </td>
		</tr>
		<tr>
			<td id="publicPort"><a href="./values.yaml#L123">publicPort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Port the session proxy is reachable on publicly: the port browsers connect to and the one the control plane dials (`https://<publicHostname>:<publicPort>/agent/api/v1/hello/`) before it hands this agent a session. Empty (the default) derives it: 4444 while the hostname is derived in-cluster, the pinned `sessionProxy.service.httpsNodePort` when the proxy Service is a `NodePort`, 443 otherwise. Set it explicitly when something in front of the proxy owns the port (an ingress or load balancer on 443, a firewall forwarding 443 to the node port). A `LoadBalancer` Service publishes the proxy's own port, 4444, unless the load balancer remaps it (an OCI load balancer does not), so set `publicPort: 4444` there. A wrong value fails silently at install time and loudly at the first launch: the Hello is refused and every session request answers "No Agent slots available". </td>
		</tr>
		<tr>
			<td id="resources"><a href="./values.yaml#L595">resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Compute resources for the agent container, passed through to `spec.resources` verbatim. Omitted from the Agent resource when empty, in which case the operator applies its own defaults. </td>
		</tr>
		<tr>
			<td id="route"><a href="./values.yaml#L835">route</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
backendPort: ""
enabled: false
host: ""
tls:
    caCertificate: ""
    certificate: ""
    destinationCACertificate: ""
    insecureEdgeTerminationPolicy: ""
    key: ""
    termination: passthrough
</pre>
</div>
			</td>
			<td>Optionally expose the operator-created session-proxy Service through an OpenShift Route, the native option on OpenShift clusters. </td>
		</tr>
		<tr>
			<td id="route--annotations"><a href="./values.yaml#L851">route.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Annotations for the Route, merged over `commonAnnotations`. The router timeout belongs here: without it OpenShift closes idle session websockets after 30 seconds. Example:   annotations:     haproxy.router.openshift.io/timeout: "3600s"</td>
		</tr>
		<tr>
			<td id="route--backendPort"><a href="./values.yaml#L855">route.backendPort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Port on the session-proxy Service to route to. Leave empty to pick it from `route.tls.termination`: 4444, the proxy's own HTTPS listener, for `passthrough` and `reencrypt`; 4445, its plain-HTTP listener, for `edge`. Set it only to override that pairing.</td>
		</tr>
		<tr>
			<td id="route--enabled"><a href="./values.yaml#L841">route.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Render the Route. Requires OpenShift (the `route.openshift.io` API). `httpRoute`, `ingress`, `route`, `tlsRoute` and `gatewayRoute` are alternatives - enable at most one of the five, since all of them point at the same operator-created session-proxy Service. Kasm sessions are long-lived VNC websockets and the OpenShift router's default connection timeout is 30s, so a timeout annotation is effectively mandatory; see `route.annotations` below.</td>
		</tr>
		<tr>
			<td id="route--host"><a href="./values.yaml#L845">route.host</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Hostname the Route serves. Defaults to `publicHostname` when empty. Under the default passthrough termination this hostname is matched against the session proxy's own certificate, so that certificate has to cover it.</td>
		</tr>
		<tr>
			<td id="route--tls"><a href="./values.yaml#L857">route.tls</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
caCertificate: ""
certificate: ""
destinationCACertificate: ""
insecureEdgeTerminationPolicy: ""
key: ""
termination: passthrough
</pre>
</div>
			</td>
			<td>TLS settings for the Route.</td>
		</tr>
		<tr>
			<td id="route--tls--caCertificate"><a href="./values.yaml#L883">route.tls.caCertificate</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>PEM CA certificate that signed `certificate`. Omitted when empty.</td>
		</tr>
		<tr>
			<td id="route--tls--certificate"><a href="./values.yaml#L881">route.tls.certificate</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>PEM certificate the router serves, for `edge` and `reencrypt`. Omitted when empty.</td>
		</tr>
		<tr>
			<td id="route--tls--destinationCACertificate"><a href="./values.yaml#L886">route.tls.destinationCACertificate</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>PEM CA certificate the router uses to validate the session proxy's certificate on a `reencrypt` Route. Omitted when empty.</td>
		</tr>
		<tr>
			<td id="route--tls--insecureEdgeTerminationPolicy"><a href="./values.yaml#L874">route.tls.insecureEdgeTerminationPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>What the Route does with plain-HTTP requests - `Redirect`, `Allow`, or `None`. Omitted from the Route when empty. `Redirect` is the usual choice for `edge`; `passthrough` supports only `Redirect` and `None`.</td>
		</tr>
		<tr>
			<td id="route--tls--key"><a href="./values.yaml#L878">route.tls.key</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>PEM private key the router serves, for `edge` and `reencrypt`. Omitted when empty. This lands in the Helm release history in plaintext - prefer letting the router use its own certificate, or passthrough with a cert-manager-issued proxy certificate.</td>
		</tr>
		<tr>
			<td id="route--tls--termination"><a href="./values.yaml#L870">route.tls.termination</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
passthrough
</pre>
</div>
			</td>
			<td>Where TLS terminates - `passthrough`, `edge` or `reencrypt`. The default, `passthrough`, gives end-to-end TLS: the router forwards the connection untouched and browsers see the session proxy's own certificate from `sessionProxy.certSecretName`. Use `edge` to terminate at the router instead, in which case supply `key`/`certificate` below or let the router serve its default certificate. Example (terminate TLS at the OpenShift router instead of at the session proxy):   route:     enabled: true     annotations:       haproxy.router.openshift.io/timeout: "3600s"     tls:       termination: edge       insecureEdgeTerminationPolicy: Redirect</td>
		</tr>
		<tr>
			<td id="seccomp"><a href="./values.yaml#L737">seccomp</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
backend: installer
enabled: false
installer:
    image:
        registry: docker.io
        repository: kasmweb/kasm-seccomp-installer
        tag: ""
    imagePullPolicy: IfNotPresent
    kubeletSeccompDir: /var/lib/kubelet/seccomp
    resources: {}
</pre>
</div>
			</td>
			<td>Let a workspace run under its image's inline seccomp profile (`security_opt: seccomp=<json>`, as the Nix bubblewrap images carry) instead of `Unconfined`. Kubernetes can only reference a profile already on the node's disk, so the agent content-hashes each inline profile and a backend gets it onto the nodes. Off by default (`seccomp.enabled`); with it off an inline profile falls back to `Unconfined`. </td>
		</tr>
		<tr>
			<td id="seccomp--backend"><a href="./values.yaml#L749">seccomp.backend</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
installer
</pre>
</div>
			</td>
			<td>How profiles reach the nodes, one of `installer` or `spo`. `installer` (default) deploys the bundled `kasm-seccomp-installer` DaemonSet (configured under `seccomp.installer`); it runs as root with a hostPath mount into the kubelet seccomp directory, so the agent namespace must admit the `privileged` Pod Security level and the nodes must allow hostPath (rules out e.g. GKE Autopilot), and it follows `workspacesNodeSelector`/`workspacesTolerations`. `spo` instead has the agent create cluster-scoped `SeccompProfile` resources for the external [Security Profiles Operator](https://github.com/kubernetes-sigs/security-profiles-operator) (1.0+) to install — no hostPath or privileged namespace, but SPO must already be running in the cluster (this chart does not install it) or the Agent reports Degraded. The `seccomp.installer` block is ignored for `spo`.</td>
		</tr>
		<tr>
			<td id="seccomp--enabled"><a href="./values.yaml#L739">seccomp.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Turn on seccomp-profile installation (renders `spec.seccomp` on the Agent).</td>
		</tr>
		<tr>
			<td id="seccomp--installer"><a href="./values.yaml#L751">seccomp.installer</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
image:
    registry: docker.io
    repository: kasmweb/kasm-seccomp-installer
    tag: ""
imagePullPolicy: IfNotPresent
kubeletSeccompDir: /var/lib/kubelet/seccomp
resources: {}
</pre>
</div>
			</td>
			<td>Configures the `installer` backend (ignored when `backend` is `spo`).</td>
		</tr>
		<tr>
			<td id="seccomp--installer--image"><a href="./values.yaml#L753">seccomp.installer.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/kasm-seccomp-installer
tag: ""
</pre>
</div>
			</td>
			<td>The kasm-seccomp-installer image.</td>
		</tr>
		<tr>
			<td id="seccomp--installer--image--registry"><a href="./values.yaml#L755">seccomp.installer.image.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
docker.io
</pre>
</div>
			</td>
			<td>Registry that hosts the installer image.</td>
		</tr>
		<tr>
			<td id="seccomp--installer--image--repository"><a href="./values.yaml#L757">seccomp.installer.image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmweb/kasm-seccomp-installer
</pre>
</div>
			</td>
			<td>Repository of the installer image, without the registry or tag.</td>
		</tr>
		<tr>
			<td id="seccomp--installer--image--tag"><a href="./values.yaml#L759">seccomp.installer.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag of the installer image. Leave empty to fall back to the chart's `appVersion`.</td>
		</tr>
		<tr>
			<td id="seccomp--installer--imagePullPolicy"><a href="./values.yaml#L761">seccomp.installer.imagePullPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
IfNotPresent
</pre>
</div>
			</td>
			<td>Pull policy for the installer image.</td>
		</tr>
		<tr>
			<td id="seccomp--installer--kubeletSeccompDir"><a href="./values.yaml#L766">seccomp.installer.kubeletSeccompDir</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
/var/lib/kubelet/seccomp
</pre>
</div>
			</td>
			<td>The kubelet's seccomp root on the node, which the installer writes profiles under (and mounts by hostPath). The default suits a stock kubelet; override it where the kubelet root is relocated — k3s (`/var/lib/rancher/k3s/agent/kubelet/seccomp`), microk8s (`/var/snap/microk8s/common/var/lib/kubelet/seccomp`).</td>
		</tr>
		<tr>
			<td id="seccomp--installer--resources"><a href="./values.yaml#L768">seccomp.installer.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Compute resources for the installer DaemonSet's container. Omitted when empty.</td>
		</tr>
		<tr>
			<td id="serverID"><a href="./values.yaml#L582">serverID</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The stable UUID this agent registers under. Leave empty to have the operator generate one and record it in the Agent's status; set it to adopt an existing registration. Omitted from the Agent resource when empty. </td>
		</tr>
		<tr>
			<td id="sessionProxy"><a href="./values.yaml#L132">sessionProxy</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
affinity: {}
autoscaling:
    enabled: false
    maxReplicas: 0
    minReplicas: 1
    scaleDownStabilizationSeconds: 1800
    sessionsPerReplica: 0
certSecretName: kasm-session-proxy-tls
certificate:
    commonName: ""
    dnsNames: []
    enabled: false
    issuerRef:
        group: cert-manager.io
        kind: ClusterIssuer
        name: ""
drainTimeoutSeconds: 300
externallyScaled: false
image:
    registry: docker.io
    repository: kasmweb/nginx
    tag: 1.25.3
internalService:
    annotations: {}
    externalTrafficPolicy: ""
    httpNodePort: ""
    httpPort: ""
    httpsNodePort: ""
    httpsPort: ""
    type: ClusterIP
networkPolicy:
    enabled: false
    extraEgress: []
nginx:
    workerConnections: ""
    workerProcesses: ""
nodeSelector: {}
podDisruptionBudget:
    maxUnavailable: ""
    minAvailable: ""
probeTimeoutSeconds: 120
proxyProtocol:
    enabled: false
    trustedCIDRs: []
reconcileIntervalSeconds: 30
replicas: 1
resolver: ""
resources: {}
routing: dynamic
selfSigned:
    enabled: true
service:
    annotations: {}
    externalTrafficPolicy: ""
    httpNodePort: ""
    httpPort: ""
    httpsNodePort: ""
    httpsPort: ""
    type: ClusterIP
sidecarImage:
    registry: docker.io
    repository: kasmweb/kasm-nginx-sidecar
    tag: ""
sidecarResources: {}
tolerations: []
topologySpreadConstraints: []
</pre>
</div>
			</td>
			<td>The nginx session proxy the operator deploys alongside the agent. It terminates the browser connection and routes it to the workspace container for the session. </td>
		</tr>
		<tr>
			<td id="sessionProxy--affinity"><a href="./values.yaml#L199">sessionProxy.affinity</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Affinity for the proxy pods, a Kubernetes `Affinity` map. Omitted from the Agent resource when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--autoscaling"><a href="./values.yaml#L220">sessionProxy.autoscaling</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
maxReplicas: 0
minReplicas: 1
scaleDownStabilizationSeconds: 1800
sessionsPerReplica: 0
</pre>
</div>
			</td>
			<td>Have the operator size the proxy Deployment by how many sessions the agent is running - the load a proxy actually carries, since a websocket relay uses little CPU and a CPU-based autoscaler would never fire before its connections ran out. Alternative to `externallyScaled`; the two cannot both be on. While enabled, `sessionProxy.replicas` is ignored. Omitted from the Agent resource unless enabled.</td>
		</tr>
		<tr>
			<td id="sessionProxy--autoscaling--enabled"><a href="./values.yaml#L222">sessionProxy.autoscaling.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Turn on session-count autoscaling for the proxy.</td>
		</tr>
		<tr>
			<td id="sessionProxy--autoscaling--maxReplicas"><a href="./values.yaml#L231">sessionProxy.autoscaling.maxReplicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>REQUIRED when enabled. Most proxy pods, whatever the session count; must be at least `minReplicas`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--autoscaling--minReplicas"><a href="./values.yaml#L228">sessionProxy.autoscaling.minReplicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>Fewest proxy pods, whatever the session count.</td>
		</tr>
		<tr>
			<td id="sessionProxy--autoscaling--scaleDownStabilizationSeconds"><a href="./values.yaml#L235">sessionProxy.autoscaling.scaleDownStabilizationSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1800
</pre>
</div>
			</td>
			<td>How long a lower replica count must be called for, without interruption, before a pod is removed - each removed pod then drains for `drainTimeoutSeconds`. Empty leaves the operator's default of 1800.</td>
		</tr>
		<tr>
			<td id="sessionProxy--autoscaling--sessionsPerReplica"><a href="./values.yaml#L226">sessionProxy.autoscaling.sessionsPerReplica</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>REQUIRED when enabled. Sessions one proxy pod is sized for; the replica count is `ceil(sessions / sessionsPerReplica)`, clamped to the min/max below. Size it from the `sessionProxy.nginx` capacity.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certSecretName"><a href="./values.yaml#L283">sessionProxy.certSecretName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasm-session-proxy-tls
</pre>
</div>
			</td>
			<td>Name of the TLS Secret (keys `tls.crt`/`tls.key`) served on the proxy's HTTPS listener. The proxy will not start without it, so either enable `sessionProxy.certificate` below or create this Secret out of band.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate"><a href="./values.yaml#L286">sessionProxy.certificate</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
commonName: ""
dnsNames: []
enabled: false
issuerRef:
    group: cert-manager.io
    kind: ClusterIssuer
    name: ""
</pre>
</div>
			</td>
			<td>Optionally have cert-manager issue the session proxy's TLS certificate into `sessionProxy.certSecretName`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate--commonName"><a href="./values.yaml#L291">sessionProxy.certificate.commonName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Certificate common name. Defaults to `publicHostname` when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate--dnsNames"><a href="./values.yaml#L295">sessionProxy.certificate.dnsNames</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Subject alternative names on the certificate. Defaults to a single-entry list holding `publicHostname` when empty. Add a wildcard entry here if sessions are served from per-session subdomains.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate--enabled"><a href="./values.yaml#L289">sessionProxy.certificate.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Render a cert-manager Certificate for the session proxy. Requires cert-manager and a usable issuer in the cluster.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate--issuerRef"><a href="./values.yaml#L297">sessionProxy.certificate.issuerRef</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
group: cert-manager.io
kind: ClusterIssuer
name: ""
</pre>
</div>
			</td>
			<td>The cert-manager issuer that signs the certificate.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate--issuerRef--group"><a href="./values.yaml#L304">sessionProxy.certificate.issuerRef.group</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
cert-manager.io
</pre>
</div>
			</td>
			<td>API group of the issuer.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate--issuerRef--kind"><a href="./values.yaml#L302">sessionProxy.certificate.issuerRef.kind</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
ClusterIssuer
</pre>
</div>
			</td>
			<td>Kind of the issuer - `ClusterIssuer` or `Issuer`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--certificate--issuerRef--name"><a href="./values.yaml#L300">sessionProxy.certificate.issuerRef.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>REQUIRED when `sessionProxy.certificate.enabled` is true. Name of the Issuer or ClusterIssuer.</td>
		</tr>
		<tr>
			<td id="sessionProxy--drainTimeoutSeconds"><a href="./values.yaml#L170">sessionProxy.drainTimeoutSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
300
</pre>
</div>
			</td>
			<td>How long a proxy pod that is being stopped keeps serving the connections it already holds. A stopping pod leaves the Service at once, so new connections go to other pods, but the desktop streams already on it keep running and are cut only when this elapses. Session streams can last hours, so set this to how long a rollout or a scale-in may take. Empty leaves the operator's default of 300.</td>
		</tr>
		<tr>
			<td id="sessionProxy--externallyScaled"><a href="./values.yaml#L241">sessionProxy.externallyScaled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Leave the proxy Deployment's replica count to something else (KEDA, an HPA) once that exists; `sessionProxy.replicas` applies only when the Deployment is first created. As with `standby`, a KEDA `ScaledObject` with a kubernetes-workload trigger on the workspace pods (selector `app.kubernetes.io/component=workspace`) keeps one proxy per so many sessions; its scale-in removes pods at its own pace, each still draining for `drainTimeoutSeconds`. Alternative to `autoscaling`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--image"><a href="./values.yaml#L134">sessionProxy.image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/nginx
tag: 1.25.3
</pre>
</div>
			</td>
			<td>The nginx session-proxy container image.</td>
		</tr>
		<tr>
			<td id="sessionProxy--image--registry"><a href="./values.yaml#L136">sessionProxy.image.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
docker.io
</pre>
</div>
			</td>
			<td>Registry that hosts the nginx image.</td>
		</tr>
		<tr>
			<td id="sessionProxy--image--repository"><a href="./values.yaml#L138">sessionProxy.image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmweb/nginx
</pre>
</div>
			</td>
			<td>Repository of the nginx image, without the registry or tag.</td>
		</tr>
		<tr>
			<td id="sessionProxy--image--tag"><a href="./values.yaml#L141">sessionProxy.image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1.25.3
</pre>
</div>
			</td>
			<td>Tag of the nginx image. This one has no fallback: it tracks upstream nginx, not the Kasm release, so templating fails if it is emptied.</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService"><a href="./values.yaml#L363">sessionProxy.internalService</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
externalTrafficPolicy: ""
httpNodePort: ""
httpPort: ""
httpsNodePort: ""
httpsPort: ""
type: ClusterIP
</pre>
</div>
			</td>
			<td>Provision a SECOND Service in front of the same proxy pods, a front door distinct from `sessionProxy.service` above — typically an internal `LoadBalancer` on a private subnet so a control plane on a peered network or in another region can reach this agent without a public path (a ClusterIP is not routable across clusters; an internal LB's private IP is). Kasm registers one hostname per agent, so pair this with split-horizon DNS that resolves `publicHostname` to this Service from the control plane's network and to the primary Service from browsers, both on `publicPort`. Same fields as `sessionProxy.service`; omitted from the Agent while it holds only defaults, so only the primary Service exists unless you set something here.</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService--annotations"><a href="./values.yaml#L369">sessionProxy.internalService.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Annotations on the second Service. This is where the cloud "internal load balancer" attribute goes (an internal scheme, a private subnet). Omitted when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService--externalTrafficPolicy"><a href="./values.yaml#L371">sessionProxy.internalService.externalTrafficPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>`Cluster` or `Local`, as `sessionProxy.service`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService--httpNodePort"><a href="./values.yaml#L375">sessionProxy.internalService.httpNodePort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Pin the plain-HTTP node port (`NodePort`/`LoadBalancer` only).</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService--httpPort"><a href="./values.yaml#L379">sessionProxy.internalService.httpPort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Service-facing port for the HTTP (4445) listener.</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService--httpsNodePort"><a href="./values.yaml#L373">sessionProxy.internalService.httpsNodePort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Pin the HTTPS node port (`NodePort`/`LoadBalancer` only).</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService--httpsPort"><a href="./values.yaml#L377">sessionProxy.internalService.httpsPort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Service-facing port for the HTTPS (4444) listener.</td>
		</tr>
		<tr>
			<td id="sessionProxy--internalService--type"><a href="./values.yaml#L366">sessionProxy.internalService.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
ClusterIP
</pre>
</div>
			</td>
			<td>Type of the second Service — usually `LoadBalancer` with an internal-scheme annotation below. Same options as `sessionProxy.service.type`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--networkPolicy"><a href="./values.yaml#L249">sessionProxy.networkPolicy</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
extraEgress: []
</pre>
</div>
			</td>
			<td>Bound where the proxy pods may connect, with an egress NetworkPolicy the operator creates. A session's route sends the user's authenticated request — cookies and the workspace credential the control plane returned — to whatever address the route names, so anything that could write a route could send those anywhere the proxy pod can reach. The policy limits egress to where the proxy has business: its own namespace (workspaces, the agent), the control plane's namespace, DNS, the API server (the sidecar's watches), plus `extraEgress`. Ingress is left open (browsers connect from anywhere). Needs a CNI that enforces NetworkPolicy. Omitted from the Agent unless `enabled`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--networkPolicy--enabled"><a href="./values.yaml#L251">sessionProxy.networkPolicy.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Create the egress NetworkPolicy.</td>
		</tr>
		<tr>
			<td id="sessionProxy--networkPolicy--extraEgress"><a href="./values.yaml#L264">sessionProxy.networkPolicy.extraEgress</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Extra egress rules allowed on top of the built-in set, in NetworkPolicy's own `egress:` terms (a list of `{to, ports}` rules). Use it for a control plane reachable only outside the cluster (an `ipBlock`) or an OTLP collector in another namespace. Applies only when `enabled`. Example:   extraEgress:     - to:         - ipBlock:             cidr: 203.0.113.0/24       ports:         - protocol: TCP           port: 443</td>
		</tr>
		<tr>
			<td id="sessionProxy--nginx"><a href="./values.yaml#L176">sessionProxy.nginx</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
workerConnections: ""
workerProcesses: ""
</pre>
</div>
			</td>
			<td>nginx worker sizing for one proxy pod, and so its connection capacity. A proxied connection uses two of a worker's connections (client and upstream), and a session holds one per service in its port map (vnc, audio, uploads, ...), so a pod carries roughly `workerProcesses * workerConnections / (2 * services-per-session)` sessions. Omitted from the Agent resource while both values are empty, leaving the operator's defaults in charge.</td>
		</tr>
		<tr>
			<td id="sessionProxy--nginx--workerConnections"><a href="./values.yaml#L182">sessionProxy.nginx.workerConnections</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>nginx `worker_connections`, per worker; the worker's file-descriptor limit is raised to match. Empty leaves the operator's default of 1024.</td>
		</tr>
		<tr>
			<td id="sessionProxy--nginx--workerProcesses"><a href="./values.yaml#L179">sessionProxy.nginx.workerProcesses</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>nginx `worker_processes`. Empty follows the container's CPU limit when one is set (rounded up), otherwise 6.</td>
		</tr>
		<tr>
			<td id="sessionProxy--nodeSelector"><a href="./values.yaml#L194">sessionProxy.nodeSelector</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Node selector for the proxy pods. Empty has them follow the agent's own `nodeSelector`. Set it to keep the proxy off a node pool an autoscaler shrinks, since a proxy pod taken away takes every stream it carries. Omitted from the Agent resource when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--podDisruptionBudget"><a href="./values.yaml#L208">sessionProxy.podDisruptionBudget</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
maxUnavailable: ""
minAvailable: ""
</pre>
</div>
			</td>
			<td>Bound how many proxy pods a voluntary disruption (a node drain, say) may take at once. Set exactly one of `minAvailable` or `maxUnavailable`; leaving both empty omits the block, and with more than one replica the operator then defaults to at most one pod disrupted. With a single replica no budget is created (it could only block the drain).</td>
		</tr>
		<tr>
			<td id="sessionProxy--podDisruptionBudget--maxUnavailable"><a href="./values.yaml#L214">sessionProxy.podDisruptionBudget.maxUnavailable</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Most proxy pods that may be unavailable, as a count or a quoted percentage. Mutually exclusive with `minAvailable`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--podDisruptionBudget--minAvailable"><a href="./values.yaml#L211">sessionProxy.podDisruptionBudget.minAvailable</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Fewest proxy pods that must stay available, as a count (`2`) or a quoted percentage (`"50%"`). Mutually exclusive with `maxUnavailable`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--probeTimeoutSeconds"><a href="./values.yaml#L155">sessionProxy.probeTimeoutSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
120
</pre>
</div>
			</td>
			<td>How long the sidecar waits for a session to become ready before giving up.</td>
		</tr>
		<tr>
			<td id="sessionProxy--proxyProtocol"><a href="./values.yaml#L392">sessionProxy.proxyProtocol</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
trustedCIDRs: []
</pre>
</div>
			</td>
			<td>PROXY protocol on the session proxy's nginx listeners, so the real client address survives an external L4 proxy that cannot set `X-Forwarded-For`. This is the layer-7 companion to `sessionProxy.service.externalTrafficPolicy: Local`; use one or the other, whichever matches how traffic actually reaches the proxy. The whole block is omitted from the Agent resource while it is disabled and no trusted CIDRs are set.</td>
		</tr>
		<tr>
			<td id="sessionProxy--proxyProtocol--enabled"><a href="./values.yaml#L398">sessionProxy.proxyProtocol.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Turn on `proxy_protocol` on both session-proxy listeners. REQUIRES the load balancer or proxy in front to actually send a PROXY protocol header on every connection: nginx expects the header and cannot fall back, so a plain client - a browser reaching the NodePort directly, a health check, `curl` against the Service - fails on these listeners once this is on. Enable it together with the matching setting on the fronting proxy, never on its own.</td>
		</tr>
		<tr>
			<td id="sessionProxy--proxyProtocol--trustedCIDRs"><a href="./values.yaml#L406">sessionProxy.proxyProtocol.trustedCIDRs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Source ranges nginx trusts to send an accurate PROXY protocol header, normally the fronting load balancer's own address range (its node subnet, the cloud LB's CIDR, the MetalLB pool). Omitted from the Agent resource when empty. Example:   trustedCIDRs:     - 10.0.0.0/16     - 192.168.1.0/24</td>
		</tr>
		<tr>
			<td id="sessionProxy--reconcileIntervalSeconds"><a href="./values.yaml#L157">sessionProxy.reconcileIntervalSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
30
</pre>
</div>
			</td>
			<td>The sidecar's session reconcile interval.</td>
		</tr>
		<tr>
			<td id="sessionProxy--replicas"><a href="./values.yaml#L153">sessionProxy.replicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>Replica count for the session-proxy Deployment the operator creates.</td>
		</tr>
		<tr>
			<td id="sessionProxy--resolver"><a href="./values.yaml#L386">sessionProxy.resolver</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>DNS server nginx uses to resolve a downstream agent's hostname for the `/desktop` relay, whose upstream comes from the control plane and so is an nginx variable — without a resolver nginx fails those with "no resolver defined" and only a bare IP works. Empty (the default) uses the pod's own cluster DNS (CoreDNS resolves in-cluster names and forwards the rest, so both relayed in-cluster sessions and external VM agents resolve). Set an explicit resolver (e.g. `8.8.8.8` or a corporate DNS) for a cluster whose DNS won't resolve the downstream's name. Omitted from the Agent when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--resources"><a href="./values.yaml#L187">sessionProxy.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Resource requests/limits for the nginx container, as a Kubernetes `ResourceRequirements` map (`requests:`/`limits:`). Set requests: without them the proxy counts for nothing in the scheduler's or a node autoscaler's arithmetic and can be packed onto a node that is then scaled away, taking its sessions with it. Omitted from the Agent resource when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--routing"><a href="./values.yaml#L164">sessionProxy.routing</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
dynamic
</pre>
</div>
			</td>
			<td>How the proxy finds a session's workspace, `static` or `dynamic`. `dynamic` (the default) has nginx look the workspace up per request in a table the sidecar keeps current, with no reload; it needs a session-proxy image carrying nginx's njs module (`kasmweb/nginx`, the default image, has it). `static` has the sidecar write an nginx location per session and reload nginx whenever one comes or goes; a reload replaces every worker, and the old ones live on for as long as the connections they hold, so under heavy session churn worker generations pile up without bound. Changing this restarts the proxy.</td>
		</tr>
		<tr>
			<td id="sessionProxy--selfSigned"><a href="./values.yaml#L268">sessionProxy.selfSigned</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
</pre>
</div>
			</td>
			<td>Last-resort certificate for the session proxy, so that an install with no certificate configured still starts instead of the proxy never coming up. </td>
		</tr>
		<tr>
			<td id="sessionProxy--selfSigned--enabled"><a href="./values.yaml#L279">sessionProxy.selfSigned.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Generate a self-signed certificate at `certSecretName` when `sessionProxy.certificate.enabled` is false and no Secret of that name exists yet. A Secret this release generated is reused across upgrades (and regenerated when `publicHostname` changes); a Secret created by anyone else is left untouched and mounted as-is, so pre-creating your own before the first install still works.  On the default proxied topology this certificate is never shown to a browser. On the direct-connect paths browsers do see it, and it **must** be replaced with a publicly trusted one - set `sessionProxy.certificate.enabled`, or pre-create the Secret. </td>
		</tr>
		<tr>
			<td id="sessionProxy--service"><a href="./values.yaml#L310">sessionProxy.service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
externalTrafficPolicy: ""
httpNodePort: ""
httpPort: ""
httpsNodePort: ""
httpsPort: ""
type: ClusterIP
</pre>
</div>
			</td>
			<td>Overrides for the session-proxy Service the operator creates. Left alone, the operator creates a plain `ClusterIP` Service and something in front of it - `httpRoute`, `ingress`, `route` or `tlsRoute` - publishes it. Set these to publish the session proxy directly instead, with no ingress layer at all. The whole block is omitted from the Agent resource while it holds nothing but defaults, which leaves the operator's own defaults in charge.</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--annotations"><a href="./values.yaml#L327">sessionProxy.service.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Annotations set on the session-proxy Service. This is where cloud load-balancer attributes belong: NLB versus ALB, an internal-only scheme, a MetalLB address pool, or PROXY protocol on the load balancer itself (which the listeners then have to be told to expect - see `sessionProxy.proxyProtocol`). Omitted from the Agent resource when empty. Example (AWS NLB, PROXY protocol v2 towards the pods):   annotations:     service.beta.kubernetes.io/aws-load-balancer-type: external     service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip     service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--externalTrafficPolicy"><a href="./values.yaml#L335">sessionProxy.service.externalTrafficPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>How the Service treats the client source address - `Cluster` or `Local`. `Cluster`, the Kubernetes default, SNATs it, so the session proxy sees the node's address instead of the user's. `Local` preserves the real client IP, but only routes traffic through nodes that are hosting a session-proxy pod: a node without one blackholes the connection. Pair it with a load balancer that honours the Service's health check, or make sure every node it advertises runs a proxy pod (raise `sessionProxy.replicas`, or pin the pods with `nodeSelector`). Omitted from the Agent resource when empty, which leaves the operator and Kubernetes at `Cluster`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--httpNodePort"><a href="./values.yaml#L347">sessionProxy.service.httpNodePort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Pin the node port for the proxy's plain-HTTP listener (4445), the one to use when TLS is terminated by something in front. Same rules as `httpsNodePort`: `NodePort` and `LoadBalancer` types only, inside 30000-32767, omitted from the Agent resource when empty, and stable across reconciles even when left unpinned.</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--httpPort"><a href="./values.yaml#L354">sessionProxy.service.httpPort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Service-facing port for the HTTP (4445) listener, for example `80`. The container keeps listening on 4445. Empty keeps 4445.</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--httpsNodePort"><a href="./values.yaml#L342">sessionProxy.service.httpsNodePort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Pin the node port for the proxy's own HTTPS listener (4444) instead of letting Kubernetes allocate one. Applies to the `NodePort` and `LoadBalancer` types only, and must fall inside the cluster's node-port range - the CRD rejects anything outside 30000-32767. Omitted from the Agent resource when empty. Leave it unset unless a firewall rule or an external load balancer has to be pointed at a fixed port: the operator carries whatever port Kubernetes allocated across reconciles, so an unpinned port is stable in practice anyway.</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--httpsPort"><a href="./values.yaml#L351">sessionProxy.service.httpsPort</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Service-facing port for the HTTPS (4444) listener, for example `443` so a `LoadBalancer` publishes the session proxy on 443 without touching the zone's port or `publicPort`. The container keeps listening on 4444. Empty keeps 4444.</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--type"><a href="./values.yaml#L317">sessionProxy.service.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
ClusterIP
</pre>
</div>
			</td>
			<td>Type of the session-proxy Service - `ClusterIP`, `NodePort` or `LoadBalancer`. `ClusterIP`, the default, keeps the proxy in-cluster and expects one of the route or ingress options to publish it. `NodePort` publishes it on a port of every node; `LoadBalancer` additionally asks the cloud provider (or MetalLB) for an external address. Both of the latter need the surrounding environment to actually route those ports to the nodes - VM or cloud firewalls that only forward 443/80 will refuse the connection before Kubernetes ever sees it.</td>
		</tr>
		<tr>
			<td id="sessionProxy--sidecarImage"><a href="./values.yaml#L144">sessionProxy.sidecarImage</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry: docker.io
repository: kasmweb/kasm-nginx-sidecar
tag: ""
</pre>
</div>
			</td>
			<td>The kasm-nginx-sidecar image that materializes per-session nginx config and reloads the proxy.</td>
		</tr>
		<tr>
			<td id="sessionProxy--sidecarImage--registry"><a href="./values.yaml#L146">sessionProxy.sidecarImage.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
docker.io
</pre>
</div>
			</td>
			<td>Registry that hosts the sidecar image.</td>
		</tr>
		<tr>
			<td id="sessionProxy--sidecarImage--repository"><a href="./values.yaml#L148">sessionProxy.sidecarImage.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
kasmweb/kasm-nginx-sidecar
</pre>
</div>
			</td>
			<td>Repository of the sidecar image, without the registry or tag.</td>
		</tr>
		<tr>
			<td id="sessionProxy--sidecarImage--tag"><a href="./values.yaml#L151">sessionProxy.sidecarImage.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag of the sidecar image. Leave empty to fall back to the chart's `appVersion`.</td>
		</tr>
		<tr>
			<td id="sessionProxy--sidecarResources"><a href="./values.yaml#L190">sessionProxy.sidecarResources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Resource requests/limits for the kasm-nginx-sidecar container, same shape as `sessionProxy.resources`. Omitted from the Agent resource when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--tolerations"><a href="./values.yaml#L196">sessionProxy.tolerations</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Tolerations for the proxy pods. Omitted from the Agent resource when empty.</td>
		</tr>
		<tr>
			<td id="sessionProxy--topologySpreadConstraints"><a href="./values.yaml#L203">sessionProxy.topologySpreadConstraints</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Topology spread constraints for the proxy pods. With more than one replica and none set, the operator spreads replicas across nodes where it can. Omitted from the Agent resource when empty.</td>
		</tr>
		<tr>
			<td id="storageMappings"><a href="./values.yaml#L557">storageMappings</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
installationID: ""
</pre>
</div>
			</td>
			<td>rclone CSI storage mappings for workspace volumes. The whole block is omitted from the Agent resource when it is disabled and no installation ID is set. </td>
		</tr>
		<tr>
			<td id="storageMappings--enabled"><a href="./values.yaml#L559">storageMappings.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Turn on rclone CSI storage mappings.</td>
		</tr>
		<tr>
			<td id="storageMappings--installationID"><a href="./values.yaml#L562">storageMappings.installationID</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Scopes the derived StorageClass and Secret names. Defaults to the Agent resource name when empty.</td>
		</tr>
		<tr>
			<td id="tlsRoute"><a href="./values.yaml#L892">tlsRoute</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
apiVersion: ""
backendPort: 4444
enabled: false
hostnames: []
parentRefs: []
</pre>
</div>
			</td>
			<td>Optionally expose the operator-created session-proxy Service through a Gateway API TLSRoute: SNI-based TLS passthrough, giving end-to-end TLS to the session proxy's own certificate the way an OpenShift `passthrough` Route does, but on any cluster with the Gateway API rather than only on OpenShift. </td>
		</tr>
		<tr>
			<td id="tlsRoute--apiVersion"><a href="./values.yaml#L927">tlsRoute.apiVersion</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>API version to render the TLSRoute with. Empty (the default) picks `gateway.networking.k8s.io/v1` when the cluster serves it (Gateway API 1.5+ standard channel), falls back to `gateway.networking.k8s.io/v1alpha2` when only the older experimental-channel CRD is served, and uses `v1` when rendering without a cluster (`helm template`). Set it to override that choice, for example when rendering offline for a cluster that still serves only `v1alpha2`.</td>
		</tr>
		<tr>
			<td id="tlsRoute--backendPort"><a href="./values.yaml#L921">tlsRoute.backendPort</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
4444
</pre>
</div>
			</td>
			<td>Port on the session-proxy Service to forward to. The default, 4444, is the proxy's own HTTPS listener - the only port that makes sense under passthrough, since nothing terminates TLS before the connection gets there.</td>
		</tr>
		<tr>
			<td id="tlsRoute--enabled"><a href="./values.yaml#L903">tlsRoute.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Render the TLSRoute from this chart. Requires the TLSRoute CRD - standard channel as `v1` since Gateway API 1.5 (Kubernetes 1.31+); older experimental-channel installs serve only `v1alpha2`, which the chart falls back to (see `tlsRoute.apiVersion`) - and a Gateway that has a listener with `protocol: TLS` and `tls.mode: Passthrough` whose `allowedRoutes` admits this namespace. `httpRoute`, `ingress`, `route`, `tlsRoute` and `gatewayRoute` are alternatives - enable at most one of the five, since all of them point at the same operator-created session-proxy Service. `gatewayRoute` below produces the same passthrough route but has the operator create and reconcile it; prefer that when the operator supports it, and reach for this chart-managed one otherwise. Nothing decrypts the connection on the way, so the Gateway sets no timeouts and applies no HTTP rules: Kasm's long-lived session websockets are bounded only by the layer-4 idle timeout of the Gateway's data plane and of anything in front of it.</td>
		</tr>
		<tr>
			<td id="tlsRoute--hostnames"><a href="./values.yaml#L917">tlsRoute.hostnames</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>SNI hostnames the route matches. Defaults to a single-entry list holding `publicHostname` when empty. Because the connection is passed through untouched, the browser validates the session proxy's own certificate (`sessionProxy.certSecretName`) against these names, so that certificate has to cover them - enable `sessionProxy.certificate` or provision the Secret out of band.</td>
		</tr>
		<tr>
			<td id="tlsRoute--parentRefs"><a href="./values.yaml#L912">tlsRoute.parentRefs</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Gateways to attach the route to, as a list of `{name, namespace}` objects. The route attaches to nothing - and the session proxy stays unreachable through the Gateway - if this is left empty. Only the `parentRefs` cross namespaces; the backend stays in this one, so no `ReferenceGrant` is needed. Example:   parentRefs:     - name: traefik-gateway       namespace: kube-system</td>
		</tr>
		<tr>
			<td id="workspaceCPURequestPercent"><a href="./values.yaml#L427">workspaceCPURequestPercent</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
100
</pre>
</div>
			</td>
			<td>Share (1-100) of a workspace image's cores that each session pod reserves as its Kubernetes CPU *request*. The manager sizes cores as a soft hint the Docker agent only ever applied as a scheduling weight; as a Kubernetes request they are a hard reservation, so at the default `100` a mostly idle desktop still holds a whole core and nodes fill long before they are busy. Lower it to bin-pack more sessions per node: `25` lets four 1-core sessions share one core's worth of requests. A CPU *limit* (on "Quotas" images) is unaffected, so sessions can still burst to their full size. The agent scales the capacity it reports to the manager by the same factor, so session accounting keeps matching what the scheduler can place. </td>
		</tr>
		<tr>
			<td id="workspaceLabels"><a href="./values.yaml#L39">workspaceLabels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Extra Kubernetes labels the operator stamps onto every workspace (session) pod this agent launches, and its resources. A session's own labels layer on top, winning on conflicting keys. Distinct from agentLabels, which target the agent's own workloads. </td>
		</tr>
		<tr>
			<td id="workspaceSecurity"><a href="./values.yaml#L687">workspaceSecurity</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
fsGroupChangePolicy: ""
profile: ""
rootFeatures: ""
rootMode: ""
sudo: false
supplementalGroups: []
userNamespaces: ""
</pre>
</div>
			</td>
			<td>How session containers run, rendered as the Agent's `spec.workspaceSecurity`. Stock Kasm images run as `kasm-user` (uid/gid 1000), and so does every session by default: `runAsNonRoot`, `allowPrivilegeEscalation: false`, every capability dropped except the few the profile below adds. An image that needs root - a run config with `user: root`, root `exec_configs` from the manager, or session recording - gets it the way `rootMode` says. Every field is optional: an empty one is omitted from the Agent and the CRD's default applies, and the whole block is omitted while every field is empty. Each session pod is labelled `kasm.com/run-mode` with `nonroot`, `userns-root` or `host-root`, for cluster policy to match on. </td>
		</tr>
		<tr>
			<td id="workspaceSecurity--fsGroupChangePolicy"><a href="./values.yaml#L730">workspaceSecurity.fsGroupChangePolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Applied to every session pod's volumes: `OnRootMismatch` (the default) skips the recursive ownership pass when a volume's root already belongs to fsGroup 1000, `Always` redoes it on every mount. Large persistent profiles start faster with the default.</td>
		</tr>
		<tr>
			<td id="workspaceSecurity--profile"><a href="./values.yaml#L716">workspaceSecurity.profile</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The capability shape of uid-1000 sessions, named after the Pod Security Standards level it satisfies. `baseline` (the default) adds `SYS_CHROOT` (Chromium's sandbox and bubblewrap need it, and Docker grants it by default) plus whatever the image's run config `cap_add`s, and an inline seccomp profile with no backend falls back to `Unconfined`. `restricted` adds nothing but `NET_BIND_SERVICE` when asked for, drops other `cap_add`s with a warning, and falls back to `RuntimeDefault`; it cannot be combined with `rootMode: host` or `sudo`.</td>
		</tr>
		<tr>
			<td id="workspaceSecurity--rootFeatures"><a href="./values.yaml#L709">workspaceSecurity.rootFeatures</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>What happens when an image that would run as uid 1000 asks for something only root can do (root `exec_configs` start or stop commands, or session recording): `promote` (the default) runs that session in `rootMode` so the feature works; `downgrade` keeps it at uid 1000, runs the commands as `kasm-user`, switches recording off and flags the KasmWorkspace; `reject` refuses the launch. `downgrade` is also the way to keep such images working on NFS-backed profiles under `rootMode: userns`.</td>
		</tr>
		<tr>
			<td id="workspaceSecurity--rootMode"><a href="./values.yaml#L698">workspaceSecurity.rootMode</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>How a session that needs root gets it: `userns` (the default) runs it as uid 0 inside a pod user namespace (`hostUsers: false`), root in the pod and an unprivileged uid on the node. User namespaces need Kubernetes 1.33+ (on by default; GA in 1.36; OpenShift 4.20), containerd 2.0+ or CRI-O 1.25+, and a 6.3+ kernel on the session nodes, and a user-namespace pod cannot mount an NFS-backed volume (NFS or EFS persistent profiles, NFS storage mappings; the container fails to create with an idmap `mount_setattr` error), while S3-style profiles and block storage are unaffected. `host` runs it as host uid 0, the way every session ran before user namespaces: it works on any node and any volume, but a container escape is root on the node, the namespace needs the `privileged` Pod Security level, and on OpenShift the workspace SCC admits host root. `forbid` refuses root outright: an image whose run config asks for it fails to launch, and root-needing features follow `rootFeatures` as if set to `downgrade`.</td>
		</tr>
		<tr>
			<td id="workspaceSecurity--sudo"><a href="./values.yaml#L720">workspaceSecurity.sudo</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Keep privilege escalation on and add `SETUID`/`SETGID` to uid-1000 sessions, so an image's baked-in sudoers entry works. Off by default: `sudo` inside a session is a path back to root in the container. Not allowed with `profile: restricted`.</td>
		</tr>
		<tr>
			<td id="workspaceSecurity--supplementalGroups"><a href="./values.yaml#L726">workspaceSecurity.supplementalGroups</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Extra group ids added to every session pod, on top of the image's run config `group_add`. The usual use is the node's `render` or `video` gid, so a uid-1000 session can open `/dev/dri` or a webcam device. Omitted when empty. Example:   supplementalGroups: [44, 109]</td>
		</tr>
		<tr>
			<td id="workspaceSecurity--userNamespaces"><a href="./values.yaml#L703">workspaceSecurity.userNamespaces</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Which sessions get a pod user namespace: `rootOnly` (the default) gives one only to root sessions under `rootMode: userns`; `always` gives every session one, uid 1000 included, for the extra isolation, at the cost of every session inheriting the user-namespace limits (no NFS-backed volumes, device ownership unmapped). `always` contradicts `rootMode: host`, and the chart refuses the pair.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling"><a href="./values.yaml#L492">workspacesAutoscaling</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
maxNodes: 0
schedulingTimeoutSeconds: 600
standby:
    enabled: false
    externallyScaled: false
    image: registry.k8s.io/pause:3.10
    priorityClass:
        create: true
        value: -10
    priorityClassName: ""
    replicas: 1
    resources: {}
</pre>
</div>
			</td>
			<td>Grow workspace capacity on demand, in two independent ways. Off by default (nothing here changes behaviour while both halves are disabled), and the whole block is omitted from the Agent unless one is enabled. `enabled` lets a session wait for a node a cluster autoscaler (Cluster Autoscaler, Karpenter, a cloud node pool) can add, instead of the launch failing when the pool is full: the agent counts nodes the autoscaler could still add as capacity (so the manager still routes the launch), stops withholding an image that would fit a fresh node, and marks the pending workspace `WaitingForCapacity` until a node joins or the timeout passes (needs an autoscaler watching for unschedulable pods on the workspace nodes). `standby` below keeps room ready ahead of demand so nobody waits. The two work independently.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--enabled"><a href="./values.yaml#L494">workspacesAutoscaling.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Turn autoscaling-aware waiting on.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--maxNodes"><a href="./values.yaml#L498">workspacesAutoscaling.maxNodes</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
0
</pre>
</div>
			</td>
			<td>The most workspace nodes the autoscaler will run; capacity is counted up to this many. `0` (the default) leaves it unset, so the pool is treated as able to grow by one node past what is running and never looks full while it can still grow. Minimum 1 when set.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--schedulingTimeoutSeconds"><a href="./values.yaml#L502">workspacesAutoscaling.schedulingTimeoutSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
600
</pre>
</div>
			</td>
			<td>How long an unschedulable session waits for a node before it fails with the scheduler's message. The clock restarts once the pod is scheduled (a fresh node has no pre-pulled images). Minimum 60.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby"><a href="./values.yaml#L511">workspacesAutoscaling.standby</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
externallyScaled: false
image: registry.k8s.io/pause:3.10
priorityClass:
    create: true
    value: -10
priorityClassName: ""
replicas: 1
resources: {}
</pre>
</div>
			</td>
			<td>Keep spare room for sessions ready ahead of demand: a Deployment of low-priority pause-container placeholders, each requesting what a session does, on the same nodes workspaces use (they follow `workspacesNodeSelector`/`workspacesTolerations`). A session that needs the room evicts a placeholder and starts at once; the evicted placeholder then goes unschedulable, which is what makes a node autoscaler add a node, so the headroom returns with nobody waiting. Works with or without `workspacesAutoscaling.enabled` above: standby alone gives instant starts until a burst exhausts the headroom (then launches are refused as on a fixed cluster unless `enabled` is also on to make them wait for a node). Off by default; omitted from the Agent unless `enabled` below is true.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--enabled"><a href="./values.yaml#L513">workspacesAutoscaling.standby.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Create the placeholder Deployment.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--externallyScaled"><a href="./values.yaml#L543">workspacesAutoscaling.standby.externallyScaled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Leave the replica count to a KEDA ScaledObject or an HPA after creation; the operator then sets `replicas` only once, at creation. Use this to scale placeholders with real demand. You supply the autoscaler yourself, targeting the placeholder Deployment `<name>-workspace-standby` (scale on running session pods, `app.kubernetes.io/component=workspace`). See the Capacity docs for a KEDA example.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--image"><a href="./values.yaml#L546">workspacesAutoscaling.standby.image</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
registry.k8s.io/pause:3.10
</pre>
</div>
			</td>
			<td>The placeholder container image. The default is a bare pause container.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--priorityClass"><a href="./values.yaml#L525">workspacesAutoscaling.standby.priorityClass</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
create: true
value: -10
</pre>
</div>
			</td>
			<td>Whether this chart creates the PriorityClass named above. A PriorityClass is a *cluster-scoped* object, so more than one agent release with `create` on must use distinct `priorityClassName`s to avoid an ownership clash; set `create: false` on the extras (or all of them) to reference a shared, admin-managed class.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--priorityClass--create"><a href="./values.yaml#L530">workspacesAutoscaling.standby.priorityClass.create</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Create the PriorityClass named by `priorityClassName` with `value` below. Default true: standby works out of the box. Set false to reference an existing PriorityClass instead. When true, `priorityClassName` must be set and `value` negative.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--priorityClass--value"><a href="./values.yaml#L534">workspacesAutoscaling.standby.priorityClass.value</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
-10
</pre>
</div>
			</td>
			<td>The (negative) value for the created PriorityClass. Only used when `create` is true; rendering fails if it is not below zero, since a session must be able to preempt a placeholder.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--priorityClassName"><a href="./values.yaml#L520">workspacesAutoscaling.standby.priorityClassName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Names the PriorityClass the placeholders run under: one with a *negative* value, so a real session (default priority) outranks it and the scheduler evicts a placeholder to make room, and the agent knows the placeholders' room is free to give away. Leave empty (the default) to derive it from the agent name as `<name>-standby`, so standby works with nothing else set. By default the chart also creates it (see `priorityClass.create`); set `priorityClass.create: false` to reference one a cluster admin manages out-of-band instead — set an explicit name here to match theirs.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--replicas"><a href="./values.yaml#L537">workspacesAutoscaling.standby.replicas</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>How many placeholders to keep. Applied when the Deployment is created and kept in step afterwards, unless `externallyScaled`. Minimum 0.</td>
		</tr>
		<tr>
			<td id="workspacesAutoscaling--standby--resources"><a href="./values.yaml#L552">workspacesAutoscaling.standby.resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>What each placeholder reserves, as a bare resource map (e.g. `{cpu: "2", memory: 2Gi}`) applied as both the request and the limit — NOT a pod-style `{requests, limits}` block. Leave empty to size it to the largest workspace in the agent's catalog (the agent reports this as status.workspaces.largestRequest), so one placeholder's room fits any image; until that is known, no placeholders are created. Set the map to pin a size instead.</td>
		</tr>
		<tr>
			<td id="workspacesNodeSelector"><a href="./values.yaml#L469">workspacesNodeSelector</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Node selector the agent applies to the workspace pods it launches. Distinct from `nodeSelector`, which places the agent itself. Omitted from the Agent resource entirely when empty. </td>
		</tr>
		<tr>
			<td id="workspacesTolerations"><a href="./values.yaml#L482">workspacesTolerations</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Tolerations every workspace pod the agent launches carries, with a workspace template's own tolerations appended per session. Set them when sessions are meant to run on tainted nodes, such as a dedicated pool tainted `kasm.com/workspaces=true:NoSchedule`. They also scope the agent's image puller and its capacity report: a node whose NoSchedule/NoExecute taints these do not tolerate is left out of the CPU and memory the agent advertises to the manager. Omitted when empty. Example:   workspacesTolerations:     - key: kasm.com/workspaces       operator: Exists       effect: NoSchedule </td>
		</tr>
		<tr>
			<td id="zone"><a href="./values.yaml#L127">zone</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
default
</pre>
</div>
			</td>
			<td>Deployment zone the agent reports to the manager. Must match a zone configured on the control plane. </td>
		</tr>
	</tbody>
</table>

