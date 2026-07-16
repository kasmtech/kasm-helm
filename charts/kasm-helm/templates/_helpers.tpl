{{/*
  Resolve the image tag for a given component.

  Precedence:
    1. per-component image.tag if set (always wins)
    2. else .Values.useImageTags if non-empty (chart-wide default)
    3. else: fail with an error naming the component

  Call with a three-element list: (list <root context> <componentTag> <componentName>)
  where <componentTag> is e.g. .Values.components.api.image.tag and <componentName>
  is the values-path component name used in the fail message ("api", "manager",
  "proxy", "guac", "rdpGateway", "rdpHttpsGateway", or "database").
*/}}
{{- define "kasm.imageTag" -}}
{{- $ctx := index . 0 -}}
{{- $componentTag := index . 1 -}}
{{- $componentName := index . 2 -}}
{{- $useImageTags := $ctx.Values.useImageTags | default "" -}}
{{- if $componentTag -}}
{{ $componentTag }}
{{- else if $useImageTags -}}
{{ $useImageTags }}
{{- else -}}
{{- $valuesPath := ternary (printf ".Values.database.image.tag") (printf ".Values.components.%s.image.tag" $componentName) (eq $componentName "database") -}}
{{- fail (printf "Image tag not set for %q. Set .Values.useImageTags (chart-wide) or %s." $componentName $valuesPath) -}}
{{- end -}}
{{- end }}

{{/*
  Constants to use across chart template files
*/}}
{{- define "kasm.constants" }}
api:
  component: api
  svc: {{ printf "%s-api" .Release.Name }}
  portName: api-pt
  image: {{ printf "%s/%s:%s" .Values.components.api.image.registry .Values.components.api.image.repository (include "kasm.imageTag" (list . .Values.components.api.image.tag "api")) }}
  port: 8080
manager:
  component: manager
  svc: {{ printf "%s-manager" .Release.Name }}
  portName: manager-pt
  image: {{ printf "%s/%s:%s" .Values.components.manager.image.registry .Values.components.manager.image.repository (include "kasm.imageTag" (list . .Values.components.manager.image.tag "manager")) }}
  port: 8181
proxy:
  component: proxy
  svc: {{ printf "%s-proxy" .Release.Name }}
  portName: proxy-pt
  image: {{ printf "%s/%s:%s" .Values.components.proxy.image.registry .Values.components.proxy.image.repository (include "kasm.imageTag" (list . .Values.components.proxy.image.tag "proxy")) }}
  http: 8080
  https: 8443
  extHttps: 443
db:
  component: db
  svc: {{ if .Values.database.standalone }}{{- .Values.database.hostname }}{{ else }}{{- printf "%s-db" .Release.Name }}{{ end }}
  portName: db-pt
  image: {{ printf "%s/%s:%s" .Values.database.image.registry .Values.database.image.repository (include "kasm.imageTag" (list . .Values.database.image.tag "database")) }}
  port: {{ .Values.database.port }}
guac:
  component: guac
  svc: {{ if .Values.kasmZones }}{{ printf "%s-guac-%s" .Release.Name (include "kasm.zoneName" (include "kasm.primaryZone" . | fromYaml).name) }}{{ else }}{{ printf "%s-guac-default" .Release.Name }}{{ end }}
  portName: guac-pt
  name: {{ if .Values.kasmZones }}{{ printf "%s-guac-%s" .Release.Name (include "kasm.zoneName" (include "kasm.primaryZone" . | fromYaml).name) }}{{ else }}{{ printf "%s-guac-default" .Release.Name }}{{ end }}
  image: {{ printf "%s/%s:%s" .Values.components.guac.image.registry .Values.components.guac.image.repository (include "kasm.imageTag" (list . .Values.components.guac.image.tag "guac")) }}
  port: 3000
  nginxPort: 9000
  ports:
    {{- $clusterSize := ternary .Values.components.guac.guacClusterSize (include "resources.preset" (dict "node" "guac-processes" "size" .Values.deploymentSize "context" .Values)) (gt (int .Values.components.guac.guacClusterSize) 0) }}
    {{- range $idx := until (int $clusterSize) }}
    - {{ printf "300%d" (add $idx 1) }}
    {{- end }}
rdpGateway:
  component: rdp-gateway
  svc: {{ if .Values.kasmZones }}{{ printf "%s-rdp-gateway-%s" .Release.Name (include "kasm.zoneName" (include "kasm.primaryZone" . | fromYaml).name) }}{{ else }}{{ printf "%s-rdp-gateway-default" .Release.Name }}{{ end }}
  portName: rdp-gw-pt
  image: {{ printf "%s/%s:%s" .Values.components.rdpGateway.image.registry .Values.components.rdpGateway.image.repository (include "kasm.imageTag" (list . .Values.components.rdpGateway.image.tag "rdpGateway")) }}
  port: 5555
  nginxPort: 9001
rdpHttpsGateway:
  component: rdp-https-gateway
  svc: {{ if .Values.kasmZones }}{{ printf "%s-rdp-https-gateway-%s" .Release.Name (include "kasm.zoneName" (include "kasm.primaryZone" . | fromYaml).name) }}{{ else }}{{ printf "%s-rdp-https-gateway-default" .Release.Name }}{{ end }}
  portName: rdp-tls-ngnx-pt
  image: {{ printf "%s/%s:%s" .Values.components.rdpHttpsGateway.image.registry .Values.components.rdpHttpsGateway.image.repository (include "kasm.imageTag" (list . .Values.components.rdpHttpsGateway.image.tag "rdpHttpsGateway")) }}
  port: 9443
  nginxPort: 9002
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
  Resolve a zone's proxy hostname. Prefers proxy_hostname; falls back to the
  deprecated proxyAddress alias for backwards compatibility. Returns an empty
  string if neither is set. If both are set, proxy_hostname wins (per values.yaml).
*/}}
{{- define "kasm.zoneProxyHostname" -}}
{{- default .proxyAddress .proxy_hostname -}}
{{- end -}}

{{/*
  Resolve a zone's proxy hostname for host-bearing resources (ingress, route,
  certificate) that cannot render a valid entry with an empty string. Fails with a
  descriptive error if the zone has neither proxy_hostname nor proxyAddress set.
*/}}
{{- define "kasm.zoneProxyHostnameRequired" -}}
{{- $hostname := include "kasm.zoneProxyHostname" . -}}
{{- if not $hostname -}}
  {{- fail (printf "kasmZones[%s]: 'proxy_hostname' (or deprecated 'proxyAddress') must be set to generate an ingress/route/certificate hostname for this zone" (default "unnamed zone" .name)) -}}
{{- end -}}
{{- $hostname -}}
{{- end -}}

{{/*
  Return user-configured Kasm zones from kasmZones only (no kasmConfig.zones fallback).
  Normalizes each zone's `name` field, falling back to the deprecated `zone_name` alias
  when `name` is not set, so following the schema's zone_name guidance does not produce
  zones with an empty/nil name.
*/}}
{{- define "kasm.configuredZones" -}}
{{- if .Values.kasmZones -}}
  {{- $result := list -}}
  {{- range $zone := .Values.kasmZones -}}
    {{- $normalized := deepCopy $zone -}}
    {{- $_ := set $normalized "name" (default $normalized.zone_name $normalized.name) -}}
    {{- $result = append $result $normalized -}}
  {{- end -}}
  {{- toYaml $result -}}
{{- else -}}
  {{- toYaml list -}}
{{- end -}}
{{- end -}}

{{/*
  Return the effective Kasm zones, falling back to a single default zone when none configured.
*/}}
{{- define "kasm.zones" -}}
{{- $zones := (include "kasm.configuredZones" . | fromYamlArray) | default list -}}
{{- if $zones -}}
  {{- toYaml $zones -}}
{{- else -}}
  {{- toYaml (list (dict "name" "default")) -}}
{{- end -}}
{{- end -}}

{{/*
  Return the primary zone as a YAML dict.
  If exactly one zone has primary: true, that zone is used. If no zone has
  primary: true, the first zone in kasmZones is treated as primary (per values.yaml).
  Fails with a descriptive error if more than one zone has primary: true, since
  that is ambiguous.
  When kasmZones is not defined, returns the implicit default zone.
*/}}
{{- define "kasm.primaryZone" -}}
{{- $configured := (include "kasm.configuredZones" . | fromYamlArray) | default list -}}
{{- if $configured -}}
  {{- $primaryZones := list -}}
  {{- range $zone := $configured -}}
    {{- if dig "primary" false $zone -}}
      {{- $primaryZones = append $primaryZones $zone -}}
    {{- end -}}
  {{- end -}}
  {{- if gt (len $primaryZones) 1 -}}
    {{- fail (printf "kasmZones has %d zones marked 'primary: true'; at most one zone may be primary. Remove 'primary: true' from all but one zone." (len $primaryZones)) -}}
  {{- else if eq (len $primaryZones) 1 -}}
    {{- toYaml (first $primaryZones) -}}
  {{- else -}}
    {{- toYaml (first $configured) -}}
  {{- end -}}
{{- else -}}
  {{- toYaml (dict "name" "default") -}}
{{- end -}}
{{- end -}}

{{/*
  Returns "true" if the given zone is in the primary region.
  Args: list of (root context, zone dict).
  A zone is in the primary region when:
    - It IS the primary zone, OR
    - It shares the same region_name as the primary zone (and region_name is non-empty).
  When no zone has region_name set, only the primary zone itself is in the primary region.
*/}}
{{- define "kasm.isInPrimaryRegion" -}}
{{- $root := index . 0 -}}
{{- $zone := index . 1 -}}
{{- $primaryZone := (include "kasm.primaryZone" $root | fromYaml) -}}
{{- if eq $zone.name $primaryZone.name -}}
true
{{- else if and $primaryZone.region_name $zone.region_name (eq $zone.region_name $primaryZone.region_name) -}}
true
{{- end -}}
{{- end -}}

{{/*
  Return a YAML array of zones that are in the primary region.
  Guac, RDP Gateway, and RDP HTTPS Gateway are only deployed in primary-region zones.
*/}}
{{- define "kasm.primaryRegionZones" -}}
{{- $zones := (include "kasm.zones" . | fromYamlArray) | default list -}}
{{- $result := list -}}
{{- range $zone := $zones -}}
  {{- if include "kasm.isInPrimaryRegion" (list $ $zone) -}}
    {{- $result = append $result $zone -}}
  {{- end -}}
{{- end -}}
{{- toYaml $result -}}
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

{{- if (or (eq $component "secrets") (eq $component "image-pull") (eq $component "db-preseed")) -}}
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
  Consolidated Kubernetes health probe helper.

  This helper renders one Kubernetes probe block using a chart-developer-selected
  probe implementation type while resolving admin-configurable probe timing from
  values.yaml.

  Required args:
    root: Root chart context. Usually pass $.
    component: Component selector used to locate healthCheckTiming in values.yaml. Standard components resolve from:
                .Values.components.<component>.healthCheckTiming. The database component is special-cased: component: db
                resolves from: .Values.database.healthCheckTiming
    probeType: Probe timing selector under healthCheckTiming. Expected values: livenessProbe, readinessProbe type: Kubernetes
              probe implementation type. Allowed values: http, https, tcp, command

  Optional args:
    timingScope: Optional sub-selector for components with multiple containers and container-specific health check timing. When
                supplied, timing resolves from: .Values.components.<component>.<timingScope>.healthCheckTiming.<probeType>
                Example timingScope selectors: nginxSidecar

  Probe-specific args:
    For type: http or https 
      path: HTTP path used by httpGet.
      portName or port: Named or numeric container port used by httpGet.
    For type: tcp
      portName or port: Named or numeric container port used by tcpSocket.
    For type: command
      command: Either a string command rendered as: /bin/sh -c "<command>" Or a list rendered directly as the exec command array.
  
  Timing resolution order:
    If component == "db":
        .Values.database.healthCheckTiming.<probeType>
    Else if container is supplied:
        .Values.components.<component>.healthCheckTiming.<container>.<probeType>
    Else:
        .Values.components.<component>.healthCheckTiming.<probeType>

  Timing defaults used when values are omitted:
    timeoutSeconds: 5
    initialDelaySeconds: 10
    periodSeconds: 30
    failureThreshold: 3
    successThreshold: 1

  Example, standard single-container component:
    livenessProbe:
      {{- include "health.probe" (dict
            "root" $
            "component" "api"
            "probeType" "livenessProbe"
            "type" "http"
            "path" "/healthz"
            "portName" "api"
          ) | nindent 6 }}
*/}}
{{- define "health.probe" -}}
{{- $root := required "health.probe requires root" .root -}}
{{- $componentName := required "health.probe requires component" .component -}}
{{- $probeType := required "health.probe requires probeType" .probeType -}}
{{- $probeKind := required "health.probe requires type: http, https, tcp, or command" .type | lower -}}

{{- $healthCheckParent := dict -}}

{{- if eq $componentName "db" -}}
  {{- $healthCheckParent = get $root.Values "database" | default dict -}}
{{- else -}}
  {{- $components := get $root.Values "components" | default dict -}}
  {{- $component := get $components $componentName | default dict -}}

  {{- if hasKey . "timingScope" -}}
    {{- $timingScope := .timingScope -}}
    {{- $healthCheckParent = get $component $timingScope | default dict -}}
  {{- else -}}
    {{- $healthCheckParent = $component -}}
  {{- end -}}
{{- end -}}

{{- $healthCheckTiming := get $healthCheckParent "healthCheckTiming" | default dict -}}
{{- $timing := get $healthCheckTiming $probeType | default dict -}}

{{- $timeoutSeconds := get $timing "timeoutSeconds" | default 5 -}}
{{- $initialDelaySeconds := get $timing "initialDelaySeconds" | default 10 -}}
{{- $periodSeconds := get $timing "periodSeconds" | default 30 -}}
{{- $failureThreshold := get $timing "failureThreshold" | default 3 -}}
{{- $successThreshold := get $timing "successThreshold" | default 1 -}}

{{- if or (eq $probeKind "http") (eq $probeKind "https") -}}
{{- $path := required "health.probe type http/https requires path" .path -}}
{{- $port := "" -}}
{{- if hasKey . "port" -}}
  {{- $port = .port -}}
{{- else if hasKey . "portName" -}}
  {{- $port = .portName -}}
{{- else -}}
  {{- fail "health.probe type http/https requires port or portName" -}}
{{- end -}}
httpGet:
  path: {{ $path | quote }}
  port: {{ $port }}
{{- if eq $probeKind "https" }}
  scheme: HTTPS
{{- end }}

{{- else if eq $probeKind "tcp" -}}
{{- $port := "" -}}
{{- if hasKey . "port" -}}
  {{- $port = .port -}}
{{- else if hasKey . "portName" -}}
  {{- $port = .portName -}}
{{- else -}}
  {{- fail "health.probe type tcp requires port or portName" -}}
{{- end -}}
tcpSocket:
  port: {{ $port }}

{{- else if eq $probeKind "command" -}}
{{- $command := required "health.probe type command requires command" .command -}}
exec:
  command:
{{- if kindIs "slice" $command }}
{{ toYaml $command | nindent 4 }}
{{- else }}
    - /bin/sh
    - -c
    - {{ $command | quote }}
{{- end }}

{{- else -}}
{{- fail (printf "health.probe received unsupported type %q. Allowed values: http, https, tcp, command" $probeKind) -}}
{{- end }}
timeoutSeconds: {{ $timeoutSeconds }}
initialDelaySeconds: {{ $initialDelaySeconds }}
periodSeconds: {{ $periodSeconds }}
failureThreshold: {{ $failureThreshold }}
successThreshold: {{ $successThreshold }}
{{- end -}}

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

{{/*
    Name from $component (a short identifier like "api" or "rdpGateway"), not $service.
    $service is already a fully release-prefixed DNS name (e.g. "<release>-rdp-gateway-<zone>");
    passing it to kasm.name would prepend the release name a second time and let kebabcase
    mangle digit/letter boundaries in it (e.g. "e2e" -> "e-2e"), which can exceed the 63-char
    Kubernetes name limit once the release name and zone name are both non-trivial.
  */}}
- name: {{ include "kasm.name" (list $context (printf "%s-is-ready" $component)) }}
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
{{- $connectionTimeout := $context.Values.dbManagement.dbConnectionTimeout -}}

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
      while ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t {{ $connectionTimeout }}; do
        echo "Waiting for DB..."
        sleep 5
      done
      {{- else if $isBackup }}
      while ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t {{ $connectionTimeout }}; do
        echo "Waiting for DB..."
        sleep 5
      done
      {{- else if $isVersion }}
      while ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t {{ $connectionTimeout }}; do
        echo "Waiting for DB..."
        sleep 5
      done

      export PGPASSWORD="${POSTGRES_PASSWORD}"
      TARGET_MAJOR=16
      SLEEP=5

      echo "Waiting for PostgreSQL ${TARGET_MAJOR}.x (If you are using external DB, you can start upgrading your DB now.)..."

      while true; do
        if ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -t {{ $connectionTimeout }} >/dev/null 2>&1; then
          echo "DB not reachable yet... waiting"
          sleep "${SLEEP}"
          continue
        fi

        VERNUM=$(PGCONNECT_TIMEOUT={{ $connectionTimeout }} psql \
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
      while [ ! $(PGCONNECT_TIMEOUT={{ $connectionTimeout }} PGPASSWORD="${POSTGRES_PASSWORD}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -p "${POSTGRES_PORT}" -h "${POSTGRES_HOST}" -t -c "select zone_id from zones" 2>/dev/null | wc -l) -ge 2 ]; do
        echo "Waiting for DB to initialize..."
        sleep 5
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
    "medium" 2
    "large" 3
  )
  "rdp-gateway" (dict
    "small" 1
    "medium" 1
    "large" 1
  )
  "rdp-https-gateway" (dict
    "small" 1
    "medium" 2
    "large" 3
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
        "limits" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "2Gi")
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
        "limits" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "2Gi" "ephemeral-storage" "2Gi")
      )
    )
    "manager" (dict
      "small" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "500m" "memory" "2Gi" "ephemeral-storage" "2Gi")
      )
    )
    "guac-processes" (dict "small" 4 "medium" 6 "large" 8)
    "guac" (dict
      "small" (dict 
        "requests" (dict "cpu" "1000m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1000m" "memory" "1Gi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict 
        "requests" (dict "cpu" "1500m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1500m" "memory" "2Gi" "ephemeral-storage" "2Gi")
      )
      "large" (dict 
        "requests" (dict "cpu" "2000m" "memory" "1Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "2000m" "memory" "4Gi" "ephemeral-storage" "2Gi")
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
    "nginx-sidecar" (dict
      "small" (dict
        "requests" (dict "cpu" "500m" "memory" "256Mi")
        "limits" (dict "cpu" "500m" "memory" "256Mi")
      )
      "medium" (dict
        "requests" (dict "cpu" "500m" "memory" "384Mi")
        "limits" (dict "cpu" "500m" "memory" "384Mi")
      )
      "large" (dict
        "requests" (dict "cpu" "1000m" "memory" "512Mi")
        "limits" (dict "cpu" "1000m" "memory" "512Mi")
      )
    )
    "nginx-conf-init" (dict
      "small" (dict
        "requests" (dict "cpu" "100m" "memory" "64Mi")
        "limits" (dict "cpu" "100m" "memory" "64Mi")
      )
      "medium" (dict
        "requests" (dict "cpu" "100m" "memory" "64Mi")
        "limits" (dict "cpu" "100m" "memory" "64Mi")
      )
      "large" (dict
        "requests" (dict "cpu" "100m" "memory" "64Mi")
        "limits" (dict "cpu" "100m" "memory" "64Mi")
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
{{- $constants := include "kasm.constants" $context | fromYaml -}}
{{- if eq $component "db" -}}
  {{- $uidGid = 70 -}}
{{- end -}}
{{- if $context.Values.trustedCaBundle.enabled -}}
- name: trusted-ca-init
  image: {{ $constants.api.image }}
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

{{/*
  Env vars so Python (requests/certifi) and other tooling use the trust store
  built by trusted-ca-init, not the bundled certifi CA file alone.
*/}}
{{- define "kasm.trustedCaEnv" -}}
{{- if .Values.trustedCaBundle.enabled }}
- name: SSL_CERT_FILE
  value: /etc/ssl/certs/ca-certificates.crt
- name: REQUESTS_CA_BUNDLE
  value: /etc/ssl/certs/ca-certificates.crt
{{- end }}
{{- end }}
