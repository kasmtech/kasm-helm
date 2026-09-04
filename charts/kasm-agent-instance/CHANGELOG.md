# Changelog

All notable changes to the kasm-agent-instance chart are documented here.

## [Unreleased]

### Fixed

- `tlsRoute` rendered `gateway.networking.k8s.io/v1alpha2`, which the Gateway API 1.5+ standard-channel CRDs no longer serve (`TLSRoute` graduated to `v1` in 1.5), so the chart-managed route was rejected by the API server on current clusters. The apiVersion is now chosen at render time: `v1` when the cluster serves it, `v1alpha2` when only the older experimental-channel CRD is served, `v1` when rendering offline, and the new `tlsRoute.apiVersion` value overrides all three.

### Added

- Initial release: creates the `Agent` custom resource (`agent.kasm.com/v1alpha1`) that the Kasm agent operator reconciles, plus its satellite objects — the manager token Secret, a cert-manager `Certificate`, and a `KasmImagePuller`.
- Adds five mutually-exclusive external-access options for the operator-created session-proxy Service (`httpRoute`, `ingress`, `route`, `tlsRoute`, `gatewayRoute`), session-proxy Service overrides with PROXY protocol support (`sessionProxy.proxyProtocol`), and a split-horizon `apiServerURL` override for manager ADMIN calls.
