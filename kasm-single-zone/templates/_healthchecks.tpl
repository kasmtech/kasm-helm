{{- define "health.http" }}
httpGet:
  host: localhost
  path: {{ .path }}
  port: {{ .name }}-port
timeoutSeconds: 10
initialDelaySeconds: 10
periodSeconds: 30
failureThreshold: 3
successThreshold: 1
{{- end }}

{{- define "health.tcp" }}
tcpSocket:
  port: {{ .port }}
timeoutSeconds: 10
initialDelaySeconds: 30
periodSeconds: 30
failureThreshold: 3
successThreshold: 1
{{- end }}

{{- define "health.command" }}
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
{{- end }}
