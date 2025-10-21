{{/*
Constants to use across chart template files
*/}}
{{- define "kasm.constants" }}
api:
  component: api
  svc: kasm-api
  portName: api-pt
  name: {{ printf "%s-api" .Release.Name }}
  image: {{ printf "%s:%s" .Values.components.api.image.repository .Values.components.api.image.tag }}
  port: 8080
manager:
  component: manager
  svc: kasm-manager
  portName: manager-pt
  name: {{ printf "%s-manager" .Release.Name }}
  image: {{ printf "%s:%s" .Values.components.manager.image.repository .Values.components.manager.image.tag }}
  port: 8181
proxy:
  component: proxy
  svc: kasm-proxy
  portName: proxy-pt
  name: {{ printf "%s-proxy" .Release.Name }}
  image: {{ printf "%s:%s" .Values.components.proxy.image.repository .Values.components.proxy.image.tag }}
  http: 8080
  https: 8443
  extHttps: 443
db:
  component: db
  svc: {{ .Values.database.hostname }}
  portName: db-pt
  name: {{ printf "%s-db" .Release.Name }}
  image: {{ printf "%s:%s" .Values.database.image.repository .Values.database.image.tag }}
  port: {{ .Values.database.port }}
guac:
  component: guac
  svc: kasm-guac
  portName: guac-pt
  name: {{ printf "%s-guac" .Release.Name }}
  image: {{ printf "%s:%s" .Values.components.guac.image.repository .Values.components.guac.image.tag }}
  port: 3000
  ports:
    - 3001
    - 3002
    - 3003
    - 3004
rdpGateway:
  component: rdp-gateway
  svc: kasm-rdp-gateway
  portName: rdp-gw-pt
  name: {{ printf "%s-rdp-gw" .Release.Name }}
  image: {{ printf "%s:%s" .Values.components.rdpGateway.image.repository .Values.components.rdpGateway.image.tag }}
  port: 5555
rdpHttpsGateway:
  component: rdp-https-gateway
  svc: kasm-rdp-https-gateway
  portName: rdp-https-gw-pt
  name: {{ printf "%s-rdp-https-gw" .Release.Name }}
  image: {{ printf "%s:%s" .Values.components.rdpHttpsGateway.image.repository .Values.components.rdpHttpsGateway.image.tag }}
  port: 9443
{{- end }}

{{/*
Database Environment variables
*/}}
{{- define "kasm.dbEnvVars" }}

{{- end }}

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
Pod security configurations for DB and DB init containers
*/}}
{{- define "db.podSecurity" }}
securityContext:
  runAsUser: 70
  runAsGroup: 70
  fsGroup: 70
  fsGroupChangePolicy: Always
{{- end }}

{{- define "db.containerSecurity" }}
securityContext:
  runAsUser: 70
  runAsGroup: 70
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
Init container used to wait for upstream services before attempting to start the primary pod container
Example:
  {{ include "kasm.initContainer" (dict "serviceName" "kasm-service-name" "servicePort" "kasm-service-port" "path" "healthcheck-path" "schema" "http" "image" "alpine/curl") }}
*/}}
{{- define "kasm.initContainer" }}
  {{- if and (hasKey . "serviceName") (hasKey . "servicePort") ( hasKey . "path" ) (hasKey . "schema") (hasKey . "image") }}
- name: {{ .serviceName }}-is-ready
  image: {{ .image }}
  imagePullPolicy: IfNotPresent
  resources:
    requests:
      cpu: 100m
      memory: 32Mi
    limits:
      cpu: 200m
      memory: 128Mi
  command:
  - /bin/sh
  - -ec
  args:
  - |
    while ! curl "{{- .schema -}}://{{- .serviceName -}}:{{- .servicePort -}}{{- .path -}}" 2>/dev/null; do echo "Waiting for the {{ .serviceName }} server to start..."; sleep 5; done
    echo "{{- .serviceName }} up. Connecting!"
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "serviceName, servicePort, path, schema, and image" | fail }}
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
      "medium" 2
      "large" 4
    )
    "db" (dict
      "small" 1
      "medium" 1
      "large" 1
    )
    "api" (dict
      "small" 1
      "medium" 2
      "large" 3
    )
    "manager" (dict
      "small" 1
      "medium" 2
      "large" 3
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
    "rdp-gateway" (dict
      "small" 1
      "medium" 2
      "large" 3
    )
    "rdp-https-gateway" (dict
      "small" 1
      "medium" 2
      "large" 3
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
        "limits" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "2000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "rdp-gateway" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "rdp-https-gateway" (dict
      "small" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "150m" "memory" "64Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
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
