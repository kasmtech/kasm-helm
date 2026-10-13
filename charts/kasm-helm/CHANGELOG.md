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

- **The Kasm Manager service is removed.** The API absorbs its functions. `templates/manager-deployment.yaml` and `templates/manager-service.yaml` are deleted, and `components.manager` is removed from `values.yaml` and `values.schema.json` (the schema now rejects it). nginx keeps the `/manager_api/` agent-facing path, but it now proxies to the API service instead of a separate Manager upstream. See [Manager removed](./README.md#manager-removed).

### Added

- Built-in OpenTelemetry observability stack, enabled by default: a single cluster-wide gateway Collector and a bundled ClickHouse StatefulSet that back logs, traces, metrics, and the Kasm Admin UI's reporting views. See the new `charts/kasm-helm/docs/observability.md`.
- nginx distributed tracing (nginx is the trace root for every request) and nginx connection metrics, both collected by an always-on Collector sidecar in the Proxy/Connection Proxy pods — no separate opt-in.
- Browser telemetry for the Kasm web UI (`observability.browser`).
- New `observability.*` values tree: gateway Collector sizing and BYO config (`existingConfigMap`), external-ClickHouse support (`observability.clickhouse.standalone`), forwarding to an external OTLP backend (`observability.collector.gateway.forward`), and per-signal retention controls (`observability.clickhouse.retention`).
- New `observability.collector.upstream` value redirects the API and API-worker OTel exporters (the only non-sidecar senders) at an external OTLP/HTTP collector — e.g. a router in front of several Kasm releases — instead of this release's local gateway. Collector sidecars (Proxy nginx, Connection Proxy, DB Postgres) are unaffected and always export to the local gateway. Same `endpoint`/`token`/`existingSecret` shape as `observability.collector.gateway.forward`. Leave empty for today's default.
- Configurable ClickHouse database name (`observability.clickhouse.database`, default `kasm_otel`), independent of the ClickHouse username, threaded through the Collector's exporters, schema initialization, the ClickHouse user's grant, and the Kasm API's read path — needed for a tenant-specific database on a shared, multi-tenant external ClickHouse.
- An always-on Collector sidecar in the Kasm DB pod collecting PostgreSQL JSON logs (PostgreSQL metrics are not collected — deferred, no receiver ships today).
- Three worked example Collector configs under `examples/`: `otel-collector-custom.yaml`, `otel-collector-splunk.yaml` (Splunk HEC forwarding), and `otel-collector-debug.yaml` (stdout debug exporter).
- New top-level `extraEnv` and per-component `components.<name>.extraEnv` (and `database.extraEnv`) values let operators inject arbitrary environment variables (`name`/`value` or `name`/`valueFrom`) into the API, Proxy, Connection Proxy (Guac/RDP Gateway/RDP HTTPS Gateway), Database, ClickHouse, and gateway Collector main containers, as well as the DB backup/init/upgrade Jobs. Follows the same global+component merge-by-name semantics as the existing `extraVolumes` family, with the component-scoped entry winning on a name collision; values are rendered through `tpl`.
- New `components.api.workerPool` (default `[]`) lets background job (BullMQ) queue consumption run on dedicated worker Deployments instead of every API replica. Leave it empty (default) and every API replica also consumes queues itself (`KASM_PROCESS=TRUE`, queues from the new `components.api.queues`/`components.api.queueConcurrency`); set one or more entries (name/queues/replicas/queueConcurrency/resources) and the API deployment switches to publish-only (`KASM_PROCESS=FALSE`) while one worker Deployment per pool per zone (`<release>-api-<pool>[-<zone>]`, no Service) consumes them instead. The API's liveness probe now checks `GET /livez` on a new port (`8081`) instead of a raw TCP check on the API port; readiness is unchanged. `database`'s computed `max_connections` preset scales up automatically with the total worker replica count across pools and zones once `workerPool` is non-empty. This replaces the earlier `apiWorkerMode`/`components.apiWorker` shape from this same unreleased cycle (never shipped, so there is no upgrade path from it): a values file using `apiWorkerMode: split` + `components.apiWorker.pools: [...]` should move those pool entries to `components.api.workerPool` and delete `apiWorkerMode`/`components.apiWorker`; a `combined`-mode file just deletes `apiWorkerMode` (default behavior is unchanged).
- Adds an override for the OpenTelemetry collector's upstream router address, letting operators point OTEL export traffic at a custom router endpoint instead of the default. Includes new end-to-end test coverage validating the routed telemetry path. <!-- hash:66f7725fa566dd2176d6b9bbad11a8909130870b -->
- Adds apiWorkerMode, letting API request handling and background worker processing scale as separate deployments per zone. Also adds a liveness endpoint for the API and a graceful shutdown window to reduce dropped requests during restarts. <!-- hash:56a53a8f8cd095fa061923388ab838658c931e61 -->
- Adds `extraEnv` support to API, Database, and Proxy components, letting operators inject custom environment variables into these workloads without modifying the chart. <!-- hash:6382063d3c5c4b5d1603947b2c40f9ab4a5928e8 -->
- Removed the standalone Manager component; the API now handles manager duties (agent registration, control-plane calls) directly. Fewer moving parts to deploy and monitor—no `manager` Deployment/Service will appear in your cluster after upgrading. <!-- hash:f1097e26998b6b39edad93f797aa010028224f3c -->
- Browser telemetry (OpenTelemetry client instrumentation) is now disabled by default; operators must explicitly enable it in `values.yaml` to collect browser-side traces. <!-- hash:079312a21b587cdf672174ee621367179259d52b -->
- Adds a ready-to-use OpenTelemetry Collector config snippet (available via a new ConfigMap, referenced in the post-install notes) that operators can paste into their own collector to forward logs, traces, and metrics into this release's OTel gateway, including the correct endpoint and auth token guidance. <!-- hash:10ec4caeb658f4d93f13ef1aabb470e889f9b77a -->
- The OTel gateway component now only renders when a destination is configured, so environments without OpenTelemetry set up no longer get an unused gateway deployment, service, and configmap. <!-- hash:4e8b421f93b7c9de36629f8773f302a5ced2973c -->
- Adds a dedicated read-only ClickHouse user for OpenTelemetry reporting queries, and switches the API and Manager components to use it instead of the full-access account. Operationally, this is transparent — no new values required — but it reduces the database access scope granted to reporting workloads. <!-- hash:4d263719d433c0fa9a494eb6b31a6ffb627a2901 -->
- Nginx access and error logs now flow to the OpenTelemetry sidecar over local syslog instead of shared log files, giving log offsets in-memory delivery with no on-disk state to lose on pod restarts. <!-- hash:d67904a75545af71691953f4ece347ca9ef3dcc2 -->
- Increases the OpenTelemetry gateway's memory limiter thresholds (from 512/128 MiB to 800/200 MiB) and reduces the tail-sampling trace buffer (from 50,000 to 25,000 traces), scaled by `deploymentSize`, to better balance memory headroom against trace retention under load. <!-- hash:4c990d77bccf109462615858e0006f0b3339ed84 -->

### Changed

- **The `logFormat` value was removed from the chart.** Console output is human-readable text for every service except the Kasm Proxy, whose stdout access log is JSON (`json_combined`) whenever `observability.enabled` is true (the default); structured logs are exported over OpenTelemetry regardless. If you were scraping JSON from pod stdout, switch to OTLP collection. (The root values schema does not reject unknown keys, so a leftover `logFormat` in a values file is a silent no-op, not a render error.)
- **New PVC and new workloads on every deployment**: a ClickHouse StatefulSet + PVC, a gateway Collector Deployment, and one extra sidecar container in every Proxy, Connection Proxy, and DB pod. Budget resources and storage accordingly before upgrading; see `charts/kasm-helm/docs/observability.md` §2 and §6.
- The Kasm Proxy's stdout access log is JSON whenever `observability.enabled` is true (the default), because the sidecar collector parses it as JSON.
- **nginx's access and error logs no longer write to an `emptyDir`.** They go to the sidecar over loopback syslog UDP instead, fixing unbounded growth on the shared log volume under sustained traffic. See `charts/kasm-helm/docs/observability.md` §4 for the fire-and-forget tradeoff this introduces at sidecar startup/restart.
- **Splunk HEC settings previously stored in the Kasm database are no longer read.** Move them into a Collector config — see `examples/otel-collector-splunk.yaml` and the upgrade note in `charts/kasm-helm/docs/observability.md` §12.
- **The gateway Collector is single-replica, enforced at render time.** `components.otelGateway.replicas` cannot be raised above 1 — every Kasm service, Collector sidecar, and out-of-cluster sender exports straight to the gateway's plain ClusterIP Service, and nothing partitions traces by ID in front of it, so a second replica would let `tail_sampling` decide on partial traces. See `charts/kasm-helm/docs/observability.md` §7.
- **If you supply your own Kasm Secret (`kasmSecrets.create: false`), it now needs two more keys**: `clickhouse-password` and `otel-bearer-token`. The chart references both via `secretKeyRef`, so a pre-created Secret without them leaves ClickHouse, the gateway Collector, the Collector sidecars, and the API/Manager pods in `CreateContainerConfigError`. See the updated `examples/kasm-secrets.yaml`. Omit them only if you also set `observability.enabled: false`.
- **The Kasm Proxy image must contain `ngx_otel_module`** (Kasm 1.20 or later) when `observability.enabled` is true, since the chart loads the module in its own `nginx.conf`. Setting `observability.enabled: false` omits the `load_module` line entirely, so the chart still deploys on an older proxy image.
- Changing `observability.clickhouse.database` on an existing deployment requires starting from an empty ClickHouse volume, or audit logs silently fall back to the shorter `retention.logsDays` window — see `charts/kasm-helm/docs/observability.md` §6.
- **The gateway Collector now renders only when it has somewhere to send telemetry.** Previously, `observability.enabled: true` with no ClickHouse and no `observability.collector.gateway.forward.endpoint` deployed a Collector that received and silently discarded everything. That combination now fails the render with a message naming `observability.clickhouse.enabled`/`.standalone` and `observability.collector.gateway.forward.endpoint` as the fix. `existingConfigMap` is unaffected — it always renders, since that config owns its own routing.
- Reworks OpenTelemetry into a forwarder/gateway architecture: nginx and Postgres now emit telemetry through dedicated sidecars instead of writing to a shared collector, removing the cross-zone hop connection-proxy pods used to take and bounding Postgres log growth on the data volume to one day. <!-- hash:a6f317b839f6adcfcd380c3a3b986357b0507157 -->
- Adds OpenTelemetry-based observability: distributed tracing and metrics/log collection for API, Manager, Guac, Proxy, RDP Gateway/HTTPS Gateway, and nginx, backed by a new ClickHouse store with configurable retention. Operators can enable this via new OTel collector, gateway, and ClickHouse values. <!-- hash:31e3bbba5fbdea28df316d826c3d0bda9c49f330 -->

### Removed

- The `api-app-config` and `manager-app-config` ConfigMaps (dead configuration — `api_server/server.py` no longer reads them).

### Changed (connection-proxy consolidation)

- Health check paths served through nginx changed to avoid a path collision now that both RDP services share one nginx: `/__healthcheck` was previously served twice, once per sidecar, on two different ports. It is now namespaced per service, and nginx itself serves a bare pod-readiness endpoint: <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

  - `/__healthcheck` (RDP Gateway) → `/rdp-gateway/__healthcheck`
  - `/__healthcheck` (RDP HTTPS Gateway) → `/rdp-https-gateway/__healthcheck`
  - `/__healthcheck` (new) → served directly by nginx itself, for pod readiness; Guac keeps its existing

- The previous restriction limiting `rdpGateway` to a single replica is removed; connection-proxy now scales 1/2/3 by `deploymentSize` like every other zone-scoped component. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

### Fixed (connection-proxy consolidation)

- A `directRdpService.perServiceSettings` entry with an empty `rdpAccessURL` (schema allowed it) silently overwrote the rdp-gateway container's `SERVER_HOSTNAME` with an empty value instead of falling back to the per-pod FQDN. Rendering now fails with a clear message instead. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- `components.connectionProxy.labels`/`annotations` were never applied to the connection-proxy StatefulSet: `kasm.metadata` looks up component-scoped values by exact key against `values.yaml`, and the template passed the kebab-case `connection-proxy` instead of `connectionProxy`. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- With more than one primary-region zone, every zone's connection-proxy replicas silently reused the same `directRdpService.perServiceSettings` list and the same `RDP_ACCESS_URLS`, so every zone advertised identical RDP addresses. `perServiceSettings` entries now take a `zone` field; with more than one zone, every entry must set it, and rendering fails if it's missing, unrecognized, or a zone ends up short of entries for its replica count. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- The rdp-https-gateway app-config ConfigMap's `app.kubernetes.io/name` label exceeded Kubernetes' 63-character label-value limit under CI's long `kasm-e2e-<job-id>` release names, failing installs with `logFormat: json`. Shortened the four connection-proxy ConfigMap component identifiers. <!-- hash:29475046a26a06c9f16b585fdc33e0e6703b3392 -->
- Regenerates preseed secret values (manager/service tokens, DB and app passwords, ClickHouse credentials, OTel bearer token) to match the fields the integ backend expects, ensuring pre-install/pre-upgrade secret provisioning stays compatible with that backend. <!-- hash:459c8e53665734d6082e0823dc302c953a523087 -->
- When observability is enabled, the proxy's console logs now use the same structured JSON format as its sidecar-bound logs (instead of the plain-text format), making stdout log output consistent for log aggregation pipelines that scrape the pod directly. <!-- hash:dc0296cb1d5a48dfc290d5dd1f703b5210d7dc21 -->
- Fixes OpenTelemetry sidecar telemetry for the database so log/trace/metric records now carry the correct pod name (and zone, for proxy/nginx sidecars) instead of a static value shared across all pods. <!-- hash:411609415b662cdd7e609a340c36aa48e041dcfd -->
- Connection-proxy logs and traces now carry their own service name in the OTel pipeline, instead of sharing a generic identifier — logs and traces from this proxy are now distinguishable from other components in your observability backend. <!-- hash:0e45a36382cb0c7bf4d1e259d9cf748b1e900001 -->
- Fixed documentation wording in the observability guide describing scaling behavior and log format settings; no functional or configuration changes for operators. <!-- hash:a74229f9804ba81d58aa160c3308cadeabd96049 -->
- Fixes the OpenTelemetry forwarder's DNS-based load balancing exporters, which failed to resolve the gateway service because the resolver port was not quoted as a string in the generated configuration. <!-- hash:b1e5dfd5f90dbefb3bb1fa57435edbe067e58cd1 -->
- Preseeded image `docker_user`/`docker_token` values that look like a YAML flow mapping — for example, the `{iam}`/`{iam:<region>}` sentinel used to authenticate to Amazon ECR via an agent IAM role — were rendered unquoted and parsed as a mapping instead of a string, so they never reached the database as credentials. These two fields are now quoted when set, while still rendering as YAML `null` when unset. <!-- hash:34c6688b7963cd485c92c30f5271ac12a636683b -->

### Documentation

- Documents how edge-injected trace-context headers are trusted and how ClickHouse credentials are managed for observability — no functional change to the chart itself. <!-- hash:780fc043281accf8cd334a9b3f915248bffdc95b -->
- Rewrites the observability documentation to describe the forwarder/gateway architecture and clarifies that the gateway only accepts traffic from forwarders, not from the host-log DaemonSet directly. No configuration or deployment changes for operators. <!-- hash:1b4f0ca90686716e5cd4448ab5a34726dccd1f56 -->

### Known Issues in Earlier Releases

- **1.1190.7 and earlier, upgrading Kasm to a new version can delete the database.** The bundled database's StatefulSet is named per Kasm version, so a version upgrade replaces it instead of updating it in place, and `database.storage.retentionPolicy.whenDeleted` defaulted to `Delete` - which removed the old volume along with the old StatefulSet. If `dbManagement.initialize` was left set instead of following the upgrade procedure (`dbManagement.initialize=false` with `dbManagement.upgrade.enable=true`), the upgrade initialized an empty database over the live deployment and every setting, user and session record was lost, with no error and no rollback.

  On those versions, before upgrading Kasm: set `database.storage.retentionPolicy.whenDeleted=Retain` so the old volume survives, and follow the upgrade procedure rather than leaving `dbManagement.initialize` on. Both are fixed in this release - see Fixed, below.

### Fixed

- A Kasm version upgrade no longer deletes the database it is upgrading. The bundled database's StatefulSet is named per Kasm version, so an upgrade replaces it rather than updating it in place, and `database.storage.retentionPolicy.whenDeleted` defaulted to `Delete` - which took the old volume with the old StatefulSet and left the pre-upgrade dump as the only copy of the data. It now defaults to `Retain`, so the previous version's volume stays in the namespace as a fallback and can be removed by hand once the upgrade is confirmed good.

- An upgrade that would replace the database while `dbManagement.initialize` is still set now fails to render instead of silently initializing an empty database over a live deployment. `dbManagement.initialize` is for a new deployment; upgrading an existing one needs `dbManagement.initialize=false` with `dbManagement.upgrade.enable=true`, which dumps the current database before the switch and restores it after. Previously this combination produced no error, no rollback and no data. The check reads the deployed StatefulSet, so it applies to `helm upgrade` and `--dry-run=server`, and stays quiet during `helm template`.

## [1.1190.6] - 2026-07-28

### Fixed

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
