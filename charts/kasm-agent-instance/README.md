# Kasm Agent Instance

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

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

## Prerequisites

* Kubernetes 1.26 or newer — the shared floor for the whole `kasm-agent` family (older versions of Kubernetes may work, however, we try to keep this chart updated to [supported versions of Kubernetes](https://kubernetes.io/releases/))
* Helm 3.18.x or newer ([installation](https://helm.sh/docs/helm/helm_install/))
* The Kasm agent operator, and its `agent.kasm.com` CRDs, installed in the cluster. This chart creates custom resources; it does not install the controller that reconciles them.
* A reachable Kasm control plane, and the shared manager token for it.
* [cert-manager](https://cert-manager.io/) when `sessionProxy.certificate.enabled` is set, the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs plus a Gateway when `httpRoute.enabled` is set, the Gateway API's **experimental** channel CRDs plus a Gateway with a `Passthrough` TLS listener when either `gatewayRoute.enabled` or `tlsRoute.enabled` is set, an ingress controller when `ingress.enabled` is set, and OpenShift (the `route.openshift.io` API) when `route.enabled` is set.

## What this chart deploys

* An `Agent` custom resource. The operator reconciles it into the agent Deployment, the session-proxy Deployment, and a session-proxy Service named `<name>-session-proxy`. None of those are created by this chart.
* A `Secret` holding the manager token, only when the token is supplied inline via `manager.token`. Referencing an existing Secret through `manager.existingTokenSecret` is preferred and takes precedence.
* Optionally, a cert-manager `Certificate` for the session proxy's HTTPS listener, a `KasmImagePuller` that pre-stages workspace images on every node, and - to expose the session proxy at the agent's public hostname - one of a Gateway API `HTTPRoute`, a Gateway API `TLSRoute`, a classic `networking.k8s.io/v1` `Ingress`, or an OpenShift `Route`. The `TLSRoute` can instead be delegated to the operator via `gatewayRoute`, in which case this chart creates no route object of its own. The session-proxy Service can also be published directly, without any of those, through `sessionProxy.service`.

## External access

The session-proxy Service the operator creates is a `ClusterIP` by default, reachable only inside the cluster. This chart offers five mutually exclusive ways to publish it at `publicHostname`; enable at most one, because all of them point at the same Service:

* `httpRoute.enabled` renders a Gateway API `HTTPRoute` attached to the Gateways in `httpRoute.parentRefs`. The Gateway's listener has to allow routes from this namespace. Only the `parentRefs` cross namespaces, so no `ReferenceGrant` is needed.
* `ingress.enabled` renders a `networking.k8s.io/v1` `Ingress` on `ingress.className`, with one `/` `Prefix` rule per entry in `ingress.hosts`, TLS from `ingress.tls`, and annotations from `ingress.annotations` merged over `commonAnnotations`.
* `route.enabled` renders an OpenShift `route.openshift.io/v1` `Route` for `route.host`, the native option on OpenShift.
* `gatewayRoute.enabled` asks the **operator** to create a Gateway API `TLSRoute` - SNI-based TLS passthrough, the same end-to-end shape as the OpenShift `Route` but on any cluster with the Gateway API.
* `tlsRoute.enabled` renders that same passthrough `TLSRoute` **from this chart** instead.

All five default their hostname to `publicHostname`.

Or skip the ingress layer entirely and publish the session-proxy Service itself - see below.

### `gatewayRoute` vs `tlsRoute` — who owns the route

Both produce a `gateway.networking.k8s.io/v1alpha2` `TLSRoute` doing SNI-based passthrough to the session proxy, and both need the same things from the cluster: `TLSRoute` ships in the Gateway API's **experimental** channel only, and the Gateway needs a listener with `protocol: TLS` and `tls.mode: Passthrough` whose `allowedRoutes` admits this namespace. What differs is ownership.

**Prefer `gatewayRoute` when the operator supports it.** The operator creates and reconciles the route itself, alongside the session-proxy Service it already owns, so the two cannot drift apart:

```yaml
gatewayRoute:
  enabled: true
  parentRef:
    name: traefik-gateway
    namespace: kube-system
    sectionName: tls-passthrough   # optional: pick one listener on the Gateway
```

Note the shape: `gatewayRoute.parentRef` is a **single** reference, where `tlsRoute.parentRefs` is a list. `parentRef.name` is required whenever `gatewayRoute.enabled` is true and templating fails without it. `gatewayRoute.hostnames` is left empty in the normal case — the *operator* defaults it to `[publicHostname]`, so this chart omits the field rather than filling it in.

Reach for `tlsRoute` when the operator predates `spec.gatewayRoute`, or when the route has to be a Helm-release object — owned by the release, torn down with it, patched by other release tooling — rather than an operator-owned one. That path takes a list of `parentRefs`, defaults `hostnames` to `publicHostname` in the chart, and exposes a `backendPort` (4444, the proxy's own HTTPS listener).

### LoadBalancer / NodePort — no ingress layer at all

Publishing the session proxy directly — a cloud NLB straight onto sessions, a corporate load
balancer forwarding to NodePorts, external SSL termination handing plain HTTP to the cluster — is
first-class: `sessionProxy.service` is passed through to the Agent, and the operator applies it to
the session-proxy Service it owns. The whole block is omitted from the Agent resource while it holds
nothing but defaults, so leaving it alone keeps the plain `ClusterIP` the operator creates on its
own; any single non-default value pulls it in.

NodePort with pinned ports, preserving the client IP:

```yaml
sessionProxy:
  service:
    type: NodePort
    externalTrafficPolicy: Local   # real client IPs; see the caveat below
    httpsNodePort: 30443           # the proxy's own TLS listener (4444)
    httpNodePort: 30080            # plain HTTP (4445), for TLS terminated in front
```

LoadBalancer with cloud annotations:

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

`httpsNodePort` and `httpNodePort` are only worth pinning when a firewall rule or an external load
balancer has to be aimed at a fixed port: the operator carries the ports Kubernetes allocated across
reconciles, so an unpinned NodePort stays stable in practice anyway. Both must fall inside the
cluster's node-port range — the CRD rejects anything outside 30000–32767.

Two caveats carry over regardless of how the Service is created. With `networkPolicies` enabled the
session-ingress allow must cover the exposure path (`networkPolicies.sessionProxy.ports` already
admits 4444/4445 from anywhere by default). And NodePort reachability from outside depends on your
environment actually routing the 30000–32767 range to the nodes — VM/cloud firewalls that only
forward 443/80 will refuse the connection before Kubernetes ever sees it (verified: the same
NodePort answers in-cluster while an unrouted LAN client gets connection-refused).

#### Preserving the client IP

Two independent mechanisms, at different layers; pick the one that matches how traffic actually
reaches the proxy.

`sessionProxy.service.externalTrafficPolicy: Local` works at **L4**. `Cluster`, the Kubernetes
default, SNATs the connection, so the session proxy logs the node's address instead of the user's.
`Local` skips that SNAT — but it also only routes traffic through nodes that are hosting a
session-proxy pod, and a node without one blackholes the connection. Pair it with a load balancer
that honours the Service's health check, or make sure every node it advertises runs a proxy pod
(raise `sessionProxy.replicas`, or pin the pods with `nodeSelector`).

`sessionProxy.proxyProtocol` works at **L7**, for an external L4 proxy that cannot set
`X-Forwarded-For` but can prepend a PROXY protocol header:

```yaml
sessionProxy:
  proxyProtocol:
    enabled: true
    trustedCIDRs:               # the fronting LB's own source range
      - 10.0.0.0/16
```

This one is all-or-nothing and needs both ends configured. Enabling it turns on `proxy_protocol` on
both nginx listeners, and nginx then **requires** a PROXY header on every connection with no
fallback: once it is on, anything connecting directly — a browser hitting the NodePort, a health
check, `curl` against the Service — fails on those listeners. Turn it on only together with the
matching setting on the load balancer in front (for example
`service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"` in
`sessionProxy.service.annotations`). `trustedCIDRs` is the set of source ranges nginx trusts to send
an accurate header — normally the fronting load balancer's address range: its node subnet, the cloud
LB's CIDR, the MetalLB pool.

#### Older operator builds

Before the operator grew `sessionProxy.service`, the working pattern was a **second Service** you
own, deployed through the umbrella chart's `extraObjects` — the operator ignores it, and its
selector matches the proxy pods, whose labels are stable. It still works, and remains the fallback
when running an operator that predates the field:

```yaml
# kasm-agent umbrella values — alongside agent.*
extraObjects:
  - apiVersion: v1
    kind: Service
    metadata:
      # "k8s-agent" is the default agent.name — keep the two in sync if you change it.
      name: k8s-agent-session-proxy-external
    spec:
      type: LoadBalancer             # or NodePort
      externalTrafficPolicy: Local
      selector:
        app.kubernetes.io/name: k8s-agent          # = agent.name
        app.kubernetes.io/component: session-proxy
      ports:
        - name: https                # the proxy's own TLS listener
          port: 443
          targetPort: 4444
```

### Where TLS terminates

The session proxy listens on two ports: 4445 is plain HTTP, and 4444 is its own HTTPS listener, served with the certificate in `sessionProxy.certSecretName`.

`httpRoute` and `ingress` both default to backend port 4445 - TLS for the public hostname terminates at the Gateway or the Ingress. Routing them to 4444 instead means telling the controller to speak TLS upstream (`nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` on ingress-nginx).

The `Route` defaults to `passthrough` termination, matching the Kasm operator's OpenShift example: the router forwards the TLS connection untouched, so browsers see the session proxy's certificate directly. That certificate therefore has to be valid for `route.host` - enable `sessionProxy.certificate` or provision `sessionProxy.certSecretName` out of band before using it. `route.backendPort` follows the termination mode when left empty: 4444 for `passthrough` and `reencrypt`, 4445 for `edge`, which terminates at the router instead. `reencrypt` additionally accepts a `route.tls.destinationCACertificate` for validating the proxy's certificate, and `edge` accepts `route.tls.key`/`certificate` plus an `insecureEdgeTerminationPolicy` of `Redirect`.

Both `TLSRoute` options - operator-managed `gatewayRoute` and chart-managed `tlsRoute` - are passthrough too, and for the same reason browsers end up validating the session proxy's own certificate, but through the Gateway API rather than the OpenShift router. They are what to reach for when you want end-to-end TLS on a cluster that is not OpenShift. The Gateway matches on SNI alone and splices the connection through without decrypting it, which is why `tlsRoute.backendPort` defaults to 4444 (nothing terminates TLS earlier, so the plain-HTTP listener would never work) and why the proxy's certificate has to cover every hostname in force - whether set explicitly or defaulted to `publicHostname`. Both require support on the Gateway side that the `HTTPRoute` path does not: `TLSRoute` is an experimental-channel CRD, and the Gateway needs a listener declared with `protocol: TLS` and `tls.mode: Passthrough` - a normal terminating HTTPS listener will not serve it.

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

Two values have no defaults and must be set:

* `manager.hostname` - the Kasm manager (or the proxy in front of it) this agent registers with.
* `publicHostname` - the externally reachable address browsers use to connect to this agent's session proxy.

Exactly one of `manager.existingTokenSecret` or `manager.token` must also be set. Templating fails with a specific message when any of these is missing.

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
			<td id="apiServerURL"><a href="./values.yaml#L253">apiServerURL</a></td>
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
			<td id="commonAnnotations"><a href="./values.yaml#L18">commonAnnotations</a></td>
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
			<td id="commonLabels"><a href="./values.yaml#L14">commonLabels</a></td>
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
			<td>Custom labels to apply to every resource created by this chart. </td>
		</tr>
		<tr>
			<td id="env"><a href="./values.yaml#L280">env</a></td>
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
			<td id="gatewayRoute"><a href="./values.yaml#L468">gatewayRoute</a></td>
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
			<td id="gatewayRoute--enabled"><a href="./values.yaml#L475">gatewayRoute.enabled</a></td>
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
			<td>Have the operator create the TLSRoute. Same cluster-side prerequisites as `tlsRoute`: the Gateway API *experimental* channel CRDs, and a Gateway with a `protocol: TLS` / `tls.mode: Passthrough` listener whose `allowedRoutes` admits this namespace. `httpRoute`, `ingress`, `route`, `tlsRoute` and `gatewayRoute` are alternatives - enable at most one of the five, since all of them point at the same session-proxy Service. Between the two passthrough options, prefer `gatewayRoute` when the operator supports it and fall back to `tlsRoute` when it does not.</td>
		</tr>
		<tr>
			<td id="gatewayRoute--hostnames"><a href="./values.yaml#L499">gatewayRoute.hostnames</a></td>
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
			<td id="gatewayRoute--parentRef"><a href="./values.yaml#L478">gatewayRoute.parentRef</a></td>
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
			<td id="gatewayRoute--parentRef--name"><a href="./values.yaml#L481">gatewayRoute.parentRef.name</a></td>
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
			<td id="gatewayRoute--parentRef--namespace"><a href="./values.yaml#L484">gatewayRoute.parentRef.namespace</a></td>
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
			<td id="gatewayRoute--parentRef--sectionName"><a href="./values.yaml#L489">gatewayRoute.parentRef.sectionName</a></td>
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
			<td id="gpu"><a href="./values.yaml#L272">gpu</a></td>
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
			<td id="gpu--enabled"><a href="./values.yaml#L274">gpu.enabled</a></td>
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
			<td id="heartbeatIntervalSeconds"><a href="./values.yaml#L192">heartbeatIntervalSeconds</a></td>
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
			<td id="httpRoute"><a href="./values.yaml#L309">httpRoute</a></td>
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
			<td id="httpRoute--backendPort"><a href="./values.yaml#L327">httpRoute.backendPort</a></td>
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
			<td id="httpRoute--enabled"><a href="./values.yaml#L313">httpRoute.enabled</a></td>
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
			<td id="httpRoute--hostnames"><a href="./values.yaml#L323">httpRoute.hostnames</a></td>
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
			<td id="httpRoute--parentRefs"><a href="./values.yaml#L320">httpRoute.parentRefs</a></td>
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
			<td id="image"><a href="./values.yaml#L27">image</a></td>
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
			<td id="image--registry"><a href="./values.yaml#L29">image.registry</a></td>
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
			<td id="image--repository"><a href="./values.yaml#L31">image.repository</a></td>
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
			<td id="image--tag"><a href="./values.yaml#L33">image.tag</a></td>
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
			<td id="imageAvailabilityPolicy"><a href="./values.yaml#L200">imageAvailabilityPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
all
</pre>
</div>
			</td>
			<td>Controls which workspace images the agent reports to the manager as available. </td>
		</tr>
		<tr>
			<td id="imagePullPolicy"><a href="./values.yaml#L204">imagePullPolicy</a></td>
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
			<td id="imagePullSecrets"><a href="./values.yaml#L213">imagePullSecrets</a></td>
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
			<td id="imagePuller"><a href="./values.yaml#L285">imagePuller</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
imagePullPolicy: IfNotPresent
images: []
resources: {}
</pre>
</div>
			</td>
			<td>Optionally pre-pull workspace images onto every targeted node with a KasmImagePuller resource, so the first session on a node does not wait for a cold image pull. </td>
		</tr>
		<tr>
			<td id="imagePuller--enabled"><a href="./values.yaml#L287">imagePuller.enabled</a></td>
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
			<td>Render the KasmImagePuller resource.</td>
		</tr>
		<tr>
			<td id="imagePuller--imagePullPolicy"><a href="./values.yaml#L289">imagePuller.imagePullPolicy</a></td>
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
			<td>Pull policy for the staged images.</td>
		</tr>
		<tr>
			<td id="imagePuller--images"><a href="./values.yaml#L302">imagePuller.images</a></td>
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
			<td>Catalog of images to stage, as a list of `{image, registry, imagePullSecrets}` objects passed through to the resource verbatim. `image` is the full reference and is authoritative for the pull; `registry` is informational; `imagePullSecrets` is an optional per-image list of `{name: <secret>}` references. Example:   images:     - image: kasmweb/chrome:1.18.0       registry: https://index.docker.io/v1/     - image: registry.example.com/team/custom-workspace:1.0       registry: https://registry.example.com       imagePullSecrets:         - name: example-registry</td>
		</tr>
		<tr>
			<td id="imagePuller--resources"><a href="./values.yaml#L305">imagePuller.resources</a></td>
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
			<td>Compute resources for the image-puller DaemonSet's containers, passed through verbatim. Omitted from the resource when empty.</td>
		</tr>
		<tr>
			<td id="ingress"><a href="./values.yaml#L332">ingress</a></td>
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
			<td id="ingress--annotations"><a href="./values.yaml#L348">ingress.annotations</a></td>
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
			<td id="ingress--backendPort"><a href="./values.yaml#L367">ingress.backendPort</a></td>
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
			<td id="ingress--className"><a href="./values.yaml#L340">ingress.className</a></td>
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
			<td id="ingress--enabled"><a href="./values.yaml#L337">ingress.enabled</a></td>
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
			<td id="ingress--hosts"><a href="./values.yaml#L354">ingress.hosts</a></td>
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
			<td id="ingress--tls"><a href="./values.yaml#L362">ingress.tls</a></td>
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
			<td id="logLevel"><a href="./values.yaml#L208">logLevel</a></td>
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
			<td id="manager"><a href="./values.yaml#L37">manager</a></td>
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
			<td id="manager--existingTokenSecret"><a href="./values.yaml#L55">manager.existingTokenSecret</a></td>
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
			<td id="manager--hostname"><a href="./values.yaml#L40">manager.hostname</a></td>
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
			<td id="manager--pathPrefix"><a href="./values.yaml#L47">manager.pathPrefix</a></td>
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
			<td id="manager--port"><a href="./values.yaml#L42">manager.port</a></td>
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
			<td id="manager--scheme"><a href="./values.yaml#L44">manager.scheme</a></td>
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
			<td id="manager--token"><a href="./values.yaml#L52">manager.token</a></td>
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
			<td id="manager--tokenSecretKey"><a href="./values.yaml#L57">manager.tokenSecretKey</a></td>
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
			<td id="metricsIntervalSeconds"><a href="./values.yaml#L196">metricsIntervalSeconds</a></td>
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
			<td>The agent's node/pod metrics scrape interval. </td>
		</tr>
		<tr>
			<td id="name"><a href="./values.yaml#L23">name</a></td>
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
			<td id="nodeSelector"><a href="./values.yaml#L218">nodeSelector</a></td>
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
			<td id="otel"><a href="./values.yaml#L262">otel</a></td>
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
			<td id="otel--enabled"><a href="./values.yaml#L265">otel.enabled</a></td>
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
			<td id="otel--endpoint"><a href="./values.yaml#L268">otel.endpoint</a></td>
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
			<td id="publicHostname"><a href="./values.yaml#L62">publicHostname</a></td>
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
			<td id="publicPort"><a href="./values.yaml#L66">publicPort</a></td>
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
			<td>Port the session proxy is reachable on publicly. </td>
		</tr>
		<tr>
			<td id="resources"><a href="./values.yaml#L258">resources</a></td>
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
			<td id="route"><a href="./values.yaml#L372">route</a></td>
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
			<td id="route--annotations"><a href="./values.yaml#L388">route.annotations</a></td>
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
			<td id="route--backendPort"><a href="./values.yaml#L392">route.backendPort</a></td>
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
			<td id="route--enabled"><a href="./values.yaml#L378">route.enabled</a></td>
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
			<td id="route--host"><a href="./values.yaml#L382">route.host</a></td>
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
			<td id="route--tls"><a href="./values.yaml#L394">route.tls</a></td>
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
			<td id="route--tls--caCertificate"><a href="./values.yaml#L420">route.tls.caCertificate</a></td>
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
			<td id="route--tls--certificate"><a href="./values.yaml#L418">route.tls.certificate</a></td>
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
			<td id="route--tls--destinationCACertificate"><a href="./values.yaml#L423">route.tls.destinationCACertificate</a></td>
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
			<td id="route--tls--insecureEdgeTerminationPolicy"><a href="./values.yaml#L411">route.tls.insecureEdgeTerminationPolicy</a></td>
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
			<td id="route--tls--key"><a href="./values.yaml#L415">route.tls.key</a></td>
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
			<td id="route--tls--termination"><a href="./values.yaml#L407">route.tls.termination</a></td>
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
			<td id="serverID"><a href="./values.yaml#L245">serverID</a></td>
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
			<td id="sessionProxy"><a href="./values.yaml#L75">sessionProxy</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
certSecretName: kasm-session-proxy-tls
certificate:
    commonName: ""
    dnsNames: []
    enabled: false
    issuerRef:
        group: cert-manager.io
        kind: ClusterIssuer
        name: ""
image:
    registry: docker.io
    repository: kasmweb/nginx
    tag: 1.25.3
probeTimeoutSeconds: 120
proxyProtocol:
    enabled: false
    trustedCIDRs: []
reconcileIntervalSeconds: 30
replicas: 1
service:
    annotations: {}
    externalTrafficPolicy: ""
    httpNodePort: ""
    httpsNodePort: ""
    type: ClusterIP
sidecarImage:
    registry: docker.io
    repository: kasmweb/kasm-nginx-sidecar
    tag: ""
</pre>
</div>
			</td>
			<td>The nginx session proxy the operator deploys alongside the agent. It terminates the browser connection and routes it to the workspace container for the session. </td>
		</tr>
		<tr>
			<td id="sessionProxy--certSecretName"><a href="./values.yaml#L104">sessionProxy.certSecretName</a></td>
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
			<td id="sessionProxy--certificate"><a href="./values.yaml#L107">sessionProxy.certificate</a></td>
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
			<td id="sessionProxy--certificate--commonName"><a href="./values.yaml#L112">sessionProxy.certificate.commonName</a></td>
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
			<td id="sessionProxy--certificate--dnsNames"><a href="./values.yaml#L116">sessionProxy.certificate.dnsNames</a></td>
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
			<td id="sessionProxy--certificate--enabled"><a href="./values.yaml#L110">sessionProxy.certificate.enabled</a></td>
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
			<td id="sessionProxy--certificate--issuerRef"><a href="./values.yaml#L118">sessionProxy.certificate.issuerRef</a></td>
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
			<td id="sessionProxy--certificate--issuerRef--group"><a href="./values.yaml#L125">sessionProxy.certificate.issuerRef.group</a></td>
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
			<td id="sessionProxy--certificate--issuerRef--kind"><a href="./values.yaml#L123">sessionProxy.certificate.issuerRef.kind</a></td>
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
			<td id="sessionProxy--certificate--issuerRef--name"><a href="./values.yaml#L121">sessionProxy.certificate.issuerRef.name</a></td>
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
			<td id="sessionProxy--image"><a href="./values.yaml#L77">sessionProxy.image</a></td>
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
			<td id="sessionProxy--image--registry"><a href="./values.yaml#L79">sessionProxy.image.registry</a></td>
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
			<td id="sessionProxy--image--repository"><a href="./values.yaml#L81">sessionProxy.image.repository</a></td>
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
			<td id="sessionProxy--image--tag"><a href="./values.yaml#L84">sessionProxy.image.tag</a></td>
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
			<td id="sessionProxy--probeTimeoutSeconds"><a href="./values.yaml#L98">sessionProxy.probeTimeoutSeconds</a></td>
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
			<td id="sessionProxy--proxyProtocol"><a href="./values.yaml#L174">sessionProxy.proxyProtocol</a></td>
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
			<td id="sessionProxy--proxyProtocol--enabled"><a href="./values.yaml#L180">sessionProxy.proxyProtocol.enabled</a></td>
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
			<td id="sessionProxy--proxyProtocol--trustedCIDRs"><a href="./values.yaml#L188">sessionProxy.proxyProtocol.trustedCIDRs</a></td>
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
			<td id="sessionProxy--reconcileIntervalSeconds"><a href="./values.yaml#L100">sessionProxy.reconcileIntervalSeconds</a></td>
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
			<td id="sessionProxy--replicas"><a href="./values.yaml#L96">sessionProxy.replicas</a></td>
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
			<td id="sessionProxy--service"><a href="./values.yaml#L131">sessionProxy.service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
externalTrafficPolicy: ""
httpNodePort: ""
httpsNodePort: ""
type: ClusterIP
</pre>
</div>
			</td>
			<td>Overrides for the session-proxy Service the operator creates. Left alone, the operator creates a plain `ClusterIP` Service and something in front of it - `httpRoute`, `ingress`, `route` or `tlsRoute` - publishes it. Set these to publish the session proxy directly instead, with no ingress layer at all. The whole block is omitted from the Agent resource while it holds nothing but defaults, which leaves the operator's own defaults in charge.</td>
		</tr>
		<tr>
			<td id="sessionProxy--service--annotations"><a href="./values.yaml#L148">sessionProxy.service.annotations</a></td>
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
			<td id="sessionProxy--service--externalTrafficPolicy"><a href="./values.yaml#L156">sessionProxy.service.externalTrafficPolicy</a></td>
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
			<td id="sessionProxy--service--httpNodePort"><a href="./values.yaml#L168">sessionProxy.service.httpNodePort</a></td>
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
			<td id="sessionProxy--service--httpsNodePort"><a href="./values.yaml#L163">sessionProxy.service.httpsNodePort</a></td>
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
			<td id="sessionProxy--service--type"><a href="./values.yaml#L138">sessionProxy.service.type</a></td>
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
			<td id="sessionProxy--sidecarImage"><a href="./values.yaml#L87">sessionProxy.sidecarImage</a></td>
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
			<td id="sessionProxy--sidecarImage--registry"><a href="./values.yaml#L89">sessionProxy.sidecarImage.registry</a></td>
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
			<td id="sessionProxy--sidecarImage--repository"><a href="./values.yaml#L91">sessionProxy.sidecarImage.repository</a></td>
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
			<td id="sessionProxy--sidecarImage--tag"><a href="./values.yaml#L94">sessionProxy.sidecarImage.tag</a></td>
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
			<td id="storageMappings"><a href="./values.yaml#L234">storageMappings</a></td>
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
			<td id="storageMappings--enabled"><a href="./values.yaml#L236">storageMappings.enabled</a></td>
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
			<td id="storageMappings--installationID"><a href="./values.yaml#L239">storageMappings.installationID</a></td>
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
			<td id="tlsRoute"><a href="./values.yaml#L429">tlsRoute</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
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
			<td id="tlsRoute--backendPort"><a href="./values.yaml#L457">tlsRoute.backendPort</a></td>
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
			<td id="tlsRoute--enabled"><a href="./values.yaml#L439">tlsRoute.enabled</a></td>
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
			<td>Render the TLSRoute from this chart. Requires the Gateway API *experimental* channel CRDs - TLSRoute is not part of the standard channel - and a Gateway that has a listener with `protocol: TLS` and `tls.mode: Passthrough` whose `allowedRoutes` admits this namespace. `httpRoute`, `ingress`, `route`, `tlsRoute` and `gatewayRoute` are alternatives - enable at most one of the five, since all of them point at the same operator-created session-proxy Service. `gatewayRoute` below produces the same passthrough route but has the operator create and reconcile it; prefer that when the operator supports it, and reach for this chart-managed one otherwise. Nothing decrypts the connection on the way, so the Gateway sets no timeouts and applies no HTTP rules: Kasm's long-lived session websockets are bounded only by the layer-4 idle timeout of the Gateway's data plane and of anything in front of it.</td>
		</tr>
		<tr>
			<td id="tlsRoute--hostnames"><a href="./values.yaml#L453">tlsRoute.hostnames</a></td>
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
			<td id="tlsRoute--parentRefs"><a href="./values.yaml#L448">tlsRoute.parentRefs</a></td>
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
			<td id="workspaceImagePullSecrets"><a href="./values.yaml#L229">workspaceImagePullSecrets</a></td>
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
			<td>Pull secrets the agent injects into launched workspace pods, for private workspace images. Distinct from `imagePullSecrets`, which pulls the agent and proxy images. Omitted from the Agent resource entirely when empty. </td>
		</tr>
		<tr>
			<td id="workspacesNodeSelector"><a href="./values.yaml#L223">workspacesNodeSelector</a></td>
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
			<td id="zone"><a href="./values.yaml#L70">zone</a></td>
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

