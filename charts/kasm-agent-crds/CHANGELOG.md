# Changelog

All notable changes to the kasm-agent-crds chart are documented here.

## [Unreleased]

### Fixed

- `Chart.yaml`'s description listed three of the five CRDs; it names the `pools.kasm.ai` pair too.

### Changed
- CRDs synced from the operator at `75503d6` (2026-09-15): `KasmImagePuller.status.nodeBackoffs[]` gains `lastEvictedPodUID`, and the descriptions no longer promise that the puller's back-off excludes nodes through its DaemonSet pod template. That exclusion is gone: every change to the back-off list rolled the DaemonSet and aborted the pulls in flight on all nodes (92 generations in an hour on a CRI-O cluster, with the partial downloads filling /var/tmp). The kubelet's own admission and the DaemonSet controller's back-off cover a node under pressure; `status.nodeBackoffs` stays as bookkeeping.
- CRDs synced from the operator at `d3a3ad4` (2026-09-15): `Agent` gains `spec.labels` (server labels advertised in every heartbeat) and `spec.workspacesTolerations` (tolerations for every workspace pod, also scoping the agent's puller and capacity report); `KasmWorkspace.status` and `KasmImagePuller.status.nodeBackoffs[]` gain `lastOOMKilledAt`, the termination time of the last OOM kill already counted, so a container that restarts before the next reconcile is still counted once.
- CRDs updated from the operator (2026-09-04): `Agent` gains `spec.sessionProxy.otel.endpoint` (session-proxy sidecar OTLP endpoint override; empty disables the exporter), and `KasmWorkspace.spec.fileMappings[]` gains `binaryData` (binary file content, mirrors a ConfigMap's `binaryData`) and `writable` (copy-on-start so the session user can edit the file).
- README lists all five CRDs, adding `warmpools` and `warmpoolinstances` in `pools.kasm.ai`; the regeneration hint says `make readme-all`; the first section links the docs index.

### Added

- Initial release: ships the same CustomResourceDefinitions as `charts/kasm-agent-operator/crds/` (agents, kasmworkspaces, and kasmimagepullers in the `agent.kasm.com` group) as ordinary Helm templates, so a release of this chart owns their lifecycle and `helm upgrade` applies schema changes — a hybrid alternative to the operator chart's bundled `crds/` install-time copy.
