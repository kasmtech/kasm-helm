{{/*
Pod hardening/security settings
*/}}
{{- define "kasm.podSecurity" }}
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  fsGroupChangePolicy: Always
{{- end }}

{{/*
Container hardening/security settings
*/}}
{{- define "kasm.containerSecurity" }}
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
{{- end }}
