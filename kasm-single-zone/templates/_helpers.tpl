{{/*
Additional labels to apply to all resources
*/}}
{{- define "kasm.defaultLabels" }}
release: {{ .Release.Name }}
kasm-version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: "{{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}"
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}

{{- end }}
