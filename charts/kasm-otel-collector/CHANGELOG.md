# Changelog

All notable changes to the kasm-otel-collector chart are documented here.

## [Unreleased]

### Changed

- **Behaviour change for existing installs:** `exporters.otlp.enabled` now defaults to `false` and `exporters.otlp.endpoint` defaults to `""`, removing the lab-only `lgtm.observability.svc.cluster.local:4317` placeholder that every default install was silently exporting to (and dropping) before. `exporters.debug.enabled` now defaults to `true` (`verbosity: basic`), so a default install logs telemetry to the collector's own stdout instead of discarding it. Installs that relied on the old OTLP default must now set `exporters.otlp.enabled: true` and `exporters.otlp.endpoint` explicitly. Templating now also fails when `exporters.otlp.enabled` or `exporters.clickhouse.enabled` is true with an empty `endpoint`, instead of quietly trying to dial nothing.
- The collector pod template now carries the `kasm.com/security` and `kasm.com/healthcheck` annotations unconditionally. They are the markers this repository's Kyverno gates key off, and without them the collector Deployment was skipped by the workload-hardening and probe policies entirely — it was only ever checked for host namespaces. `podSecurityContext` gains `fsGroupChangePolicy: OnRootMismatch` (a no-op, since this chart sets no `fsGroup`) and `securityContext` gains `runAsNonRoot: true` and `seccompProfile.type: RuntimeDefault`, restating at container scope what `podSecurityContext` already applied, because that is the scope both Pod Security admission and the gate read. No runtime behavior changes.
- The collector pod's annotations are now built by merging the chart's own keys with `podAnnotations` and `commonAnnotations` instead of concatenating the three blocks. A values key that collides with `checksum/config` or either Kyverno marker used to emit a duplicate YAML key; the chart's own key now wins outright, then `podAnnotations`, then `commonAnnotations`.
- README: the first section links the docs index. The HTML values-table template moved to the shared `_templates.gotmpl`.

### Added

- Initial release: an OpenTelemetry Collector that receives OTLP traces, metrics, and logs from the Kasm agent components, with toggleable exporters (OTLP/gRPC, ClickHouse, debug) and an optional `k8s_events` receiver that ingests Kubernetes Events as log records.
