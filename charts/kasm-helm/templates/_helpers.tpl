{{/*
  Constants to use across chart template files
*/}}
{{- define "kasm.constants" }}
api:
  component: api
  svc: {{ printf "%s-api" .Release.Name }}
  portName: api-pt
  image: {{ printf "%s/%s:%s" .Values.components.api.image.registry .Values.components.api.image.repository .Values.components.api.image.tag }}
  port: 8080
manager:
  component: manager
  svc: {{ printf "%s-manager" .Release.Name }}
  portName: manager-pt
  image: {{ printf "%s/%s:%s" .Values.components.manager.image.registry .Values.components.manager.image.repository .Values.components.manager.image.tag }}
  port: 8181
proxy:
  component: proxy
  svc: {{ printf "%s-proxy" .Release.Name }}
  portName: proxy-pt
  image: {{ printf "%s/%s:%s" .Values.components.proxy.image.registry .Values.components.proxy.image.repository .Values.components.proxy.image.tag }}
  http: 8080
  https: 8443
  extHttps: 443
db:
  component: db
  svc: {{ if .Values.database.standalone }}{{- .Values.database.hostname }}{{ else }}{{- printf "%s-db" .Release.Name }}{{ end }}
  portName: db-pt
  image: {{ printf "%s/%s:%s" .Values.database.image.registry .Values.database.image.repository .Values.database.image.tag }}
  port: {{ .Values.database.port }}
guac:
  component: guac
  svc: {{ if .Values.kasmZones }}{{ printf "%s-guac-%s" .Release.Name (include "kasm.zoneName" (index .Values.kasmZones 0).name) }}{{ else }}{{ printf "%s-guac-default" .Release.Name }}{{ end }}
  portName: guac-pt
  name: {{ if .Values.kasmZones }}{{ printf "%s-guac-%s" .Release.Name (include "kasm.zoneName" (index .Values.kasmZones 0).name) }}{{ else }}{{ printf "%s-guac-default" .Release.Name }}{{ end }}
  image: {{ printf "%s/%s:%s" .Values.components.guac.image.registry .Values.components.guac.image.repository .Values.components.guac.image.tag }}
  port: 3000
  ports:
    - 3001
    - 3002
    - 3003
    - 3004
rdpGateway:
  component: rdp-gateway
  svc: {{ if .Values.kasmZones }}{{ printf "%s-rdp-gateway-%s" .Release.Name (include "kasm.zoneName" (index .Values.kasmZones 0).name) }}{{ else }}{{ printf "%s-rdp-gateway-default" .Release.Name }}{{ end }}
  portName: rdp-gw-pt
  image: {{ printf "%s/%s:%s" .Values.components.rdpGateway.image.registry .Values.components.rdpGateway.image.repository .Values.components.rdpGateway.image.tag }}
  port: 5555
rdpHttpsGateway:
  component: rdp-https-gateway
  svc: {{ if .Values.kasmZones }}{{ printf "%s-rdp-https-gateway-%s" .Release.Name (include "kasm.zoneName" (index .Values.kasmZones 0).name) }}{{ else }}{{ printf "%s-rdp-https-gateway-default" .Release.Name }}{{ end }}
  portName: rdp-https-gw-pt
  image: {{ printf "%s/%s:%s" .Values.components.rdpHttpsGateway.image.registry .Values.components.rdpHttpsGateway.image.repository .Values.components.rdpHttpsGateway.image.tag }}
  port: 9443
{{- end }}

{{/*
  Normalize a zone name to a DNS-safe label component.
  Mirrors the normalization used by `kasm.name` so hostnames built inline
  (proxy upstreams, init containers, env vars) match the actual Service names.
*/}}
{{- define "kasm.zoneName" -}}
{{- regexReplaceAll "[^a-zA-Z0-9]+" . "-" | lower -}}
{{- end -}}

{{/*
  Pre-upgrade DB backup PVC name. Embeds Chart.AppVersion with dots replaced
  so the resulting name is safe for DNS-1035 contexts and matches the
  normalization used for the DB StatefulSet name.
*/}}
{{- define "kasm.dbUpgradeBackupPvcName" -}}
{{- printf "%s-%s-db-pre-upgrade-backup" .Release.Name (.Chart.AppVersion | replace "." "-") | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Full resource name
*/}}
{{- define "kasm.name" -}}
{{- $context := index . 0 -}}
{{- $component := kebabcase (index . 1) -}}

{{- $resource := "" -}}
{{- if ge (len .) 3 -}}
  {{- $resource = index . 2 -}}
{{- end -}}

{{- $zone := "" -}}
{{- if ge (len .) 4 -}}
  {{- $zone = index . 3 -}}
{{- end -}}

{{- $extra := "" -}}
{{- if ge (len .) 5 -}}
  {{- $extra = index . 4 -}}
{{- end -}}

{{- if $extra -}}
  {{- printf "%s-%s-%s-%s" $context.Release.Name $component (include "kasm.zoneName" $zone) $extra -}}
{{- else if $zone -}}
  {{- printf "%s-%s-%s" $context.Release.Name $component (include "kasm.zoneName" $zone) -}}
{{- else -}}
  {{- printf "%s-%s" $context.Release.Name $component -}}
{{- end -}}
{{- end -}}

{{/*
  Metadata block for resources
  Usage:
    {{- include "kasm.metadata" (dict "context" . "component" "api" "resource" "deployment") | nindent 2 }}
Where:
  .context   = root context (.)
  .component = component name (e.g. "api", "proxy", "db", etc)
  .resource  = resource type (e.g. "deployment", "service", "pod", etc)
  .zone      = (optional) zone name for Kasm zone-scoped resources
  .include   = (optional) if set to "la", includes only labels and annotations; otherwise emits all
  .name      = (optional) overrides name generation
*/}}
{{- define "kasm.metadata" -}}
{{- $ctx := .context -}}
{{- $component := .component -}}
{{- $resource := .resource -}}
{{- $zone := .zone | default "" -}}
{{- $include := .include | default "" -}}
{{- $nameOrig := .name | default "" -}}

{{/* Name Resolution */}}
{{- $constants := include "kasm.constants" $ctx | fromYaml -}}

{{- $labelName := "" -}}
{{- if $zone -}}
  {{- $labelName = include "kasm.name" (list $ctx $component "" $zone) -}}
{{- else -}}
  {{- $labelName = include "kasm.name" (list $ctx $component) -}}
{{- end -}}

{{- $name := "" -}}
{{- if $nameOrig -}}
  {{- $name = $nameOrig -}}
{{- else if and (eq $component "db") (eq $resource "statefulSet") -}}
  {{- $name = printf "%s-db-%s" $ctx.Release.Name ($ctx.Chart.AppVersion | replace "." "-") | trunc 63 | trimSuffix "-" -}}
{{- else if and (eq $component "pre-upgrade-backup") (eq $resource "pvc") -}}
  {{- $name = include "kasm.dbUpgradeBackupPvcName" $ctx -}}
{{- else if $zone -}}
  {{- $name = include "kasm.name" (list $ctx $component "" $zone) -}}
{{- else -}}
  {{- $name = include "kasm.name" (list $ctx $component) -}}
{{- end -}}

{{/* Labels */}}
{{- $labels := dict -}}

{{- with $ctx.Values.labels -}}
  {{- $labels = merge $labels . -}}
{{- end -}}

{{- with (get $ctx.Values.components .component) -}}
  {{- with .labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if $resource -}}
  {{- with (get $ctx.Values.extraLabels $resource) -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if and (eq $component "rdpGateway") (eq $resource "service") -}}
  {{- with $ctx.Values.directRdpService.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $resource "ingress" -}}
  {{- with $ctx.Values.ingress.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $resource "route" -}}
  {{- with $ctx.Values.route.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "cert-manager" -}}
  {{- with $ctx.Values.certificate.certManager.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "db" -}}
  {{- with $ctx.Values.database.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "image-pull" -}}
  {{- with $ctx.Values.imagePullSecrets.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- if and (or (eq $component "proxy") (eq $component "proxy-ext")) (eq $resource "service") -}}
  {{- with $ctx.Values.proxyService.labels -}}
    {{- $labels = merge $labels . -}}
  {{- end -}}
{{- end -}}

{{- $labels = merge $labels (dict
  "kasm.com/version" $ctx.Chart.AppVersion
  "app.kubernetes.io/name" $labelName
  "app.kubernetes.io/component" (kebabcase $component)
  "app.kubernetes.io/instance" $ctx.Release.Name
  "app.kubernetes.io/version" $ctx.Chart.AppVersion
  "app.kubernetes.io/managed-by" "Helm"
  "helm.sh/chart" (printf "%s-%s" $ctx.Chart.Name $ctx.Chart.Version)
  "app.kubernetes.io/part-of" "kasm"
) -}}


{{/* Annotations */}}
{{- $annotations := dict -}}

{{- with $ctx.Values.annotations -}}
  {{- $annotations = merge $annotations . -}}
{{- end -}}

{{- if eq $resource "ingress" -}}
  {{- with $ctx.Values.ingress.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- with (get $ctx.Values.components .component) -}}
  {{- with .annotations }}
    {{- $annotations = merge $annotations . -}}
  {{- end }}
{{- end }}

{{- if .resource -}}
  {{- with (get $ctx.Values.extraAnnotations .resource) -}}
    {{- $annotations = merge $annotations . -}}
  {{- end }}
{{- end -}}

{{- if and (eq $component "rdpGateway") (eq $resource "service") -}}
  {{- with $ctx.Values.directRdpService.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if and (or (eq $component "proxy") (eq $component "proxy-ext")) (eq $resource "service") -}}
  {{- with $ctx.Values.proxyService.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $resource "route" -}}
  {{- with $ctx.Values.route.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "cert-manager" -}}
  {{- with $ctx.Values.certificate.certManager.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "db" -}}
  {{- with $ctx.Values.database.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{- if eq $component "image-pull" -}}
  {{- with $ctx.Values.imagePullSecrets.annotations -}}
    {{- $annotations = merge $annotations . -}}
  {{- end -}}
{{- end -}}

{{/* Special Cases */}}

{{- if and $ctx.Values.applyHealthChecks (has .resource (list "deployment" "pod" "statefulSet" "daemonset" "job" "cronJob" "cronPod")) -}}
  {{- $annotations = merge $annotations (dict "kasm.com/healthcheck" "true") -}}
{{- end -}}

{{- if and $ctx.Values.applySecurity (has .resource (list "deployment" "pod" "statefulSet" "daemonset" "job" "cronJob" "cronPod")) -}}
  {{- $annotations = merge $annotations (dict "kasm.com/security" "true") -}}
{{- end -}}

{{- if and (eq .component "db-backup") (eq .resource "pvc") -}}
  {{- $annotations = merge $annotations (dict
  "helm.sh/resource-policy" "keep"
  "helm.sh/hook-weight" "100"
  ) -}}
{{- end -}}

{{- if (or (eq $component "secrets") (eq $component "image-pull")) -}}
  {{- $annotations = merge $annotations (dict
      "helm.sh/hook" "pre-install,pre-upgrade"
    ) -}}
{{- end -}}

{{- if (and (eq $component "pre-upgrade-backup") (eq $resource "pvc")) -}}
  {{- $annotations = merge $annotations (dict
      "helm.sh/resource-policy" "keep"
      "helm.sh/hook-weight" "-10"
      "helm.sh/hook" "pre-upgrade,pre-install"
    ) -}}
{{- end -}}

{{- if (and (eq $component "pre-upgrade-backup") (eq $resource "job")) -}}
  {{- $annotations = merge $annotations (dict
      "helm.sh/hook-weight" "10"
      "helm.sh/hook" "pre-upgrade,pre-install"
    ) -}}
{{- end -}}

{{/* Output Metadata Block */}}

{{- if eq .include "all" }}
name: {{ $name }}
namespace: {{ $ctx.Release.Namespace }}
{{- end }}
{{- if or (eq .include "all") (eq .include "la") }}
labels:
{{- toYaml $labels | nindent 2 }}
{{- with $annotations }}
annotations:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- if eq .include "match" }}
app.kubernetes.io/name: {{ $labelName }}
app.kubernetes.io/component: {{ (kebabcase $component) }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
{{- end }}
{{- end -}}

{{/*
Pod hardening/security settings
Usage:
  {{ include "kasm.securityContext" (list . 1000 pod) | nindent 6 }}
Where:
  index 1 = runAsUser/runAsGroup integer
  index 2 = context ("pod" or "container")
*/}}
{{- define "kasm.securityContext" -}}
{{- $rootContext := index . 0 -}}
{{- $runAs := index . 1 -}}
{{- $context := index . 2 -}}
{{- $ro := true -}}
{{- if ge (len .) 4 -}}
  {{- $opts := index . 3 -}}
  {{- if and $opts (hasKey $opts "readOnlyRootFilesystem") -}}
    {{- $ro = get $opts "readOnlyRootFilesystem" -}}
  {{- end -}}
{{- end -}}

{{- if $rootContext.Values.applySecurity -}}
securityContext:
  {{- if eq $context "pod" }}
    {{- if not $rootContext.Values.isOpenshift }}
  runAsUser: {{ $runAs }}
  runAsGroup: {{ $runAs }}
  fsGroup: {{ $runAs }}
    {{- end }}
  fsGroupChangePolicy: OnRootMismatch
  {{- else if eq $context "container" -}}
    {{- if not $rootContext.Values.isOpenshift }}
  runAsUser: {{ $runAs }}
  runAsGroup: {{ $runAs }}
    {{- end }}
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: {{ $ro }}
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
  {{- else -}}
    {{- printf "ERROR: Invalid context value '%s'. Allowed values are %s" $context "pod, container" | fail }}
  {{- end -}}
{{- end -}}
{{- end -}}

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
timeoutSeconds: 5
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
timeoutSeconds: 5
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
timeoutSeconds: 5
initialDelaySeconds: 10
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
timeoutSeconds: 5
initialDelaySeconds: 10
periodSeconds: 30
failureThreshold: 3
successThreshold: 1
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "command" | fail}}
  {{- end }}
{{- end }}

{{/*
  Init container used to wait for upstream services before attempting to start the primary pod container
  Example:
    {{ include "kasm.initContainer" (dict "serviceName" "kasm-service-name" "servicePort" "kasm-service-port" "path" "healthcheck-path" "schema" "http" "image" "alpine/curl") }}
*/}}
{{- define "kasm.initContainer" }}
  {{- if and (hasKey . "context") (hasKey . "serviceName") (hasKey . "servicePort") ( hasKey . "path" ) (hasKey . "schema") (hasKey . "image") (hasKey . "component")}}
  {{- $context := .context -}}
  {{- $service := .serviceName -}}
  {{- $port := .servicePort -}}
  {{- $path := .path -}}
  {{- $schema := .schema -}}
  {{- $image := .image -}}
  {{- $component := .component -}}
  {{- $merged := fromYaml (include "kasm.mergedValues" (dict "root" $context "componentName"  $component)) -}}

- name: {{ include "kasm.name" (list $context $service "is-ready")}}
  image: {{ $image }}
  imagePullPolicy: {{ $context.Values.imagePullPolicy }}
  {{- include "kasm.securityContext" (list $context 1000 "container") | nindent 2 }}
  resources:
    requests:
      cpu: 200m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 128Mi
  command:
  - /bin/sh
  - -ec
  args:
  - |
    while ! curl "{{- $schema -}}://{{- $service -}}:{{- $port -}}{{- $path -}}" 2>/dev/null; do echo "Waiting for the {{ $service }} server to start..."; sleep 5; done
    echo "{{- $service }} up. Connecting!"
  {{- if or $context.Values.trustedCaBundle.enabled $merged.initMounts }}
  volumeMounts:
    {{- if $context.Values.trustedCaBundle.enabled }}
    - name: usr-local-share
      mountPath: /usr/local/share/ca-certificates
      readOnly: true
    - name: etc-ssl-certs
      mountPath: /etc/ssl/certs
    {{- end }}
    {{- with $merged.initMounts }}
      {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- else }}
    {{- printf "ERROR: Invalid or non-existent key. Allowed values are %s" "context, serviceName, servicePort, path, schema, image, and component" | fail }}
  {{- end }}
{{- end }}

{{/*
  DB readiness check container to prevent services from starting prematurely
  Example usage:
    {{ include "kasm.dbIsReady" (dict "context" . "function" "init") }}
*/}}
{{- define "kasm.dbIsReady" -}}
{{- $context := .context -}}
{{- $function := default "ready" .function -}}

{{- $allowedFunctions := list "init" "version" "backup" "ready" -}}
{{- if not (has $function $allowedFunctions) -}}
  {{- printf
      "ERROR: Unknown dbIsReady function '%s'. Allowed values are %s"
      $function
      (join ", " $allowedFunctions)
    | fail
  -}}
{{- end -}}

{{- $isInit := eq $function "init" -}}
{{- $isVersion := eq $function "version" -}}
{{- $isBackup := eq $function "backup" -}}
{{- $isReady := eq $function "ready" -}}

{{- $constants := include "kasm.constants" $context | fromYaml -}}

{{- $merged := dict -}}
{{- if or $isInit $isVersion $isReady -}}
  {{- $merged = fromYaml (include "kasm.mergedValues" (dict "root" $context "componentName" "api")) -}}
{{- end -}}

{{- $containerName := "db-is-ready" -}}
{{- if $isBackup -}}
  {{- $containerName = "db-is-ready-for-backup" -}}
{{- else if $isVersion -}}
  {{- $containerName = "db-major-version-is-ready" -}}
{{- end -}}

{{- $postgresHost := $constants.db.svc -}}
{{- if $isBackup -}}
  {{- $dbOldHost := "kasm-db" -}}
  {{- if and $context.Values.database.standalone $context.Values.database.hostname -}}
    {{- $dbOldHost = $context.Values.database.hostname -}}
  {{- else if $context.Values.dbManagement.upgrade.oldDbHostname -}}
    {{- $dbOldHost = $context.Values.dbManagement.upgrade.oldDbHostname -}}
  {{- end -}}
  {{- $postgresHost = $dbOldHost -}}
{{- end -}}

{{- $needsDbCredentials := or $isReady $isVersion -}}
{{- $needsResources := or $isReady $isVersion -}}
{{- $needsTmpDir := or $isInit $isReady $isBackup $isVersion -}}
{{- $hasTrustedCaBundle := and (not $isBackup) $context.Values.trustedCaBundle.enabled -}}
{{- $initMounts := get $merged "initMounts" -}}
{{- $hasInitMounts := and (not $isBackup) $initMounts -}}
{{- $needsVolumeMounts := or $needsTmpDir $hasTrustedCaBundle $hasInitMounts -}}

- name: {{ $containerName }}
  image: {{ $constants.api.image }}
  imagePullPolicy: {{ $context.Values.imagePullPolicy }}
  {{- if $needsResources }}
  resources: {{- include "resources.preset" (dict "node" "api" "size" "small" "context" $context.Values) | nindent 4 }}
  {{- end }}
  {{- include "kasm.securityContext" (list $context 1000 "container") | nindent 2 }}
  env:
    - name: POSTGRES_HOST
      value: {{ $postgresHost | quote }}
    - name: POSTGRES_PORT
      value: {{ $constants.db.port | quote }}
    {{- if $needsDbCredentials }}
    - name: POSTGRES_DB
      value: {{ $context.Values.database.kasmDbName }}
    - name: POSTGRES_USER
      value: {{ $context.Values.database.kasmDbUser }}
    - name: POSTGRES_PASSWORD
      valueFrom:
        secretKeyRef:
        {{- if $context.Values.database.kasmDbSecret -}}
          {{ $context.Values.database.kasmDbSecret | toYaml | nindent 10 }}
        {{- else }}
          name: {{ $context.Release.Name }}-secrets
          key: "db-password"
        {{- end }}
    {{- end }}
  command:
    - /bin/bash
    - -c
  args:
    - |
      {{- if $isInit }}
      while ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t 10; do
        echo "Waiting for DB..."
        sleep 5
      done
      {{- else if $isBackup }}
      while ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t 10; do
        echo "Waiting for DB..."
        sleep 5
      done
      {{- else if $isVersion }}
      while ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t 10; do
        echo "Waiting for DB..."
        sleep 5
      done

      export PGPASSWORD="${POSTGRES_PASSWORD}"
      TARGET_MAJOR=16
      SLEEP=5

      echo "Waiting for PostgreSQL ${TARGET_MAJOR}.x (If you are using external DB, you can start upgrading your DB now.)..."

      while true; do
        if ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t 5 >/dev/null 2>&1; then
          echo "DB not reachable yet... waiting"
          sleep "${SLEEP}"
          continue
        fi

        VERNUM=$(psql \
          -h "${POSTGRES_HOST}" \
          -p "${POSTGRES_PORT}" \
          -U "${POSTGRES_USER}" \
          -d "${POSTGRES_DB}" \
          -Atc "SHOW server_version_num;" 2>/dev/null)

        if [[ -z "${VERNUM}" ]]; then
          echo "DB is not reachable or queryable... waiting"
          sleep "${SLEEP}"
          continue
        fi

        MAJOR=$((VERNUM / 10000))

        if (( MAJOR == TARGET_MAJOR )); then
          echo "PostgreSQL ${MAJOR}.x detected (server_version_num=${VERNUM})"
          break
        else
          echo "PostgreSQL ${MAJOR}.x detected (need ${TARGET_MAJOR}.x) ... waiting"
          sleep "${SLEEP}"
        fi
      done
      {{- else if $isReady }}
      while [ ! $(PGPASSWORD="${POSTGRES_PASSWORD}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -p "${POSTGRES_PORT}" -h "${POSTGRES_HOST}" -t -c "select zone_id from zones" 2>/dev/null | wc -l) -ge 2 ]; do
        echo "Waiting for DB to initialize..."
        sleep 30
      done

      cp /src/api_server/data/migration/alembic.ini /tmp/alembic.ini
      sed -i 's|script_location = %(here)s/alembic|script_location = /src/api_server/data/migration/alembic|g' /tmp/alembic.ini
      sed -i 's/# sourceless = false/sourceless = true/g' /tmp/alembic.ini
      cat /tmp/alembic.ini

      until alembic -c /tmp/alembic.ini \
        -x kasm_config=/opt/kasm/current/conf/app/api/api.app.config.yaml current \
        | grep -q "(head)"
      do
        echo "Waiting for DB migrations to reach head..."
        sleep 5
      done

      echo "Database is at head ✅"
      {{- end }}
  {{- if $needsVolumeMounts }}
  volumeMounts:
    {{- if $needsTmpDir }}
    - name: tmp-data
      mountPath: /tmp
    {{- end }}
    {{- if $hasTrustedCaBundle }}
    - name: usr-local-share
      mountPath: /usr/local/share/ca-certificates
      readOnly: true
    - name: etc-ssl-certs
      mountPath: /etc/ssl/certs
    {{- end }}
    {{- with $initMounts }}
      {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
  Return a replica object based on given presets
  Example usage:
  {{ include "replicas.preset" (dict "node" "proxy" "size" "small") -}}
*/}}
{{- define "replicas.preset" -}}
{{- $presetSizes := dict
  "proxy" (dict
    "small" 1
    "medium" 2
    "large" 3
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
    "medium" 1
    "large" 1
  )
  "rdp-gateway" (dict
    "small" 1
    "medium" 1
    "large" 1
  )
  "rdp-https-gateway" (dict
    "small" 1
    "medium" 1
    "large" 1
  )
-}}

{{- if not (hasKey $presetSizes .node) -}}
  {{- printf
      "ERROR: Unknown component '%s'. Allowed components are %s"
      .node
      (join ", " (keys $presetSizes))
    | fail
  -}}
{{- end -}}

{{- dig .node .size nil $presetSizes -}}
{{- end -}}

{{/*
  Return a resource request/limit object based on given presets
  Example usage:
  {{- include "resources.preset" (dict "node" "proxy" "size" "small" "context" .) -}}
*/}}
{{- define "resources.preset" }}
  {{- $context := default (dict) .context -}}
  {{- $zoneCount := len (default (list 1) (index $context "kasmZones")) -}}
  {{- $presetSizes := dict
    "proxy" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "proxy-processes" (dict "small" 2 "medium" 6 "large" 12)
    "db-max-connections" (dict "small" 200 "medium" (mul 400 $zoneCount) "large" (mul 600 $zoneCount))
    "db" (dict
      "small" (dict 
        "requests" (dict "cpu" "750m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "750m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "1.5" "memory" "2048Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1.5" "memory" "2048Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "4.0" "memory" "8192Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "4.0" "memory" "8192Mi" "ephemeral-storage" "2Gi")
      )
    )
    "api" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "manager" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "guac" (dict
      "small" (dict 
        "requests" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "2000m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "2000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "rdp-gateway" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
    "rdp-https-gateway" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "2Gi")
      )
    )
  }}

{{- if not (hasKey $presetSizes .node) -}}
  {{- printf
      "ERROR: Unknown component '%s'. Allowed components are %s"
      .node
      (join ", " (keys $presetSizes))
    | fail
  -}}
{{- end -}}

{{- dig .node .size nil $presetSizes | toYaml -}}
{{- end -}}

{{/*
kasm.mergeExtras
Returns a single YAML object with:
- volumes:            deduped []corev1.Volume
- containerMounts:    deduped []corev1.VolumeMount  (for the main container)
- initMounts:         deduped []corev1.VolumeMount  (for init containers)
- extraContainers:    deduped []corev1.Container    (sidecars)
- extraInitContainers:deduped []corev1.Container    (init sidecars)
Dedup rules:
- Containers: by .name (component overrides global on same name)
- VolumeMounts: by "<name>|<mountPath>" (separate sets for init vs main)
- Volumes: by a stable synthetic key (secret/configmap/pvc/emptyDir/name)
*/}}
{{- define "kasm.volumeKey" -}}
  {{- if .secret -}}
    secret-{{ .secret.secretName | default "kasm-mount" }}
  {{- else if .configMap -}}
    configmap-{{ .configMap.name | default "kasm-mount" }}
  {{- else if .persistentVolumeClaim -}}
    pvc-{{ .persistentVolumeClaim.claimName | default "kasm-mount" }}
  {{- else if .emptyDir -}}
    emptydir-{{ .name | default "kasm-mount" }}
  {{- else -}}
    name-{{ .name | default "kasm-mount" }}
  {{- end -}}
{{- end -}}

{{- define "kasm.mountKey" -}}
  {{- printf "%s|%s" (default "" .name) (default "" .mountPath) -}}
{{- end -}}

{{- define "kasm.mergedValues" -}}
  {{- $root := .root -}}
  {{- $componentName := .componentName -}}
  {{- $component := ternary $root.Values.database (index (default dict $root.Values.components) $componentName) (eq $componentName "database") -}}

  {{/* Start with shallow dicts for globals+component to make intent explicit */}}
  {{- $global := dict
      "extraVolumes"         (default (list) $root.Values.extraVolumes)
      "extraContainerMounts" (default (list) $root.Values.extraContainerVolumeMounts)
      "extraInitMounts"      (default (list) $root.Values.extraInitVolumeMounts)
      "extraContainers"      (default (list) $root.Values.extraContainers)
      "extraInitContainers"  (default (list) $root.Values.extraInitContainers)
    -}}
  {{- $componentLevel := dict
      "extraVolumes"         (default (list) $component.extraVolumes)
      "extraContainerMounts" (default (list) $component.extraVolumeMounts)
      "extraContainers"      (default (list) $component.extraContainers)
      "extraInitContainers"  (default (list) $component.extraInitContainers)
    -}}

  {{/* Build dedupe maps */}}
  {{- $volMap := dict -}}
  {{- range $v := get $global "extraVolumes" -}}
    {{- $_ := set $volMap (include "kasm.volumeKey" $v) $v -}}
  {{- end -}}
  {{- range $v := get $componentLevel "extraVolumes" -}}
    {{- $_ := set $volMap (include "kasm.volumeKey" $v) $v -}}
  {{- end -}}

  {{- $mainMountMap := dict -}}
  {{- range $mounts := get $global "extraContainerMounts" -}}
    {{- $_ := set $mainMountMap (include "kasm.mountKey" $mounts) $mounts -}}
  {{- end -}}
  {{- range $mounts := get $componentLevel "extraContainerMounts" -}}
    {{- $_ := set $mainMountMap (include "kasm.mountKey" $mounts) $mounts -}}
  {{- end -}}

  {{- $initMountMap := dict -}}
  {{- range $mounts := get $global "extraInitMounts" -}}
    {{- $_ := set $initMountMap (include "kasm.mountKey" $mounts) $mounts -}}
  {{- end -}}

  {{- $sidecarMap := dict -}}
  {{- range $containers := get $global "extraContainers" -}}
    {{- if not $containers.name -}} {{- fail "extraContainers entries must define 'name'" -}} {{- end -}}
    {{- $_ := set $sidecarMap $containers.name $containers -}}
  {{- end -}}
  {{- range $containers := get $componentLevel "extraContainers" -}}
    {{- if not $containers.name -}} {{- fail "extraContainers entries must define 'name'" -}} {{- end -}}
    {{- $_ := set $sidecarMap $containers.name $containers -}}
  {{- end -}}

  {{- $initCtrMap := dict -}}
  {{- range $containers := get $global "extraInitContainers" -}}
    {{- if not $containers.name -}} {{- fail "extraInitContainers entries must define 'name'" -}} {{- end -}}
    {{- $_ := set $initCtrMap $containers.name $containers -}}
  {{- end -}}
  {{- range $containers := get $componentLevel "extraInitContainers" -}}
    {{- if not $containers.name -}} {{- fail "extraInitContainers entries must define 'name'" -}} {{- end -}}
    {{- $_ := set $initCtrMap $containers.name $containers -}}
  {{- end -}}

  {{/* Convert maps back to lists in a single object; emit YAML once */}}
  {{- $out := dict -}}
  {{- $_ := set $out "volumes"            (values $volMap) -}}
  {{- $_ := set $out "containerMounts"    (values $mainMountMap) -}}
  {{- $_ := set $out "initMounts"         (values $initMountMap) -}}
  {{- $_ := set $out "extraContainers"    (values $sidecarMap) -}}
  {{- $_ := set $out "extraInitContainers" (values $initCtrMap) -}}
  {{- toYaml $out -}}
{{- end -}}

{{/*
  Script to load custom CA bundle into Kasm containers
*/}}
{{- define "kasm.trustedCaInit" }}
{{- $context := index . 0 -}}
{{- $component := index . 1 -}}
{{- $uidGid := 1000 -}}
{{- if eq $component "db" -}}
  {{- $uidGid = 70 -}}
{{- end -}}
- name: trusted-ca-init
  image: {{ printf "%s/%s:%s" $context.Values.components.api.image.registry $context.Values.components.api.image.repository $context.Values.components.api.image.tag }}
  imagePullPolicy: {{ $context.Values.imagePullPolicy }}
  {{- include "kasm.securityContext" (list $context $uidGid "container") | nindent 2 }}
  command:
    - /bin/bash
    - -c
  args:
    - |
      /opt/ca-init/init-ca-trust.sh
  volumeMounts:
    - name: ca-init-script
      mountPath: /opt/ca-init/init-ca-trust.sh
      subPath: init-ca-trust.sh
      readOnly: true
    - name: ca-tmp
      mountPath: /tmp
    - name: usr-local-share
      mountPath: /usr/local/share/ca-certificates
      readOnly: true
    - name: etc-ssl-certs
      mountPath: /etc/ssl/certs
{{- end -}}

{{- define "kasm.trustedCaVolumes" -}}
{{- if .Values.trustedCaBundle.enabled -}}
- name: ca-init-script
  configMap:
    name: {{ include "kasm.name" (list . "caBundleScript" "configmap") }}
    defaultMode: 0555
- name: ca-tmp
  emptyDir: {}
- name: usr-local-share
  configMap:
    name: {{ .Values.trustedCaBundle.configMapName | default (include "kasm.name" (list . "caBundleCert" "configmap")) }}
- name: etc-ssl-certs
  emptyDir: {}
{{- end }}
{{- end }}

{{- define "kasm.trustedCaVolumeMounts" -}}
{{- if .Values.trustedCaBundle.enabled -}}
- name: usr-local-share
  mountPath: /usr/local/share/ca-certificates
  readOnly: true
- name: etc-ssl-certs
  mountPath: /etc/ssl/certs
{{- end }}
{{- end }}
