# H1 — Values, schema, helpers, secret keys

> **Historical / superseded.** Execution record for `docs/otel-integration-plan.md`; several decisions here were reversed in design review (`kasm-helm-4ss`) and do not describe the shipped chart — see `charts/kasm-helm/docs/observability.md` for current behavior.

> **SUPERSEDED IN PART (2026-08-06).** H1 is complete, but the `collector` values tree was
> restructured afterwards when the forwarder/gateway split landed. The YAML block in §1 below shows the
> **original** flat shape and is kept only as a record of what was executed. The tree as it actually
> stands is:
>
> ```
> collector:
>   externalEndpoint, image                       # apply to both tiers
>   forwarder: {existingConfigMap, replicas, resources, externalService}
>   gateway:   {existingConfigMap, replicas, resources}
>   tailSamplePercentage, forward                 # pipeline behaviour, applied at the gateway
> ```
>
> Rule: tier sub-trees hold **deployment** concerns (how many, how big, which ConfigMap, which
> Service); the `collector` level holds **pipeline behaviour**, so configuring sampling does not
> require knowing which tier implements it. Read `charts/kasm-helm/values.yaml` and the
> "Collector tier topology" row in `PROGRESS.md` for the authoritative shape — not §1 below.

**Repo:** `kasm-helm` (working dir `components/kasm-helm`)
**Depends on:** nothing. **Blocks:** H2, H3, H4, H5.
**Size:** medium. No new workloads are created in this phase — foundation only.

At the end of this phase the chart must still render and lint exactly as before, with a new
`observability` values tree that nothing consumes yet.

---

## 1. `charts/kasm-helm/values.yaml`

Insert the `observability:` block **after** the `components:` block and **before** the
`####  Extra Kubernetes config settings  ####` banner.

Follow the file's comment conventions exactly (see `00-SHARED-CONTEXT.md` §5): one
`# <dotted.path> -- <description>` line per key, continuation lines prefixed with `#`, blank `#`
line between blocks. `helm-docs` turns these into `README.md`, and `make readme-check` is a CI gate.

```yaml
# Configure the Kasm observability stack (OpenTelemetry Collector + ClickHouse). Kasm services emit
# logs, traces, and metrics over OTLP to a Collector, which stores them in ClickHouse where they back
# the reporting UI. See [Observability](./docs/observability.md) for architecture and sizing guidance.
#
observability:
  # observability.enabled -- Master switch for the whole observability stack. Set to false to deploy
  # no Collector and no ClickHouse, disable the OpenTelemetry SDKs in every Kasm service, and serve a
  # disabled browser-telemetry stub. Reporting features that read telemetry will return empty results.
  #
  enabled: true

  # Configure the OpenTelemetry Collector.
  #
  collector:
    # observability.collector.forwarder.existingConfigMap -- Name of a user-created ConfigMap holding a complete
    # Collector configuration under the key `config.yaml`. Set this to take full ownership of the
    # Collector config: the chart renders none of its own, and the values that only shape that config
    # (`tailSamplePercentage`, `forward`, and `clickhouse.retention`) are ignored. Start from the
    # chart's rendered output or from `examples/otel-collector-custom.yaml`.
    #
    existingConfigMap: ""
    # observability.collector.externalEndpoint -- Point every Kasm service at an OTLP/HTTP endpoint you
    # already run instead of deploying a Collector with this chart (e.g. `http://alloy.observability:4318`).
    # No Collector Deployment, Service, or config is rendered when this is set.
    #
    externalEndpoint: ""
    # observability.collector.image -- Configure the image repository where the image is stored. Use this
    # to point to a private hosted container registry instead of our public DockerHub hosted one.
    #
    image:
      registry: docker.io
      repository: otel/opentelemetry-collector-contrib
      # observability.collector.image.tag -- Tag for the Collector image. Unlike Kasm components this is
      # pinned by the chart rather than falling back to `useImageTags`, because the Collector is versioned
      # independently of Kasm.
      tag: "0.156.0"
    # observability.collector.forwarder.replicas -- Override the replica count set by deploymentSize. Set to 0 to use
    # the deploymentSize preset (default).
    #
    replicas: 0
    # observability.collector.forwarder.resources -- Manually configure the Collector Deployment resources. This
    # overrides the pre-defined `deploymentSize` values.
    #
    resources: {}
    # observability.collector.tailSamplePercentage -- Percentage (0-100) of traces to keep after the
    # always-keep rules. Traces containing an error, and traces slower than one second, are always kept
    # regardless of this value.
    #
    tailSamplePercentage: 10
    # observability.collector.forward -- Forward a copy of all telemetry to an external OTLP/HTTP endpoint
    # in addition to storing it in ClickHouse. Useful for shipping to a vendor or a central Collector.
    #
    forward:
      # observability.collector.forward.endpoint -- OTLP/HTTP endpoint to forward to (e.g.
      # `https://otlp-gateway.example.com/otlp`). Leave empty to disable forwarding.
      endpoint: ""
      # observability.collector.forward.token -- Bearer token for the forwarding endpoint. Prefer
      # `existingSecret` over putting a credential in values.
      token: ""
      # observability.collector.forward.existingSecret -- Read the forwarding bearer token from an existing
      # Secret instead of `token`. Both `name` and `key` are required when used.
      existingSecret:
        name: ""
        key: ""
    # observability.collector.forwarder.externalService -- Expose the Collector's OTLP/gRPC port (4317) outside the
    # cluster so Kasm Agents or Collectors running outside Kubernetes can forward telemetry in. The
    # connection requires the bearer token stored in the `otel-bearer-token` key of the Kasm secret.
    #
    externalService:
      enabled: false
      type: LoadBalancer
      annotations: {}
      labels: {}

  # observability.fileLogs -- Have Kasm services additionally write JSON log files to a shared volume,
  # tailed by a Collector sidecar. Off by default: services export logs over OTLP, which needs no volume.
  # Enable this only if you specifically want file-shaped JSON logs inside the pods.
  #
  fileLogs:
    # observability.fileLogs.enabled -- Enable JSON file logging plus a log-tailing sidecar on the
    # components listed in `components` below.
    enabled: false
    # observability.fileLogs.sizeLimit -- Size limit of the emptyDir volume holding the log files.
    sizeLimit: 512Mi
    # observability.fileLogs.components -- Which Kasm components get file logging and a tailing sidecar.
    # Allowed entries: api, manager, guac.
    components:
      - api
      - manager
      - guac

  # observability.hostLogs -- Collect the Kasm Proxy's nginx access and error logs with a Collector
  # DaemonSet that reads the container runtime's log files from each node. This is the standard
  # Kubernetes log-collection pattern and requires no changes to the proxy pod. The DaemonSet reads only
  # this release's proxy pods, in this namespace, and derives pod metadata from the log file path, so it
  # needs no ServiceAccount and no cluster permissions.
  #
  # NOTE: the DaemonSet mounts a hostPath and runs as root, both of which are forbidden by the
  # `baseline` and `restricted` Pod Security Standards. If your namespace enforces either, set this to
  # false and use `nginxLogs` instead.
  #
  hostLogs:
    # observability.hostLogs.enabled -- Deploy the node-level log collection DaemonSet.
    enabled: true
    # observability.hostLogs.persistOffsets -- Keep track of how far through each log file the collector
    # has read, in a directory on the node, so a collector restart neither loses nor repeats log lines.
    # Requires a second, writable hostPath.
    persistOffsets: true
    # observability.hostLogs.extraSelectors -- Additional pod-name patterns in this namespace to collect
    # logs from, e.g. `kasm-db-*` to capture the bundled database's logs. The release's proxy pods are
    # always collected. Kasm's API, Manager, Guac, and RDP services are deliberately excluded: they
    # export their logs over OTLP already, and collecting their console output as well would store every
    # log line twice.
    # Example:
    #   extraSelectors:
    #     - kasm-db-*
    extraSelectors: []
    # observability.hostLogs.tolerations -- Tolerations for the DaemonSet, so it can schedule onto
    # tainted nodes. Only needed if Kasm pods themselves run on tainted nodes.
    tolerations: []
    # observability.hostLogs.resources -- Manually configure the DaemonSet's resources. This overrides
    # the pre-defined `deploymentSize` values.
    resources: {}

  # observability.nginxLogs -- Collect the Kasm Proxy's nginx logs and connection metrics with a
  # Collector sidecar in the proxy pod, reading a shared volume, instead of the `hostLogs` DaemonSet.
  # Off by default: `hostLogs` is the recommended mechanism.
  #
  # Use this when your namespace enforces the `baseline` or `restricted` Pod Security Standards, which
  # forbid the hostPath mount the DaemonSet needs. This path also collects nginx connection metrics,
  # which the DaemonSet cannot reach.
  #
  # `hostLogs.enabled` and `nginxLogs.enabled` are mutually exclusive.
  #
  nginxLogs:
    # observability.nginxLogs.enabled -- Enable the nginx log/metrics sidecar in the Kasm Proxy pod.
    enabled: false
    # observability.nginxLogs.sizeLimit -- Size limit of the emptyDir volume shared between nginx and the sidecar.
    sizeLimit: 512Mi

  # Configure ClickHouse, the telemetry store that backs Kasm reporting.
  #
  clickhouse:
    # observability.clickhouse.enabled -- Deploy a ClickHouse StatefulSet to store telemetry. Set to false
    # to run the Collector with no telemetry store at all: signals are received and discarded, and Kasm
    # reporting features return empty results. To use a ClickHouse you already run, leave this true and set
    # `standalone` instead.
    #
    enabled: true
    # observability.clickhouse.standalone -- Setting standalone to true will prevent the deployment of the
    # ClickHouse StatefulSet and requires you to have a ClickHouse server already set up and awaiting
    # connections. Use the endpoint values below to connect to your external instance.
    #
    standalone: false
    # observability.clickhouse.nativeEndpoint -- DSN for ClickHouse's native interface, used by the
    # Collector to write telemetry (e.g. `tcp://clickhouse.example.com:9440?secure=true&skip_verify=true`).
    # A bare `host:port` is wrapped with the chart's defaults. Only used when `standalone` is true, and
    # required together with `httpEndpoint`.
    #
    nativeEndpoint: ""
    # observability.clickhouse.httpEndpoint -- URL for ClickHouse's HTTP interface, used by Kasm to read
    # reports and logs (e.g. `https://clickhouse.example.com:8443`). Only used when `standalone` is true,
    # and required together with `nativeEndpoint`.
    #
    httpEndpoint: ""
    # observability.clickhouse.database -- Name of the ClickHouse database holding Kasm telemetry.
    #
    database: kasm_otel
    # observability.clickhouse.username -- ClickHouse user Kasm connects as.
    #
    username: kasm_otel
    # observability.clickhouse.existingSecret -- Read the ClickHouse password from an existing Secret
    # instead of the chart-generated `clickhouse-password` key. Both `name` and `key` are required when used.
    #
    existingSecret:
      name: ""
      key: ""
    # observability.clickhouse.tls -- Enable TLS on the bundled ClickHouse's 8443 (HTTPS) and 9440 (native)
    # ports using the same certificate as the rest of Kasm, mirroring how the bundled Kasm DB is configured.
    # Requires `certificate.secretName` or cert-manager. Has no effect when `standalone` is true.
    #
    tls: true
    # observability.clickhouse.image -- Configure the image repository where the image is stored. Use this
    # to point to a private hosted container registry instead of our public DockerHub hosted one.
    #
    image:
      registry: docker.io
      repository: clickhouse/clickhouse-server
      # observability.clickhouse.image.tag -- Tag for the ClickHouse image. Pinned by the chart rather than
      # falling back to `useImageTags`, because ClickHouse is versioned independently of Kasm.
      tag: "24.12-alpine"
    # observability.clickhouse.resources -- Manually configure the ClickHouse StatefulSet resources. This
    # overrides the pre-defined `deploymentSize` values.
    #
    resources: {}
    # observability.clickhouse.healthCheckTiming -- Override the pod's default healthcheck timing values for
    # liveness and/or readiness probes. Values provided individually override their respective timing value.
    #
    healthCheckTiming:
      livenessProbe: {}
      readinessProbe: {}
    # Configure the storage for the ClickHouse StatefulSet.
    #
    storage:
      # observability.clickhouse.storage.storageClassName -- Set the storage class to attach to ClickHouse for
      # storage. Leaving this blank will use the cluster-default storage class.
      #
      storageClassName: ""
      # observability.clickhouse.storage.pvcSize -- Size of the PVC backing ClickHouse, in GiB. Telemetry volume
      # scales with session count and retention; see the observability documentation for sizing guidance.
      #
      pvcSize: 20
      # observability.clickhouse.storage.retentionPolicy -- Configure how the ClickHouse volume should be retained
      # or deleted throughout the StatefulSet's lifecycle. Defaults to Retain so telemetry history survives an
      # uninstall.
      #
      retentionPolicy:
        whenDeleted: Retain
        whenScaled: Retain
    # observability.clickhouse.retention -- How long each class of telemetry is kept before ClickHouse deletes it.
    # Applied to the schema at install time and re-applied by a post-upgrade Job when these values change.
    #
    retention:
      # observability.clickhouse.retention.logsDays -- Retention in days for general application logs.
      logsDays: 30
      # observability.clickhouse.retention.auditLogsDays -- Retention in days for security-relevant audit logs
      # (login and logout events). Usually longer than general logs to satisfy audit requirements.
      auditLogsDays: 365
      # observability.clickhouse.retention.tracesDays -- Retention in days for distributed traces.
      tracesDays: 7
      # observability.clickhouse.retention.metricsDays -- Retention in days for metrics.
      metricsDays: 90
    # observability.clickhouse.annotations -- Custom annotations to add to the ClickHouse StatefulSet
    annotations: {}
    # observability.clickhouse.labels -- Custom labels to add to the ClickHouse StatefulSet
    labels: {}

  # observability.browser -- Collect real-user telemetry from the Kasm web UI in the user's browser.
  #
  browser:
    # observability.browser.enabled -- Serve the browser telemetry runtime configuration so the Kasm web UI
    # reports page loads and user interactions. When false, a stub is served that disables the browser SDK
    # without producing console errors.
    enabled: true
```

## 2. `charts/kasm-helm/values.schema.json`

Add a matching `observability` entry under the root `properties`. The root has
`"additionalProperties": false`, so **this is not optional** — without it every render fails.

- Mirror the structure exactly, including nested `additionalProperties: false` on each object.
- Copy the `values.yaml` descriptions into `description` fields (existing entries do this; use `\n`
  for line breaks).
- `type` per key; `default` for every scalar.
- `enum` on `externalService.type`: `["LoadBalancer", "NodePort", "ClusterIP"]`.
- `fileLogs.components`: `{"type": "array", "items": {"type": "string", "enum": ["api","manager","guac"]}}`.
- `hostLogs.extraSelectors`: `{"type": "array", "items": {"type": "string"}}`.
- `hostLogs.tolerations`: `{"type": "array"}` (free-form, like the chart's other passthrough lists).
- `retentionPolicy.whenDeleted` / `whenScaled`: `enum: ["Retain","Delete"]`.
- `annotations`/`labels`: `"additionalProperties": true`.
- Keep root properties in the file's existing (roughly alphabetical-ish, not strictly sorted) order —
  insert `observability` where it reads naturally; do not re-sort the file.

Validate the JSON parses before moving on:

```bash
python3 -c "import json;json.load(open('charts/kasm-helm/values.schema.json'));print('ok')"
```

## 3. `charts/kasm-helm/templates/_helpers.tpl`

### 3a. Constants

Add to the `kasm.constants` define (after `rdpHttpsGateway`):

```gotemplate
otel:
  component: otel-collector
  svc: {{ printf "%s-otel-collector" .Release.Name }}
  portName: otel-pt
  image: {{ printf "%s/%s:%s" .Values.observability.collector.image.registry .Values.observability.collector.image.repository .Values.observability.collector.image.tag }}
  otlpHttp: 4318
  otlpGrpc: 4317
  otlpNginx: 4316
  health: 13133
  selfMetrics: 8888
clickhouse:
  component: clickhouse
  svc: {{ if .Values.observability.clickhouse.standalone }}{{- .Values.observability.clickhouse.httpEndpoint }}{{ else }}{{- printf "%s-clickhouse" .Release.Name }}{{ end }}
  portName: ch-pt
  image: {{ printf "%s/%s:%s" .Values.observability.clickhouse.image.registry .Values.observability.clickhouse.image.repository .Values.observability.clickhouse.image.tag }}
  http: 8123
  native: 9000
  httpTls: 8443
  nativeTls: 9440
proxyStubStatus: 8090
```

Note: the images use the pinned `.tag` directly rather than `kasm.imageTag`, because these are
third-party images that must not follow `useImageTags`. Do **not** route them through
`kasm.imageTag`.

For `clickhouse.svc`, prefer keeping it as the in-cluster service name only and resolving external
endpoints separately in `kasm.clickhouseEnv` — a URL in a `svc` field is confusing. Implement it that
way if it reads more cleanly; note the choice in `PROGRESS.md`.

### 3b. Presets

`replicas.preset` and `resources.preset` both `fail` on unknown `node` keys. Add:

`replicas.preset` — `"otel-collector"`: small 1, medium 2, large 2. ClickHouse is a StatefulSet with
one replica by design; do not add a `clickhouse` entry to `replicas.preset` (hardcode `replicas: 1`
in H3, as `db-statefulset.yaml` does).

`resources.preset` — add both keys, matching the existing nested `requests`/`limits` +
`ephemeral-storage` shape:

| node             | size   | requests cpu / mem | limits cpu / mem |
| ---------------- | ------ | ------------------ | ---------------- |
| `otel-collector` | small  | 200m / 256Mi       | 500m / 512Mi     |
| `otel-collector` | medium | 500m / 512Mi       | 1 / 1Gi          |
| `otel-collector` | large  | 1 / 1Gi            | 2 / 2Gi          |
| `clickhouse`     | small  | 500m / 1Gi         | 1 / 2Gi          |
| `clickhouse`     | medium | 1 / 2Gi            | 2 / 4Gi          |
| `clickhouse`     | large  | 2 / 4Gi            | 4 / 8Gi          |

Include `ephemeral-storage` on both (`requests: 50Mi`, `limits: 2Gi`) to satisfy the Kyverno
`resources.required.enforce` policy the way existing components do.

Also add a `"otel-sidecar"` resources entry (small/medium/large all: requests `100m`/`128Mi`, limits
`200m`/`256Mi`) — H5 uses it for the log-tailing sidecars **and** for the host-log DaemonSet, both of
which are much lighter than the central Collector.

Add `extraAnnotations.daemonSet` and `extraLabels.daemonSet` to `values.yaml` (and the schema) for
consistency with the existing per-resource-type keys — H5's DaemonSet passes `"resource" "daemonSet"`
to `kasm.metadata`, which looks those up.

### 3c. New helpers

Append at the end of `_helpers.tpl`, each with a usage comment in the file's existing style.

**`kasm.otelEnv`** — the shared SDK env block. Call:

```gotemplate
{{- include "kasm.otelEnv" (dict "context" $ "serviceName" "kasm-api" "zone" $zone.name) | nindent 12 }}
```

Emits, as a YAML list fragment suitable for splicing into a container's `env:`:

- When `observability.enabled` is `false`: only `- name: OTEL_SDK_DISABLED` / `value: "true"`.
- Otherwise:
  - `OTEL_SERVICE_NAME` = the passed `serviceName`
  - `OTEL_EXPORTER_OTLP_ENDPOINT` = `observability.collector.externalEndpoint` if set, else
    `http://<release>-otel-collector-<zone>:4318`
  - `OTEL_EXPORTER_OTLP_PROTOCOL` = `http/protobuf`
  - `OTEL_PYTHON_EXCLUDED_URLS` = `socket.io/*,healthcheck` — **only for the Python services**
    (api, manager). Gate it on a `"python" true` flag in the dict rather than emitting it for guac
    and the RDP gateways.
  - `OTEL_RESOURCE_ATTRIBUTES` = `deployment.environment=kubernetes,service.namespace=<namespace>`
  - `KASM_LOG_FILE_ENABLED` = `"false"`, unless this component is in
    `observability.fileLogs.components` **and** `observability.fileLogs.enabled` is true, in which
    case `"true"` plus `KASM_LOG_FILE_PATH` = `/opt/kasm/current/log/<serviceName>.log`
  - `KASM_LOG_CONSOLE_COLOR` = `"false"` (no TTY in a pod; colour codes just pollute `kubectl logs`)

  Accept an optional `"component"` key (e.g. `"api"`) used for the `fileLogs.components` membership
  test; when absent, treat file logging as disabled.

**`kasm.clickhouseEnv`** — the reporting read path, for api and manager only. Call:

```gotemplate
{{- include "kasm.clickhouseEnv" (dict "context" $) | nindent 12 }}
```

Emits nothing at all when `observability.enabled` is false **or** `clickhouse.enabled` is false and
`standalone` is false (no store to read). Otherwise:

- `KASM_CLICKHOUSE_ENDPOINT` — `httpEndpoint` when `standalone`, else
  `http://<release>-clickhouse:8123`, or `https://<release>-clickhouse:8443` when
  `clickhouse.tls` is true
- `KASM_CLICKHOUSE_DATABASE`, `KASM_CLICKHOUSE_USER` from values
- `KASM_CLICKHOUSE_PASSWORD` via `secretKeyRef` — `existingSecret.name`/`.key` when set, else
  `$constants.secrets.name` / `clickhouse-password`
- `KASM_CLICKHOUSE_CA_CERT` = `/etc/ssl/certs/kasm_clickhouse.crt` **only** when the bundled
  ClickHouse is in use with `tls: true` (H3 mounts the cert there). **Confirm the exact variable
  names against H0's `PROGRESS.md` entry before writing this** — H0 owns that contract.

Wrap the endpoint scheme/port logic in a small sub-helper if it gets unwieldy; H3, H4 and the
retention Job all need "how do I reach ClickHouse", so a single `kasm.clickhouseHttpEndpoint` /
`kasm.clickhouseNativeDsn` pair of helpers is worth it. If you add them, document them in
`PROGRESS.md` so later phases use them instead of re-deriving.

**`kasm.observabilityValidate`** — render-time validation, called once from a template that always
renders (put the call at the top of `templates/otel-collector-configmap.yaml` in H4, and for now
just define the helper). Uses `fail` for errors and `printf`-to-nothing for warnings (Helm has no
warn primitive — for warnings, prefer a comment in `NOTES.txt`; only `fail` on real errors):

- `standalone: true` and either endpoint empty → fail, naming both values
- `standalone: true` and `enabled: false` → fail (mutually exclusive)
- `forward.existingSecret.name` set without `.key`, or vice versa → fail
- `collector.externalEndpoint` set and `existingConfigMap` set → fail (no chart-rendered collector
  exists to configure)
- `fileLogs.components` containing anything other than `api`/`manager`/`guac` → fail, naming the bad
  entry
- `hostLogs.enabled` **and** `nginxLogs.enabled` both true → fail. They are two mechanisms for the same
  job and enabling both double-stores every nginx log line. The message must say which is which
  (DaemonSet vs sidecar) and that restricted-PSS namespaces want `nginxLogs`.
- `tailSamplePercentage` outside 0–100 → fail

## 4. `charts/kasm-helm/templates/kasm-password-secret.yaml`

Add `clickhouse-password` and `otel-bearer-token` to the `$knownKeys` list. That is the only change
needed — the existing loop already handles lookup-preservation on upgrade, explicit pins via
`kasmSecrets.passwords`, and random generation.

Then add both keys to `kasmSecrets.passwords` in `values.yaml` (empty strings, alongside
`manager-token` etc.) and to the schema, so they are pinnable and documented like the others.

Check whether `charts/kasm-helm/templates/db-preseed-secret.yaml` or `_kasm_config_helper.tpl`
enumerate the same key list (the preseed path builds its own secret when
`kasmConfig.generatePreseed` is true — note `kasm-password-secret.yaml` is skipped entirely in that
case). If the preseed path needs the two new keys as well, add them there; if not, note in
`PROGRESS.md` that preseed deployments source these credentials elsewhere so H3/H4 can handle it.

## 5. `charts/kasm-helm/images.txt`

Append:

```
otel/opentelemetry-collector-contrib:0.156.0
clickhouse/clickhouse-server:24.12-alpine
```

Check `tests/default_image_tags_test.yaml` and `tests/e2e/images.txt` — the former may assert on the
image list, and the latter is used by `make kind-load-images`. Update both if they enumerate images.
Note that `images.txt` uses Kasm's `1.19.0-rolling` tags for Kasm components; our two entries are
correctly pinned to upstream versions instead.

---

## Verify

```bash
python3 -c "import json;json.load(open('charts/kasm-helm/values.schema.json'));print('schema ok')"
make lint
make render        # every scenario must still render
make unittest      # existing suites must still pass unchanged
```

Then confirm the new values are actually visible and validated:

```bash
# should fail with a schema error, proving the schema is wired up
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.bogusKey=1
# should succeed
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.enabled=false >/dev/null && echo ok
```

## Definition of done

- `make lint render unittest` all green, **no rendered output changed** except the two new secret keys.
- `values.schema.json` parses and rejects unknown `observability.*` keys.
- The three new helpers exist and are documented in-file, but nothing calls `otelEnv`/`clickhouseEnv`
  yet.
- Presets exist for `otel-collector`, `clickhouse`, and `otel-sidecar`.
- `make readme-check` will now fail (README is stale) — that is expected; **do not** run `make readme`
  here. H7 regenerates it once. Note this in `PROGRESS.md`.

## Hand-off notes

Record in `PROGRESS.md`: the final helper names and their exact argument dicts, whether you added the
`clickhouseHttpEndpoint`/`clickhouseNativeDsn` sub-helpers, the `clickhouse.svc` decision, and
whether the preseed secret path needed the new keys. H2–H5 all call into this.
