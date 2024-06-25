{{- /*
Generate Kasm passwords if not added by the user
*/}}
{{- define "kasm.passwordValues" }}
{{- $namespace := .Values.namespace | default .Release.Namespace | quote }}
{{- $secretName := (printf "%s%s" .Values.kasmApp.name "-secrets") | quote }}
{{- range $key, $value := .Values.kasmPasswords }}
{{- $secretsObj := (lookup "v1" "Secret" $namespace $secretName) | default dict }}
{{- $secretsData := (get $secretsObj "data") | default dict }}
{{- $valueSecret := (get $secretsData $key) | default (randAlphaNum 26 | b64enc) ($value | b64enc) }}
{{ $key }}: {{ $valueSecret | quote }}
{{- end }}
{{- end }}

{{/*
Generate certificates for Kasm Proxy service
*/}}
{{- define "kasm.gen-proxy-certs" }}
{{- $altNames := list ( printf "%s.%s" .Values.host .Release.Namespace ) ( printf "%s.%s.svc" (include "kasm.name" .) .Release.Namespace ) }}
{{- $ca := genCA "kasm-ca" 365 -}}
{{- $cert := genSignedCert .Values.host nil $altNames 365 $ca }}
certfile.crt: {{ $cert.Cert | b64enc }}
keyfile.key: {{ $cert.Key | b64enc }}
{{- end }}

{{/*
Generate certificates for Kasm RDP Gateway service
*/}}
{{- define "kasm.gen-rdp-gateway-certs" }}
{{- $altNames := list ( printf "%s.%s" .Values.host .Release.Namespace ) ( printf "%s.%s.svc" (include "kasm.name" .) .Release.Namespace ) }}
{{- $ca := genCA "kasm-ca" 365 -}}
{{- $cert := genSignedCert .Values.host nil $altNames 365 $ca }}
rdpproxy.crt: {{ $cert.Cert | b64enc }}
rdpproxy.key: {{ $cert.Key | b64enc }}
{{- end }}


{{/*
Additional labels to apply to all resources
*/}}
{{- define "kasm.defaultLabels" }}
app: {{ .Values.kasmApp.name | default "kasm" }}
release: {{ .Release.Name }}
kasm-version: {{ .Chart.AppVersion }}
"app.kubernetes.io/name": {{ .Values.kasmApp.name | default "kasm" }}
"helm.sh/chart": {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
"app.kubernetes.io/managed-by": {{ .Release.Service }}
"app.kubernetes.io/instance": {{ .Release.Name }}
app.kubernetes.io/version": {{ .Chart.AppVersion }}
{{- end }}
