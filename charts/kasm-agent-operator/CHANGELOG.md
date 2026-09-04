# Changelog

All notable changes to the kasm-agent-operator chart are documented here.

## [Unreleased]

### Changed
- CRDs updated from the operator (2026-09-04): `Agent` gains `spec.sessionProxy.otel.endpoint` (session-proxy sidecar OTLP endpoint override; empty disables the exporter), and `KasmWorkspace.spec.fileMappings[]` gains `binaryData` (binary file content, mirrors a ConfigMap's `binaryData`) and `writable` (copy-on-start so the session user can edit the file).


### Added

- Initial release: installs the `agent.kasm.com` and `pools.kasm.ai` CustomResourceDefinitions, the static cluster RBAC the operator and the workloads it reconciles require, and the controller-manager Deployment.
