# Helm Chart OpenTelemetry Integration Plan

Mirror the observability stack added to `kasm_backend` on `feature/DEV-31` (OTel Collector +
ClickHouse + nginx tracing + browser telemetry) into the `kasm-helm` chart.

Source of truth for behaviour: `kasm_backend/docs/telemetry/` (`explanation/architecture.md`,
`reference/configuration.md`, `how-to/deploy.md`, `how-to/upgrade.md`).

Design decisions are settled — see §11 for the record and the backend follow-ups they imply.

---

## 1. What landed in kasm_backend (the thing being mirrored)

| Area                  | Docker/install.sh artifact                                                                         | Helm equivalent needed                                        |
| --------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Collector container   | `kasm_otel_collector` in every `docker-compose-*.yaml`, image `otel/opentelemetry-collector-contrib:0.156.0` | forwarder Deployment + Service per zone, one cluster gateway, plus a host-log DaemonSet (§3) |
| Collector config      | `install/conf/otel/otel-collector-remote.yaml` (forward-only) and `-local.yaml` (samples + exports)  | one ConfigMap per tier, overridable wholesale (§5)            |
| ClickHouse            | `kasm_clickhouse` (`clickhouse/clickhouse-server:24.12-alpine`), `docker-compose-clickhouse.yaml`   | StatefulSet + Service + PVC + configmaps, on by default        |
| ClickHouse configs    | `install/conf/clickhouse/{config.xml,users.xml,init-schema.sql}`                                     | ConfigMap + Secret-backed password                            |
| Retention             | init-schema TTL substitution on install; `ALTER TABLE … MODIFY TTL` on upgrade                       | init ConfigMap + post-upgrade retention Job                   |
| Service SDK wiring    | `OTEL_*` env on api/manager/agent/guac/rdp-gateway/rdp-https-gateway                                | env blocks on each Deployment/StatefulSet                     |
| ClickHouse read path  | `KASM_CLICKHOUSE_{ENDPOINT,DATABASE,USER,PASSWORD}` on api + manager                                | env blocks + Secret ref                                       |
| nginx tracing         | `install/conf/nginx/otel.conf` (http context), `otel_span_attr`/`otel_trace off` in `services.d/*`  | inline into `nginx-shared-configmap.yaml` + `proxy-configmaps.yaml` |
| nginx metrics         | `install/conf/nginx/stub_status.conf` (port 8090) scraped by collector `nginx/metrics` receiver     | rendered but **not scraped** — known gap, see §3b              |
| nginx logs            | collector `filelog/nginx_{access,error}` reading `/opt/kasm/<ver>/log/nginx/*`                       | DaemonSet tailing `/var/log/pods`, glob-scoped to the proxy (§3) |
| Browser telemetry     | `services.d/otel_browser.conf` → `/otel-config.js`, `/otel-time`; API `/api/client/telemetry/{traces,logs,metrics}` | proxy configmap locations                     |
| Logging refactor      | `api_server/log/handlers.py` **deleted**; `libs/telemetry` env-driven logging                        | **breaking** — retires both app configmaps (§2)               |
| DB schema             | migration `9c703ca4da21_remove_log_table`                                                           | nothing (db-upgrade Job already runs alembic)                 |
| Splunk HEC            | `install/bin/utils/migrate_splunk_config` rewrites collector config from DB settings                | documented example collector ConfigMap (§7)                   |

Fixed facts worth not re-deriving:

- Collector ports: `4318` OTLP/HTTP (local services), `4317` OTLP/gRPC + bearer auth (remote
  collectors), `4316` OTLP/gRPC **unauthenticated** (nginx `ngx_otel_module` cannot send bearer
  tokens), `13133` health, `8888` self-metrics (Prometheus).
- ClickHouse: `8123` HTTP, `9000` native, `8443` HTTPS, `9440` native-TLS. Database `kasm_otel`,
  user `kasm_otel`. `otel_logs` is pre-created by `init-schema.sql` (two-tier conditional TTL via a
  `MATERIALIZED IsAudit` column); `otel_traces`/`otel_metrics_*` are auto-created by the exporter.
- Retention defaults: logs 30d, audit logs 365d, traces 7d, metrics 90d. Tail sampling default 10 %
  of non-error/non-slow traces (`decision_wait: 30s`).
- Service names: `kasm-api`, `kasm-manager`, `kasm-agent`, `kasm-guac`, `kasm-rdp-gateway`,
  `kasm-rdp-https-gateway`, `kasm-proxy` (injected by the collector, not by nginx), `kasm-web`.

---

## 2. Logging: go OTel-native, retire the app configmaps

`server.py` dropped `logging.config.dictConfig(app_config['logging']['api_server'])` in favour of
`init_telemetry()`. `kasm_telemetry` emits **console as human-readable text** (colour via
`KASM_LOG_CONSOLE_COLOR`) and **file as JSON**; there is no json-console mode and we are not adding
one. Logs leave the services over OTLP.

**Three supported paths, in order of preference:**

| Path                            | Chart mechanism                                                                                                              | Recommended?     |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| 1. OTLP to the collector        | default — `OTEL_EXPORTER_OTLP_ENDPOINT` at the collector Service; customers point the collector at their own backend (`forward.endpoint`) or bring their own collector config | **yes, default** |
| 2. JSON file + sidecar          | `observability.fileLogs.enabled: true` → per-pod `emptyDir` at `/opt/kasm/current/log`, `KASM_LOG_FILE_ENABLED=true`, `KASM_LOG_FILE_PATH` into it, and a collector sidecar with a `filelog` receiver | for customers who want file-shaped JSON |
| 3. Collector `debug` exporter → pod stdout | documented values snippet / example ConfigMap; the collector prints what it received so cluster log-scrapers can pick it up from *one* pod | supported, not recommended |

Consequences for the chart:

- **Delete `templates/api-app-configmap.yaml` and `templates/manager-app-configmap.yaml`** and their
  mounts/volumes in `api-deployment.yaml` / `manager-deployment.yaml`. Their `logging:` sections are
  dead, and the remaining keys (`database`, `server`, `manager`, `share`) are byte-equivalent to the
  image's baked-in config and are overridden by env vars anyway. *Verify before deleting:* diff the
  rendered configmap body against `install/conf/app/{api,manager}/*.app.config.yaml` to confirm
  equivalence modulo `logging:`.
- **`KASM_LOG_FILE_ENABLED=false` is mandatory** on every `kasm_telemetry` consumer unless path 2 is
  enabled — `readOnlyRootFilesystem: true` is the chart default and `init_logging()` will mkdir/open
  `/opt/kasm/current/log/*.log` at startup.
- **`logFormat` keeps a narrower meaning:** nginx access-log format (`json_combined` vs `main`) and
  the Postgres json log symlink. Document that it no longer affects api/manager, whose console output
  is always text.
- **`tests/e2e/test_10_json_logging.py`** must be re-scoped: assert JSON stdout for nginx + Postgres
  only, and add coverage for path 2 (JSON lines present in the `emptyDir` file) rather than on api /
  manager stdout. Note that the proxy's stdout access log is now JSON whenever telemetry is enabled,
  independently of `logFormat` (§3).

### 2b. The chart overrides `nginx.conf`, which is where `load_module` lives

`kasm_nginx/Dockerfile` ships `ngx_otel_module.so` and injects
`load_module modules/ngx_otel_module.so;` as line 1 of the image's `/etc/nginx/nginx.conf`. The chart
mounts its own `nginx.conf` from `nginx-shared-configmap.yaml` over that path, so the module is never
loaded and every `otel_*` directive becomes an "unknown directive" fatal config error.

→ `nginx-shared-configmap.yaml` must emit `load_module modules/ngx_otel_module.so;` as the first line
of `nginx.conf` (unconditionally — the `.so` is always in the image and is inert without `otel.conf`),
and gate the `otel_exporter`/`otel_service_name`/`otel_trace` http-context block on
`observability.enabled`. Same for the guac / rdp-gateway / rdp-https-gateway nginx sidecars if they
mount their own `nginx.conf`.

---

## 3. Collector topology: forwarder per zone + one cluster gateway + a host-log DaemonSet

Docker gets one collector per node with the nginx log directory bind-mounted in. The Kubernetes
equivalent of "one collector per node reading local log files" is a **DaemonSet mounting
`/var/log/pods`** — the standard pattern for centralized log collection in Kubernetes. nginx writes to
stdout/stderr, the container runtime persists that to `/var/log/pods/...` on the node, and the
node-local collector tails it.

This mirrors the Docker install's two tiers exactly: `otel-collector-remote.yaml` batches and forwards
with no sampling and no ClickHouse exporter, and `otel-collector-local.yaml` on the app node is the only
place `tail_sampling` and the ClickHouse exporters live. The Kubernetes shape is the same split, with
the zone forwarder playing the role of the remote collector.

```
   api ─┐
   mgr ─┤
  guac ─┼──── OTLP :4318 ───────────────┐
   rdp ─┤                               │
 nginx ─┘    spans :4316                │
                                        │
                                        ▼
          ┌────────────────────────────────────────────────────────────┐
          │ otel-collector-<zone>  —  forwarder Deployment, N per zone │
          │ otlp/local 4318 · otlp/remote 4317 · otlp/nginx 4316       │
          │ memory_limiter, batch                                      │
          │ NO tail_sampling, NO ClickHouse exporter                   │
          └─────────────────────────────────────────┬──────────────────┘
  nginx ─ stdout/stderr                             │ :4317 (bearer)
        │ container runtime                         │
        ▼                                           │
  /var/log/pods/<ns>_<rel>-proxy-*                  │
        ▲                                           │
  ┌──────────────────────────────────────────┐
  │ otel-collector DaemonSet                 │
  │ hostPath /var/log/pods (ro)              │
  │ glob-scoped to this release's proxy pods │
  └────────────────────┬─────────────────────┘
                       │ :4317 (bearer)             │
                       └────────────────────────────┤
                                                    ▼
                    ┌────────────────────────────────────────────────────────┐
                    │ otel-gateway  —  ONE per cluster, replicas: 1          │
                    │ otlp/remote 4317 (bearer)                              │
                    │ tail_sampling  ◄── sole owner of the sampling decision │
                    │ 3× clickhouse exporters  ◄── sole writer to ClickHouse │
                    └───────────────────────┬────────────────────────────────┘
                                            ▼
                          ClickHouse StatefulSet  (or external)
```

- **One forwarder Deployment per zone**, named/labelled like api/manager/proxy are. It runs
  `memory_limiter` + `batch` only — **no `tail_sampling` and no ClickHouse exporter** — and forwards to
  the gateway over `otlp` gRPC with the bearer token, exactly as `otel-collector-remote.yaml` does in
  Docker. It holds no cross-request state, so it scales freely with `deploymentSize`. The `otlp/remote`
  receiver is still rendered so out-of-cluster agents and proxies can point at the zone's Service.
- **One gateway Deployment per cluster**, `replicas: 1`. It owns the `tail_sampling` processor and the
  three ClickHouse exporters, mirroring `otel-collector-local.yaml` on the Docker app node.
  **`replicas: 1` is a correctness requirement, not a sizing choice** — `tail_sampling` must observe
  every span of a trace in one process to decide keep-or-drop, and a ClusterIP Service spreads a
  trace's spans across replicas. Splitting it produces traces with missing spans, and
  `tailSamplePercentage` silently stops meaning "this share of traces". Scaling past one instance needs
  a `loadbalancing` exporter keyed on trace ID in front of a sampling tier; that is a follow-up, not
  something the chart does today. Being the sole ClickHouse writer also keeps insert batches
  consolidated (ClickHouse degrades under many small concurrent inserts) and avoids concurrent
  `create_schema: true` DDL from every zone.
- **One DaemonSet per cluster** (not per zone — nodes are not zone-partitioned in this chart). It
  exports straight to the gateway, so it needs no notion of a "primary zone"; the pod name recorded on
  each record identifies which proxy it came from.
- **Selection is done by the include glob, not by a filter processor.** The chart knows the release
  name and namespace at render time, so the DaemonSet reads only
  `/var/log/pods/<namespace>_<release>-proxy-*/*/*.log`. This is deliberately narrower than the
  general "collect everything, then filter on `k8sattributes`" recipe, and it buys three things:
  - it never reads another workload's or another tenant's logs;
  - far less file I/O per node;
  - the `container` operator derives namespace, pod, container and UID **from the file path**
    (`add_metadata_from_filepath`), so we need **no `k8sattributes` processor, no ServiceAccount, and
    no RBAC at all**. The chart currently creates zero RBAC objects; this keeps it that way.
- **Stream routing.** CRI records which stream each line came from, and the `container` operator
  surfaces it as `log.iostream`. A `router` operator sends `stdout` (the JSON access log) through
  `json_parser` and `stderr` (the nginx error log) through the `regex_parser`, reusing the operator
  chains from `otel-collector-local.yaml` verbatim.
- **nginx's access log must be JSON when telemetry is on.** The `json_parser` operator requires it, so
  when `observability.enabled` the stdout access log uses `json_combined` regardless of `logFormat`.
  This is a small, documented narrowing of `logFormat` for the proxy; the `main` format carries strictly
  less information.
- **No shared volume and no second `access_log`.** This is simpler than a sidecar: nothing is mounted
  into the proxy pod, `kubectl logs` behaviour is unchanged, and there is one collection path instead
  of two.
- **Offset persistence.** A `file_storage` extension backed by a second (`DirectoryOrCreate`) hostPath
  keeps filelog offsets across DaemonSet restarts, so a restart neither loses nor duplicates lines.

### 3a. The Pod Security cost, and the fallback

`hostPath` volumes are forbidden by **both** the `baseline` and `restricted` Pod Security Standards,
and reading `/var/log/pods` needs `runAsUser: 0`, which `restricted` also forbids. The chart currently
advertises and **tests** restricted-namespace support (`tests/e2e/test_06_pod_security_standards.py`,
`make e2e-pss`, `tests/kyverno/pod-security.baseline.yaml`).

So the DaemonSet **cannot run in a namespace that enforces baseline or restricted**. Consequences:

| Deployment                              | nginx log collection                                            |
| --------------------------------------- | --------------------------------------------------------------- |
| Default namespace (no PSS enforcement)  | DaemonSet — the recommended path                                 |
| `baseline`/`restricted` enforced         | `hostLogs.enabled: false`; use `nginxLogs.enabled: true` instead |

The **sidecar path is therefore retained, default off**, purely as the PSS-restricted alternative:
`emptyDir` + a `filelog` sidecar in the proxy pod, as originally planned. It costs little to keep
(the same `kasm.otelSidecar` helper serves `fileLogs`) and it is the only way to collect nginx logs
in a restricted namespace. Rendering both at once must `fail`.

nginx **spans** are unaffected in every case — `ngx_otel_module` talks to the collector directly over
the network and needs neither mechanism.

### 3b. Known gap: nginx connection metrics

The Docker install scrapes `stub_status` on port 8090 with the collector's `nginx/metrics` receiver.
A DaemonSet cannot reach a pod's loopback, and scraping the proxy *Service* round-robins across
replicas, which makes cumulative counters (`accepted`, `handled`, `requests`) meaningless.

**Decision: drop nginx connection metrics from the Kubernetes deployment for now.** Request rate,
latency, and status-code distribution are all still available from the access logs and from nginx
spans; the only genuinely lost signal is `connections active`. Two ways to get it back later, both
recorded as follow-ups rather than built now:

1. `k8s_observer` + `receiver_creator` in the DaemonSet to discover node-local proxy pods and
   instantiate an `nginx` receiver per pod — correct, but reintroduces a ServiceAccount and pod
   list/watch RBAC.
2. The sidecar path, which can scrape `localhost:8090` — already available to restricted-namespace
   deployments as a side effect of the fallback.

The `stub_status.conf` server block is still rendered (cheap, harmless, and needed by option 2), just
not scraped by default.

---

## 4. New chart files

```
charts/kasm-helm/templates/
  otel-collector-configmap.yaml          # per-zone forwarder config (skipped if BYO configmap)
  otel-collector-deployment.yaml         # per-zone forwarder, replicas from deploymentSize preset
  otel-collector-service.yaml            # 4316/4317/4318/13133 (+8888)
  otel-gateway-configmap.yaml            # gateway config: tail_sampling + clickhouse exporters
  otel-gateway-deployment.yaml           # one per cluster, replicas: 1 (correctness, see §3)
  otel-gateway-service.yaml              # 4317/13133 (+8888)
  otel-collector-daemonset.yaml          # node-local host-log collector (hostPath /var/log/pods)
  otel-collector-daemonset-configmap.yaml# filelog config, glob-scoped to the release's proxy pods
  otel-collector-sidecar-configmap.yaml  # filelog sidecar configs (fileLogs, and the PSS fallback)
  clickhouse-statefulset.yaml            # PVC via volumeClaimTemplates, uid 101, TLS like the bundled DB
  clickhouse-service.yaml                # 8123/9000 + 8443/9440
  clickhouse-configmap.yaml              # config.xml, users.xml, init-schema.sql (TTLs from values)
  clickhouse-retention-job.yaml          # post-upgrade hook: ALTER TABLE … MODIFY TTL
```

Touched existing files:

| File                                    | Change                                                                                              |
| --------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `_helpers.tpl`                          | `kasm.constants` entries for `otel` + `clickhouse`; `kasm.otelEnv` helper (shared `OTEL_*` block, takes service name); `kasm.clickhouseEnv` for api/manager; `kasm.otelSidecar` for the filelog sidecar + its `emptyDir` (used by `fileLogs` and the PSS fallback) |
| `api-deployment.yaml`                   | `kasm.otelEnv` + `kasm.clickhouseEnv`; log-file env per §2; drop app-config mount; optional sidecar   |
| `manager-deployment.yaml`               | same (`OTEL_SERVICE_NAME=kasm-manager`)                                                             |
| `guac-statefulset.yaml`                 | `kasm.otelEnv` (`kasm-guac`); `LOG_FILE_NAME_PATTERN`/`LOG_DATE_FORMAT`/`LOG_TIMESTAMP_FORMAT` now env-overridable |
| `rdp-gateway-deployment.yaml`           | `kasm.otelEnv` (`kasm-rdp-gateway`)                                                                 |
| `rdp-https-gateway-statefulset.yaml`    | `kasm.otelEnv` (`kasm-rdp-https-gateway`)                                                           |
| `proxy-deployment.yaml`                 | container port 8090; sidecar + `emptyDir` **only** on the PSS fallback path                          |
| `nginx-shared-configmap.yaml`           | `load_module` first line (§2b); `otel.conf` http-context block; stdout access_log forced to `json_combined` when telemetry is on |
| `proxy-configmaps.yaml`                 | `otel_browser.conf` (`/otel-config.js`, `/otel-time`), `stub_status.conf`, `otel_span_name`/`otel_span_attr` on `admin_api`/`client_api`/`manager_api`/`agent`, `otel_trace off` on `health`/`checkvalid`/internal auth subrequests |
| `guac-nginx-configmap.yaml`, `rdp-*-nginx-configmap.yaml` | `load_module` if they own `nginx.conf`; `otel_trace off` on tunnels                |
| `api-app-configmap.yaml`, `manager-app-configmap.yaml` | **deleted** (§2)                                                                     |
| `kasm-password-secret.yaml`             | new generated keys `clickhouse-password`, `otel-bearer-token` (preserve-on-upgrade like the others) |
| `images.txt`                            | add `otel/opentelemetry-collector-contrib:0.156.0`, `clickhouse/clickhouse-server:24.12-alpine`     |
| `values.schema.json`                    | the `observability` subtree                                                                         |
| `NOTES.txt`                             | one line on where telemetry lands / how to disable                                                   |
| `examples/`                             | `otel-collector-custom.yaml`, `otel-collector-splunk.yaml`, `otel-collector-debug.yaml` (§7)         |

---

## 5. `values.yaml` surface — thin, with the config as a replaceable ConfigMap

Everything in the collector config that is *not* an endpoint, credential, or number the chart also
needs elsewhere is **not** a value. The chart renders one sensible collector ConfigMap; customers who
need more take it over wholesale. Precedent in this chart: `components.rdpGateway.iniConfigMapName`,
`trustedCaBundle.configMapName`, `kasmConfig.existingDefaultPropertiesSecret`.

```yaml
observability:
  # observability.enabled -- master switch; false ≙ install.sh --skip-otel
  enabled: true

  collector:
    # collector.externalEndpoint -- ≙ --otel-collector-endpoint. Set to an external OTLP
    # endpoint to skip deploying either collector tier; services export straight to it.
    externalEndpoint: ""
    image: {registry: docker.io, repository: otel/opentelemetry-collector-contrib, tag: "0.156.0"}

    # One sub-tree per tier (§3). Deployment concerns live here; pipeline behaviour
    # (sampling, forwarding) stays at the collector level below, so configuring it does
    # not require knowing which tier implements it.
    forwarder:
      # collector.forwarder.existingConfigMap -- name of a user-created ConfigMap holding a
      # complete forwarder config (key: config.yaml). Set this to take full control: the chart
      # renders no forwarder config of its own. The gateway config is unaffected.
      existingConfigMap: ""
      replicas: 0                 # 0 = deploymentSize preset
      resources: {}
      # collector.forwarder.externalService -- expose 4317 for out-of-cluster agents/zones
      externalService: {enabled: false, type: LoadBalancer, annotations: {}}
    gateway:
      # collector.gateway.existingConfigMap -- as above, for the gateway config. The values
      # that only feed that config (tailSamplePercentage, forward, retention TTLs) are ignored.
      existingConfigMap: ""
      replicas: 0                 # 0 = deploymentSize preset, which is 1 at every size (§3)
      resources: {}

    tailSamplePercentage: 10      # ≙ --otel-trace-sample-percentage; applied at the gateway
    forward:                      # ≙ --otel-forward-endpoint/--otel-forward-token; at the gateway
      endpoint: ""
      token: ""
      existingSecret: {name: "", key: ""}

  # observability.fileLogs -- path 2 in the logging matrix: services write JSON log files to a
  # shared emptyDir and a filelog sidecar forwards them. Off by default (OTLP is the default path).
  fileLogs:
    enabled: false
    sizeLimit: 512Mi
    # which components get the emptyDir + sidecar
    components: [api, manager, guac]

  # observability.nginxLogs -- proxy-pod filelog sidecar for nginx access/error logs + stub_status
  nginxLogs:
    enabled: true
    sizeLimit: 512Mi

  clickhouse:
    enabled: true                 # false ≙ --no-clickhouse (collector falls back to `debug`)
    standalone: false             # true ≙ external CH via the two endpoints below
    nativeEndpoint: ""            # e.g. tcp://host:9440?secure=true&skip_verify=true
    httpEndpoint: ""              # e.g. https://host:8443 — required together with the above
    database: kasm_otel
    username: kasm_otel
    existingSecret: {name: "", key: ""}
    tls: true                     # bundled CH: enable 8443/9440 using certificate.secretName
    image: {registry: docker.io, repository: clickhouse/clickhouse-server, tag: "24.12-alpine"}
    resources: {}
    storage:
      storageClassName: ""
      pvcSize: 20
      retentionPolicy: {whenDeleted: Retain, whenScaled: Retain}
    # retention -- feeds both init-schema.sql and the collector's per-signal exporter TTLs
    retention: {logsDays: 30, auditLogsDays: 365, tracesDays: 7, metricsDays: 90}

  # observability.browser -- serves /otel-config.js with enabled true|false
  # (≙ otel_browser.conf vs otel_browser_disabled.conf)
  browser:
    enabled: true
```

Dropped from the earlier draft, now config-only (documented via `examples/`): Splunk HEC block,
`memoryLimiterMib`, `extraConfig` deep-merge, per-signal exporter queue tuning, collector self-metrics
scrape wiring.

Validation in a fail block, mirroring `validate_otel_flags()`:

- `nativeEndpoint`/`httpEndpoint` must be set together, unless `collector.externalEndpoint` is set
  (no bundled collector ⇒ no native writer).
- `clickhouse.standalone: true` + `clickhouse.enabled: false` → fail (≙ `--clickhouse-endpoint` with
  `--no-clickhouse`).
- `collector.externalEndpoint` set while a bundled ClickHouse is still deployed → warn (it will
  receive nothing unless the external collector exports back to it).
- `collector.gateway.existingConfigMap` set together with `forward.*`/`tailSamplePercentage` overrides → warn
  that they are ignored.
- `observability.enabled: false` + any other `observability.*` override → warn.

---

## 6. Behaviour parity checklist

| Installer behaviour                                              | Chart mechanism                                                                 |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `--skip-otel` removes collector + ClickHouse, serves disabled browser stub | `observability.enabled: false` → no collector/CH objects, `OTEL_SDK_DISABLED=true`, `/otel-config.js` returns `{"enabled":false}` |
| `--no-clickhouse` swaps CH exporters for `debug`                 | `clickhouse.enabled: false` → collector config renders `debug` exporter only     |
| External CH: collector native DSN + api HTTP URL                 | `clickhouse.standalone: true` + both endpoints + `existingSecret`               |
| `secure=true` DSN auto-gets `skip_verify=true`                   | replicate in the template — the collector's ClickHouse exporter takes no CA path |
| Retention applied at install (init-schema) and on upgrade (ALTER) | init ConfigMap for fresh PVCs; `helm.sh/hook: post-upgrade` Job runs the ALTERs  |
| Retention self-guards when CH is external                        | skip the Job when `clickhouse.standalone` or `!clickhouse.enabled`               |
| Warn-and-skip degradation when CH is unreachable                 | nothing to do — api/manager already degrade (reports return empty)               |
| Collector reads the nginx log files (`group_add KASM_GID`)         | DaemonSet reads `/var/log/pods` as root over a read-only hostPath; no cert or group juggling. Central collector needs the TLS cert only when `externalService.enabled` |
| ClickHouse TLS on 8443/9440 using the shared cert                | mount `certificate.secretName` exactly as `db-statefulset.yaml` does (§11.5)      |
| ClickHouse database name is configurable, independent of username (H0b) | `observability.clickhouse.database` (default `kasm_otel`) must be threaded to **all five** sites together — reads (api/manager env), writes (all three collector exporters' `database:`), schema init (`CREATE DATABASE`/`CREATE TABLE`), the `users.xml` grant, and the retention Job's `ALTER TABLE` — a partial template splits reads from writes with no error anywhere, and the grant for an XML-defined user cannot be fixed by SQL afterward |

---

## 7. Splunk HEC and other exporters

`install/bin/utils/migrate_splunk_config` reads legacy Splunk settings from the Kasm DB and
un-comments the `splunk_hec/logs` exporter + `logs/splunk` pipeline in the on-disk collector config. A
chart can't mutate a rendered ConfigMap, and per §5 this isn't values surface, so:

- ship `examples/otel-collector-splunk.yaml` — a complete collector config with the Splunk HEC
  exporter and pipeline wired, to be applied as a ConfigMap and referenced via
  `observability.collector.forwarder.existingConfigMap`;
- likewise `examples/otel-collector-debug.yaml` (logging path 3) and
  `examples/otel-collector-custom.yaml` (skeleton + the placeholder list the chart normally fills);
- release note for ≤1.19 upgrades: DB-stored Splunk HEC settings are no longer read; copy the endpoint
  and token into an `existingConfigMap`.

---

## 8. Tests

New `charts/kasm-helm/tests/` (helm-unittest) suites:

| Suite                            | Asserts                                                                                     |
| -------------------------------- | ------------------------------------------------------------------------------------------- |
| `otel_collector_test.yaml`       | Deployment/Service/ConfigMap render when enabled; absent when disabled or when `externalEndpoint` is set; per-zone naming; `existingConfigMap` suppresses the rendered config and is mounted instead |
| `otel_env_test.yaml`             | every service container gets the right `OTEL_SERVICE_NAME`/endpoint; `KASM_LOG_FILE_ENABLED=false` by default and `true` + path under `fileLogs`; `OTEL_SDK_DISABLED` when off |
| `otel_collector_config_test.yaml`| sample percentage, TTL hours, exporter selection (clickhouse vs debug vs external), forward block, secret refs |
| `otel_daemonset_test.yaml`       | DaemonSet + its ConfigMap render by default and disappear when `hostLogs.enabled=false`; hostPath is read-only; include glob contains the templated namespace and `<release>-proxy-*`; no ServiceAccount/ClusterRole rendered anywhere; exports to the primary zone's collector |
| `otel_sidecar_test.yaml`         | no sidecar in the proxy pod by default; sidecar + `emptyDir` present when `nginxLogs.enabled=true`; app pods get one only under `fileLogs.enabled`; component list respected; `hostLogs` + `nginxLogs` both enabled → render fails |
| `clickhouse_test.yaml`           | StatefulSet/PVC/Service/init-schema TTL substitution; TLS mounts + 8443/9440 when `tls: true`; absent when standalone/disabled |
| `clickhouse_external_test.yaml`  | api/manager env point at external endpoints; no bundled CH; retention Job not rendered       |
| `nginx_otel_test.yaml`           | `load_module` is line 1 of `nginx.conf`; `otel.conf` block present/absent; stub_status server; `otel_trace off` on health/internal locations; stdout access_log is `json_combined` when telemetry is on, honours `logFormat` when off |
| `otel_browser_test.yaml`         | `/otel-config.js` enabled vs disabled stub; `/otel-time` present                             |
| `negative_validation_test.yaml`  | extend with the §5 mutual-exclusion failures                                                 |

Existing suites to update: `default_image_tags_test.yaml`, `components_toggle_test.yaml`,
`healthchecks_test.yaml`, `pod_security_test.yaml`, `services_ports_test.yaml`,
`configmaps_content_test.yaml`, `deployment_size_test.yaml`, `log_format_test.yaml` (§2),
plus new `tests/values/observability-{disabled,external-ch,filelogs,byo-config}.yaml`.

E2E (`tests/e2e/`):

- `test_12_observability.py` — default install; collector + ClickHouse pods ready; after driving a
  login, query ClickHouse from the api pod for non-zero `otel_logs`/`otel_traces`/`otel_metrics` rows
  with `ServiceName IN ('kasm-api','kasm-manager','kasm-proxy','kasm-guac')`.
- `test_13_observability_disabled.py` — `observability.enabled=false`: no collector/CH objects, all
  pods healthy, `/otel-config.js` returns `enabled:false`.
- `test_14_observability_filelogs.py` — `fileLogs.enabled=true`: JSON lines present in the `emptyDir`
  file and the same records land in ClickHouse via the sidecar.
- `test_10_json_logging.py` — re-scope per §2.
- Wire into the `e2e` target list, `Makefile` shortcuts (`e2e-observability`, `e2e-observability-off`,
  `e2e-observability-filelogs`), and `tests/e2e/images.txt`.
- Kyverno/PSS: collector (uid 10001) and ClickHouse (uid 101) must satisfy `pod-security.baseline`,
  `resources.required.enforce`, `probes.required` — ClickHouse probes on `/ping`, collector on
  `:13133/`.

---

## 9. Docs / release plumbing

- `make readme` — regenerate `charts/kasm-helm/README.md` (`readme-check` is a CI gate).
- `make changelog` — CHANGELOG entry (`changelog-check` is a CI gate).
- `charts/kasm-helm/docs/observability.md` — new page: architecture sketch, the three logging paths
  from §2 with the recommendation stated plainly, ClickHouse sizing/storage guidance,
  external-ClickHouse recipe, BYO collector config + `examples/`, disabling telemetry, Splunk
  migration note, troubleshooting (collector logs, `debug` exporter, `:13133` health).
- Public docs (`components/kasm-workspaces-docs`) — Kubernetes column in the observability
  configuration tables; tracked in `kasm_backend/docs/telemetry/prompts/public-docs-update.md`.
- `tests/schemas/1_19_0-schema.yaml` — check whether preseed validation is affected by the `log`
  table removal.

---

## 10. Suggested sequencing

| Phase | Content                                                                                                                  | Gate                                  |
| ----- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| H0    | Land the two kasm_backend follow-ups from §11.5 (`KASM_CLICKHOUSE_CA_CERT`/verify) — needed before ClickHouse TLS is usable by the api read path | backend MR merged     |
| H1    | `values.yaml` + `values.schema.json` + `_helpers.tpl` constants/env/sidecar helpers + secret keys; no new workloads yet    | `make lint unittest`                  |
| H2    | Service env wiring (api, manager, guac, rdp-gateway, rdp-https-gateway); delete both app configmaps; log-file env         | `otel_env_test`, `log_format_test`    |
| H3    | ClickHouse StatefulSet/Service/ConfigMap/retention Job, incl. TLS in the Postgres shape                                  | `clickhouse_test`, `kubeconform`       |
| H4    | Collector ConfigMap/Deployment/Service, `existingConfigMap` path, validations                                             | `otel_collector*_test`                 |
| H5    | Host-log DaemonSet; `load_module`, `otel.conf`, stub_status, span attrs, browser configs; sidecar fallback + app-pod file logs | `nginx_otel_test`, `otel_daemonset_test`, `otel_sidecar_test`, `otel_browser_test` |
| H6    | E2E scenarios + Makefile targets + Kyverno/PSS pass                                                                      | `make e2e-observability*`              |
| H7    | `make docs`, `observability.md`, `examples/`, images.txt, CHANGELOG                                                       | `readme-check`, `changelog-check`      |

---

## 11. Decision record

All six decisions below were implemented as described (with the amendments already noted inline)
across H1–H6; see `PROGRESS.md` for the phase-by-phase record and its Follow-ups section for
anything deliberately left undone.

1. **Status: implemented.** **Logging — OTel-native.** OTLP to the collector is the default and
   recommended path. File-based JSON stays available via `emptyDir` + `filelog` sidecar. Collector
   `debug` exporter to stdout is supported for customers who want today's scrape-the-pod-logs
   behaviour, but explicitly not recommended. No json-console mode is being added to
   `libs/telemetry`.
2. **Status: implemented.** **nginx logs — a DaemonSet mounting `/var/log/pods`,** the standard
   Kubernetes centralized-log pattern, with the include glob scoped to the release's own proxy pods.
   Selecting by glob rather than by a `k8sattributes` filter means no ServiceAccount and no RBAC.
   Because `hostPath` and `runAsUser: 0` are both forbidden by the `baseline`/`restricted` Pod
   Security Standards, the `emptyDir` + sidecar mechanism is **retained as a default-off fallback**
   for restricted namespaces — see §3a. nginx connection metrics are dropped in Kubernetes for now
   (§3b) — tracked as a Follow-up in `PROGRESS.md`.
3. **Status: implemented.** **ClickHouse — bundled and enabled by default.** It is part of Kasm;
   customers opt out via `observability.clickhouse.enabled: false` or point at an external instance.
4. **Status: implemented.** **Multi-zone — one forwarder collector per zone, plus one cluster-wide gateway.** Revised
   2026-08-06: the original decision was one collector per zone writing straight to ClickHouse, each
   running `tail_sampling`. That is wrong — `tail_sampling` needs every span of a trace in one process,
   so N zone collectors (or a single zone collector with `replicas > 1`, which the `deploymentSize`
   presets gave us at medium and large) each vote on a fragment of any trace that crosses zones or
   replicas, yielding traces with missing spans. The two-tier split matches what the Docker install
   already ships (`otel-collector-remote.yaml` forwards without sampling; `otel-collector-local.yaml`
   samples and exports once) and ports its config nearly 1:1. See §3.
   - Considered and rejected: **collapsing everything into the DaemonSet** (services addressing a
     node-local agent via `status.hostIP` + `hostPort`). It fixes nothing the two-tier split does not,
     and `hostPort`/`hostNetwork` are forbidden by `baseline` PSS — so a restricted namespace would
     lose *all* telemetry rather than just nginx host logs (§3a).
5. **Status: implemented** (H0 landed the backend follow-ups; H3 wired the chart side; H2 added a
   standalone-ClickHouse TLS-trust surface not originally anticipated by this item — see
   `PROGRESS.md`'s Contract registry). **ClickHouse TLS — follow the bundled Postgres shape:** mount `certificate.secretName` and enable
   `https_port 8443` / `tcp_port_secure 9440` from `config.xml`, exactly as `db-statefulset.yaml`
   mounts `db_server.crt`/`.key`. Two backend follow-ups make it actually usable, and the first is a
   **pre-existing gap in the docker `--role clickhouse` topology too**:
   - `api_server/api_server/data/clickhouse_reports.py::_get_client()` calls
     `clickhouse_connect.get_client(interface="https", …)` with no `verify`/`ca_cert` argument, so it
     defaults to full certificate verification. Against a self-signed `kasm_nginx` cert — which is
     what both the dedicated `clickhouse` role and this chart present — report queries over
     `https://host:8443` will fail TLS. Add `KASM_CLICKHOUSE_CA_CERT` (preferred: the chart mounts the
     same cert and verification actually succeeds) and/or `KASM_CLICKHOUSE_VERIFY=false`.
   - The collector's ClickHouse exporter takes no CA path, only DSN query args, so collector→CH stays
     `secure=true&skip_verify=true`. Fine in-cluster; note it in the docs.

   If those follow-ups slip, fall back to plaintext `8123`/`9000` in-cluster (traffic never leaves the
   pod network) and turn TLS on only when ClickHouse is exposed outside the cluster.
6. **Status: implemented** (H1 built the values surface; H4 built the ConfigMaps; H7 added the
   worked examples). **Collector config is a ConfigMap, not a values tree.** Only endpoints,
   credentials, and numbers the chart needs in more than one place stay in `values.yaml`; everything
   else is served by `observability.collector.{forwarder,gateway}.existingConfigMap` plus worked
   examples under `examples/`. (Revised from the original single-tier wording per decision 4's
   amendment — there are two `existingConfigMap` keys, one per tier.)
