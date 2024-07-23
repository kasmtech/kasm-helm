{{/*
Service template to use for Kasm services used to generate service definitions
Example:
  {{ include "kasm.serviceTemplate" (list . "service-name" "kasm-role-name" (list <port1> <port2> <etc>) ) }}
*/}}
{{- define "kasm.serviceTemplate" }}
{{- $values := index . 0 -}}
{{- $serviceName := index . 1 -}}
{{- $roleName := index . 2 -}}
{{- $servicePorts := index . 3 -}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $serviceName }}
  namespace: {{ $values.Values.namespace | default $values.Release.Namespace }}
  labels:
    app.kubernetes.io/name: {{ $roleName }}-svc
    {{- include "kasm.defaultLabels" $values | indent 4 }}
spec:
  selector:
    app.kubernetes.io/name: {{ $roleName }}
  ports:
  {{- range $servicePorts }}
    - name: "{{ $serviceName }}-{{ . }}"
      protocol: TCP
      port: {{ . }}
  {{- end }}
{{- end }}