# Changelog

All notable changes to the kasm-helm chart are documented here.

## [Unreleased]

### Breaking Changes

- The front-door publishers (`ingress`, `route`, `httpRoute`, `tlsRoute`) publish only `publicAddr`, routed to the primary zone's proxy Service. The per-zone `proxy_hostname` rules/objects they used to render are removed: a zone's `proxy_hostname` is associated with a different backend, usually behind a different ingress or load balancer entirely. `proxy_hostname` still feeds the database preseed and the chart-minted certificate SANs. `httpRoute.zones` is removed from `values.yaml` and the schema; it existed only to attach the now-removed per-zone routes (`upstreamAuth.httpRoute.zones` / `upstreamAuth.tlsRoute.zones` are unaffected).

- With more than one `kasmZones` entry, exactly one deployed zone must be marked `primary: true`; the silent first-zone-as-primary fallback is removed. A single configured zone is still implicitly primary. Multi-zone values files without an explicit primary now fail at render time with a descriptive error.

- Guac (StatefulSet), RDP Gateway (Deployment), and RDP HTTPS Gateway (StatefulSet), each previously running its own nginx sidecar on its own port (9000/9001/9002), are consolidated into **one** zone-scoped StatefulSet, `<release>-connection-proxy-<zone>`, running a single nginx container on **8443** in front of up to three service containers (guac, rdp-gateway, rdp-https-gateway). This mirrors the VM deployment paradigm the Kasm backend models: one nginx, one hostname, three separate service-type registrations. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

- `components.guac`, `components.rdpGateway`, and `components.rdpHttpsGateway` are **removed** from `values.yaml` and `values.schema.json`, replaced by a single nested `components.connectionProxy` tree. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

The three independent replica counts (`components.guac.replicas`, `components.rdpGateway.replicas`, `components.rdpHttpsGateway.replicas`) collapse into one: `components.connectionProxy.replicas`. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

- The legacy singular `directRdpService.rdpAccessURL` is still honored, but only when `components.connectionProxy` resolves to 1 replica and `perServiceSettings` is empty; the chart fails at render time if `rdpAccessURL` and a non-empty `perServiceSettings` are both set, if `rdpAccessURL` is used with more than 1 replica, or if `perServiceSettings` has fewer entries than there are replicas. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

- `directRdpService.annotations`/`labels` remain a shared base merged into every per-replica Service alongside the chart's usual global/component labels and annotations, but `perServiceSettings[i]`'s own `annotations`/`labels` take precedence over that shared base on a key collision (most specific wins). <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

See [Migrating to connection-proxy](./README.md#migrating-to-connection-proxy) for the full old-key-to-new-key mapping.

### Added

- Adds `kasmZones[].seedOnly`: a zone marked `seedOnly: true` is written to the database preseed (when `kasmConfig.generatePreseed` is true) but deploys no workloads, Services, routing rules or certificate hostnames in this cluster. Built for multi-cluster deployments: the cluster that initializes the database lists every zone and marks the remotely hosted ones `seedOnly: true`, and each remote cluster installs the chart with a values file listing only its own zone(s), `dbManagement.initialize: false`, and the shared external database. Guardrails fail the render when the primary zone is `seedOnly`, when every zone is `seedOnly`, or when a `seedOnly` zone shares a `region_name` with a deployed zone (zones in one region deploy to one cluster).

- Adds `certificate.selfSigned.enabled` (default `true`), a last-resort certificate so that an install with nothing configured actually starts. Every TLS-terminating pod mounts the certificate Secret as a non-optional volume, so previously a default install rendered cleanly and then sat in `ContainerCreating` forever. It renders only when neither real source is present — `certificate.secretName` unset and `certificate.certManager.enabled` false — and reuses an existing Secret of that name via `lookup`, so the certificate is stable across upgrades and pre-creating your own still works. The Secret records the hostname it was generated for in its own `self-signed-for` key, so changing `publicAddr` regenerates it rather than leaving a stale certificate that the ingress controller silently replaces with its own default; a Secret without that marker was created by someone else and is never overwritten. The result is **not publicly trusted** and NOTES.txt says so at the end of every install that falls back to it.

- Adds Gateway API support for publishing the Kasm proxy: `httpRoute` renders an `HTTPRoute` and `tlsRoute` renders a SNI-passthrough `TLSRoute` (standard-channel `v1` since Gateway API 1.5; `tlsRoute.apiVersion` falls back to `v1alpha2` for older experimental-channel bundles). Both fan out per zone the way the OpenShift Route already does — one object per `kasmZones` entry plus one for `publicAddr` — and both join the existing `ingress`/`route` mutual exclusion, so at most one of the four can be enabled. Unlike an Ingress, a Gateway API route carries no certificate: the chart still mints the Secret, but it has to be referenced from the Gateway listener's `certificateRefs`.
- Adds `tcpRoute`, publishing the RDP Gateway through a Gateway API `TCPRoute` as an alternative to `directRdpService`. Requires Gateway API 1.6 or newer, where `TCPRoute` is standard-channel `v1`. A `TCPRoute` matches on neither hostname nor SNI, so where more than one zone sits in the primary region each needs its own Gateway listener — `tcpRoute.zones` carries the per-zone `parentRefs`, and the render fails naming any zone left out. The backend is the ordinal-0 per-pod direct RDP Service that `connection-proxy-services.yaml` renders (ClusterIP while the Gateway fronts it); because a `TCPRoute` advertises a single hostname, enabling it pins `components.connectionProxy` to one replica - per-replica fan-out belongs to `directRdpService.perServiceSettings`.
- Adds `trustedCaBundle.resources`, which overrides the CPU/memory requests and limits on the `trusted-ca-init` initContainer that is injected into every Kasm workload while the trusted CA bundle is enabled. Leave it empty (the default) to keep the chart's `api`/`small` preset.
- Adds `upstreamAuth`, publishing a separate, out-of-band URL for the zone's Upstream Auth Address — the management endpoint external Kasm Agents and Windows services use for `/api/` and `/manager_api/` — typically a private load balancer or an internal ingress class/Gateway. Five publishers, at most one enabled, all independent of the front-door choice: `upstreamAuth.service` (one `LoadBalancer`/`NodePort` Service per deployed zone, `<release>-upstream-auth-<zone>`, private via annotations such as `service.beta.kubernetes.io/aws-load-balancer-scheme: internal`), `upstreamAuth.ingress`, `upstreamAuth.route`, `upstreamAuth.httpRoute` and `upstreamAuth.tlsRoute` (one host/route per deployed zone, each routing to that zone's own proxy Service; the Gateway API publishers carry the same per-zone `zones[].parentRefs` override as `httpRoute.zones`). Per-zone hostnames come from `kasmZones[].upstream_auth_address` with `upstreamAuth.hostname` as the primary zone's fallback; resolved hostnames seed the database preseed's `upstream_auth_address` (untouched zones keep `$request_host$`); they are NOT added to the cert-manager/self-signed certificate SANs, since they typically live in a private DNS zone a public issuer cannot validate (Kasm agents do not validate the certificate; a front end that must present a covering certificate takes one via `upstreamAuth.ingress.secretName`). Guardrails fail the render when two publishers are enabled, when a host-bearing publisher has no hostname source or a `host:port` value, when two deployed zones resolve to the same address, and when a pinned `nodePort` meets more than one deployed zone.
- Adds `kasmConfig.authDomain`, which sets Kasm's `kasm_auth_domain` global setting (the domain the session cookie is scoped to) at database initialization. Kubernetes-agent deployments need it pointed at the parent domain covering both the control plane's `publicAddr` and the agent's session hostname, otherwise the browser never sends the cookie to the agent and every session connection fails with a 401 — previously an unavoidable manual post-install step through the admin UI or API. It needs no `generatePreseed` and is applied last, so it wins over both `kasmConfig.config` and `kasmConfig.existingDefaultPropertiesSecret`. Fresh installs only; existing databases still change the value in the admin UI under Settings → Auth, or through the admin API.

### Changed

- Health check paths served through nginx changed to avoid a path collision now that both RDP services share one nginx: `/__healthcheck` was previously served twice, once per sidecar, on two different ports. It is now namespaced per service, and nginx itself serves a bare pod-readiness endpoint: <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

  - `/__healthcheck` (RDP Gateway) → `/rdp-gateway/__healthcheck`
  - `/__healthcheck` (RDP HTTPS Gateway) → `/rdp-https-gateway/__healthcheck`
  - `/__healthcheck` (new) → served directly by nginx itself, for pod readiness; Guac keeps its existing

- The previous restriction limiting `rdpGateway` to a single replica is removed; connection-proxy now scales 1/2/3 by `deploymentSize` like every other zone-scoped component. <!-- hash:a5a100c96fdc34e08c415ae7337da9485ad14ebc -->

- Fixed `proxyService.type=NodePort` publishing nothing. It was accepted by the schema and documented in `values.yaml` as an allowed type, but `proxy-service-external.yaml` rendered only for `LoadBalancer` — so setting it left the proxy on `ClusterIP` with no external Service and no error. The external Service now renders for `NodePort` as well, `proxyService.nodePort` pins the port when you want it stable, and the same two restrictions that apply to `LoadBalancer` (not alongside an Ingress/Route/Gateway API route, not with `kasmZones`) now apply to `NodePort`. Verified end to end on kind, where NodePort is the only option needing neither an ingress controller nor a load-balancer provider.

- The cross-value checks that reject conflicting exposure settings moved out of `route.yaml`, `proxy-service-external.yaml` and `rdp-gateway-deployment.yaml` into a single `_validation.tpl`, invoked from `validation.yaml` so they run on every render including `helm template` and `--dry-run`. The rules became n-way when the Gateway API options were added, and holding them in the templates they constrain meant repeating each rule in every template it touched. Existing messages are unchanged; failures are now attributed to `validation.yaml`.
- `directRdpService.loadBalancerPort` is now also the port `tcpRoute` forwards to, so it applies even when `directRdpService.enabled` is false. The advertised RDP hostname resolves through `kasm.directRdpEntriesForZone` for both publication paths: with `tcpRoute` enabled it yields the route's `rdpAccessURL`, so the rdp-gateway container registers the Gateway's hostname through the same `RDP_ACCESS_URLS` plumbing `perServiceSettings` uses.
- README: two stale helm-docs comments removed (an artifacthub URL belonging to another project, and a docs path that does not exist); the first section links the docs index. The HTML values-table template moved to the shared `_templates.gotmpl` at the repo root, which `make readme` and `make readme-all` pass to helm-docs.

### Fixed

- A deployed zone without `proxy_hostname` added a bogus empty SAN (rendered from Go's `<no value>`) to the certificates instead of being skipped; the cert-manager Certificate also failed the render outright where the self-signed path skipped. Both now skip hostname-less zones.
- The rdp-https-gateway app-config ConfigMap resolved its zone from the first `kasmZones` entry instead of the primary zone, so with `primary: true` on a non-first zone the ConfigMap named the wrong zone and disagreed with the per-zone `SERVER_ZONE_NAME` env var. It now resolves through `kasm.primaryZone`.
- The api, manager, and kasm-proxy Services and the proxy-settings ConfigMap ranged over raw `kasmZones` instead of the normalized zone list, so a zone declared only with the `zone_name` alias got an empty name suffix on those four resources while its Deployment was suffixed correctly.
- A `directRdpService.perServiceSettings` entry with an empty `rdpAccessURL` (schema allowed it) silently overwrote the rdp-gateway container's `SERVER_HOSTNAME` with an empty value instead of falling back to the per-pod FQDN. Rendering now fails with a clear message instead. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- `components.connectionProxy.labels`/`annotations` were never applied to the connection-proxy StatefulSet: `kasm.metadata` looks up component-scoped values by exact key against `values.yaml`, and the template passed the kebab-case `connection-proxy` instead of `connectionProxy`. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- With more than one primary-region zone, every zone's connection-proxy replicas silently reused the same `directRdpService.perServiceSettings` list and the same `RDP_ACCESS_URLS`, so every zone advertised identical RDP addresses. `perServiceSettings` entries now take a `zone` field; with more than one zone, every entry must set it, and rendering fails if it's missing, unrecognized, or a zone ends up short of entries for its replica count. <!-- hash:cb83115f48e0be49c373052ae0276c4468ad769f -->
- The rdp-https-gateway app-config ConfigMap's `app.kubernetes.io/name` label exceeded Kubernetes' 63-character label-value limit under CI's long `kasm-e2e-<job-id>` release names, failing installs with `logFormat: json`. Shortened the four connection-proxy ConfigMap component identifiers. <!-- hash:29475046a26a06c9f16b585fdc33e0e6703b3392 -->

- The render error for `dbManagement.initialize` and `dbManagement.upgrade.enable` both set pointed at a placeholder URL (`https://some.upgrade.url`). It now names the two values an upgrade needs and the procedure page, `docs/how-to/day-2.md`, which documents the control-plane upgrade path for the first time: the pre-upgrade dump, the per-version database StatefulSet, the restore-or-migrate branch, the external-database paths and the `oldDbHostname` default that only fits a release named `kasm`.
- NOTES.txt printed `Kasm URL: https://` when `publicAddr` was unset, and always named the credentials Secret `<release>-secrets` even when `kasmSecrets.name` overrides it. It now gives the LoadBalancer, NodePort or port-forward route to the UI while `publicAddr` is empty, uses the configured Secret name, and no longer repeats the self-signed certificate paragraph twice. A new `kasm.proxyExternalAddress` helper reads the assigned LoadBalancer address (or node address and port) back with `lookup`, so from the first `helm upgrade` on the notes print the actual `https://` URL; Helm renders notes before creating anything, so the first install still shows the `kubectl` command instead.
- `certificate.selfSigned` emitted its Secret even when one already existed at the chart's default name that the release did not own, which Helm refuses to adopt (`helm install` and `helm upgrade` fail with `exists and cannot be imported into the current release`). The template now reads the existing Secret's `meta.helm.sh/release-name`/`release-namespace` annotations: a release-owned Secret is reused, or regenerated on a `publicAddr` change, as before; a Secret created by anyone else renders nothing, so pre-creating your own at that name works as documented.
- Fixed the `$default_http_port` nginx map advertising **443 for every scheme**. It carried entries for `default 443` and `"https" 443` but none for `http`, despite the comment above it stating the intent ("80 for http, 443 for https"). That value feeds `X-Forwarded-Port` on the `client_api` and `admin_api` upstreams, so any deployment fronted by plain HTTP — TLS terminated at a load balancer or ingress and forwarded as HTTP — had Kasm advertise port 443 in the URLs it builds, including session URLs. Found by installing behind an HTTP-only ingress and watching the browser be sent to `:443`.
- Fixed three initContainers that shipped with no CPU or memory requests and limits at all: `trusted-ca-init` (injected into every workload when `trustedCaBundle.enabled` is true), and `db-is-ready` plus `prepare-db-preseed` in the DB initialization Job. Unbounded containers are evicted first under node pressure and are rejected outright by a namespace with a `LimitRange` that has no defaults, so the DB init Job could fail to schedule on an otherwise healthy cluster. All three now carry the chart's `api`/`small` preset, and `trusted-ca-init` is overridable through the new `trustedCaBundle.resources`. The `db-is-ready-for-backup` variant used by the pre-upgrade backup Job gets the same treatment.

- Fixed the DB preseed merging `kasmConfig.config.settings` into Kasm's default seed by list concatenation, which left a duplicate row for any setting that already exists in that seed (`kasm_auth_domain` and 86 others) and made every `/api/authenticate` call fail with a 500 (`MultipleResultsFound`) until one row was deleted by hand. Settings now upsert on `name` + `category`: a preseeded setting replaces its default counterpart, defaults with no counterpart are kept, and genuinely new settings are still appended.

## [1.1190.6] - 2026-07-28

### Changed


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
