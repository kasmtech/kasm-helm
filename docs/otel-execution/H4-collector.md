# H4 — The OpenTelemetry Collector

> **Historical / superseded.** Execution record for `docs/otel-integration-plan.md`; several decisions here were reversed in design review (`kasm-helm-4ss`) and do not describe the shipped chart — see `charts/kasm-helm/docs/observability.md` for current behavior.

**Repo:** `kasm-helm`. **Depends on:** H1. **Parallel-safe with:** H2, H3, H5.
**Size:** large.

Deploy **two** Collector tiers and render their configs:

1. a **forwarder** Deployment + Service **per zone** — receives from Kasm services and nginx, batches,
   forwards. No sampling, no ClickHouse.
2. a **gateway** Deployment + Service, **one per cluster, `replicas: 1`** — owns `tail_sampling` and
   the three ClickHouse exporters.

This mirrors Docker exactly: `otel-collector-remote.yaml` is the forwarder, `otel-collector-local.yaml`
is the gateway. **Read both in full before starting**, plus plan §3 for why the split is a correctness
requirement rather than a sizing choice. Your job is to port them, replacing installer `sed`
placeholders with Helm templating and Docker service names with Kubernetes ones.

**The single most important rule in this phase:** `tail_sampling` and the ClickHouse exporters appear
in the gateway config *only*. Putting `tail_sampling` in the per-zone forwarders (or running the gateway
with more than one replica) splits each trace's spans across processes that each vote independently, so
traces come out with spans missing and `tailSamplePercentage` stops meaning what it says. It fails
silently — data still arrives, it is just wrong.

---

## 1. `templates/otel-collector-configmap.yaml` — the per-zone forwarder config

Renders when `observability.enabled` **and** `collector.forwarder.existingConfigMap` is empty **and**
`collector.externalEndpoint` is empty. Port `kasm_backend/install/conf/otel/otel-collector-remote.yaml`.
Nothing in this config varies per zone except the gateway endpoint (which does not vary either), so
render **one** ConfigMap and mount it from every zone's forwarder Deployment.

Call the validation helper from H1 at the top of this file (it renders in every enabled scenario):

```gotemplate
{{- include "kasm.observabilityValidate" . }}
```

### Placeholder → Helm mapping

| Placeholder in the source          | Replace with                                                                 |
| ---------------------------------- | ---------------------------------------------------------------------------- |
| `$OTEL_BEARER_TOKEN`               | **Do not template.** Use `${env:OTEL_BEARER_TOKEN}` and supply it from the Secret in §2 |
| `$CLICKHOUSE_PASSWORD`             | **Do not template.** Use `${env:CLICKHOUSE_PASSWORD}` from the Secret          |
| `$OTEL_TRACE_SAMPLE_PERCENTAGE`    | `{{ .Values.observability.collector.tailSamplePercentage }}`                   |
| `$OTEL_LOGS_TTL_HOURS`             | `{{ mul .Values.observability.clickhouse.retention.logsDays 24 }}h`            |
| `$OTEL_TRACES_TTL_HOURS`           | `{{ mul ...tracesDays 24 }}h`                                                  |
| `$OTEL_METRICS_TTL_HOURS`          | `{{ mul ...metricsDays 24 }}h`                                                 |

The Collector expands `${env:VAR}` at startup, which keeps both credentials out of the ConfigMap.
This is the whole reason to prefer it over Helm templating — do not "simplify" it.

### Receivers

- `otlp/local` on `0.0.0.0:4318` (HTTP) — unchanged.
- `otlp/remote` on `0.0.0.0:4317` (gRPC) with `bearertokenauth/server`. Keep the auth; it is what
  makes `collector.forwarder.externalService` safe to expose. Leave the commented-out TLS block out entirely
  rather than porting a commented block.
- `otlp/nginx` on `0.0.0.0:4316` (gRPC, no auth). Keep it — see `00-SHARED-CONTEXT.md` §6.7.
- **Drop** `nginx/metrics`, `filelog/nginx_access` and `filelog/nginx_error` from *this* config. In
  Kubernetes the nginx log receivers live in H5's host-log DaemonSet, which reads the node's
  `/var/log/pods`; the central Collector has no access to those files. `nginx/metrics` is dropped
  entirely on the default path — see plan §3b. This is the single biggest structural difference from the
  Docker config.
- The optional log sidecars in the proxy pod forward into their **zone's forwarder** over `otlp/remote`
  (4317) with the bearer token, so that receiver is load-bearing in Kubernetes, not just for
  out-of-cluster senders. The host-log **DaemonSet skips this tier and sends straight to the gateway** —
  it is cluster-wide and has no zone affinity, so routing it through a zone forwarder would mean picking
  an arbitrary "primary" zone for no benefit (H5 owns that exporter).

### Processors (forwarder)

Port `batch` and `memory_limiter` from the remote config verbatim. **No `tail_sampling` here** — see
the rule at the top of this doc.

### Exporters (forwarder)

A single `otlp` gRPC exporter to the gateway, ported from the remote config's `otlp/forward`:

- `endpoint`: `{{ $constants.otel.gatewaySvc }}:4317` (H1 added `gatewaySvc`; it is cluster-wide, not
  zone-scoped, so it takes no zone argument)
- `headers.Authorization: "Bearer ${env:OTEL_BEARER_TOKEN}"` — `${env:}`, never templated
- `tls.insecure: true` (in-cluster traffic; the Docker config does the same)
- Port `retry_on_failure` and `sending_queue` verbatim — they are what makes a gateway restart lossless

**Forwarding to an external backend** (`collector.forward.endpoint`) belongs on the **gateway**, not
here, so a forwarded copy reflects the sampling decision. Do not add `otlphttp/external` to this tier.

### Service block (forwarder)

- `extensions: [health_check]` on `0.0.0.0:13133`. No `bearertokenauth/server` unless you keep the
  `otlp/remote` receiver — you do (see Receivers), so keep it.
- All three pipelines: receivers `[otlp/local, otlp/remote, otlp/nginx]`, processors
  `[memory_limiter, batch]`, exporter `[otlp]`.
- Port the `telemetry.metrics.readers[]` Prometheus block on 8888 verbatim.

---

## 1b. `templates/otel-gateway-configmap.yaml` — the gateway config

Renders when `observability.enabled` and `collector.externalEndpoint` is empty. Port
`otel-collector-local.yaml`, skipped when `collector.gateway.existingConfigMap` is set.

**Two `existingConfigMap` keys, one per tier** (H1 added `collector.gateway.existingConfigMap` for
this): `collector.forwarder.existingConfigMap` overrides the forwarder config, `collector.gateway.existingConfigMap`
overrides the gateway config. They are independent — overriding one leaves the other chart-rendered.
A single key covering both tiers would be ambiguous and would force customers who only want to tweak
sampling to hand-maintain the forwarder config too.

### Receivers (gateway)

Only `otlp/remote` on `0.0.0.0:4317` (gRPC) with `bearertokenauth/server`. The forwarders and the
DaemonSet are its only clients. Do **not** render `otlp/local` (4318) or `otlp/nginx` (4316) here —
nothing addresses the gateway directly, and exposing them invites config that bypasses the forwarders.

### Processors (gateway)

Port `batch`, `memory_limiter` and `tail_sampling` verbatim, including the explanatory comments about
`decision_wait` — they are worth keeping. Only
`policies[2].probabilistic.sampling_percentage` is templated.

### Exporters (gateway)

Three ClickHouse exporters (`clickhouse/logs`, `clickhouse/traces`, `clickhouse/metrics`), each with
its own `ttl`, `create_schema: true`, `retry_on_failure` and `sending_queue` — port those blocks,
including the comment explaining why there are three instances. **They are not unchanged**: the
`database:` key in all three must be templated from `.Values.observability.clickhouse.database`
(H0b), not left as the literal `kasm_otel`. Leaving it literal silently splits reads from writes —
the collector would keep writing to `kasm_otel` while the API reads whatever
`.Values.observability.clickhouse.database` is set to, producing an empty UI with no error anywhere.
`create_schema: true` is retained deliberately for this reason: `GRANT ALL ON <db>.*` (H3's
`users.xml` templating) includes `CREATE TABLE`, so the exporter can still create `otel_traces` and
`otel_metrics_*` inside whichever database is configured. For a customer-managed external
ClickHouse, that grant is a documented operator prerequisite (H7).

Endpoint DSN, by scenario:

| Scenario                                        | DSN                                                                     |
| ----------------------------------------------- | ----------------------------------------------------------------------- |
| bundled ClickHouse, `tls: false`                | `tcp://<release>-clickhouse:9000?dial_timeout=10s`                       |
| bundled ClickHouse, `tls: true`                 | `tcp://<release>-clickhouse:9440?secure=true&skip_verify=true&dial_timeout=10s` |
| `standalone: true`                              | `.Values.observability.clickhouse.nativeEndpoint` verbatim if it contains `://`, else wrapped as `tcp://<value>?dial_timeout=10s` |

`skip_verify=true` is required for the bundled TLS case: the certificate is self-signed and the
ClickHouse exporter accepts no CA path, only DSN query args. Replicate the installer's
`configure_otel_external_database` behaviour for the standalone case: if the supplied DSN contains
`secure=true` but not `skip_verify`, append `skip_verify=true`. Use the H3-recorded endpoints rather
than re-deriving them, and prefer the `kasm.clickhouseNativeDsn` helper if H1 created one.

**When `clickhouse.enabled: false` and not `standalone`:** replace all three exporters with a single
`debug` exporter (`verbosity: basic`) and point all three pipelines at it. This mirrors
`configure_otel_no_database` in `install.sh` and stops the Collector crash-looping on a DNS lookup for
a service that does not exist.

**Forwarding:** when `collector.forward.endpoint` is set, add an `otlphttp/external` exporter with
that endpoint, an `Authorization: Bearer ${env:OTEL_FORWARD_TOKEN}` header when a token or
`existingSecret` is configured, and append it to all three pipelines — stacking with ClickHouse rather
than replacing it. Mirror `configure_otel_forward_endpoint`.

**Splunk:** do **not** port the commented-out `splunk_hec` blocks. They become
`examples/otel-collector-splunk.yaml` in H7.

### Service block (gateway)

- `extensions: [bearertokenauth/server, health_check]`, `health_check` on `0.0.0.0:13133`.
- Pipelines: `logs`, `traces`, `metrics`, each receiving from `[otlp/remote]` only (no filelog/nginx
  receivers, no `otlp/local`, no `otlp/nginx`), with **`tail_sampling` in the traces chain only**.
- Port the `telemetry.metrics.readers[].pull.exporter.prometheus` block on port 8888 verbatim,
  including the comment about the removed flat `address:` form — that comment prevents a real
  regression.

## 2. `templates/otel-collector-deployment.yaml` — per-zone forwarder

Renders when `observability.enabled` and `collector.externalEndpoint` is empty. Zone-scoped: copy the
`range` + `---` shape from `api-deployment.yaml` exactly.

- Replicas: `ternary .Values.observability.collector.forwarder.replicas (include "replicas.preset" (dict "node" "otel-collector" "size" .Values.deploymentSize)) (gt (int ...) 0)`.
- `strategy: RollingUpdate` with the same `maxUnavailable`/`maxSurge` idiom as the API Deployment.
- Metadata via `kasm.metadata` with `"component" "otel-collector"`, `"zone" $zone.name`.
- Container name via `include "kasm.name" (list $ "otel-collector" "container" $zone.name)`.
- Image: `$constants.otel.image`; `imagePullPolicy: {{ $.Values.imagePullPolicy }}`;
  `imagePullSecrets` block copied from the API Deployment.
- `kasm.securityContext (list $ 10001 "pod")` / `(list $ 10001 "container")` — 10001 is the
  collector image's non-root user. The collector needs no writable root; keep
  `readOnlyRootFilesystem: true`. If it needs scratch space, add an `emptyDir` at `/tmp` rather than
  relaxing the security context.
- Env:
  - `OTEL_BEARER_TOKEN` ← `secretKeyRef` `$constants.secrets.name` / `otel-bearer-token`
  - `CLICKHOUSE_PASSWORD` ← `secretKeyRef` (`clickhouse.existingSecret` when set, else
    `$constants.secrets.name` / `clickhouse-password`) — only when a ClickHouse exporter is actually
    configured
  - `OTEL_FORWARD_TOKEN` ← from `forward.existingSecret` or a literal `forward.token`, only when
    forwarding is on
  - `GOMEMLIMIT` set to ~80 % of the memory limit in effect, so the Go runtime cooperates with
    `memory_limiter`. Derive it from the resolved resources; if that is awkward to compute in
    templating, set it from the preset table with a short comment.
- Ports: 4318, 4317, 4316, 13133, 8888 — names ≤15 chars (`otlp-http`, `otlp-grpc`, `otlp-nginx`,
  `health`, `self-metrics`).
- Config mount: `/etc/otelcol-contrib/config.yaml` (subPath `config.yaml`) from either the rendered
  ConfigMap or `collector.forwarder.existingConfigMap`. **The customer's ConfigMap must use the key
  `config.yaml`** — this is documented in `values.yaml`; fail with a clear message if you can detect
  otherwise (you cannot at render time, so just document it).
- Probes when `.Values.applyHealthChecks`: liveness and readiness `http` on `/` port 13133. Use the
  `timingParent` extension if H3 added it, passing nothing for now (there is no
  `observability.collector.healthCheckTiming` value — do not add one unless you also add it to
  `values.yaml` and the schema, which is out of scope here; defaults are fine).
- Resources: `.Values.observability.collector.forwarder.resources` when set, else `resources.preset` node
  `otel-collector`.
- Add a checksum annotation on the pod template so config changes trigger a rollout:
  ```gotemplate
  checksum/config: {{ include (print $.Template.BasePath "/otel-collector-configmap.yaml") $ | sha256sum }}
  ```
  Only when rendering our own ConfigMap — with `existingConfigMap` there is nothing to checksum.
  Check whether other templates in this chart already use a checksum idiom and match it; if none do,
  it is still correct to add here.

## 3. `templates/otel-collector-service.yaml` — per-zone forwarder

Two Services, both zone-scoped:

1. **Always** (when the Deployment renders): a ClusterIP Service named
   `<release>-otel-collector-<zone>` exposing 4318, 4317, 4316, 13133, 8888. This name must match
   what `kasm.otelEnv` emits as `OTEL_EXPORTER_OTLP_ENDPOINT` — cross-check against H1's
   `PROGRESS.md` entry and fix whichever is wrong.
2. **When `collector.forwarder.externalService.enabled`**: a second Service of
   `.type` exposing **only 4317**, with `.annotations` and `.labels` applied, following how
   `proxy-service-external.yaml` handles type/annotations. Name it
   `<release>-otel-collector-<zone>-external`.

## 3b. `templates/otel-gateway-deployment.yaml` and `otel-gateway-service.yaml`

Both render when `observability.enabled` and `collector.externalEndpoint` is empty. **Not zone-scoped**
— exactly one of each per release, so no `range` over zones.

Deployment: same shape as the forwarder Deployment above, with these differences.

- **`replicas: 1`, hardcoded.** Read it from
  `ternary .Values.observability.collector.gateway.replicas (include "replicas.preset" (dict "node" "otel-gateway" "size" .Values.deploymentSize)) (gt (int ...) 0)` so an operator who has
  built trace-ID-aware routing can override it, but the preset is 1 at every size and that is
  deliberate — see plan §3. Add a comment in the template saying why, or someone will "fix" it.
- `strategy: Recreate`, not `RollingUpdate`. Two gateways briefly coexisting during a rollout is the
  same split-trace problem as `replicas: 2`, just transient; a few seconds of dropped telemetry on
  upgrade is the better trade.
- Metadata via `kasm.metadata` with `"component" "otel-gateway"`; container name via
  `include "kasm.name" (list $ "otel-gateway" "container")`.
- Env: `OTEL_BEARER_TOKEN` and `CLICKHOUSE_PASSWORD` (the latter only when a ClickHouse exporter is
  configured), plus `OTEL_FORWARD_TOKEN` when forwarding is on — the gateway is the tier that talks to
  ClickHouse and to any external forward target, so these belong **here, not on the forwarder**. The
  forwarder needs only `OTEL_BEARER_TOKEN`.
- Ports: 4317, 13133, 8888 only.
- Resources: `.Values.observability.collector.gateway.resources` when set, else `resources.preset` node
  `otel-gateway`. `GOMEMLIMIT` from that limit, same approach as the forwarder.
- Checksum annotation over `otel-gateway-configmap.yaml`.

Service: one ClusterIP named `<release>-otel-gateway` (must equal `$constants.otel.gatewaySvc`)
exposing 4317, 13133, 8888. No external Service variant — out-of-cluster senders point at a zone
forwarder's `externalService`, which is where `collector.forwarder.externalService` already applies.


---

## Verify

```bash
make lint render kubeconform kyverno unittest

# default: config renders, no credentials in it
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/default.yaml \
  | awk '/otel-collector-config/,/^---/' | grep -E 'password|token' 
# ^ should only show ${env:...} references, never a literal value

# TTLs and sampling are templated
helm template kasm-test charts/kasm-helm -n kasm-test \
  --set observability.clickhouse.retention.logsDays=60 \
  --set observability.collector.tailSamplePercentage=50 | grep -E 'ttl: 1440h|sampling_percentage: 50'

# no database → debug exporter, no clickhouse exporters
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.clickhouse.enabled=false \
  | grep -E 'debug:|clickhouse/logs'

# external collector → no Deployment, no Service, no ConfigMap, and no gateway either
helm template kasm-test charts/kasm-helm -n kasm-test \
  --set observability.collector.externalEndpoint=http://alloy:4318 | grep -ciE 'otel-collector|otel-gateway'  # → 0

# THE CRITICAL ONE: tail_sampling and the clickhouse exporters exist exactly once, in the gateway.
# Two zones must still yield one tail_sampling.
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/multizone-config.yaml \
  | grep -c 'tail_sampling:'          # → 1
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/multizone-config.yaml \
  | grep -c 'clickhouse/traces:'      # → 1
# and the gateway is single-replica
helm template kasm-test charts/kasm-helm -n kasm-test | \
  python3 -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind')=='Deployment' and d['metadata']['name'].endswith('-otel-gateway'):
        assert d['spec']['replicas']==1, d['spec']['replicas']; print('gateway replicas: 1')
"

# BYO config → Deployment mounts the named ConfigMap, chart renders none
helm template kasm-test charts/kasm-helm -n kasm-test \
  --set observability.collector.forwarder.existingConfigMap=my-collector | grep -A3 'configMap:' | grep my-collector

# the config the collector will actually load is valid YAML
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/default.yaml \
  | python3 -c "
import sys,yaml
docs=[d for d in yaml.safe_load_all(sys.stdin) if d and d.get('kind')=='ConfigMap' and 'otel-collector' in d['metadata']['name']]
for d in docs: yaml.safe_load(d['data']['config.yaml']); print('collector config parses:', d['metadata']['name'])
"
```

That last check is the important one — a malformed collector config renders fine as a ConfigMap and
only fails at pod start.

Add `tests/values/observability-disabled.yaml` and `tests/values/observability-byo-config.yaml` to the
render matrix.

## Definition of done

- Forwarder Deployment, Service and ConfigMap render per zone; the gateway Deployment, Service and
  ConfigMap render exactly once per release; all of them disappear correctly under `enabled: false` and
  `externalEndpoint`.
- **`tail_sampling:` appears exactly once in the whole rendered output, and so does each
  `clickhouse/{logs,traces,metrics}` exporter — verified with two zones configured.**
- **The gateway Deployment has `replicas: 1` and `strategy: Recreate`.**
- **Neither the ClickHouse password nor the bearer token appears literally in the ConfigMap** — both go
  through `${env:...}`.
- The rendered `config.yaml` parses as YAML in every scenario.
- `debug` exporter substitution works when there is no database; forwarding stacks on top of ClickHouse
  when configured.
- No nginx `filelog`/`nginx metrics` receivers in the central config (they belong to H5).
- `make lint render kubeconform kyverno unittest` green.

## Hand-off notes

Record in `PROGRESS.md`: the exact forwarder Service name per zone (H2's env points at these), **the
gateway Service name** (H5's DaemonSet exports to it directly — it is not zone-scoped), which tier
`existingConfigMap` overrides and what you did about the other tier, the `GOMEMLIMIT` approach, and the
port names you chose. Flag any place the Docker config had something you deliberately dropped.
