{{/*
Add image pull block to deployment if Docker credentials required
*/}}
{{- define "image.pullSecrets" }}
imagePullSecrets:
  - name: {{ .Values.global.image.pullSecrets }}
{{- end }}