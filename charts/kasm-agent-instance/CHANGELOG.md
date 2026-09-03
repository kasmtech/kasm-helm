# Changelog

All notable changes to the kasm-agent-instance chart are documented here.

## [Unreleased]

### Added

- Initial release: creates the `Agent` custom resource (`agent.kasm.com/v1alpha1`) that the Kasm agent operator reconciles, plus its satellite objects — the manager token Secret, a cert-manager `Certificate`, and a `KasmImagePuller`.
- Adds five mutually-exclusive external-access options for the operator-created session-proxy Service (`httpRoute`, `ingress`, `route`, `tlsRoute`, `gatewayRoute`), session-proxy Service overrides with PROXY protocol support (`sessionProxy.proxyProtocol`), and a split-horizon `apiServerURL` override for manager ADMIN calls.
