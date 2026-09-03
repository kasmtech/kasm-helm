{{/*
  Chart name, for the resources this umbrella chart owns directly.

  Neither dependency is aliased, so Helm never rewrites `.Chart.Name` here and this is always
  "kasm-platform". Truncated to 63 characters so it stays a valid label value.

  Call with the root context: (include "kasmPlatform.name" .)
*/}}
{{- define "kasmPlatform.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Name prefix shared by every resource this umbrella chart owns directly.

  That is the auth-domain hook Job and whatever is supplied through `extraObjects`; both
  dependencies name their own resources. Truncated to 63 characters so it stays a valid name
  prefix — callers that append a suffix must truncate again.

  Call with the root context: (include "kasmPlatform.fullname" .)
*/}}
{{- define "kasmPlatform.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "kasmPlatform.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Standard labels applied to resources this umbrella chart owns directly.

  Mirrors the `kasmAgent.labels` helper so both umbrellas stamp the same shape, and deliberately
  omits `app.kubernetes.io/component` — callers add it when the resource has one. Subchart resources
  carry their own labels from their own helpers and are unaffected by this.

  Call with the root context: (include "kasmPlatform.labels" .)
*/}}
{{- define "kasmPlatform.labels" -}}
app.kubernetes.io/name: {{ include "kasmPlatform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasm-ai
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}
