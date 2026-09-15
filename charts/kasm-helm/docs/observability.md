# Observability

This chart ships a built-in OpenTelemetry observability stack: logs, traces, and metrics from
every Kasm service, nginx distributed tracing, browser telemetry, and a ClickHouse-backed store
that powers the reporting views in the Kasm Admin UI. It is enabled by default.

## 1. What you get

- **Structured logs, traces, and metrics** from every Kasm service (`api`, `manager`, `guac`,
  `rdp-gateway`, `rdp-https-gateway`), exported over OTLP.
- **nginx as the trace root.** The Kasm Proxy's nginx is instrumented (`ngx_otel_module`), so a
  request's trace starts at the proxy and continues into the service that handles it. nginx logs
  and connection metrics are collected by an always-on sidecar — see §4.
- **PostgreSQL logs**, collected by an always-on sidecar in the DB pod. **PostgreSQL metrics are
  not collected** — deferred; see §4.
- **Browser telemetry** from the Kasm web UI (page loads, user interactions).
- **ClickHouse-backed reporting** in the Kasm Admin UI — the same data these signals produce is
  what the reporting views read back.

```
  browser --OTLP--> +-----------------------------------------------+
                    | Kasm namespace                                |
                    |                                               |
                    | nginx (proxy) --trace root--> api / manager   |
                    |    |                              |           |
                    |    | sidecar (logs, conn metrics) OTLP        |
                    |    v                              |           |
                    | forwarder Collector (cluster-wide, 1+ pods) <--+
                    |    |  (batch; no sampling, no ClickHouse)     |
                    |    v  loadbalancing exporter (hash on traceID)|
                    | gateway Collector (cluster-wide, 1+ pods)     |
                    |    |  (tail_sampling; only ClickHouse writer) |
                    |    v                                          |
                    | ClickHouse (logs / traces / metrics)          |
                    |    ^                                          |
                    |    | reads                                    |
                    | Kasm Admin UI reporting                       |
                    +-----------------------------------------------+
```

## 2. What gets deployed

| Workload                                   | Count                          | Notes                                                                              |
| ------------------------------------------ | ------------------------------ | ----------------------------------------------------------------------------------- |
| Collector *forwarder* Deployment + Service | 1/2/2 by `deploymentSize`, cluster-wide (not per zone) | What every Kasm service and every sidecar exports to. Batches and forwards only.  |
| Collector *gateway* Deployment + Service   | one by default, cluster-wide   | Makes the trace-sampling decision; the only writer to ClickHouse. Scalable — see §7. |
| ClickHouse StatefulSet + Service + PVC     | one                             | Bundled and enabled by default.                                                     |
| nginx + DB sidecar containers              | one per Proxy/Connection Proxy/DB pod, unconditional | No DaemonSet, no separate opt-in — always present when `observability.enabled`. |

Budget for this up front: a new PVC (`observability.clickhouse.storage.pvcSize`, default 20 GiB),
a new StatefulSet, two new Collector Deployments, and one extra container in every proxy/DB pod.
See §6 for sizing.

## 3. Getting logs into your own tooling

There are two ways to get Kasm's logs, in order of recommendation:

1. **OTLP export to the bundled Collector (recommended, default).** Every service exports logs,
   traces, and metrics over OTLP already; no extra configuration needed. Point
   `observability.collector.gateway.forward.endpoint` at your own OTLP/HTTP backend (see §8) to
   get a copy of everything alongside ClickHouse, or replace either tier's Collector config
   entirely with `existingConfigMap` (see §9) to send only to your own backend.
2. **The Collector's `debug` exporter to stdout.** Not recommended; see
   `examples/otel-collector-debug.yaml`. Supported for customers who want today's
   scrape-the-pod-logs behavior, at the cost of a second, more expensive Collector path.

**Important:** `logFormat` was removed from the chart. Every service's stdout is now
human-readable text; structured logs go out over OTLP instead (see §4 for how nginx and DB logs
are collected). If you were scraping JSON from `api`/`manager` pod stdout, switch to OTLP
collection. The root values schema does not reject unknown top-level keys, so a leftover
`logFormat` in your values file is a silent no-op, not a render error — remove it rather than
relying on a schema error to catch it. Separately, the Proxy's access log is forced to JSON
whenever `observability.enabled` is true, because the sidecar collector parses it as JSON (see
§4).

## 4. How nginx and DB logs are collected, and the early-startup caveat

An OpenTelemetry Collector sidecar runs, unconditionally, in every Kasm Proxy pod, every
Connection Proxy pod (guac/rdp-gateway/rdp-https-gateway), and the Kasm DB pod, whenever
`observability.enabled` is true. There is no DaemonSet, no `hostPath`, and no opt-in/opt-out
knob — this is the only nginx/DB log-collection path the chart offers, and it needs no
ServiceAccount and no cluster RBAC.

Each sidecar is that pod's single egress point to the forwarder:

- The nginx sidecar tails the access and error log files nginx writes to a shared `emptyDir`,
  scrapes nginx connection metrics from `stub_status` over the pod's own loopback interface, and
  receives nginx's OTLP traces on a loopback-only gRPC listener. Because it scrapes loopback
  directly (not a Service), nginx connection metrics are collected correctly regardless of
  replica count — the round-robin/DaemonSet problem that ruled out per-node metrics scraping in an
  earlier design does not apply to a per-pod sidecar.
- The DB sidecar tails PostgreSQL's JSON log file from the data PVC. **It does not collect
  PostgreSQL metrics** — a `postgresql` receiver would need database credentials inside the DB
  pod, and that is deliberately deferred until there is a concrete need for it. Request rate,
  error, and query-log visibility for the DB come from these logs and from the API/Manager's own
  traces of their DB calls, not from DB-side metrics.

**Known early-startup caveat.** nginx (and PostgreSQL) start writing to their log files as soon as
their container starts, which can be before the sidecar container in the same pod is ready. The
sidecar's `filelog` receivers use `start_at: end`: on first boot, the sidecar begins reading from
whatever the end of the file is *at the moment it starts*, not from the beginning. Any log lines
written between the primary container's start and the sidecar's readiness are therefore **not**
collected — they are silently skipped, not duplicated or replayed later. This is a narrow,
one-time gap at pod startup; it does not recur on ordinary log rotation or on Collector restarts
after the checkpoint file exists (`file_storage` offsets survive a sidecar restart).

nginx **traces** are unaffected by any of this — `ngx_otel_module` talks to the sidecar directly
over the network as spans are emitted, with nothing to tail from a file.

## 5. Using your own ClickHouse

Set `observability.clickhouse.standalone: true` and point at an instance you already run:

```yaml
observability:
  clickhouse:
    enabled: true
    standalone: true
    nativeEndpoint: "tcp://clickhouse.example.com:9440?secure=true&skip_verify=true"
    httpEndpoint: "https://clickhouse.example.com:8443"
    database: kasm_tenant_a
    username: kasm_otel
    existingSecret:
      name: my-clickhouse-credentials
      key: password
```

`nativeEndpoint` and `httpEndpoint` are two different interfaces, not two ways to say the same
thing — **both are required together**. The Collector's gateway writes over the native protocol
(`nativeEndpoint`); the Kasm API reads reports and logs over HTTP (`httpEndpoint`). Leaving
either unset fails the render.

`observability.clickhouse.database` is independent of `username` — a tenant may run the same user
(`kasm_otel`) inside a differently-named database on a shared, multi-tenant ClickHouse instance.
Before your first install against a standalone ClickHouse, as the operator you must:

1. **Create the database.** The chart and the Collector do not create it for you.
2. **Create or reuse a user**, and
3. **`GRANT ALL ON <database>.* TO <user>`.** This is required, not optional — the Collector's
   `create_schema: true` setting relies on `CREATE TABLE` to create `otel_traces`/
   `otel_metrics_*` in that database on first write.

Grants for an operator-managed (XML-defined) ClickHouse user generally cannot be changed by a
later `GRANT` SQL statement issued at runtime. Get the database name and the grant right before
first install — fixing a mismatch afterward means editing the ClickHouse user configuration and
restarting ClickHouse, not running a `GRANT`.

If your standalone ClickHouse presents a certificate from a private or self-signed CA, set
`observability.clickhouse.caCert` (a literal PEM) or `caCertConfigMap` (an existing ConfigMap with
a `ca.crt` key) so the Kasm API/Manager can verify it when reading reports over HTTPS. Set
`tlsVerify: false` instead only if you cannot distribute a CA certificate — this disables
verification and is not recommended.

## 6. Storage and retention sizing

Four independent retention windows, applied to the ClickHouse schema at install time and
re-applied by a post-upgrade Job whenever you change them:

| Value                                              | Default  | Covers                                             |
| --------------------------------------------------- | -------- | --------------------------------------------------- |
| `observability.clickhouse.retention.logsDays`      | 30 days  | General application logs                           |
| `observability.clickhouse.retention.auditLogsDays` | 365 days | Security-relevant audit logs (login/logout events) |
| `observability.clickhouse.retention.tracesDays`    | 7 days   | Distributed traces                                 |
| `observability.clickhouse.retention.metricsDays`   | 90 days  | Metrics                                            |

Volume growth is driven by session count, traffic, and (for traces) the sampling percentage in
§7 — busier deployments and longer retention both need a bigger
`observability.clickhouse.storage.pvcSize` (default 20 GiB).

To change retention on a live release, change the values and run `helm upgrade` — the chart's
post-upgrade Job re-applies the new TTLs. **Reducing retention frees disk space only on
ClickHouse's next TTL merge**, not immediately; do not expect an instant drop in PVC usage after
a `helm upgrade` that shortens a retention window.

### Changing the database name needs an empty volume

`auditLogsDays` is implemented with a materialized `IsAudit` column on `otel_logs` that lets one
table carry two TTLs. That column is created by the initial schema, which ClickHouse runs **only when
its data directory is empty**.

The consequence: if you point an existing ClickHouse volume at a *new*
`observability.clickhouse.database`, the initial schema does not run for the new name, and
`otel_logs` gets created by the Collector instead — with a single flat `logsDays` TTL and no audit
tier. **Audit logs would then be deleted after `logsDays` (30 days by default) rather than
`auditLogsDays` (365).** Nothing reports this; the deployment looks healthy.

So when changing `observability.clickhouse.database` on an existing deployment, start from an empty
volume:

```bash
helm uninstall <release> -n <namespace>
kubectl delete pvc -l app.kubernetes.io/component=clickhouse -n <namespace>
helm install <release> ... --set observability.clickhouse.database=<new-name>
```

Note that this **discards existing telemetry history** — export anything you need to keep first. If
you cannot lose history, keep the current database name.

To check an existing deployment:

```bash
kubectl exec -n <namespace> <release>-clickhouse-0 -- \
  clickhouse-client --query "SHOW CREATE TABLE <database>.otel_logs" | grep -c IsAudit
```

`1` or more means the audit tier is in place; `0` means `otel_logs` was created without it and audit
logs are on the shorter window.

This applies only to changing the database *name*. A normal `helm upgrade` that keeps the name is
unaffected — the table already exists and the post-upgrade Job updates its TTLs in place.

## 7. Trace sampling, and scaling the gateway

Traces containing an error, and traces slower than one second, are **always kept** regardless of
the sampling setting. Of everything else, `observability.collector.gateway.tailSamplePercentage`
(default `10`, i.e. 10%) is kept. Say this plainly to anyone investigating "missing" traces: a
trace that wasn't slow and had no error is very likely a case of correct, expected sampling, not a
bug or a dropped signal.

Sampling happens once, at the gateway Collector, which is why it needs to see every span of a
trace in one process. The forwarder's exporter to the gateway is a **`loadbalancing` exporter**,
not a plain `otlp` exporter pointed at a ClusterIP: it resolves the gateway's headless Service
(DNS resolver) and hashes each trace's ID to one gateway backend, so every span of a trace lands
on the same gateway pod regardless of which forwarder pod it arrived through. This is what makes
it **safe to run more than one gateway replica** — a correctness property of the load-balancing
scheme, not a manual sizing tradeoff.

**Scale-out procedure:**

1. Set `components.otelGateway.replicas`. Raising `deploymentSize` does **not** scale the
   gateway — its replica preset is 1 at every size, since sampling correctness is the concern
   here, not throughput; this is the one component you scale by hand.
2. `helm upgrade`. The gateway Deployment's rollout uses `maxSurge: 0` / `maxUnavailable: 1`, so
   pods change one at a time; a trace whose spans straddle the rollout can still split across the
   old and new pod, bounded by `tail_sampling`'s `decision_wait` (30s) — an accepted, temporary
   cost of being able to scale and update at all, not an ongoing issue.
3. Do **not** point anything directly at the gateway's plain `<release>-otel-gateway` ClusterIP
   Service with more than one replica configured — only the forwarder's `loadbalancing` exporter
   (via the headless Service) preserves the "every span of a trace, one process" invariant.
   Sending telemetry straight to the ClusterIP with multiple gateway replicas silently produces
   traces with missing spans.
4. `num_traces` and the `memory_limiter` limits baked into the gateway config scale with
   `deploymentSize` (small/medium/large: 25000/50000/100000 `num_traces`, 800/1600/3200 MiB
   `limit_mib`, 200/400/800 MiB `spike_limit_mib`). The pod's own resource requests/limits scale
   alongside them (512Mi/1Gi/2Gi memory requests, 1Gi/2Gi/4Gi memory limits). A manual
   `components.otelGateway.resources` override does **not** rescale these — see the note on
   `components.otelGateway.resources` in `values.yaml`.

The forwarder tier scales freely regardless of the gateway; it does no sampling and holds no
cross-request state.

## 8. Forwarding to an external backend

Send a copy of everything to a vendor or a central Collector, in addition to storing it in
ClickHouse:

```yaml
observability:
  collector:
    gateway:
      forward:
        endpoint: "https://otlp-gateway.example.com/otlp"
        existingSecret:
          name: my-otlp-forward-token
          key: token
```

Prefer `existingSecret` over the plaintext `token` field. Forwarding happens at the gateway, so
the forwarded copy reflects the same sampling decision as what lands in ClickHouse.

## 9. Bringing your own Collector config

Take full ownership of either tier's Collector configuration with an `existingConfigMap`:

```yaml
observability:
  collector:
    forwarder:
      existingConfigMap: kasm-otel-collector-custom   # forwarder tier only
    gateway:
      existingConfigMap: kasm-otel-gateway-custom      # gateway tier only — ClickHouse, sampling
```

Each ConfigMap must hold a complete Collector configuration under the key `config.yaml`; the chart
renders none of its own for that tier when set. The two tiers are independent — setting one does
not affect the other. Every value that only shapes a tier's own config (e.g.
`tailSamplePercentage`, `forward`, `clickhouse.retention` for the gateway) is ignored once that
tier's `existingConfigMap` is set, since the chart no longer renders the template that would have
read them.

Start from `examples/otel-collector-custom.yaml` (a gateway-shaped starting point, safe to edit —
its tuning values are illustrative and match no rendered `deploymentSize` preset), `examples/otel-collector-splunk.yaml` (adds a Splunk HEC exporter), or
`examples/otel-collector-debug.yaml` (adds the `debug` stdout exporter from §3). All three are
complete, applyable ConfigMaps for the **gateway** tier; there is no matching forwarder example
because the forwarder's own config is a thin batch-and-loadbalance shape with nothing customers
typically need to change (see `templates/otel-forwarder-configmap.yaml` if you do need to replace
it).

## 10. Disabling telemetry

```yaml
observability:
  enabled: false
```

This is a fully supported opt-out. It deploys no Collector and no ClickHouse, disables the
OpenTelemetry SDK in every Kasm service (`OTEL_SDK_DISABLED=true`), and serves a disabled
browser-telemetry stub instead of the real one. Kasm continues to operate normally; **reporting
views in the Admin UI that read telemetry return empty results.**

## 11. Troubleshooting

- **Check the Collector's own logs first** — both the forwarder and the gateway Deployments log
  to stdout.
- **Health endpoint:** each Collector, and each sidecar, exposes `:13133` (`health_check`
  extension). A pod that fails its own health check is a good first signal something's wrong
  before diving into data.
- **Confirm data is arriving:** query ClickHouse directly, e.g.
  `clickhouse-client --query "SELECT count() FROM otel_logs"` against the ClickHouse Service (or
  your standalone instance).
- **"No data" usually means one of:**
  - the OpenTelemetry SDK is disabled (`observability.enabled: false`, or `OTEL_SDK_DISABLED=true`
    set some other way)
  - a service is pointed at the wrong Collector endpoint (rare — the chart sets this for you
    unless you've overridden it)
  - ClickHouse is unreachable from the gateway — this fails **warn-and-skip**, not hard: the
    gateway logs a retry/queue warning and keeps accepting telemetry rather than crashing, so
    check the gateway's own logs for ClickHouse connection errors.
  - the early-startup gap in §4, if the missing lines are a handful right at pod start.
- **Spot the `debug` exporter path:** if you've adopted `examples/otel-collector-debug.yaml`, or
  otherwise added a `debug` exporter, remember it duplicates every signal into the gateway pod's
  own stdout — a busy gateway with `debug` enabled will have much higher pod log volume than one
  without it, which is normal for that path and not itself a problem to chase.

## 12. Upgrading from Kasm 1.19 or earlier

**Splunk HEC settings that previously lived in the Kasm database** (Admin UI → Server Settings)
are no longer read by Kasm. If you had Splunk forwarding configured there, move those settings
into a Collector config: start from `examples/otel-collector-splunk.yaml`, fill in your real
token and endpoint (via a Secret — see that file's header comment, not a literal value), and set
`observability.collector.gateway.existingConfigMap` to it. This does not happen automatically;
until you do this, Splunk forwarding stops on upgrade.

**`logFormat: json`** no longer affects the API or Manager services — see §3 above.

**If you are upgrading from an early feature build of this chart** that had per-zone forwarders,
a `hostLogs` DaemonSet, `observability.fileLogs`, or a gateway hard-limited to one replica: those
values are gone, not renamed. The chart's root values schema does not reject unknown top-level
`observability.*` keys, so leftover values under the old names are silently ignored rather than
causing a render failure — remove them from your values file rather than relying on a schema
error to catch them. See `charts/kasm-helm/CHANGELOG.md` for the full list.
