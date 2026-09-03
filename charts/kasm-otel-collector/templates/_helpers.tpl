{{/*
  Chart name, optionally overridden by .Values.nameOverride.

  This chart deliberately does NOT reuse the `kasm.*` helpers from the kasm-helm
  chart: it is consumed as a subchart alongside them, and sharing a helper
  namespace across two independently versioned charts makes both undefinable.
*/}}
{{- define "kasmOtelCollector.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
  Fully qualified resource name.

  Precedence:
    1. .Values.fullnameOverride if set (used verbatim)
    2. else the release name alone, when it already contains the chart name
    3. else "<release>-<chart name>"
*/}}
{{- define "kasmOtelCollector.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
  Chart name and version, as the `helm.sh/chart` label value.
*/}}
{{- define "kasmOtelCollector.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
  Selector labels. These are immutable on a Deployment, so nothing release- or
  version-dependent beyond the instance name belongs here.
*/}}
{{- define "kasmOtelCollector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kasmOtelCollector.name" . }}
app.kubernetes.io/component: otel-collector
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
  Full label set applied to every resource this chart creates.
*/}}
{{- define "kasmOtelCollector.labels" -}}
helm.sh/chart: {{ include "kasmOtelCollector.chart" . }}
{{ include "kasmOtelCollector.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasm-ai
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
  Join the split registry/repository/tag into a single image reference.
  An empty .Values.image.tag falls back to the chart's appVersion.
*/}}
{{- define "kasmOtelCollector.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.registry -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end }}

{{/*
  Name of the ServiceAccount the collector pod runs as.
*/}}
{{- define "kasmOtelCollector.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "kasmOtelCollector.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{/*
  The rendered collector configuration (the ConfigMap's config.yaml key).

  Kept in a helper rather than inline in configmap.yaml so the Deployment can
  hash exactly the same bytes for its checksum/config annotation.

  The explanatory comments below are load-bearing documentation for choices that
  were arrived at empirically - keep them with the settings they explain.
*/}}
{{- define "kasmOtelCollector.config" -}}
{{- if .Values.configOverride -}}
{{- .Values.configOverride -}}
{{- else -}}
{{- $k8sEvents := .Values.receivers.k8sEvents.enabled -}}
{{- $otlp := .Values.exporters.otlp.enabled -}}
{{- $clickhouse := .Values.exporters.clickhouse.enabled -}}
{{- $debug := .Values.exporters.debug.enabled -}}
{{/* Traces and logs go to every enabled exporter; metrics deliberately skip ClickHouse. */}}
{{- $allExporters := list -}}
{{- $metricsExporters := list -}}
{{- if $otlp -}}
{{- $allExporters = append $allExporters "otlp_grpc/backend" -}}
{{- $metricsExporters = append $metricsExporters "otlp_grpc/backend" -}}
{{- end -}}
{{- if $clickhouse -}}
{{- $allExporters = append $allExporters "clickhouse/archive" -}}
{{- end -}}
{{- if $debug -}}
{{- $allExporters = append $allExporters "debug" -}}
{{- $metricsExporters = append $metricsExporters "debug" -}}
{{- end -}}
{{- if not $allExporters -}}
{{- fail "kasm-otel-collector: no exporters are enabled, so the collector would drop every signal it receives. Enable at least one of exporters.otlp.enabled, exporters.clickhouse.enabled, or exporters.debug.enabled (otelCollector.* under the kasm-agent umbrella chart)." -}}
{{- end -}}
{{- $logsProcessors := ternary (list "memory_limiter" "transform/k8s_events" "resource/k8s_events" "batch/logs") (list "memory_limiter" "batch/logs") $k8sEvents -}}
{{- $logsReceivers := ternary (list "otlp" "k8s_events") (list "otlp") $k8sEvents -}}
extensions:
  health_check:
    endpoint: "0.0.0.0:13133"

receivers:
  otlp:
    protocols:
      http:
        endpoint: "0.0.0.0:4318"
      grpc:
        endpoint: "0.0.0.0:4317"
{{ if $k8sEvents }}
  # What Kubernetes itself is doing to a session, not just our own code:
  # scheduling failures, image pulls, probe failures, OOMKills, container
  # creation - as log records, one per Event object, carrying the
  # involvedObject's name/kind as resource attributes so they correlate
  # with the app traces for the same pod/deployment. Scoped to this
  # namespace only (role.yaml's Role matches) rather than cluster-wide.
  k8s_events:
    namespaces: [{{ .Release.Namespace }}]
{{ end }}
processors:
  # Percentage-based so this stays correct if the container's memory
  # limit (deployment.yaml) ever changes, instead of a hand-recomputed
  # Mib value that silently drifts out of sync.
  memory_limiter:
    check_interval: {{ .Values.processors.memoryLimiter.checkInterval }}
    limit_percentage: {{ .Values.processors.memoryLimiter.limitPercentage }}
    spike_limit_percentage: {{ .Values.processors.memoryLimiter.spikeLimitPercentage }}

  # kube-probe hits /__ready every 10s and /__healthcheck every 15s. Each
  # is a single-span trace with a hardcoded 200, so nothing is orphaned by
  # dropping them and nothing is learned by keeping them.
  #
  # The heartbeat traces (heartbeat.beat + kube.NodeStats +
  # kube.WorkspaceContainers, every 5s) are deliberately NOT dropped --
  # they are the only continuous signal that the agent is talking to the
  # API server. Add them here if they get noisy.
  filter/probes:
    error_mode: ignore
    traces:
      span:
{{- /* OTTL conditions embed double quotes, so single-quote them unless the
       expression itself contains a single quote. */ -}}
{{- range .Values.processors.filterProbes.spans }}
        - {{ if contains "'" . }}{{ . | quote }}{{ else }}{{ . | squote }}{{ end }}
{{- end }}
    # No metrics filter: otelhttp aggregates http.server.* without a
    # route or path attribute, so probe traffic is indistinguishable from
    # real API traffic at the datapoint level. Fixing that needs a code
    # change in kasm-agent-api, not a collector rule.

  # kasm-agent-api exports its histograms with Delta temporality.
  # Prometheus is cumulative-only and silently DROPS delta metrics on its
  # OTLP receiver -- without this, http.server.* never appears in Grafana
  # even though the collector reports them exported successfully.
  deltatocumulative:
    max_stale: {{ .Values.processors.deltatocumulative.maxStale }}

  batch:
    timeout: {{ .Values.processors.batch.timeout }}
    send_batch_size: {{ .Values.processors.batch.sendBatchSize }}
    send_batch_max_size: {{ .Values.processors.batch.sendBatchMaxSize }}

  # Log records apparently run larger than trace/metric records once
  # marshaled - the shared `batch` processor's 2048-record ceiling was
  # producing logs batches that decompress past lgtm's default 4MiB gRPC
  # max-recv-message-size, so every logs batch was rejected outright
  # (ResourceExhausted) while traces/metrics on the same exporter were
  # fine. A much smaller ceiling for logs specifically avoids hitting
  # that limit without touching lgtm's own gRPC server config.
  batch/logs:
    timeout: {{ .Values.processors.batchLogs.timeout }}
    send_batch_size: {{ .Values.processors.batchLogs.sendBatchSize }}
    send_batch_max_size: {{ .Values.processors.batchLogs.sendBatchMaxSize }}
{{ if $k8sEvents }}
  # k8s_events records carry no service.name (they're not app telemetry),
  # so they'd otherwise land in Loki under the generic "unknown_service"
  # bucket. `insert` (not `upsert`) means this only fills the gap for
  # those records - otlp-sourced app logs already have a real
  # service.name and are left alone.
  resource/k8s_events:
    attributes:
      - key: service.name
        value: kubernetes-events
        action: insert

  # k8s.object.name is the *owned child's* name (Pod/ReplicaSet/Deployment),
  # not the KasmWorkspace's own name - e.g. a Pod event carries
  # "kws-alpine-3-<hex>-deploy-<rshash>-<podhash>". Derive the actual
  # workspace name so events can be filtered by the same identifier as
  # everywhere else (kasm.workspace on our own spans), one pattern per
  # object kind since the suffix differs by how far down the owner chain
  # the event fired.
  transform/k8s_events:
    log_statements:
      - context: resource
        statements:
          - set(resource.attributes["kasm.workspace"], ExtractPatterns(resource.attributes["k8s.object.name"], "^(?P<ws>.+)-deploy-[^-]+-[^-]+$")["ws"]) where resource.attributes["k8s.object.kind"] == "Pod"
          - set(resource.attributes["kasm.workspace"], ExtractPatterns(resource.attributes["k8s.object.name"], "^(?P<ws>.+)-deploy-[^-]+$")["ws"]) where resource.attributes["k8s.object.kind"] == "ReplicaSet"
          - set(resource.attributes["kasm.workspace"], ExtractPatterns(resource.attributes["k8s.object.name"], "^(?P<ws>.+)-deploy$")["ws"]) where resource.attributes["k8s.object.kind"] == "Deployment"
          - set(resource.attributes["kasm.workspace"], resource.attributes["k8s.object.name"]) where resource.attributes["k8s.object.kind"] == "KasmWorkspace"
{{ end }}
exporters:
{{- if $debug }}
  debug:
    verbosity: {{ .Values.exporters.debug.verbosity }}
{{- end }}
{{- if $otlp }}
  otlp_grpc/backend:
    endpoint: {{ .Values.exporters.otlp.endpoint }}
    tls:
      insecure: {{ .Values.exporters.otlp.tlsInsecure }}
    retry_on_failure:
      enabled: true
    sending_queue:
      enabled: true
      queue_size: {{ .Values.exporters.otlp.sendingQueueSize }}
{{- end }}
{{- if $clickhouse }}
  # Long-retention archive. Gets the same spans and log records lgtm gets,
  # kept for months instead of days and queryable in SQL -- the joins,
  # windows and percentiles-by-arbitrary-attribute that TraceQL and LogQL
  # can't express. Tempo and Loki remain the live debugging UI; adding this
  # changes nothing about what they receive.
  #
  # Metrics deliberately do not go here: Prometheus already keeps them
  # cumulative and cheap, and ClickHouse adds nothing for that shape.
  #
  # create_schema builds otel_traces / otel_logs and their materialized views
  # on first connect, so there is no migration step to run by hand.
  clickhouse/archive:
    endpoint: {{ .Values.exporters.clickhouse.endpoint }}
    database: {{ .Values.exporters.clickhouse.database }}
    username: {{ .Values.exporters.clickhouse.username }}
    # Injected into the collector container from the Secret named by
    # exporters.clickhouse.existingSecret. The collector refuses to start if
    # this is unset -- the Secret must exist in this namespace before install.
    password: ${env:CLICKHOUSE_PASSWORD}
    create_schema: {{ .Values.exporters.clickhouse.createSchema }}
    logs_table_name: {{ .Values.exporters.clickhouse.logsTableName }}
    traces_table_name: {{ .Values.exporters.clickhouse.tracesTableName }}
    # Table-level TTL; ClickHouse drops whole expired parts on merge, so this
    # costs nothing to enforce. 90 days.
    ttl: {{ .Values.exporters.clickhouse.ttl }}
    timeout: {{ .Values.exporters.clickhouse.timeout }}
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
    # ClickHouse prefers fewer, larger inserts. The queue absorbs a restart
    # or a merge pause without backpressuring the lgtm path alongside it.
    sending_queue:
      enabled: true
      queue_size: {{ .Values.exporters.clickhouse.sendingQueueSize }}
{{- end }}

service:
  telemetry:
    logs:
      level: {{ .Values.telemetry.logsLevel }}
    metrics:
      level: {{ .Values.telemetry.metricsLevel }}
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, filter/probes, batch]
      exporters: [{{ join ", " $allExporters }}]
{{- if $metricsExporters }}
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [{{ join ", " $metricsExporters }}]
{{- end }}
    logs:
      receivers: [{{ join ", " $logsReceivers }}]
      processors: [{{ join ", " $logsProcessors }}]
      exporters: [{{ join ", " $allExporters }}]
{{- end -}}
{{- end }}
