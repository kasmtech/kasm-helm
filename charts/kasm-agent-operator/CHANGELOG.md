# Changelog

All notable changes to the kasm-agent-operator chart are documented here.

## [Unreleased]

### Changed
- The controller-manager pod template now carries the `kasm.com/security` and `kasm.com/healthcheck` annotations unconditionally. They are the markers this repository's Kyverno gates key off, and without them the operator Deployment was skipped by the workload-hardening and probe policies entirely — it was only ever checked for host namespaces. The pod and container securityContexts gain the fields those gates require and the Deployment did not state: `fsGroupChangePolicy: OnRootMismatch` on the pod (a no-op, since no `fsGroup` is set), and `runAsNonRoot: true` plus `seccompProfile.type: RuntimeDefault` restated at container scope, where the pod-level values already applied. No runtime behavior changes.
- `kasm-nginx-sidecar` ClusterRole now also grants `services` get/list/watch, mirroring the operator repo's regenerated `nginx_sidecar_clusterrole.yaml`: the sidecar watches a session's workspace Service directly instead of polling DNS, which raced the Service record's own propagation. Reads only; the role still grants no write verb on anything.
- `manager-role` no longer grants any access to Secrets. The operator only ever reads, creates and updates the per-workspace storage-mapping Secret by name, so that access is granted per namespace by the `kasm-agent-instance` chart (`operatorRBAC.*`) wherever an Agent is installed. Requires the operator build that stops caching Secrets (2026-09-08 or later); an older operator fails its cache sync under this role.
- `manager-role` ClusterRole narrowed to match the operator build that stops caching Secrets (2026-09-08): `secrets` is get/create/update only (no list, watch, patch, delete), `persistentvolumes` and `clusterrolebindings` drop list/watch (and patch), `rolebindings` drops delete. Every other rule is unchanged. Requires that operator build; an older operator's Secret informer needs the previous broad rule.
- CRDs updated from the operator (2026-09-04): `Agent` gains `spec.sessionProxy.otel.endpoint` (session-proxy sidecar OTLP endpoint override; empty disables the exporter), and `KasmWorkspace.spec.fileMappings[]` gains `binaryData` (binary file content, mirrors a ConfigMap's `binaryData`) and `writable` (copy-on-start so the session user can edit the file).


### Added

- Initial release: installs the `agent.kasm.com` CustomResourceDefinitions, the static cluster RBAC the operator and the workloads it reconciles require, and the controller-manager Deployment.
