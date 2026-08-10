# Observability

This chart ships a built-in OpenTelemetry observability stack: logs, traces, and metrics from
every Kasm service, nginx distributed tracing, browser telemetry, and a ClickHouse-backed store
that powers the reporting views in the Kasm Admin UI. It is enabled by default.

## 1. What you get

- **Structured logs, traces, and metrics** from every Kasm service (`api`, `manager`, `guac`,
  `rdp-gateway`, `rdp-https-gateway`), exported over OTLP.
- **nginx as the trace root.** The Kasm Proxy's nginx is instrumented (`ngx_otel_module`), so a
  request's trace starts at the proxy and continues into the service that handles it.
- **Browser telemetry** from the Kasm web UI (page loads, user interactions).
- **ClickHouse-backed reporting** in the Kasm Admin UI — the same data these signals produce is
  what the reporting views read back.

```
  browser --OTLP--> +-----------------------------------------------+
                    | Kasm namespace                                |
                    |                                               |
                    | nginx (proxy) --trace root--> api / manager   |
                    |    |                              |           |
                    |    | access/error logs           OTLP         |
                    |    v                              |           |
                    | forwarder Collector (per zone) <--+           |
                    |    |  (batch; no sampling, no ClickHouse)     |
                    |    v                                          |
                    | gateway Collector (cluster-wide, 1 pod)       |
                    |    |  (tail_sampling; only ClickHouse writer) |
                    |    v                                          |
                    | ClickHouse (logs / traces / metrics)          |
                    |    ^                                          |
                    |    | reads                                    |
                    | Kasm Admin UI reporting                       |
                    +-----------------------------------------------+
```

## 2. What gets deployed

| Workload                                   | Count             | Notes                                                                                       |
| ------------------------------------------ | ----------------- | ------------------------------------------------------------------------------------------- |
| Collector *forwarder* Deployment + Service | one per zone      | What Kasm services and nginx export to. Batches and forwards only.                          |
| Collector *gateway* Deployment + Service   | one, cluster-wide | Makes the trace-sampling decision; the only writer to ClickHouse.                           |
| ClickHouse StatefulSet + Service + PVC     | one               | Bundled and enabled by default.                                                             |
| nginx log DaemonSet or proxy-pod sidecar   | one of the two    | Default is the DaemonSet — see §4 below, the one place a default doesn't fit every cluster. |

Budget for this up front: a new PVC (`observability.clickhouse.storage.pvcSize`, default 20 GiB),
a new StatefulSet, two new Collector Deployments, and — on the default path — one DaemonSet pod
per node. See §6 for sizing.

## 3. Getting logs into your own tooling

There are three ways to get Kasm's logs, in order of recommendation:

1. **OTLP export to the bundled Collector (recommended, default).** Every service exports logs,
   traces, and metrics over OTLP already; no extra configuration needed. Point
   `observability.collector.forward.endpoint` at your own OTLP/HTTP backend (see §8) to get a
   copy of everything alongside ClickHouse, or replace the Collector config entirely with
   `existingConfigMap` (see §9) to send only to your own backend.
2. **File-based JSON logging (`observability.fileLogs`).** Off by default. Enable this only if you
   specifically need JSON log files inside the pod, tailed by a sidecar Collector — for example, a
   log-shipping agent already deployed cluster-wide that scrapes files rather than OTLP.
3. **The Collector's `debug` exporter to stdout.** Not recommended; see
   `examples/otel-collector-debug.yaml`. Supported for customers who want today's
   scrape-the-pod-logs behavior, at the cost of a second, more expensive Collector path.

**Important:** `logFormat: json` no longer changes API or Manager console output — those
services no longer honor the setting. Their stdout is human-readable text; their structured logs
go out over OTLP instead. If you were scraping JSON from `api`/`manager` pod stdout, switch to
OTLP collection or enable `observability.fileLogs`. `logFormat` still controls the Database's and
nginx-owning pods' (Proxy, RDP Gateway, RDP HTTPS Gateway) console format as before — except that
the Proxy's access log is forced to JSON whenever `observability.enabled` is true, regardless of
`logFormat`, because the log collector parses it as JSON (see §4).

## 4. How nginx logs are collected, and the Pod Security trade-off

This is the one place in the chart where the default does not fit every cluster.

By default, a DaemonSet reads the container runtime's log files from each node
(`/var/log/pods`), scoped to this release's proxy pods only (via an include glob, not a
Kubernetes API watch). It needs no ServiceAccount and no cluster permissions — the chart creates
zero RBAC objects.

That DaemonSet mounts a `hostPath` and runs as root, so it **cannot run in a namespace enforcing
the `baseline` or `restricted` Pod Security Standards.** If yours does, set:

```yaml
observability:
  hostLogs:
    enabled: false
  nginxLogs:
    enabled: true
```

This switches to a sidecar container in the proxy pod instead, sharing an `emptyDir` volume with
nginx — no hostPath, no root. As a bonus, the sidecar path also collects nginx **connection
metrics** (`connections active/accepted/handled`), which the DaemonSet path does not.

nginx **traces** work identically on both paths — this trade-off is about logs and connection
metrics only.

**Known gap, stated plainly:** on the default (DaemonSet) path, nginx connection metrics are
**not** collected — a DaemonSet cannot reach pod loopback (`stub_status`), and scraping the proxy
Service instead would round-robin across replicas and corrupt the cumulative counters it returns.
Request rate, latency, and status codes are unaffected — those all come from access logs and
spans on both paths. Enable `observability.nginxLogs` if you need connection metrics.

`hostLogs.enabled` and `nginxLogs.enabled` are mutually exclusive; the chart fails the render if
both are true.

### On OpenShift

Setting `isOpenshift: true` forces the sidecar path automatically: the chart fails the render
(rather than silently deploying a broken DaemonSet) if `hostLogs.enabled` is left at its default
`true` on OpenShift. A `hostPath` + root DaemonSet would need a `SecurityContextConstraint` this
chart does not ship, so on OpenShift you must set `nginxLogs.enabled: true` (and leave
`hostLogs.enabled: false`) — the same values as the restricted-PSS case above, for the same
underlying reason.

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
| -------------------------------------------------- | -------- | -------------------------------------------------- |
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

## 7. Trace sampling

Traces containing an error, and traces slower than one second, are **always kept** regardless of
the sampling setting. Of everything else, `observability.collector.tailSamplePercentage` (default
`10`, i.e. 10%) is kept. Say this plainly to anyone investigating "missing" traces: a trace that
wasn't slow and had no error is very likely a case of correct, expected sampling, not a bug or a
dropped signal.

Sampling happens once, at the gateway Collector — the single cluster-wide Deployment that sees
every span of a trace. This is also why the gateway is `replicas: 1` **as a correctness
requirement, not a sizing choice**: the sampling decision needs every span of a trace in one
process, and a plain Kubernetes Service load-balances requests (and therefore spans) across
replicas. Raising `observability.collector.gateway.replicas` above 1 without also putting
trace-ID-aware load balancing in front of the gateway does not increase throughput — it silently
produces traces with missing spans, because each replica votes on only the fragment of a trace it
happens to receive. The forwarder tier (per zone) scales freely; it does no sampling and holds no
cross-request state.

## 8. Forwarding to an external backend

Send a copy of everything to a vendor or a central Collector, in addition to storing it in
ClickHouse:

```yaml
observability:
  collector:
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

Start from `examples/otel-collector-custom.yaml` (a copy of the chart's own rendered gateway
config, safe to edit), `examples/otel-collector-splunk.yaml` (adds a Splunk HEC exporter), or
`examples/otel-collector-debug.yaml` (adds the `debug` stdout exporter from §3). All three are
complete, applyable ConfigMaps.

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
- **Health endpoint:** each Collector exposes `:13133` (`health_check` extension). A pod that
  fails its own health check is a good first signal something's wrong before diving into data.
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
