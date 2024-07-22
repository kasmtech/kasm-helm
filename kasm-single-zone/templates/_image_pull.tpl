{{- define "image.pullSecrets" }}
imagePullSecrets:
  - name: {{ .Values.global.image.pullSecrets }}
{{- end }}