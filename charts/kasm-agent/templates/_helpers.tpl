{{/*
  Name prefix shared by every resource this umbrella chart owns directly.

  The umbrella only owns the baseline NetworkPolicies and whatever is supplied through
  `extraObjects`; the subcharts name their own resources. Truncated to 63 characters so it stays a
  valid label value and a valid name prefix.

  Call with the root context: (include "kasmAgent.fullname" .)
*/}}
{{- define "kasmAgent.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Standard labels applied to resources this umbrella chart owns directly.

  Deliberately does NOT include `app.kubernetes.io/component` — the baseline NetworkPolicies apply
  to the whole namespace rather than to one component. Subchart resources carry their own labels
  from their own helpers and are not affected by this one.

  Call with the root context: (include "kasmAgent.labels" .)
*/}}
{{- define "kasmAgent.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasm-ai
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}
