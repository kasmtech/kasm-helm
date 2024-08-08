{{/*
HTTP Healthcheck template
Example usage:
  {{- include "health.http" (dict "path" "healthcheck-path" "portName" "service-port-name") }}
*/}}
{{- define "health.http" }}
  {{- if and (hasKey . "path") (hasKey . "portName") }}
httpGet:
  path: {{ .path }}
  port: {{ .portName }}
timeoutSeconds: 10
initialDelaySeconds: 10
periodSeconds: 30
failureThreshold: 3
successThreshold: 1
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "path, portName" | fail}}
  {{- end }}
{{- end }}

{{/*
HTTPS Healthcheck template
Example usage:
  {{- include "health.https" (dict "path" "healthcheck-path" "portName" "service-port-name") }}
*/}}
{{- define "health.https" }}
  {{- if and (hasKey . "path") (hasKey . "portName") }}
httpGet:
  path: {{ .path }}
  port: {{ .portName }}
  scheme: HTTPS
timeoutSeconds: 10
initialDelaySeconds: 10
periodSeconds: 30
failureThreshold: 3
successThreshold: 1
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "path, portName" | fail}}
  {{- end }}
{{- end }}

{{/*
TCP Healthcheck template
Example usage:
  {{- include "health.tcp" (dict "portName" "service-port-name") }}
*/}}
{{- define "health.tcp" }}
  {{- if hasKey . "portName" }}
tcpSocket:
  port: {{ .portName }}
timeoutSeconds: 10
initialDelaySeconds: 30
periodSeconds: 30
failureThreshold: 3
successThreshold: 1
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "portName" | fail}}
  {{- end }}
{{- end }}

{{/*
Command-based Healthcheck template
Example usage:
  {{- include "health.command" (dict "command" "healthcheck-command") }}
*/}}
{{- define "health.command" }}
  {{- if hasKey . "command" }}
exec:
  command:
    - /bin/sh
    - -c
    - {{ .command }}
timeoutSeconds: 10
initialDelaySeconds: 20
periodSeconds: 30
failureThreshold: 3
successThreshold: 1
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "command" | fail}}
  {{- end }}
{{- end }}
