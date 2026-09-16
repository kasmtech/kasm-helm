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
                    | gateway Collector (cluster-wide, 1 pod)     <--+
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
| Collector *gateway* Deployment + Service   | one, cluster-wide, pinned      | The only OTel Collector tier in the chart. Every Kasm service, every sidecar, and any out-of-cluster senders export straight to it. Makes the trace-sampling decision and is the only writer to ClickHouse. Pinned to 1 replica — see §7. |
| ClickHouse StatefulSet + Service + PVC     | one                             | Bundled and enabled by default.                                                     |
| nginx + DB sidecar containers              | one per Proxy/Connection Proxy/DB pod, unconditional | No DaemonSet, no separate opt-in — always present when `observability.enabled`. |

Budget for this up front: a new PVC (`observability.clickhouse.storage.pvcSize`, default 20 GiB),
a new StatefulSet, one new Collector Deployment, and one extra container in every proxy/DB pod.
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

Each sidecar is that pod's single egress point to the gateway:

- The nginx sidecar receives nginx's access and error logs over loopback syslog UDP (nginx sends
  them directly; there is no shared log volume between the containers), scrapes nginx connection
  metrics from `stub_status` over the pod's own loopback interface, and receives nginx's OTLP
  traces on a loopback-only gRPC listener. Because it scrapes loopback directly (not a Service),
  nginx connection metrics are collected correctly regardless of replica count — the
  round-robin/DaemonSet problem that ruled out per-node metrics scraping in an earlier design does
  not apply to a per-pod sidecar.
- The DB sidecar tails PostgreSQL's JSON log file from the data PVC. **It does not collect
  PostgreSQL metrics** — a `postgresql` receiver would need database credentials inside the DB
  pod, and that is deliberately deferred until there is a concrete need for it. Request rate,
  error, and query-log visibility for the DB come from these logs and from the API/Manager's own
  traces of their DB calls, not from DB-side metrics.

**Known early-startup caveat.** PostgreSQL starts writing to its log file as soon as its container
starts, which can be before the sidecar container in the same pod is ready. The DB sidecar's
`filelog` receiver uses `start_at: end`: on first boot, the sidecar begins reading from whatever
the end of the file is *at the moment it starts*, not from the beginning. Any log lines written
between the primary container's start and the sidecar's readiness are therefore **not** collected
— they are silently skipped, not duplicated or replayed later. This is a narrow, one-time gap at
pod startup; it does not recur on ordinary log rotation or on Collector restarts after the
checkpoint file exists (`file_storage` offsets survive a sidecar restart).

nginx's access and error logs go out over loopback syslog UDP instead: fire-and-forget, no
checkpoint, no replay. If the sidecar container isn't yet listening on the syslog port — pod
startup, or a sidecar restart — nginx's UDP datagrams for that window are simply dropped by the
kernel; nginx does not block or retry. This is a similarly narrow gap, but unlike the DB's
file-based caveat it can also recur on every sidecar restart, not just pod startup.

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

Credentials note: with the bundled ClickHouse, the chart's generated Secret carries two keys —
`clickhouse-password` (writer, used by the gateway and retention Job) and `clickhouse-ro-password`
(the read-only `kasm_otel_ro` user api/manager query reports with). If you supply your own chart
Secret (`kasmSecrets.create: false`), it must carry both keys, or point
`observability.clickhouse.existingSecret` (and `readKey` for the read-only side) at a Secret you
manage. External ClickHouse deployments default to the single writer credential unless
`readUsername` is set.
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

## 7. Trace sampling, and the single-replica gateway

Traces containing an error, and traces slower than one second, are **always kept** regardless of
the sampling setting. Of everything else, `observability.collector.gateway.tailSamplePercentage`
(default `10`, i.e. 10%) is kept. Say this plainly to anyone investigating "missing" traces: a
trace that wasn't slow and had no error is very likely a case of correct, expected sampling, not a
bug or a dropped signal.

Sampling happens once, at the gateway Collector, which is why it needs to see every span of a
trace in one process. Every Kasm service, every sidecar, and any out-of-cluster senders export
straight to the gateway's plain `<release>-otel-gateway` ClusterIP Service — there is no forwarder
tier in front of it any more, and nothing partitions traces by ID before they reach it. The
gateway authenticates both of its receivers with the same bearer token: Collector sidecars (nginx,
DB) use OTLP/gRPC on `:4317`, while the Kasm app services (api, manager) use OTLP/HTTP on `:4318`
because that is the protocol their SDKs are wired to send, not a choice this chart makes.

**`components.otelGateway.replicas` is pinned to 1.** `deploymentSize` never raises it (the
replica preset is 1 at every size), and the chart fails the render if you set it above 1: with
plain ClusterIP round-robin and no trace-ID-aware routing in front of the gateway, a second
replica would receive some spans of a trace while the first receives the rest, and
`tail_sampling` would decide keep/drop on a partial trace, silently. `num_traces` and the
`memory_limiter` limits baked into the gateway config still scale with `deploymentSize`
(small/medium/large: 25000/50000/100000 `num_traces`, 800/1600/3200 MiB `limit_mib`, 200/400/800
MiB `spike_limit_mib`), as do the pod's own resource requests/limits (512Mi/1Gi/2Gi memory
requests, 1Gi/2Gi/4Gi memory limits) — a manual `components.otelGateway.resources` override does
**not** rescale these, see the note on `components.otelGateway.resources` in `values.yaml`.

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

Take full ownership of the gateway's Collector configuration with an `existingConfigMap`:

```yaml
observability:
  collector:
    gateway:
      existingConfigMap: kasm-otel-gateway-custom      # ClickHouse, sampling, receiver, everything
```

The ConfigMap must hold a complete Collector configuration under the key `config.yaml`; the chart
renders none of its own when this is set. Every value that only shapes the rendered config (e.g.
`tailSamplePercentage`, `forward`, `clickhouse.retention`) is ignored once `existingConfigMap` is
set, since the chart no longer renders the template that would have read them.

Start from `examples/otel-collector-custom.yaml` (safe to edit — its tuning values are
illustrative rather than preset-derived), `examples/otel-collector-splunk.yaml` (adds a Splunk HEC
exporter), or `examples/otel-collector-debug.yaml` (adds the `debug` stdout exporter from §3). All
three are complete, applyable ConfigMaps for the gateway — the only OTel Collector tier in the
chart.

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

- **Check the Collector's own logs first** — the gateway Deployment logs to stdout.
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
values are gone, not renamed. `observability` and `components` both set
`additionalProperties: false` in `values.schema.json`, so leftover keys under the old names are
**rejected** — `helm upgrade` fails with e.g. `at '/observability': additional properties
'fileLogs' not allowed`. Delete them from your values file. See
`charts/kasm-helm/CHANGELOG.md` for the full list. (Unknown keys at the values *root*, such as the
removed `logFormat`, are the exception: the root schema is permissive, so those are silent no-ops
— see §3.)

**If you are upgrading from a build that had the single cluster-wide `otel-forwarder` tier**
(`components.otelForwarder`, `observability.collector.forwarder.*`): that tier and its Deployment,
Service, and ConfigMap are gone. Every Kasm service and sidecar now exports straight to the
gateway, and `components.otelGateway.replicas` is pinned to 1. Delete any
`components.otelForwarder` and `observability.collector.forwarder.*` values before upgrading —
both are rejected by the schema (`additional properties 'forwarder' not allowed`), so leaving
them fails the upgrade at validation.

## 13. Edge trust: client-supplied trace context

The internet-facing Kasm Proxy sets `otel_trace_context propagate;` in its `otel.conf`
(`charts/kasm-helm/templates/proxy-configmaps.yaml:87`). OpenTelemetry has no concept of trace
ownership: nginx only checks whether an inbound request carries a syntactically valid
`traceparent` header. If it does, the trace continues with the client-chosen trace ID; if not,
nginx mints a new one. Nothing validates who minted it, so any client controls the trace ID (and
the `sampled` flag) for its own requests. This has three consequences:

1. **Trace collision.** Two unrelated clients sending the same `traceparent` produce spans that
   merge into one stored trace — unrelated activity gets written and read back together. This is
   data mixing, not a cosmetic display issue.
2. **Sampling control.** The `sampled` flag rides in the same header, so a client can influence
   whether its own traffic is retained, undermining
   `observability.collector.gateway.tailSamplePercentage` (§7).

(A third consequence used to apply here: a client that reused one trace ID could pin its traffic
to a single gateway pod via the forwarder's trace-ID-hashing `loadbalancing` exporter. That
exporter, and the forwarder tier it lived in, are gone — the gateway is a single pod now, pinned
by `kasm.observabilityValidate` (§7) — so there is no longer a second gateway pod to pin traffic
away from.)

**Why `propagate` is kept anyway:** the browser telemetry path
(`charts/kasm-helm/templates/proxy-configmaps.yaml:301-305`, `/otel-config.js`, `serviceName:
"kasm-web"`) is a client-generated-trace design on purpose — the browser starts the trace so that
real-user-monitoring spans link end-to-end with the backend spans of the same page load. Switching
to `otel_trace_context ignore` would sever that linkage.

**The two alternative postures, and their trade-offs** (an operator/backend decision, not a chart
default — this chart does not choose one for you):

- `otel_trace_context ignore` — nginx mints its own trace ID and disregards any client-supplied
  one. This is the normal posture for a public edge and closes all three issues above, but it
  breaks browser-to-backend trace linkage: RUM spans and backend spans of the same request no
  longer share a trace ID.
- `otel_trace_context extract` — trusts the inbound `traceparent` for correlation but is only
  appropriate when the proxy sits behind another trusted reverse proxy that itself strips or
  regenerates client-supplied trace context before it reaches this chart's ingress; it does not
  solve the exposure for a directly internet-facing proxy.

If you keep `propagate`, treat inbound trace IDs as untrusted input: apply rate limiting or
cardinality controls downstream rather than trusting sampling or gateway placement decisions that
assume good-faith trace IDs.
