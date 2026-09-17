{{/*
kasm-common — shared library templates.

This is a Helm library chart (type: library in Chart.yaml), so none of these `define` blocks
render on their own. charts/kasm-helm vendors it as a `file://` dependency; once `helm dependency
build`/`update` has run, every named template below is available in the same template namespace as
charts/kasm-helm/templates/_helpers.tpl, and either chart's templates can call either chart's
`define`s.

Delegation now flows kasm.* -> kasm.common.*: the real implementations of naming, metadata,
securityContext, health probes, and the shared nginx log-operator chains live here so any chart
depending only on kasm-common (e.g. kasm-otel-router, bd kasm-helm-l0r) can call them standalone.
charts/kasm-helm's own kasm.name/kasm.zoneName/kasm.metadata/kasm.securityContext/health.probe/
kasm.otelNginxAccessLogOperators/kasm.otelNginxErrorLogOperators are now one-line delegates kept for
backward compatibility with kasm-helm's existing (non-OTel) call sites — migrating those call sites
to call kasm.common.* directly is a separate, later ticket.

Values keys the real implementations here read directly from the caller's root context:
  kasm.common.metadata:        .Values.labels, .Values.components.<name>.{labels,annotations},
                                .Values.extraLabels/.extraAnnotations, .Values.ingress,
                                .Values.route, .Values.certificate.certManager, .Values.database,
                                .Values.imagePullSecrets, .Values.kasmSecrets, .Values.proxyService,
                                .Values.applyHealthChecks, .Values.applySecurity, .Release, .Chart
  kasm.common.securityContext: .Values.applySecurity, .Values.isOpenshift
  kasm.common.name:            .Release.Name (via the root context passed in)
  health.common.*:             caller-supplied dict only; no Values keys read directly

Known gap: kasm.common.metadata's `component: "pre-upgrade-backup", resource: "pvc"` branch calls
kasm.dbUpgradeBackupPvcName, which is kasm-helm-only and has not moved here. That branch will fail
for a standalone consumer that hits it; every other branch (including every call in kasm-helm today)
does not reach it. More broadly, kasm.common.metadata dereferences the Values keys listed above
without nil-guards (verbatim from the original), so a standalone consumer must define each listed
key (empty maps suffice) or metadata rendering nil-pointers — tightening this is part of the
helper-migration ticket, not day-one scope.
*/}}

{{/*
  Full resource name

  Truncated to 63 chars (trailing '-' trimmed after truncation) so the result is always safe as
  both a Kubernetes name and a label VALUE (the stricter of the two limits). This is the sole
  place the name string is assembled, and every caller -- resource metadata.name and the
  "app.kubernetes.io/name" label value alike (see kasm.common.metadata) -- gets the identical
  truncated string, which is what keeps a Deployment's selector.matchLabels equal to its own pod
  template's labels even once the untruncated name would have exceeded 63 chars (selector
  immutability requires the same input to always produce the same output everywhere). Truncation
  is not collision-safe: two distinct long names that share the same first 63 characters (or first
  62 followed by a run of non-alphanumerics on the boundary) truncate to the same string. That is a
  known, accepted gap -- out of scope here.
*/}}
{{- define "kasm.common.name" -}}
{{- $context := index . 0 -}}
{{- $component := kebabcase (index . 1) -}}

{{- $resource := "" -}}
{{- if ge (len .) 3 -}}
  {{- $resource = index . 2 -}}
{{- end -}}

{{- $zone := "" -}}
{{- if ge (len .) 4 -}}
  {{- $zone = index . 3 -}}
{{- end -}}

{{- $extra := "" -}}
{{- if ge (len .) 5 -}}
  {{- $extra = index . 4 -}}
{{- end -}}

{{- $name := "" -}}
{{- if $extra -}}
  {{- $name = printf "%s-%s-%s-%s" $context.Release.Name $component (include "kasm.common.zoneName" $zone) $extra -}}
{{- else if $zone -}}
  {{- $name = printf "%s-%s-%s" $context.Release.Name $component (include "kasm.common.zoneName" $zone) -}}
{{- else -}}
  {{- $name = printf "%s-%s" $context.Release.Name $component -}}
{{- end -}}
{{- $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Normalize a zone name to a DNS-safe label component.
  Mirrors the normalization used by `kasm.common.name` so hostnames built inline
  (proxy upstreams, init containers, env vars) match the actual Service names.
*/}}
{{- define "kasm.common.zoneName" -}}
{{- regexReplaceAll "[^a-zA-Z0-9]+" . "-" | lower -}}
{{- end -}}

{{/*
  Metadata block for resources
  Usage:
    {{- include "kasm.common.metadata" (dict "context" . "component" "api" "resource" "deployment") | nindent 2 }}
Where:
  .context   = root context (.)
  .component = component name (e.g. "api", "proxy", "db", etc)
  .resource  = resource type (e.g. "deployment", "service", "pod", etc)
  .zone      = (optional) zone name for Kasm zone-scoped resources
  .include   = (optional) if set to "la", includes only labels and annotations; otherwise emits all
  .name      = (optional) overrides name generation
*/}}
{{- define "kasm.common.metadata" -}}
{{- $ctx := .context -}}
{{- $component := .component -}}
{{- $resource := .resource -}}
{{- $zone := .zone | default "" -}}
{{- $include := .include | default "" -}}
{{- $nameOrig := .name | default "" -}}

{{- $labelName := "" -}}
{{- if $zone -}}
  {{- $labelName = include "kasm.common.name" (list $ctx $component "" $zone) -}}
{{- else -}}
  {{- $labelName = include "kasm.common.name" (list $ctx $component) -}}
{{- end -}}

{{- $name := "" -}}
{{- if $nameOrig -}}
  {{- $name = $nameOrig -}}
{{- else if and (eq $component "db") (eq $resource "statefulSet") -}}
  {{- $name = printf "%s-db-%s" $ctx.Release.Name ($ctx.Chart.AppVersion | replace "." "-") | trunc 63 | trimSuffix "-" -}}
{{- else if and (eq $component "pre-upgrade-backup") (eq $resource "pvc") -}}
  {{- $name = include "kasm.dbUpgradeBackupPvcName" $ctx -}}
{{- else if $zone -}}
  {{- $name = include "kasm.common.name" (list $ctx $component "" $zone) -}}
{{- else -}}
  {{- $name = include "kasm.common.name" (list $ctx $component) -}}
{{- end -}}

{{/* Labels */}}
{{- $labels := dict -}}

{{- with $ctx.Values.labels -}}
  {{- $labels = merge $labels . -}}
{{- end -}}

{{- with (get $ctx.Values.components .component) -}}
  {{- with .labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if $resource -}}
  {{- with (get $ctx.Values.extraLabels $resource) -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $resource "ingress" -}}
  {{- with $ctx.Values.ingress.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $resource "route" -}}
  {{- with $ctx.Values.route.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "cert-manager" -}}
  {{- with $ctx.Values.certificate.certManager.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "db" -}}
  {{- with $ctx.Values.database.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "image-pull" -}}
  {{- with $ctx.Values.imagePullSecrets.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "secrets" -}}
  {{- with $ctx.Values.kasmSecrets.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if and (or (eq $component "proxy") (eq $component "proxy-ext")) (eq $resource "service") -}}
  {{- with $ctx.Values.proxyService.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- $labels = merge $labels (dict
  "kasm.com/version" $ctx.Chart.AppVersion
  "app.kubernetes.io/name" $labelName
  "app.kubernetes.io/component" (kebabcase $component)
  "app.kubernetes.io/instance" $ctx.Release.Name
  "app.kubernetes.io/version" $ctx.Chart.AppVersion
  "app.kubernetes.io/managed-by" "Helm"
  "helm.sh/chart" (printf "%s-%s" $ctx.Chart.Name $ctx.Chart.Version)
  "app.kubernetes.io/part-of" "kasm"
) -}}


{{/* Annotations */}}
{{- $annotations := dict -}}

{{- with $ctx.Values.annotations -}}
  {{- $annotations = merge $annotations . -}}
{{- end -}}

{{- if eq $resource "ingress" -}}
  {{- with $ctx.Values.ingress.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- with (get $ctx.Values.components .component) -}}
  {{- with .annotations }}
    {{- $annotations = merge $annotations . -}}
  {{- end }}
{{- end }}

{{- if .resource -}}
  {{- with (get $ctx.Values.extraAnnotations .resource) -}}
    {{- $annotations = merge $annotations . -}}
  {{- end }}
{{- end -}}

{{- if and (or (eq $component "proxy") (eq $component "proxy-ext")) (eq $resource "service") -}}
  {{- with $ctx.Values.proxyService.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $resource "route" -}}
  {{- with $ctx.Values.route.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "cert-manager" -}}
  {{- with $ctx.Values.certificate.certManager.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "db" -}}
  {{- with $ctx.Values.database.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "image-pull" -}}
  {{- with $ctx.Values.imagePullSecrets.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "secrets" -}}
  {{- with $ctx.Values.kasmSecrets.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{/*
  Caller-supplied ad-hoc annotations (e.g. a checksum/config annotation computed by the calling
  template). Merged in like every other annotation source above rather than emitted as a second
  "annotations:" block, which would be a duplicate YAML key.
*/}}
{{- with .extraAnnotations -}}
  {{- $annotations = merge $annotations . -}}
{{- end -}}

{{/* Special Cases */}}

{{- if and $ctx.Values.applyHealthChecks (has .resource (list "deployment" "pod" "statefulSet" "daemonset" "job" "cronJob" "cronPod")) -}}
  {{- $annotations = merge $annotations (dict "kasm.com/healthcheck" "true") -}}
{{- end -}}

{{- if and $ctx.Values.applySecurity (has .resource (list "deployment" "pod" "statefulSet" "daemonset" "job" "cronJob" "cronPod")) -}}
  {{- $annotations = merge $annotations (dict "kasm.com/security" "true") -}}
{{- end -}}

{{- if and (eq .component "db-backup") (eq .resource "pvc") -}}
  {{- $annotations = merge $annotations (dict
  "helm.sh/resource-policy" "keep"
  "helm.sh/hook-weight" "100"
  ) -}}
{{- end -}}

{{- if (or (eq $component "secrets") (eq $component "image-pull") (eq $component "db-preseed")) -}}
  {{- $annotations = merge $annotations (dict
      "helm.sh/hook" "pre-install,pre-upgrade"
    ) -}}
{{- end -}}

{{- if (and (eq $component "pre-upgrade-backup") (eq $resource "pvc")) -}}
  {{- $annotations = merge $annotations (dict
      "helm.sh/resource-policy" "keep"
      "helm.sh/hook-weight" "-10"
      "helm.sh/hook" "pre-upgrade,pre-install"
    ) -}}
{{- end -}}

{{- if (and (eq $component "pre-upgrade-backup") (eq $resource "job")) -}}
  {{- $annotations = merge $annotations (dict
      "helm.sh/hook-weight" "10"
      "helm.sh/hook" "pre-upgrade,pre-install"
    ) -}}
{{- end -}}

{{/* Output Metadata Block */}}

{{- if eq .include "all" }}
name: {{ $name }}
namespace: {{ $ctx.Release.Namespace }}
{{- end }}
{{- if or (eq .include "all") (eq .include "la") }}
labels:
{{- toYaml $labels | nindent 2 }}
{{- with $annotations }}
annotations:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- if eq .include "match" }}
app.kubernetes.io/name: {{ $labelName }}
app.kubernetes.io/component: {{ (kebabcase $component) }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
{{- end }}
{{- end -}}

{{/*
Pod hardening/security settings
Usage:
  {{ include "kasm.common.securityContext" (list . 1000 pod) | nindent 6 }}
Where:
  index 1 = runAsUser/runAsGroup integer
  index 2 = context ("pod" or "container")
*/}}
{{- define "kasm.common.securityContext" -}}
{{- $rootContext := index . 0 -}}
{{- $runAs := index . 1 -}}
{{- $context := index . 2 -}}
{{- $ro := true -}}
{{- if ge (len .) 4 -}}
  {{- $opts := index . 3 -}}
  {{- if and $opts (hasKey $opts "readOnlyRootFilesystem") -}}
    {{- $ro = get $opts "readOnlyRootFilesystem" -}}
  {{- end -}}
{{- end -}}

{{- if $rootContext.Values.applySecurity -}}
securityContext:
  {{- if eq $context "pod" }}
    {{- if not $rootContext.Values.isOpenshift }}
  runAsUser: {{ $runAs }}
  runAsGroup: {{ $runAs }}
  fsGroup: {{ $runAs }}
    {{- end }}
  fsGroupChangePolicy: OnRootMismatch
  {{- else if eq $context "container" -}}
    {{- if not $rootContext.Values.isOpenshift }}
  runAsUser: {{ $runAs }}
  runAsGroup: {{ $runAs }}
    {{- end }}
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: {{ $ro }}
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
  {{- else -}}
    {{- printf "ERROR: Invalid context value '%s'. Allowed values are %s" $context "pod, container" | fail }}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
  Consolidated Kubernetes health probe helper.

  This helper renders one Kubernetes probe block using a chart-developer-selected
  probe implementation type while resolving admin-configurable probe timing from
  values.yaml.

  Required args:
    root: Root chart context. Usually pass $.
    component: Component selector used to locate healthCheckTiming in values.yaml. Standard components resolve from:
                .Values.components.<component>.healthCheckTiming. The database component is special-cased: component: db
                resolves from: .Values.database.healthCheckTiming
    probeType: Probe timing selector under healthCheckTiming. Expected values: livenessProbe, readinessProbe type: Kubernetes
              probe implementation type. Allowed values: http, https, tcp, command

  Optional args:
    timingScope: Optional sub-selector for components with multiple containers and container-specific health check timing. When
                supplied, timing resolves from: .Values.components.<component>.<timingScope>.healthCheckTiming.<probeType>
                Example timingScope selectors: nginxSidecar
    timingParent: Optional dict, used in place of the .Values.components.<component> lookup for components that
                don't live under .Values.components (e.g. observability.clickhouse, observability.collector).
                When supplied, timing resolves from: <timingParent>.healthCheckTiming.<probeType>, and both the
                "db" special-case and the "components" lookup are skipped entirely. Takes priority over timingScope.

  Probe-specific args:
    For type: http or https
      path: HTTP path used by httpGet.
      portName or port: Named or numeric container port used by httpGet.
    For type: tcp
      portName or port: Named or numeric container port used by tcpSocket.
    For type: command
      command: Either a string command rendered as: /bin/sh -c "<command>" Or a list rendered directly as the exec command array.

  Timing resolution order:
    If component == "db":
        .Values.database.healthCheckTiming.<probeType>
    Else if container is supplied:
        .Values.components.<component>.healthCheckTiming.<container>.<probeType>
    Else:
        .Values.components.<component>.healthCheckTiming.<probeType>

  Timing defaults used when values are omitted:
    timeoutSeconds: 5
    initialDelaySeconds: 10
    periodSeconds: 30
    failureThreshold: 3
    successThreshold: 1

  Example, standard single-container component:
    livenessProbe:
      {{- include "health.common.probe" (dict
            "root" $
            "component" "api"
            "probeType" "livenessProbe"
            "type" "http"
            "path" "/healthz"
            "portName" "api"
          ) | nindent 6 }}
*/}}
{{- define "health.common.probe" -}}
{{- $root := required "health.common.probe requires root" .root -}}
{{- $componentName := required "health.common.probe requires component" .component -}}
{{- $probeType := required "health.common.probe requires probeType" .probeType -}}
{{- $probeKind := required "health.common.probe requires type: http, https, tcp, or command" .type | lower -}}

{{- $healthCheckParent := dict -}}

{{- if hasKey . "timingParent" -}}
  {{- $healthCheckParent = .timingParent | default dict -}}
{{- else if eq $componentName "db" -}}
  {{- $healthCheckParent = get $root.Values "database" | default dict -}}
{{- else -}}
  {{- $components := get $root.Values "components" | default dict -}}
  {{- $component := get $components $componentName | default dict -}}

  {{- if hasKey . "timingScope" -}}
    {{- $timingScope := .timingScope -}}
    {{- $healthCheckParent = get $component $timingScope | default dict -}}
  {{- else -}}
    {{- $healthCheckParent = $component -}}
  {{- end -}}
{{- end -}}

{{- $healthCheckTiming := get $healthCheckParent "healthCheckTiming" | default dict -}}
{{- $timing := get $healthCheckTiming $probeType | default dict -}}

{{- $timeoutSeconds := get $timing "timeoutSeconds" | default 5 -}}
{{- $initialDelaySeconds := get $timing "initialDelaySeconds" | default 10 -}}
{{- $periodSeconds := get $timing "periodSeconds" | default 30 -}}
{{- $failureThreshold := get $timing "failureThreshold" | default 3 -}}
{{- $successThreshold := get $timing "successThreshold" | default 1 -}}

{{- if or (eq $probeKind "http") (eq $probeKind "https") -}}
{{- $path := required "health.common.probe type http/https requires path" .path -}}
{{- $port := "" -}}
{{- if hasKey . "port" -}}
  {{- $port = .port -}}
{{- else if hasKey . "portName" -}}
  {{- $port = .portName -}}
{{- else -}}
  {{- fail "health.common.probe type http/https requires port or portName" -}}
{{- end -}}
httpGet:
  path: {{ $path | quote }}
  port: {{ $port }}
{{- if eq $probeKind "https" }}
  scheme: HTTPS
{{- end }}

{{- else if eq $probeKind "tcp" -}}
{{- $port := "" -}}
{{- if hasKey . "port" -}}
  {{- $port = .port -}}
{{- else if hasKey . "portName" -}}
  {{- $port = .portName -}}
{{- else -}}
  {{- fail "health.common.probe type tcp requires port or portName" -}}
{{- end -}}
tcpSocket:
  port: {{ $port }}

{{- else if eq $probeKind "command" -}}
{{- $command := required "health.common.probe type command requires command" .command -}}
exec:
  command:
{{- if kindIs "slice" $command }}
{{ toYaml $command | nindent 4 }}
{{- else }}
    - /bin/sh
    - -c
    - {{ $command | quote }}
{{- end }}

{{- else -}}
{{- fail (printf "health.common.probe received unsupported type %q. Allowed values: http, https, tcp, command" $probeKind) -}}
{{- end }}
timeoutSeconds: {{ $timeoutSeconds }}
initialDelaySeconds: {{ $initialDelaySeconds }}
periodSeconds: {{ $periodSeconds }}
failureThreshold: {{ $failureThreshold }}
successThreshold: {{ $successThreshold }}
{{- end -}}

{{/*
  health.common.http/https/tcp/command — pin `type` for health.common.probe so callers don't repeat
  it. All other health.common.probe args (root, component, probeType, path/port/portName/command,
  timingScope, timingParent) pass through unchanged.
*/}}
{{- define "health.common.http" -}}
{{- include "health.common.probe" (merge (dict "type" "http") .) -}}
{{- end -}}

{{- define "health.common.https" -}}
{{- include "health.common.probe" (merge (dict "type" "https") .) -}}
{{- end -}}

{{- define "health.common.tcp" -}}
{{- include "health.common.probe" (merge (dict "type" "tcp") .) -}}
{{- end -}}

{{- define "health.common.command" -}}
{{- include "health.common.probe" (merge (dict "type" "command") .) -}}
{{- end -}}

{{/*
  Construct an image reference from a {registry, repository, tag} dict.
  Usage:
    {{ include "kasm.common.imageRef" (dict "registry" .registry "repository" .repository "tag" .tag) }}
*/}}
{{- define "kasm.common.imageRef" -}}
{{- printf "%s/%s:%s" .registry .repository .tag -}}
{{- end -}}

{{/*
  OTel Collector config fragments shared across the gateway, nginx-sidecar, and db-sidecar
  ConfigMaps (otel-*-configmap.yaml). Extracted so the shapes those three configs share can't
  drift independently; anything signal-specific (receivers, exporters that write to ClickHouse or
  do tail_sampling, etc.) stays inline in its own configmap template.
*/}}

{{/*
  health_check extension block, identical everywhere except the port.
  Usage: {{ include "kasm.common.otelHealthCheckExtension" (dict "port" 13133) | nindent 6 }}
*/}}
{{- define "kasm.common.otelHealthCheckExtension" -}}
health_check:
  endpoint: "0.0.0.0:{{ .port }}"
{{- end -}}

{{/*
  memory_limiter processor shape, identical everywhere except the two limits.
  Usage: {{ include "kasm.common.otelMemoryLimiter" (dict "limitMib" 256 "spikeLimitMib" 64) | nindent 6 }}
*/}}
{{- define "kasm.common.otelMemoryLimiter" -}}
memory_limiter:
  check_interval: 5s
  limit_mib: {{ .limitMib }}
  spike_limit_mib: {{ .spikeLimitMib }}
{{- end -}}

{{/*
  batch processor — identical in every OTel config in this chart, no exceptions.
  Usage: {{ include "kasm.common.otelBatchProcessor" . | nindent 6 }}
*/}}
{{- define "kasm.common.otelBatchProcessor" -}}
batch:
  send_batch_size: 5000
  timeout: 10s
{{- end -}}

{{/*
  resource processor stamping identity attributes onto every record a sidecar forwards. This is the
  Collector's own ${env:} config-expansion (already used above for OTEL_EXPORTER_OTLP_ENDPOINT/
  OTEL_BEARER_TOKEN), not the SDK's OTEL_RESOURCE_ATTRIBUTES env var — the Collector binary does not
  apply that to pipeline data, only to its own internal telemetry resource, so a resource processor
  is the only mechanism that actually reaches emitted rows.
  Args (dict):
    context = root context (.)
    zone    = (optional bool) true to also stamp kasm.zone from ${env:OTEL_KASM_ZONE}. Only the
              nginx sidecars run per-zone; omit for callers with no zone concept (the DB sidecar).
  Both env-backed values carry a `:-unknown` fallback: an attribute processor rejects an empty
  string as "unset" (0.156.0), and `make otel-validate` runs `otelcol validate` against this
  config with neither POD_NAME nor OTEL_KASM_ZONE in its environment. Real pods always set both.
  Usage:
    processors:
      {{- include "kasm.common.otelResourceProcessor" (dict "context" . "zone" true) | nindent 6 }}
*/}}
{{- define "kasm.common.otelResourceProcessor" -}}
{{- $ctx := .context -}}
resource:
  attributes:
    - key: k8s.pod.name
      value: "${env:POD_NAME:-unknown}"
      action: upsert
    - key: service.namespace
      value: {{ $ctx.Release.Namespace | quote }}
      action: upsert
    - key: deployment.environment
      value: kubernetes
      action: upsert
    {{- if .zone }}
    - key: kasm.zone
      value: "${env:OTEL_KASM_ZONE:-unknown}"
      action: upsert
    {{- end }}
{{- end -}}

{{/*
  otlp/gRPC exporter the nginx-sidecar and db-sidecar configs use to send everything straight to
  the gateway over OTEL_EXPORTER_OTLP_ENDPOINT, authenticated with OTEL_BEARER_TOKEN. Identical in
  both callers, including the queue sizing (these sidecars are low-volume compared to the gateway
  tier). In-cluster traffic only; not attempting mTLS between the sidecar and the gateway.
  Usage: {{ include "kasm.common.otelOtlpExporterToGateway" . | nindent 6 }}
*/}}
{{- define "kasm.common.otelOtlpExporterToGateway" -}}
otlp:
  endpoint: "${env:OTEL_EXPORTER_OTLP_ENDPOINT}"
  headers:
    Authorization: "Bearer ${env:OTEL_BEARER_TOKEN}"
  tls:
    insecure: true
  retry_on_failure:
    enabled: true
    initial_interval: 5s
    max_interval: 30s
    max_elapsed_time: 300s
  sending_queue:
    enabled: true
    num_consumers: 2
    queue_size: 500
{{- end -}}

{{/*
  Operator chain for the nginx JSON access log, ported (including overwrite_text: true) from
  kasm_backend/install/conf/otel/otel-collector-local.yaml. Used directly as the `operators:` list
  of the otel-sidecar's syslog/nginx_access receiver (otel-nginx-sidecar-configmap.yaml). nginx
  sends the JSON payload as the syslog message; the syslog receiver already lands it in
  attributes.message, so the chain's json_parser reads from there instead of body.
  Args (dict):
    context     = root context (.)
    serviceName = resource["service.name"]/attributes["application"] to stamp on every record
                  (e.g. "kasm-proxy", "kasm-connection-proxy")
  Usage:
    operators:
      {{- include "kasm.common.otelNginxAccessLogOperators" (dict "context" . "serviceName" "kasm-proxy") | nindent 8 }}
*/}}
{{- define "kasm.common.otelNginxAccessLogOperators" -}}
{{- $serviceName := .serviceName -}}
- type: json_parser
  parse_from: attributes.message
  timestamp:
    parse_from: attributes.time_iso8601
    layout: "%Y-%m-%dT%H:%M:%S%z"
- type: severity_parser
  parse_from: attributes.http_status
  overwrite_text: true
  mapping:
    error: "5xx"
    warn:  "4xx"
    info:  "2xx"
    debug: "3xx"
- type: add
  field: body
  value: EXPR(attributes["request"] + '" ' + attributes["http_status"] + ' ' + attributes["body_bytes_sent"] + ' "' + attributes["http_user_agent"] + '"')
- type: move
  from: attributes.request_method
  to:   attributes.http.request.method
- type: move
  from: attributes.uri
  to:   attributes.url.path
- type: move
  from: attributes.http_status
  to:   attributes.http.response.status_code
- type: add
  field: resource["service.name"]
  value: {{ $serviceName }}
- type: add
  field: attributes["application"]
  value: {{ $serviceName }}
{{- end -}}

{{/*
  Operator chain for the nginx error log, ported from
  kasm_backend/install/conf/otel/otel-collector-local.yaml. See kasm.common.otelNginxAccessLogOperators
  for the serviceName arg this define shares and why parse_from targets attributes.message: nginx's
  syslog error_log keeps its own "date [level] pid#tid: message" text as the syslog message body, so
  the regex still matches, just against attributes.message instead of the file line.
  Args (dict):
    context     = root context (.)
    serviceName = resource["service.name"] to stamp on every record (e.g. "kasm-proxy",
                  "kasm-connection-proxy")
  Usage:
    operators:
      {{- include "kasm.common.otelNginxErrorLogOperators" (dict "context" . "serviceName" "kasm-proxy") | nindent 8 }}
*/}}
{{- define "kasm.common.otelNginxErrorLogOperators" -}}
{{- $serviceName := .serviceName -}}
- type: regex_parser
  parse_from: attributes.message
  regex: '^(?P<timestamp>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(?P<level>\w+)\] (?P<pid>\d+)#\d+: (?:\*\d+ )?(?P<message>.+)$'
  timestamp:
    parse_from: attributes.timestamp
    layout: "%Y/%m/%d %H:%M:%S"
- type: severity_parser
  parse_from: attributes.level
  overwrite_text: true
  mapping:
    fatal:  crit
    error:  [error, alert, emerg]
    warn:   warn
    info:   notice
    debug:  [info, debug]
- type: add
  field: resource["service.name"]
  value: {{ $serviceName }}
{{- end -}}
