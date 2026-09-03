{{/*
  Helpers for the kasm-agent-operator chart.

  These deliberately do NOT reuse the `kasm.*` helpers from the kasm-helm chart: that chart's helpers
  are driven by a different values shape (components, zones, deployment sizes). The label vocabulary
  below is kept in step with it so both charts' objects are selectable the same way.
*/}}

{{/*
  The chart name, used for the `app.kubernetes.io/name` label and as the suffix of generated
  resource names. Honors `nameOverride`.
*/}}
{{- define "kasmAgentOperator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  The fully qualified name of the chart's generated resources (the operator Deployment).

  Precedence:
    1. `fullnameOverride` if set
    2. else the release name alone, when it already contains the chart name
    3. else "<release>-<chart name>"

  The RBAC objects this chart ships are NOT named through this helper: they keep the fixed names the
  operator's kustomize deployment uses, so a cluster converting from kustomize to Helm keeps working.
*/}}
{{- define "kasmAgentOperator.fullname" -}}
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
{{- end -}}

{{/*
  The `helm.sh/chart` label value: "<chart name>-<chart version>".
*/}}
{{- define "kasmAgentOperator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  The full label set applied to every object this chart renders.
*/}}
{{- define "kasmAgentOperator.labels" -}}
helm.sh/chart: {{ include "kasmAgentOperator.chart" . }}
{{ include "kasmAgentOperator.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: kasm-ai
{{- end -}}

{{/*
  The immutable subset of the labels used as the Deployment's selector. Keep this to name, instance,
  and component: everything else in the label set (chart version, app version) changes on upgrade, and
  a Deployment's selector is immutable.
*/}}
{{- define "kasmAgentOperator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kasmAgentOperator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: operator
{{- end -}}

{{/*
  The operator image reference, joined from `image.registry`, `image.repository`, and `image.tag`.
  An empty tag falls back to the chart's appVersion; an empty registry yields an unqualified
  "<repository>:<tag>" reference, which the container runtime resolves against its own default.
*/}}
{{- define "kasmAgentOperator.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.registry -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
  The OTLP endpoint the operator exports telemetry to. Defaults to the collector the `kasm-agent`
  umbrella chart deploys alongside this subchart in the release namespace.
*/}}
{{- define "kasmAgentOperator.otelEndpoint" -}}
{{- .Values.otel.endpoint | default (printf "http://%s-kasm-otel-collector:4318" .Release.Name) -}}
{{- end -}}
