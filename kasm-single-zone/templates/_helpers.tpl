{{/*
Additional labels to apply to all resources
*/}}
{{- define "kasm.defaultLabels" }}
kasm-version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: "{{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}"
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: "kasm"

{{- end }}

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

{{/*
Add image pull block to deployment if Docker credentials required
*/}}
{{- define "image.pullSecrets" }}
imagePullSecrets:
  - name: {{ .Values.global.image.pullSecrets }}
{{- end }}

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

{{/*
Return a replica object based on given presets
Example usage:
{{ include "replicas.preset" (dict "node" "proxy" "size" "small") -}}
*/}}
{{- define "replicas.preset" }}
  {{- $presetSizes := dict
    "proxy" (dict
      "small" 1
      "medium" 4
      "large" 8
    )
    "db" (dict
      "small" 1
      "medium" 1
      "large" 1
    )
    "api" (dict
      "small" 1
      "medium" 4
      "large" 8
    )
    "manager" (dict
      "small" 1
      "medium" 4
      "large" 8
    )
    "guac" (dict
      "small" 1
      "medium" 2
      "large" 3
    )
    "rdp" (dict
      "small" 1
      "medium" 2
      "large" 3
    )
    "share" (dict
      "small" 1
      "medium" 2
      "large" 3
    )
    "redis" (dict
      "small" 1
      "medium" 1
      "large" 1
    )
  }}
  {{- if hasKey $presetSizes .node }}
    {{- if hasKey (get $presetSizes .node) .size }}
      {{- dig .node .size "" $presetSizes | toYaml -}}
    {{- else }}
      {{- printf "ERROR: Preset key '%s' invalid. Allowed values are %s" .size (join "," (keys (get $presetSizes .node))) | fail }}
    {{- end }}
  {{- else }}
    {{- printf "ERROR: Preset key '%s' invalid. Allowed values are %s" .node (join "," (keys $presetSizes)) | fail }}
  {{- end }}
{{- end }}

{{/*
Return a resource request/limit object based on given presets
Example usage:
{{- include "resources.preset" (dict "node" "proxy" "size" "small") -}}
*/}}
{{- define "resources.preset" }}
  {{- $presetSizes := dict
    "proxy" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "proxy-processes" (dict "small" 2 "medium" 6 "large" 12)
    "db" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "128Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "750m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "512m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1.5" "memory" "2048Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "512m" "memory" "2048Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "4.0" "memory" "8192Mi" "ephemeral-storage" "2Gi")
      )
    )
    "api" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "manager" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "guac" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "rdp" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "share" (dict
      "small" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "redis" (dict
      "small" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "100m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
  }}
  {{- if hasKey $presetSizes .node }}
    {{- if hasKey (get $presetSizes .node) .size }}
      {{- dig .node .size "" $presetSizes | toYaml -}}
    {{- else }}
      {{- printf "ERROR: Preset key '%s' invalid. Allowed values are %s" .size (join "," (keys (get $presetSizes .node))) | fail }}
    {{- end }}
  {{- else }}
    {{- printf "ERROR: Preset key '%s' invalid. Allowed values are %s" .node (join "," (keys $presetSizes)) | fail }}
  {{- end }}
{{- end }}
