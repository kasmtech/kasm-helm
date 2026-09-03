# Changelog

All notable changes to the kasm-otel-collector chart are documented here.

## [Unreleased]

### Added

- Initial release: an OpenTelemetry Collector that receives OTLP traces, metrics, and logs from the Kasm agent components, with toggleable exporters (OTLP/gRPC, ClickHouse, debug) and an optional `k8s_events` receiver that ingests Kubernetes Events as log records.
