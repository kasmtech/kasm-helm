{{- define "kasm.podSecurity" }}
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
{{- end }}

{{- define "kasm.containerSecurity" }}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
{{- end }}
