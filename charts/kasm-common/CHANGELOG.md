# Changelog

All notable changes to the kasm-common chart are documented here.

## [Unreleased]

### Added

- Adds per-zone worker pools for the API service via a new apiWorkerMode setting, letting operators scale API worker processes independently per zone instead of using a single shared pool. <!-- hash:56a53a8f8cd095fa061923388ab838658c931e61 -->

### Changed

- `kasm.common.otelNginxAccessLogOperators` drops `query_string` and rebuilds the request line without it, stores `url.path`/`http.request.method`/`http.response.status_code` under flat keys instead of nested objects, tags the session websocket close row as `kasm.session.client_detached`, and no longer adds an `application` attribute.

### Fixed

- Fixes sidecar telemetry to correctly report the pod name and zone, and prevents a missing ClickHouse secret from breaking chart rendering. <!-- hash:411609415b662cdd7e609a340c36aa48e041dcfd -->