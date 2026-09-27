# Changelog

All notable changes to the kasm-helm chart are documented here.

## [Unreleased]

### Breaking Changes

- Guac (StatefulSet), RDP Gateway (Deployment), and RDP HTTPS Gateway (StatefulSet), each previously running its own nginx sidecar on its own port (9000/9001/9002), are consolidated into **one** zone-scoped StatefulSet, `<release>-connection-proxy-<zone>`, running a single nginx container on **8443** in front of up to three service containers (guac, rdp-gateway, rdp-https-gateway). This mirrors the VM deployment paradigm the Kasm backend models: one nginx, one hostname, three separate service-type registrations. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

- `components.guac`, `components.rdpGateway`, and `components.rdpHttpsGateway` are **removed** from `values.yaml` and `values.schema.json`, replaced by a single nested `components.connectionProxy` tree. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

The three independent replica counts (`components.guac.replicas`, `components.rdpGateway.replicas`, `components.rdpHttpsGateway.replicas`) collapse into one: `components.connectionProxy.replicas`. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

- The legacy singular `directRdpService.rdpAccessURL` is still honored, but only when `components.connectionProxy` resolves to 1 replica and `perServiceSettings` is empty; the chart fails at render time if `rdpAccessURL` and a non-empty `perServiceSettings` are both set, if `rdpAccessURL` is used with more than 1 replica, or if `perServiceSettings` has fewer entries than there are replicas. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

- `directRdpService.annotations`/`labels` remain a shared base merged into every per-replica Service alongside the chart's usual global/component labels and annotations, but `perServiceSettings[i]`'s own `annotations`/`labels` take precedence over that shared base on a key collision (most specific wins). <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

See [Migrating to connection-proxy](./README.md#migrating-to-connection-proxy) for the full old-key-to-new-key mapping.

### Changed

- Health check paths served through nginx changed to avoid a path collision now that both RDP services share one nginx: `/__healthcheck` was previously served twice, once per sidecar, on two different ports. It is now namespaced per service, and nginx itself serves a bare pod-readiness endpoint: <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

  - `/__healthcheck` (RDP Gateway) → `/rdp-gateway/__healthcheck`
  - `/__healthcheck` (RDP HTTPS Gateway) → `/rdp-https-gateway/__healthcheck`
  - `/__healthcheck` (new) → served directly by nginx itself, for pod readiness; Guac keeps its existing

- The previous restriction limiting `rdpGateway` to a single replica is removed; connection-proxy now scales 1/2/3 by `deploymentSize` like every other zone-scoped component. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

### Fixed

- A `directRdpService.perServiceSettings` entry with an empty `rdpAccessURL` (schema allowed it) silently overwrote the rdp-gateway container's `SERVER_HOSTNAME` with an empty value instead of falling back to the per-pod FQDN. Rendering now fails with a clear message instead. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- `components.connectionProxy.labels`/`annotations` were never applied to the connection-proxy StatefulSet: `kasm.metadata` looks up component-scoped values by exact key against `values.yaml`, and the template passed the kebab-case `connection-proxy` instead of `connectionProxy`. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- With more than one primary-region zone, every zone's connection-proxy replicas silently reused the same `directRdpService.perServiceSettings` list and the same `RDP_ACCESS_URLS`, so every zone advertised identical RDP addresses. `perServiceSettings` entries now take a `zone` field; with more than one zone, every entry must set it, and rendering fails if it's missing, unrecognized, or a zone ends up short of entries for its replica count. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- The rdp-https-gateway app-config ConfigMap's `app.kubernetes.io/name` label exceeded Kubernetes' 63-character label-value limit under CI's long `kasm-e2e-<job-id>` release names, failing installs with `logFormat: json`. Shortened the four connection-proxy ConfigMap component identifiers. <!-- hash:29475046a26a06c9f16b585fdc33e0e6703b3392 -->
- Preseeded image `docker_user`/`docker_token` values that look like a YAML flow mapping — for example, the `{iam}`/`{iam:<region>}` sentinel used to authenticate to Amazon ECR via an agent IAM role — were rendered unquoted and parsed as a mapping instead of a string, so they never reached the database as credentials. These two fields are now quoted when set, while still rendering as YAML `null` when unset. <!-- hash:34c6688b7963cd485c92c30f5271ac12a636683b -->

## [1.1190.6] - 2026-07-28

### Changed

- The API deployment now checks a dedicated `/livez` HTTP endpoint for its liveness probe (previously a TCP socket check), backed by a new startup probe that gives the container up to 5 minutes to come up before liveness checks begin. This makes liveness failures reflect actual API health rather than just port reachability, reducing the chance of unnecessary restarts during slow startups. <!-- hash:903d4fe1d934397c7f0222684fdb702d27588c4f -->
- The rendered `api.app.config.yaml` now includes `server.liveness_port` and `server.liveness_stall_seconds`, matching the api image's new configurable liveness settings (still overridable via `KASM_LIVENESS_PORT`/`KASM_LIVENESS_STALL_SECONDS`). No operator action required — this keeps the chart's config in sync with the api image's defaults introduced alongside the `/livez` liveness probe. <!-- hash:f55868eed3e969a6e91694d555d6163155906ae1 -->

### Fixed

- Corrects the API startup probe's grace period, reducing it from 300 seconds to 180 seconds before the pod is marked as failed. <!-- hash:bdb84c1d0e4792940eefa4cbc811baa103e36f93 -->
- Fixed the API server to require HTTPS by default for internal Kasm service-to-service communication instead of HTTP, closing an unencrypted-transport gap. No operator action required unless you've overridden `SERVER_INTERNAL_SCHEMA` explicitly. <!-- hash:c4d02388b6ad40fbdf012b3049b80000b3e05f7b -->

## [1.1190.5] - 2026-07-27

### Added

- Adds a `nginxResolver` value so operators can point the internal nginx config at a specific DNS resolver IP instead of the built-in Kubernetes default, useful for custom cluster DNS setups. <!-- hash:16c22be688eb328eba96c9fc592fdea55b383782 -->
- Adds `kasmSecrets`, a values.yaml setting for supplying custom or an existing Kubernetes secret with your own credentials (admin/user passwords, DB password, service tokens) instead of relying on the chart-generated ones. <!-- hash:82422ac17925d9d4c7b02ae74bacaba74dd1dc54 -->

### Changed

- Guac, RDP Gateway, and RDP HTTPS Gateway now support the global and per-component `extraVolumes`/`extraVolumeMounts` settings from `nginxSidecar`, letting operators mount custom volumes (e.g. certs, config) into these gateway pods without templating workarounds. <!-- hash:e923e40341e1c2f11574da42a707d4b05f0b2be2 -->

### Fixed

- Guac, RDP Gateway, and RDP HTTPS Gateway now reach the API through the Kasm Proxy instead of connecting to the API service directly. Operators do not need to change any values; existing API-related configuration continues to apply, but API traffic for these components now flows through the proxy layer. <!-- hash:45d702ff871637eef8ddc627344907194d7d82ca -->


## [1.1190.4] - 2026-07-25

### Fixed

- Fixed component images to pull the correct release tag instead of the develop branch tag, ensuring deployments use tested, versioned images rather than a moving target. <!-- hash:80a1334a6ca84f9fb7825185ed1a720ca2dfbcc8 -->

## [1.1190.3] - 2026-07-16

### Added

- Adds DB preseed support via the new `kasmConfig` values block, allowing operators to seed initial users, groups, and configuration into Kasm on first install. <!-- hash:5dd5b6299c7fa0a815f9d2b7c09a66fe6ad66b72 -->
- Adds extensive DB preseed documentation in the `./docs` directory providing operators with seed data semantics and configuration capabilities <!-- hash:5dd5b6299c7fa0a815f9d2b7c09a66fe6ad66b72 -->

### Fixed

- Fixed DB preseed data generation to correctly merge configurations, apply resource precedence, and resolve config resources by name, preventing silent misconfigurations in installations that use custom users, groups, or Kasm API settings. <!-- hash:eb7cf7262c5253ce9a08e6c9c18d9f453949b5b9 -->

## [1.1190.2] - 2026-07-08

### Changed

- Increased database keepalive intervals to prevent connections from being dropped during long-running Autoscaling queries and other extended operations; also consolidated statement and idle-transaction timeout settings into a single location. <!-- hash:c034e751e99eb1a9bf04063d0e2dff71ec681aa7 -->

## [1.1190.1] - 2026-07-07

### Added

- **Per-component health check timing** — Liveness and readiness probe intervals, timeouts, and thresholds are now configurable independently for each component (API, Manager, Proxy, Guac, RDP Gateway, RDP HTTPS Gateway, and Database) via `components.<name>.healthCheckTiming` in `values.yaml`. <!-- hash:8669c368e2d89d70a8e3c8dae6951cd35d289469 -->
- **Database connection timeout setting** — A new `dbManagement.dbConnectionTimeout` value controls how long the DB init job waits for Postgres to accept connections before failing. The default is 10 seconds. <!-- hash:8669c368e2d89d70a8e3c8dae6951cd35d289469 -->
- Nginx access logs on the Proxy, RDP Gateway, and RDP HTTPS Gateway components now emit structured JSON to stdout, including session metadata such as upstream timing and cookie username, making them compatible with Grafana Alloy log scraping and other stdout-based log collectors. <!-- hash:5b793703d2f896a7803bcd07c285a2a160dc6cdb -->
- Added `logFormat` value (`"log"` or `"json"`) to control console log output format across API, Manager, Database, RDP Gateway, RDP HTTPS Gateway, and all Nginx pods; set `json` to emit structured JSON logs compatible with log aggregation pipelines. Currently, the `kasm-guac` pod does not support this setting and continues using its default format. <!-- hash:ea007555ad72e42286f1f852a67a602fe7d72a07 -->
- **API thread pool tuning** — Two new `components.api` values expose the CherryPy worker thread pool to Helm operators: `threadPool` (default `20`) sets the number of worker threads, and `threadPoolLogInterval` (default `0`, disabled) sets the interval in seconds between diagnostic log lines reporting thread pool usage. <!-- hash:a31edda5c2387ee6b3f32a3bebe8d349e180f9d9 -->

### Changed

- Guac, RDP Gateway, and RDP HTTPS Gateway now route API communication through the proxy service instead of the API service directly, improving request handling consistency across connection proxies. <!-- hash:d6472916c53c7adc18962426a0d5cee5453354cb -->
- Guac, RDP Gateway, and RDP HTTPS Gateway nginx listeners now enforce TLS for all internal communication. <!-- hash:4c04e023cc34b4dbdbb1c463158c68d99f59820b -->
- Manager and API components now treat all internal communications as HTTPS. <!-- hash:4c04e023cc34b4dbdbb1c463158c68d99f59820b -->

### Fixed

- Fixed Kasm 1.19.0 Support Bundle generation failure. <!-- hash:4c04e023cc34b4dbdbb1c463158c68d99f59820b -->
- Fixed Nginx access and error logs now route to stdout/stderr so they appear in `kubectl logs` output. <!-- hash:4c04e023cc34b4dbdbb1c463158c68d99f59820b -->
- **Guac local proxy routing** — A misconfigured nginx location block in the Guac sidecar caused requests to the Guac local proxy path to be forwarded incorrectly. The block has been corrected. <!-- hash:6ca6d01798a073c4f05a4f11db2806f73681e6ab -->

### Removed

- The proxy no longer waits on Guac and the RDP gateways during startup. The circular init-container dependency could cause deployments to stall indefinitely; Kubernetes readiness probes now handle dependency ordering at the traffic level. <!-- hash:7caca9ecceaf00c8e6e4834cfe8cf6a77566a877 -->

### Documentation

- The chart README has been substantially revised to cover the current deployment model, multi-zone topology, security context configuration, health check customization, and operational procedures. <!-- hash:f7e3d10c2bf3879e713f06c5634cf1f202b0c7ce -->
- README updated to document the new `components.api.threadPool` and `components.api.threadPoolLogInterval` values. <!-- hash:31c4670e575bf94f156bbb226bfbe66f1cce55f8 -->


## [1.1190.0] - 2026-06-12

- Initial GA Helm Chart release
