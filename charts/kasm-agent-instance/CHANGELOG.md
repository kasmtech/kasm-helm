# Changelog

All notable changes to the kasm-agent-instance chart are documented here.

## [Unreleased]

### Changed

- README lists the self-signed session-proxy Secret with its three render-time lookup cases (generate; reuse or regenerate when release-owned; leave untouched when created by anyone else), states that only one of the five exposure options renders and that `httpRoute`/`tlsRoute` need a non-empty `parentRefs`, cuts the LoadBalancer/NodePort, client-IP and older-operator material to the two value snippets and the 30000-32767 constraint (linking the how-to), and lists the required values with `inClusterControlPlane` in mind. The HTML values-table template moved to the shared `_templates.gotmpl`.

### Fixed

- `inClusterControlPlane` derived the manager hostname and session hostname but left the ports to the umbrella's values, and `kasm-platform` set `manager.port: 8080`, `manager.scheme: http` and `publicPort: 4444` unconditionally. Any install under `kasm-platform` that set `publicHostname` (every direct-connect, Ingress, HTTPRoute or passthrough example) therefore registered `<publicHostname>:4444`, the API's hello was refused, and every launch failed with "No resources are available". The chart now derives 8080/http and 4444 itself, and only while the matching hostname is derived; an explicit hostname takes the ordinary 443/https and `publicPort` (443).
- `httpRoute.parentRefs` and `tlsRoute.parentRefs` rendered only `name` and `namespace`, silently dropping `sectionName`, `port` and `kind`. They are passed through verbatim now, as the kasm-helm chart already did.
- `make images-agent` also missed every `KasmImagePuller.spec.images[].image` entry: its extractor did not match a key that opens a YAML list item (`- image: ...`), so the workspace images a release pre-pulls were absent from the airgap mirror list. Found by `make images-check`, which now extracts references with an independent structural yq walk instead of re-running the same awk (an earlier version could not fail).
- `sessionProxy.selfSigned` emitted its Secret even when one of that name already existed that the release did not own — the pre-created, bring-your-own case the value's own comment promised would work, and the exact flow `tests/values-agent/dev-parity.yaml` and `examples/kasm-agent/dev-cluster-values.yaml` document. Helm refuses to adopt a resource without its ownership metadata, so `helm install` failed with `exists and cannot be imported into the current release`. The template now reads the existing Secret's `meta.helm.sh/release-name`/`release-namespace` annotations: a Secret this release owns is reused (or regenerated when its `self-signed-for` marker no longer matches `publicHostname`), and a Secret anyone else created renders nothing at all, leaving the proxy to mount it by name.
- The five session-proxy exposure options (`ingress`, `httpRoute`, `route`, `tlsRoute`, `gatewayRoute`) could all be enabled at once, and `httpRoute`/`tlsRoute` rendered a route with no `parentRefs` — attached to no Gateway — without complaint. A new `templates/validation.yaml` (mirroring kasm-helm's) fails the render when more than one is enabled, or when either Gateway API route has empty `parentRefs`, naming the values involved.
- `make images-agent` omitted the session proxy's nginx sidecar. It matched only lines whose key was literally `image:`, and the sidecar is referenced at `Agent.spec.sessionProxy.sidecarImage` — so `docker.io/kasmweb/kasm-nginx-sidecar` never appeared in the generated list, and an airgap mirror built from it produced a session proxy that could not start (the proxy is a two-container pod). The extractor now matches any key ending in `image`, and a new `make images-check` target fails when the rendered manifests reference an image the list does not carry. Wired into the `docs-check` CI matrix.

### Added

- Adds `inClusterControlPlane` (default `false`), which derives `manager.hostname`, the manager token Secret and `publicHostname` from a `kasm-helm` release installed under the same release name and namespace. Those three values otherwise have no default and fail the render, which is what made a Kubernetes agent impossible to install without a values file. Anything set explicitly still wins.
- Adds `sessionProxy.selfSigned.enabled` (default `true`), generating the Secret named by `sessionProxy.certSecretName` when cert-manager is not issuing one — the session proxy will not start without it. An existing Secret of that name is reused. On the default relayed topology this certificate is never shown to a browser; on direct-connect paths it must be replaced with a publicly trusted one.

- A namespaced `Role` + `RoleBinding` (`<fullname>-operator`), always rendered, granting the Kasm agent operator's ServiceAccount `secrets` get/create/update in this namespace: the operator's ClusterRole no longer carries any Secret access. `operatorRBAC.serviceAccount.name` names the ServiceAccount (default `controller-manager`) and `operatorRBAC.serviceAccount.namespace` where it runs (empty = this release's namespace; set it in the two-namespace layout).

### Fixed

- `tlsRoute` rendered `gateway.networking.k8s.io/v1alpha2`, which the Gateway API 1.5+ standard-channel CRDs no longer serve (`TLSRoute` graduated to `v1` in 1.5), so the chart-managed route was rejected by the API server on current clusters. The apiVersion is now chosen at render time: `v1` when the cluster serves it, `v1alpha2` when only the older experimental-channel CRD is served, `v1` when rendering offline, and the new `tlsRoute.apiVersion` value overrides all three.

### Added

- Initial release: creates the `Agent` custom resource (`agent.kasm.com/v1alpha1`) that the Kasm agent operator reconciles, plus its satellite objects — the manager token Secret, a cert-manager `Certificate`, and a `KasmImagePuller`.
- Adds five mutually-exclusive external-access options for the operator-created session-proxy Service (`httpRoute`, `ingress`, `route`, `tlsRoute`, `gatewayRoute`), session-proxy Service overrides with PROXY protocol support (`sessionProxy.proxyProtocol`), and a split-horizon `apiServerURL` override for manager ADMIN calls.
