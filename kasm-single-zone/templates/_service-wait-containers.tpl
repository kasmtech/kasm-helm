{{/*
Init container used to wait for upstream services before attempting to start the primary pod container
Example:
  {{ include "kasm.initContainer" (dict "serviceName" "kasm-service-name" "servicePort" "kasm-service-port" "path" "healthcheck-path" "schema" "http") }}
*/}}
{{- define "kasm.initContainer" }}
  {{- if and (hasKey . "serviceName") (hasKey . "servicePort") ( hasKey . "path" ) (hasKey . "schema")}}
- name: {{ .serviceName }}-is-ready
  image: alpine/curl:8.8.0
  imagePullPolicy: IfNotPresent
  command:
  - /bin/sh
  - -ec
  args:
  - |
    while ! curl "{{- .schema -}}://{{- .serviceName -}}:{{- .servicePort -}}{{- .path -}}" 2>/dev/null; do echo "Waiting for the {{- .serviceName -}} server to start..."; sleep 5; done
    echo "{{- .serviceName -}} up. Connecting!"
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "serviceName, servicePort, path" | fail}}
  {{- end }}
{{- end }}
