# Changelog

All notable changes to the kasm-helm chart are documented here.

## [1.1190.7] - 2026-09-22

### Added

- Adds `httpRoute`, `tlsRoute` and `tcpRoute` Gateway API publishers for the front-door Kasm proxy and RDP Gateway, and an `upstreamAuth` section publishing the out-of-band management endpoint (`/api/`, `/manager_api/`) via a Service, Ingress, OpenShift Route, HTTPRoute or TLSRoute, one per zone.
- Adds a global `serviceAccount` value with per-component overrides for `components.api` and `components.manager`, letting operators reference an existing ServiceAccount by name (e.g. EKS Pod Identity) or have the chart create one with custom annotations (e.g. IRSA's `eks.amazonaws.com/role-arn`). `extraAnnotations.serviceAccount` / `extraLabels.serviceAccount` can also target the rendered ServiceAccount, and `serviceAccount.annotations` values are now schema-validated as strings.

### Changed

- Rewrote the DB preseed guide (`docs/preseed.md`) into a full `kasmConfig` reference: every section (groups, users, images, autoscale, zones, SSO connectors, server pools, storage, DNS/VM provider configs, and more) now documents each field's type, default, and whether it is required, alongside how name-based cross-references and ID/token resolution work and how to supply credentials inline or from existing Secrets. The Default API Users permissions caveat in `docs/default-api-users.md` now renders as a proper warning callout. <!-- hash:b123b471b27ca3a0ca942a72dafc7d654364dac4 -->

### Fixed

- Tightened validation for the `httpRoute`/`tlsRoute`/`tcpRoute` and `upstreamAuth` publishers added above: `upstreamAuth.service.type` and every `backendProtocol` are now schema-enforced enums; `tcpRoute.enabled` now requires `components.rdpGateway.enabled`; and `tcpRoute`/`upstreamAuth.httpRoute`/`upstreamAuth.tlsRoute` now resolve each zone's effective `parentRefs` (per-zone override, else the global fallback) and fail at render time if any deployed zone would still attach to no Gateway, or if `.zones` names an unknown or duplicate zone. The DB preseed's `upstream_auth_address` now also resolves through the same per-zone/`upstreamAuth.hostname` fallback as the Gateway API publishers, instead of only reading a zone's own field.
- DB preseed autoscale configs now render `connection_info` and `hooks` as JSON objects (`{}` when empty) instead of quoted strings (`"{}"`, or `"map[...]"` for non-empty maps), which left preseeded `Server` autoscale configs unreadable and uneditable in the Kasm UI/API. <!-- hash:06adf14a2137e7bc058caa2ec3d6621f0d45c24b -->
- DB preseed `server_pools[].type`/`server_pool_type` now normalizes case-insensitively to the two values Kasm actually accepts (`Docker Agent`, `Server Pool`) and defaults to `Docker Agent` when omitted, instead of defaulting to and passing through the unrecognized value `Docker`. Any other value now fails the render with an error naming the offending pool. <!-- hash:6a2247fa313ded8cd490744a812bc609524fb28d -->
- Preseeded image `docker_user`/`docker_token` values that look like a YAML flow mapping — for example, the `{iam}`/`{iam:<region>}` sentinel used to authenticate to Amazon ECR via an agent IAM role — were rendered unquoted and parsed as a mapping instead of a string, so they never reached the database as credentials. These two fields are now quoted when set, while still rendering as YAML `null` when unset. <!-- hash:34c6688b7963cd485c92c30f5271ac12a636683b -->

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
