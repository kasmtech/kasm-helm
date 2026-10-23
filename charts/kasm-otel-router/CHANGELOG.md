# Changelog

All notable changes to the kasm-otel-router chart are documented here.

## [Unreleased]

### Added

- Kasm Workspaces now collects Kubernetes events and routes them through the OTel router, giving operators visibility into cluster-level events (scheduling failures, pod restarts, etc.) alongside existing telemetry without deploying a separate collector. <!-- hash:c384287629da54338d55fda1cd64214f911c9424 -->
- Adds the kasm-otel-router chart, a lightweight OpenTelemetry Collector deployment that authenticates incoming trace, log, and metric data and routes it to the correct tenant backend based on service namespace, so unmatched telemetry is logged and counted instead of silently dropped. <!-- hash:6898c81df6bc0d11f7dd25cef906e588cad2e9f1 -->

### Fixed

- Adds a Service for the OTel router so trace/metric senders can actually reach the collector's OTLP gRPC (4317), OTLP HTTP (4318), health, and metrics ports over the cluster network. <!-- hash:dd74a11ca6b12fc2fdc81b81eb46a964cc56f772 -->

### Documentation

- Adds documentation for the OTel router chart and updates its observability guidance, giving operators clearer setup and configuration reference. <!-- hash:fa796192a8bd639551934714e00b8715cf8b860f -->