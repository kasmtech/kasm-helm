{{- define "kasm.apiWaitContainer" }}
- name: api-is-ready
  image: alpine/curl:8.8.0
  imagePullPolicy: IfNotPresent
  command:
  - /bin/sh
  - -ec
  args:
  - |
      while ! curl http://kasm-api:8080/api/__healthcheck 2>/dev/null | grep -q true; do echo "Waiting for the API server to start..."; sleep 5; done
{{- end }}