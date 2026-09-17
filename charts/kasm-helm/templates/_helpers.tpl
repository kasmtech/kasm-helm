{{/*
  Resolve the image tag for a given component.

  Precedence:
    1. per-component image.tag if set (always wins)
    2. else .Values.useImageTags if non-empty (chart-wide default)
    3. else: fail with an error naming the component

  Call with a three-element list: (list <root context> <componentTag> <componentName>)
  where <componentTag> is e.g. .Values.components.api.image.tag and <componentName>
  is the values-path component name used in the fail message ("api",
  "proxy", "connectionProxy.nginx", "connectionProxy.guac", "connectionProxy.rdpGateway",
  "connectionProxy.rdpHttpsGateway", or "database").
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
  Resolve the IP address nginx's `resolver` directive should use for dynamic upstream DNS
  resolution (proxy and connection-proxy nginx ConfigMaps).

  Precedence:
    1. .Values.nginxResolver if explicitly set (always wins)
    2. else the live cluster's kube-dns Service ClusterIP, via `lookup` (only available against
       a real cluster during install/upgrade; always empty under `helm template`/`--dry-run`, and
       empty if the cluster's DNS Service isn't named "kube-dns" in "kube-system" or the Helm
       service account lacks permission to read Services there)
    3. else the historical hardcoded default, 127.0.0.11

  Call with the root context: (include "kasm.nginxResolver" .)
*/}}
{{- define "kasm.nginxResolver" -}}
{{- if .Values.nginxResolver -}}
{{ .Values.nginxResolver }}
{{- else -}}
{{- $kubeDnsSvc := lookup "v1" "Service" "kube-system" "kube-dns" -}}
{{- if and $kubeDnsSvc $kubeDnsSvc.spec $kubeDnsSvc.spec.clusterIP -}}
{{ $kubeDnsSvc.spec.clusterIP }}
{{- else -}}
127.0.0.11
{{- end -}}
{{- end -}}
{{- end }}

{{/*
  Constants to use across chart template files
*/}}
{{- define "kasm.constants" }}
secrets:
  component: secrets
  name: {{ default (printf "%s-secrets" .Release.Name) .Values.kasmSecrets.name }}
api:
  component: api
  svc: {{ printf "%s-api" .Release.Name }}
  portName: api-pt
  image: {{ printf "%s/%s:%s" .Values.components.api.image.registry .Values.components.api.image.repository (include "kasm.imageTag" (list . .Values.components.api.image.tag "api")) }}
  port: 8080
  livenessPortName: api-live-pt
  livenessPort: 8081
apiWorker:
  component: apiWorker
  {{- if eq (include "kasm.apiWorkerMode" .Values) "split" }}
  image: {{ printf "%s/%s:%s" .Values.components.apiWorker.image.registry .Values.components.apiWorker.image.repository (include "kasm.imageTag" (list . .Values.components.apiWorker.image.tag "apiWorker")) }}
  {{- end }}
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
connectionProxy:
  component: connection-proxy
  svc: {{ if .Values.kasmZones }}{{ printf "%s-connection-proxy-%s" .Release.Name (include "kasm.zoneName" (include "kasm.primaryZone" . | fromYaml).name) }}{{ else }}{{ printf "%s-connection-proxy-default" .Release.Name }}{{ end }}
  portName: cp-nginx-pt
  nginxPort: 8443
  {{- $cp := .Values.components.connectionProxy }}
  image: {{ if and $cp.nginx.image.registry $cp.nginx.image.repository }}{{ printf "%s/%s:%s" $cp.nginx.image.registry $cp.nginx.image.repository (include "kasm.imageTag" (list . $cp.nginx.image.tag "connectionProxy.nginx")) }}{{ end }}
  guac:
    port: 3000
    portName: cp-guac-pt
    image: {{ if and $cp.guac.image.registry $cp.guac.image.repository }}{{ printf "%s/%s:%s" $cp.guac.image.registry $cp.guac.image.repository (include "kasm.imageTag" (list . $cp.guac.image.tag "connectionProxy.guac")) }}{{ end }}
    ports:
      {{- $cpClusterSize := ternary $cp.guac.guacClusterSize (include "resources.preset" (dict "node" "guac-processes" "size" .Values.deploymentSize "context" .Values)) (gt (int $cp.guac.guacClusterSize) 0) }}
      {{- range $idx := until (int $cpClusterSize) }}
      - {{ printf "300%d" (add $idx 1) }}
      {{- end }}
  rdpGateway:
    port: 5555
    portName: cp-rdp-gw-pt
    directPort: 3389
    directPortName: cp-rdp-drct-pt
    image: {{ if and $cp.rdpGateway.image.registry $cp.rdpGateway.image.repository }}{{ printf "%s/%s:%s" $cp.rdpGateway.image.registry $cp.rdpGateway.image.repository (include "kasm.imageTag" (list . $cp.rdpGateway.image.tag "connectionProxy.rdpGateway")) }}{{ end }}
  rdpHttpsGateway:
    port: 9443
    portName: cp-rdp-tls-pt
    image: {{ if and $cp.rdpHttpsGateway.image.registry $cp.rdpHttpsGateway.image.repository }}{{ printf "%s/%s:%s" $cp.rdpHttpsGateway.image.registry $cp.rdpHttpsGateway.image.repository (include "kasm.imageTag" (list . $cp.rdpHttpsGateway.image.tag "connectionProxy.rdpHttpsGateway")) }}{{ end }}
otel:
  portName: otel-pt
  gatewayComponent: otel-gateway
  gatewaySvc: {{ printf "%s-otel-gateway" .Release.Name }}
  gatewayImage: {{ include "kasm.common.imageRef" .Values.components.otelGateway.image }}
  sidecarImage: {{ include "kasm.common.imageRef" .Values.components.otelSidecar.image }}
  otlpHttp: 4318
  otlpGrpc: 4317
  otlpNginx: 4316
  syslogAccess: 5140
  syslogError: 5141
  health: 13133
  selfMetrics: 8888
clickhouse:
  component: clickhouse
  svc: {{ printf "%s-clickhouse" .Release.Name }}
  portName: ch-pt
  image: {{ printf "%s/%s:%s" .Values.components.clickhouse.image.registry .Values.components.clickhouse.image.repository .Values.components.clickhouse.image.tag }}
  http: 8123
  native: 9000
  httpTls: 8443
  nativeTls: 9440
proxyStubStatus: 8090
{{- end }}

{{/*
  Normalize a zone name to a DNS-safe label component.
  Mirrors the normalization used by `kasm.name` so hostnames built inline
  (proxy upstreams, init containers, env vars) match the actual Service names.
  Delegates to kasm.common.zoneName (charts/kasm-common); see that chart's _helpers.tpl for the
  real implementation.
*/}}
{{- define "kasm.zoneName" -}}
{{- include "kasm.common.zoneName" . -}}
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
  Resolve directRdpService.perServiceSettings entries for one zone, WITHOUT validation (no `fail` calls).
  Validation lives in kasm.directRdpServiceValidateZone, called only from connection-proxy-services.yaml,
  so any render failure always attributes to that template (helm-unittest's failedTemplate assertions
  require the failure to originate from the template under test, and Helm renders every template file in
  one pass, so a `fail` reachable from two files could attribute to whichever one Go evaluates first).

  Call with (list <root context> <zone name>); returns a YAML array (parse with fromYamlArray) of
  perServiceSettings-shaped entries. List order is the ordinal (index 0 is pod ordinal 0, etc), scoped to
  entries for this zone.

  With exactly one primary-region zone, every entry applies regardless of its `zone` field -- backward
  compatible with configs from before multi-zone support, where `zone` was never set. With more than one
  primary-region zone, only entries whose `zone` field matches this zone name are included; position
  within that filtered subset is the ordinal, so entries for other zones interleaved in the list don't
  shift it.
*/}}
{{- define "kasm.directRdpEntriesForZone" -}}
{{- $ctx := index . 0 -}}
{{- $zoneName := index . 1 -}}
{{- $zoneCount := len (include "kasm.primaryRegionZones" $ctx | fromYamlArray) -}}
{{- $flat := $ctx.Values.directRdpService.perServiceSettings | default list -}}
{{- $entries := list -}}
{{- if le $zoneCount 1 -}}
  {{- if $flat -}}
    {{- $entries = $flat -}}
  {{- else if $ctx.Values.directRdpService.rdpAccessURL -}}
    {{- $entries = list (dict "rdpAccessURL" $ctx.Values.directRdpService.rdpAccessURL) -}}
  {{- end -}}
{{- else -}}
  {{- range $flat -}}
    {{- if eq (.zone | default "") $zoneName -}}
      {{- $entries = append $entries . -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $entries | toYaml -}}
{{- end -}}

{{/*
  Validate directRdpService settings for one zone against components.connectionProxy's replica count.
  Call with (list <root context> <zone name>). No-op when directRdpService is disabled. Only called from
  connection-proxy-services.yaml -- see kasm.directRdpEntriesForZone for why that matters.

  With more than one primary-region zone, a flat list without a `zone` per entry can't express distinct
  addresses per zone, so the legacy singular rdpAccessURL and zone-less perServiceSettings entries are
  rejected outright rather than silently reused across every zone.
*/}}
{{- define "kasm.directRdpServiceValidateZone" -}}
{{- $ctx := index . 0 -}}
{{- $zoneName := index . 1 -}}
{{- if $ctx.Values.directRdpService.enabled -}}
  {{- $constants := include "kasm.constants" $ctx | fromYaml -}}
  {{- $cp := $ctx.Values.components.connectionProxy -}}
  {{- $cpReplicas := ternary $cp.replicas (include "replicas.preset" (dict "node" $constants.connectionProxy.component "size" $ctx.Values.deploymentSize)) (gt (int $cp.replicas) 0) -}}
  {{- $zoneCount := len (include "kasm.primaryRegionZones" $ctx | fromYamlArray) -}}
  {{- $multiZone := gt $zoneCount 1 -}}
  {{- $flat := $ctx.Values.directRdpService.perServiceSettings | default list -}}
  {{- if $multiZone -}}
    {{- if $ctx.Values.directRdpService.rdpAccessURL -}}
      {{- fail (printf "directRdpService.rdpAccessURL (legacy singular) cannot be used with more than one primary-region zone (%d configured): set a zone field on every directRdpService.perServiceSettings entry instead." $zoneCount) -}}
    {{- end -}}
    {{- $validZones := dict -}}
    {{- range (include "kasm.primaryRegionZones" $ctx | fromYamlArray) -}}
      {{- $validZones = set $validZones .name true -}}
    {{- end -}}
    {{- range $i, $entry := $flat -}}
      {{- $entryZone := $entry.zone | default "" -}}
      {{- if not $entryZone -}}
        {{- fail (printf "directRdpService.perServiceSettings[%d] has no zone set, but %d primary-region zones are configured. Every entry needs a zone field naming which zone it belongs to." $i $zoneCount) -}}
      {{- end -}}
      {{- if not (hasKey $validZones $entryZone) -}}
        {{- fail (printf "directRdpService.perServiceSettings[%d].zone %q does not match any configured primary-region zone." $i $entryZone) -}}
      {{- end -}}
    {{- end -}}
  {{- else -}}
    {{- if and $ctx.Values.directRdpService.rdpAccessURL $flat -}}
      {{- fail "directRdpService.rdpAccessURL (legacy singular) and directRdpService.perServiceSettings are both set. This is ambiguous: remove rdpAccessURL and configure every replica via perServiceSettings instead." -}}
    {{- end -}}
    {{- if and $ctx.Values.directRdpService.rdpAccessURL (gt (int $cpReplicas) 1) -}}
      {{- fail (printf "directRdpService.rdpAccessURL (legacy singular) is set but components.connectionProxy has %d replica(s). The legacy singular URL is only honored at 1 replica: move to directRdpService.perServiceSettings, with one ordinal-indexed entry per replica." (int $cpReplicas)) -}}
    {{- end -}}
  {{- end -}}
  {{- $entries := include "kasm.directRdpEntriesForZone" (list $ctx $zoneName) | fromYamlArray -}}
  {{- if lt (len $entries) (int $cpReplicas) -}}
    {{- if $multiZone -}}
      {{- fail (printf "directRdpService.enabled is true but only %d entr(y/ies) are configured for zone %q while components.connectionProxy has %d replica(s). Each connection-proxy replica needs its own externally reachable RDP address: add more directRdpService.perServiceSettings entries with zone: %s." (len $entries) $zoneName (int $cpReplicas) $zoneName) -}}
    {{- else -}}
      {{- fail (printf "directRdpService.enabled is true but only %d entr(y/ies) are configured in directRdpService.perServiceSettings (or the legacy singular directRdpService.rdpAccessURL) while components.connectionProxy has %d replica(s). Each connection-proxy replica needs its own externally reachable RDP address: set directRdpService.perServiceSettings to a list with at least %d entries, ordinal-indexed (perServiceSettings[0] for pod ordinal 0, perServiceSettings[1] for ordinal 1, etc)." (len $entries) (int $cpReplicas) (int $cpReplicas)) -}}
    {{- end -}}
  {{- end -}}
  {{- range $i, $entry := $entries -}}
    {{- if not (hasKey $entry "rdpAccessURL") -}}
      {{- if $multiZone -}}
        {{- fail (printf "directRdpService.perServiceSettings has no rdpAccessURL for zone %q ordinal %d." $zoneName $i) -}}
      {{- else -}}
        {{- fail (printf "directRdpService.perServiceSettings[%d] is missing the required key rdpAccessURL." $i) -}}
      {{- end -}}
    {{- end -}}
    {{- if not (trim ($entry.rdpAccessURL | toString)) -}}
      {{- if $multiZone -}}
        {{- fail (printf "directRdpService.perServiceSettings has an empty rdpAccessURL for zone %q ordinal %d. Each connection-proxy replica needs its own non-empty externally reachable RDP address." $zoneName $i) -}}
      {{- else -}}
        {{- fail (printf "directRdpService.perServiceSettings[%d].rdpAccessURL is empty. Each connection-proxy replica needs its own non-empty externally reachable RDP address." $i) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
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
  Delegates to kasm.common.name (charts/kasm-common); see that chart's _helpers.tpl for the real
  implementation.
*/}}
{{- define "kasm.name" -}}
{{- include "kasm.common.name" . -}}
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
  Delegates to kasm.common.metadata (charts/kasm-common); see that chart's _helpers.tpl for the
  real implementation.
*/}}
{{- define "kasm.metadata" -}}
{{- include "kasm.common.metadata" . -}}
{{- end -}}

{{/*
Pod hardening/security settings
Usage:
  {{ include "kasm.securityContext" (list . 1000 pod) | nindent 6 }}
Where:
  index 1 = runAsUser/runAsGroup integer
  index 2 = context ("pod" or "container")
  Delegates to kasm.common.securityContext (charts/kasm-common); see that chart's _helpers.tpl for
  the real implementation.
*/}}
{{- define "kasm.securityContext" -}}
{{- include "kasm.common.securityContext" . -}}
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
    timingParent: Optional dict, used in place of the .Values.components.<component> lookup for components that
                don't live under .Values.components (e.g. observability.clickhouse, observability.collector).
                When supplied, timing resolves from: <timingParent>.healthCheckTiming.<probeType>, and both the
                "db" special-case and the "components" lookup are skipped entirely. Takes priority over timingScope.

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

  Delegates to health.common.probe (charts/kasm-common); see that chart's _helpers.tpl for the real
  implementation.
*/}}
{{- define "health.probe" -}}
{{- include "health.common.probe" . -}}
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

  Note: "otel-gateway" is 1 at every size and pinned there — kasm.observabilityValidate fails the
  render if components.otelGateway.replicas is set above 1. Every sender now talks to the gateway's
  ClusterIP Service directly; nothing partitions traces by ID in front of it, so a second replica
  would let tail_sampling see partial traces and silently drop spans.
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
  "connection-proxy" (dict
    "small" 1
    "medium" 2
    "large" 3
  )
  "otel-gateway" (dict
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
  Resolve and validate the top-level apiWorkerMode toggle.
  Usage: {{ include "kasm.apiWorkerMode" $.Values }}
  Fails if set to anything other than "combined" or "split".
*/}}
{{- define "kasm.apiWorkerMode" -}}
{{- $mode := default "combined" .apiWorkerMode -}}
{{- $allowed := list "combined" "split" -}}
{{- if not (has $mode $allowed) -}}
  {{- fail (printf "apiWorkerMode must be one of %s, got %q" (join ", " $allowed) $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end -}}

{{/*
  Resolve, normalize, and validate components.apiWorker.pools.
  Usage: {{ include "kasm.apiWorkerPools" $.Values | fromYamlArray }}
  Returns an empty YAML list in "combined" mode (pools are unused). In "split" mode, returns
  one entry per pool: {name, slug, queues, replicas, queueConcurrency, resources}, where slug is
  the pool name normalized via kasm.zoneName (mirrors how zone names get slugged into resource
  names) and replicas resolves the 0 = deploymentSize-preset convention using the "api" node's
  replicas.preset (worker pools are just API processes, so they share the api preset).
  Fails if: split mode with an empty pools list; any pool missing 'name'; two pools normalizing
  to the same slug.
*/}}
{{- define "kasm.apiWorkerPools" -}}
{{- $vals := . -}}
{{- $mode := include "kasm.apiWorkerMode" $vals -}}
{{- if eq $mode "split" -}}
  {{/*
    No client-side fallback here: values.yaml ships a non-empty default
    (components.apiWorker.pools: [{name: default, queues: all, replicas: 0}]), so an empty list
    at this point means the user explicitly emptied it, which is the "split with empty pools"
    failure below, not a signal to fall back to a built-in default.
  */}}
  {{- $awComponents := default dict (index $vals "components") -}}
  {{- $awComponent := default dict (index $awComponents "apiWorker") -}}
  {{- $pools := index $awComponent "pools" -}}
  {{- if not $pools -}}
    {{- fail "apiWorkerMode: split requires at least one entry in components.apiWorker.pools" -}}
  {{- end -}}
  {{- $seen := dict -}}
  {{- $result := list -}}
  {{- range $i, $p := $pools -}}
    {{- if not $p.name -}}
      {{- fail (printf "components.apiWorker.pools[%d] is missing required field 'name'" $i) -}}
    {{- end -}}
    {{- $slug := include "kasm.zoneName" $p.name -}}
    {{- if hasKey $seen $slug -}}
      {{- fail (printf "components.apiWorker.pools has duplicate normalized name %q (pool %q collides with an earlier pool)" $slug $p.name) -}}
    {{- end -}}
    {{- $_ := set $seen $slug true -}}
    {{- $poolReplicas := default 0 $p.replicas -}}
    {{- $replicas := ternary (int $poolReplicas) (include "replicas.preset" (dict "node" "api" "size" $vals.deploymentSize) | int) (gt (int $poolReplicas) 0) -}}
    {{- $entry := dict
        "name" $p.name
        "slug" $slug
        "queues" (default "all" $p.queues)
        "replicas" $replicas
        "queueConcurrency" (default dict $p.queueConcurrency)
        "resources" $p.resources
      -}}
    {{- $result = append $result $entry -}}
  {{- end -}}
  {{- toYaml $result -}}
{{- else -}}
  {{- toYaml (list) -}}
{{- end -}}
{{- end -}}

{{/*
  Return a resource request/limit object based on given presets
  Example usage:
  {{- include "resources.preset" (dict "node" "proxy" "size" "small" "context" .) -}}
*/}}
{{- define "resources.preset" }}
  {{- $context := default (dict) .context -}}
  {{- $zoneCount := len (default (list 1) (index $context "kasmZones")) -}}
  {{/*
    Extra Postgres connection headroom for split-mode worker pods. Each worker pod is a full API
    process (POSTGRES_POOL_SIZE 10 + POSTGRES_MAX_OVERFLOW 20 = 30 possible connections), running
    once per pool per zone, so headroom = 30 * (sum of every pool's replica count) * zoneCount.
    Zero in combined mode (no separate worker pods exist; the base preset already covers the api
    pods either way).
  */}}
  {{- $workerConnHeadroom := 0 -}}
  {{- range $p := (include "kasm.apiWorkerPools" $context | fromYamlArray) -}}
    {{- $workerConnHeadroom = add $workerConnHeadroom (mul (mul (int $p.replicas) $zoneCount) 30) -}}
  {{- end -}}
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
    "db-max-connections" (dict
      "small" (add 200 $workerConnHeadroom)
      "medium" (add (mul 400 $zoneCount) $workerConnHeadroom)
      "large" (add (mul 600 $zoneCount) $workerConnHeadroom)
    )
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
    "guac-processes" (dict "small" 4 "medium" 6 "large" 8)
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
    "connection-proxy-nginx" (dict
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
    "connection-proxy-guac" (dict
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
    "connection-proxy-rdp-gateway" (dict
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
    "connection-proxy-rdp-https-gateway" (dict
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
    "otel-gateway" (dict
      "small" (dict
        "requests" (dict "cpu" "300m" "memory" "512Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1" "memory" "1Gi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict
        "requests" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1" "memory" "2Gi" "ephemeral-storage" "2Gi")
      )
      "large" (dict
        "requests" (dict "cpu" "1" "memory" "2Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "2" "memory" "4Gi" "ephemeral-storage" "2Gi")
      )
    )
    "clickhouse" (dict
      "small" (dict
        "requests" (dict "cpu" "500m" "memory" "1Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "1" "memory" "2Gi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict
        "requests" (dict "cpu" "1" "memory" "2Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "2" "memory" "4Gi" "ephemeral-storage" "2Gi")
      )
      "large" (dict
        "requests" (dict "cpu" "2" "memory" "4Gi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "4" "memory" "8Gi" "ephemeral-storage" "2Gi")
      )
    )
    "otel-sidecar" (dict
      "small" (dict
        "requests" (dict "cpu" "100m" "memory" "128Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "200m" "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
      "medium" (dict
        "requests" (dict "cpu" "100m" "memory" "128Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "200m" "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
      "large" (dict
        "requests" (dict "cpu" "100m" "memory" "128Mi" "ephemeral-storage" "50Mi")
        "limits" (dict "cpu" "200m" "memory" "256Mi" "ephemeral-storage" "2Gi")
      )
    )
    "otel-gateway-tuning" (dict
      "small" (dict "limit_mib" 800 "spike_limit_mib" 200 "num_traces" 25000)
      "medium" (dict "limit_mib" 1600 "spike_limit_mib" 400 "num_traces" 50000)
      "large" (dict "limit_mib" 3200 "spike_limit_mib" 800 "num_traces" 100000)
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
- extraEnv:           deduped []corev1.EnvVar       (main container only, this round)
Dedup rules:
- Containers: by .name (component overrides global on same name)
- VolumeMounts: by "<name>|<mountPath>" (separate sets for init vs main)
- Volumes: by a stable synthetic key (secret/configmap/pvc/emptyDir/name)
- EnvVar: by .name (component overrides global on same name); each entry is passed through
  `tpl` against the root context before merging, so values can reference e.g. {{ .Release.Name }}
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
      "extraEnv"             (default (list) $root.Values.extraEnv)
    -}}
  {{- $componentLevel := dict
      "extraVolumes"         (default (list) $component.extraVolumes)
      "extraContainerMounts" (default (list) $component.extraVolumeMounts)
      "extraContainers"      (default (list) $component.extraContainers)
      "extraInitContainers"  (default (list) $component.extraInitContainers)
      "extraEnv"             (default (list) $component.extraEnv)
      "nginxSidecarVolumes"  (default (list) (dig "nginxSidecar" "extraVolumes" (list) $component))
      "nginxSidecarMounts"   (default (list) (dig "nginxSidecar" "extraVolumeMounts" (list) $component))
    -}}

  {{/* Build dedupe maps */}}
  {{- $volMap := dict -}}
  {{- range $v := get $global "extraVolumes" -}}
    {{- $_ := set $volMap (include "kasm.volumeKey" $v) $v -}}
  {{- end -}}
  {{- range $v := get $componentLevel "extraVolumes" -}}
    {{- $_ := set $volMap (include "kasm.volumeKey" $v) $v -}}
  {{- end -}}
  {{- range $v := get $componentLevel "nginxSidecarVolumes" -}}
    {{- $_ := set $volMap (include "kasm.volumeKey" $v) $v -}}
  {{- end -}}

  {{- $sidecarMountMap := dict -}}
  {{- range $mounts := get $componentLevel "nginxSidecarMounts" -}}
    {{- $_ := set $sidecarMountMap (include "kasm.mountKey" $mounts) $mounts -}}
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

  {{/*
    extraEnv order must be deterministic (sprig `values` on a map returns randomized Go map
    order, which would reshuffle the container env list on every render/upgrade). Scheme:
    global entries keep their values-order position unless a component entry overrides the
    same name, in which case that name is dropped from the global position and re-emitted at
    its component-list position instead. Ties within a single list (duplicate names) keep the
    first occurrence's position.
  */}}
  {{- $envMap := dict -}}
  {{- $envOrder := list -}}
  {{- $envSeen := dict -}}
  {{- $compEnvNames := dict -}}
  {{- range $e := get $componentLevel "extraEnv" -}}
    {{- if $e.name -}}
      {{- $_ := set $compEnvNames $e.name true -}}
    {{- end -}}
  {{- end -}}
  {{- range $e := get $global "extraEnv" -}}
    {{- if not $e.name -}} {{- fail "extraEnv entries must define 'name'" -}} {{- end -}}
    {{- $tplE := tpl ($e | toYaml) $root | fromYaml -}}
    {{- $_ := set $envMap $tplE.name $tplE -}}
    {{- if and (not (hasKey $compEnvNames $tplE.name)) (not (hasKey $envSeen $tplE.name)) -}}
      {{- $envOrder = append $envOrder $tplE.name -}}
      {{- $_ := set $envSeen $tplE.name true -}}
    {{- end -}}
  {{- end -}}
  {{- range $e := get $componentLevel "extraEnv" -}}
    {{- if not $e.name -}} {{- fail "extraEnv entries must define 'name'" -}} {{- end -}}
    {{- $tplE := tpl ($e | toYaml) $root | fromYaml -}}
    {{- $_ := set $envMap $tplE.name $tplE -}}
    {{- if not (hasKey $envSeen $tplE.name) -}}
      {{- $envOrder = append $envOrder $tplE.name -}}
      {{- $_ := set $envSeen $tplE.name true -}}
    {{- end -}}
  {{- end -}}
  {{- $envList := list -}}
  {{- range $n := $envOrder -}}
    {{- $envList = append $envList (get $envMap $n) -}}
  {{- end -}}

  {{/* Convert maps back to lists in a single object; emit YAML once */}}
  {{- $out := dict -}}
  {{- $_ := set $out "volumes"            (values $volMap) -}}
  {{- $_ := set $out "containerMounts"    (values $mainMountMap) -}}
  {{- $_ := set $out "initMounts"         (values $initMountMap) -}}
  {{- $_ := set $out "extraContainers"    (values $sidecarMap) -}}
  {{- $_ := set $out "extraInitContainers" (values $initCtrMap) -}}
  {{- $_ := set $out "nginxSidecarMounts" (values $sidecarMountMap) -}}
  {{- $_ := set $out "extraEnv"           $envList -}}
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

{{/*
  Shared OpenTelemetry SDK env block for Kasm service containers.
  Usage:
    {{- include "kasm.otelEnv" (dict "context" $ "serviceName" "kasm-api" "zone" $zone.name) | nindent 12 }}
  Where:
    context     = root context (.)
    serviceName = OTEL_SERVICE_NAME value, e.g. "kasm-api"
    zone        = (optional) zone name (from kasm.zones), recorded as the kasm.zone resource
                  attribute. Zones no longer select an endpoint: there is one cluster-wide gateway.
    sidecar     = (optional bool) set true for containers in a pod that runs a Collector sidecar
                  (Connection Proxy). Those export to the sidecar over loopback and the sidecar is the
                  pod's single egress point; everything else exports straight to the gateway Service.
    python      = (optional bool) set true for the Python services (api) to also emit
                  OTEL_PYTHON_EXCLUDED_URLS.
  Emits a YAML list fragment suitable for splicing into a container's `env:`.
*/}}
{{- define "kasm.otelEnv" -}}
{{- $ctx := .context -}}
{{- $obs := $ctx.Values.observability -}}
{{- $serviceName := required "kasm.otelEnv requires serviceName" .serviceName -}}
{{- if not $obs.enabled }}
- name: OTEL_SDK_DISABLED
  value: "true"
{{- else }}
{{- $constants := include "kasm.constants" $ctx | fromYaml -}}
{{- $zone := .zone | default "" -}}
{{- $endpoint := "" -}}
{{- $protocol := "" -}}
{{- if .sidecar -}}
  {{- $endpoint = printf "http://localhost:%v" $constants.otel.otlpHttp -}}
  {{- $protocol = "http/protobuf" -}}
{{- else -}}
  {{/* Every non-sidecar sender (Kasm app services) talks straight to the gateway (no forwarder
       tier between them), authenticated with the same bearer token the gateway's
       bearertokenauth/server extension checks. HTTP, not gRPC: the Kasm app SDKs are wired to
       the OTLP HTTP exporter (that choice lives in kasm_backend, not this chart), so the gateway
       exposes an authenticated HTTP receiver alongside the gRPC one the Collector sidecars use. */}}
  {{- $endpoint = printf "http://%s:%v" $constants.otel.gatewaySvc $constants.otel.otlpHttp -}}
  {{- $protocol = "http/protobuf" -}}
{{- end }}
- name: OTEL_SERVICE_NAME
  value: {{ $serviceName | quote }}
{{- if not .sidecar }}
- name: OTEL_BEARER_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ $constants.secrets.name }}
      key: otel-bearer-token
- name: OTEL_EXPORTER_OTLP_HEADERS
  value: "Authorization=Bearer $(OTEL_BEARER_TOKEN)"
{{- end }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ $endpoint | quote }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: {{ $protocol | quote }}
{{- if .python }}
- name: OTEL_PYTHON_EXCLUDED_URLS
  value: "socket.io/*,healthcheck"
{{- end }}
- name: OTEL_RESOURCE_ATTRIBUTES
  {{- if $zone }}
  value: {{ printf "deployment.environment=kubernetes,service.namespace=%s,kasm.zone=%s" $ctx.Release.Namespace (include "kasm.zoneName" $zone) | quote }}
  {{- else }}
  value: {{ printf "deployment.environment=kubernetes,service.namespace=%s" $ctx.Release.Namespace | quote }}
  {{- end }}
{{- end }}
{{- /*
  The logging vars below are emitted whether or not observability is enabled. They are not OTel
  settings: kasm_telemetry defaults log_file_enabled to TRUE, and init_logging() then does
  mkdir(parents=True) + opens the log file. With the chart's default readOnlyRootFilesystem and
  nothing mounted at /opt/kasm/current/log, that raises OSError and the container dies at startup.
  Gating these on observability.enabled would therefore make `observability.enabled: false`
  un-deployable.
*/ -}}
{{- include "kasm.loggingEnv" (dict "context" $ctx "serviceName" $serviceName "component" (.component | default "")) }}
{{- end }}

{{/*
  ClickHouse HTTP(S) endpoint Kasm (api) reads reports from.
  Usage:
    {{ include "kasm.clickhouseHttpEndpoint" (dict "context" $) }}
*/}}
{{- define "kasm.clickhouseHttpEndpoint" -}}
{{- $ctx := .context -}}
{{- $ch := $ctx.Values.observability.clickhouse -}}
{{- if $ch.standalone -}}
{{- $ch.httpEndpoint -}}
{{- else -}}
{{- $scheme := ternary "https" "http" $ch.tls -}}
{{- $port := ternary 8443 8123 $ch.tls -}}
{{- printf "%s://%s-clickhouse:%d" $scheme $ctx.Release.Name (int $port) -}}
{{- end -}}
{{- end -}}

{{/*
  ClickHouse native-protocol DSN the Collector writes telemetry to.
  Usage:
    {{ include "kasm.clickhouseNativeDsn" (dict "context" $) }}
*/}}
{{- define "kasm.clickhouseNativeDsn" -}}
{{- $ctx := .context -}}
{{- $ch := $ctx.Values.observability.clickhouse -}}
{{- if $ch.standalone -}}
  {{- if contains "://" $ch.nativeEndpoint -}}
    {{- $ch.nativeEndpoint -}}
  {{- else -}}
    {{- printf "tcp://%s" $ch.nativeEndpoint -}}
  {{- end -}}
{{- else -}}
{{- $port := ternary 9440 9000 $ch.tls -}}
{{- printf "tcp://%s-clickhouse:%d%s" $ctx.Release.Name (int $port) (ternary "?secure=true" "" $ch.tls) -}}
{{- end -}}
{{- end -}}

{{/*
  ClickHouse reporting read-path env vars for the Kasm api container.
  Emits nothing when observability is disabled, or when there is no store to read
  (clickhouse.enabled is false and standalone is false).
  Usage:
    {{- include "kasm.clickhouseEnv" (dict "context" $) | nindent 12 }}
*/}}
{{- define "kasm.clickhouseEnv" -}}
{{- $ctx := .context -}}
{{- $obs := $ctx.Values.observability -}}
{{- $ch := $obs.clickhouse -}}
{{- if and $obs.enabled (or $ch.standalone $ch.enabled) }}
{{- $constants := include "kasm.constants" $ctx | fromYaml -}}
{{- $endpoint := include "kasm.clickhouseHttpEndpoint" (dict "context" $ctx) -}}
{{- $secretName := default $constants.secrets.name $ch.existingSecret.name -}}
{{- $secretKey := default "clickhouse-password" $ch.existingSecret.key -}}
{{- /* api reads as the RO user when one is configured. An unset readUsername defaults to
     "kasm_otel_ro" when the chart manages ClickHouse (enabled && !standalone) — a stock install
     gets the read-only split without extra values. A standalone external ClickHouse has no
     RO user provisioned unless readUsername is set explicitly, so an unset value there falls
     back to the writer credential unchanged. */ -}}
{{- $readUser := $ch.readUsername -}}
{{- if not $readUser -}}
{{- if and $ch.enabled (not $ch.standalone) -}}
{{- $readUser = "kasm_otel_ro" -}}
{{- else -}}
{{- $readUser = $ch.username -}}
{{- end -}}
{{- end -}}
{{- $readSecretKey := $secretKey -}}
{{- if ne $readUser $ch.username }}
{{- if $ch.existingSecret.readKey }}
{{- $readSecretKey = $ch.existingSecret.readKey }}
{{- else if $ch.existingSecret.name }}
{{- $readSecretKey = $secretKey }}
{{- else }}
{{- $readSecretKey = "clickhouse-ro-password" }}
{{- end }}
{{- end -}}
- name: KASM_CLICKHOUSE_ENDPOINT
  value: {{ $endpoint | quote }}
- name: KASM_CLICKHOUSE_DATABASE
  value: {{ $ch.database | quote }}
- name: KASM_CLICKHOUSE_USER
  value: {{ $readUser | quote }}
- name: KASM_CLICKHOUSE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: {{ $readSecretKey }}
{{- if and (not $ch.standalone) $ch.tls }}
- name: KASM_CLICKHOUSE_CA_CERT
  value: /etc/ssl/certs/kasm_clickhouse.crt
{{- else if and $ch.standalone (or $ch.caCert $ch.caCertConfigMap) }}
- name: KASM_CLICKHOUSE_CA_CERT
  value: /etc/ssl/certs/kasm_clickhouse_ca.crt
{{- else if and $ch.standalone (not $ch.tlsVerify) }}
- name: KASM_CLICKHOUSE_VERIFY
  value: "false"
{{- end }}
{{- end }}
{{- end -}}

{{/*
  Render-time validation for the observability values tree. Call once from a template that
  always renders (called at the top of templates/otel-gateway-configmap.yaml).
  Usage:
    {{ include "kasm.observabilityValidate" $ }}
*/}}
{{- define "kasm.observabilityValidate" -}}
{{- $ctx := . -}}
{{- $obs := $ctx.Values.observability -}}
{{- $ch := $obs.clickhouse -}}
{{- $collector := $obs.collector -}}
{{- if $ch.standalone -}}
  {{- if or (not $ch.nativeEndpoint) (not $ch.httpEndpoint) -}}
    {{- fail "observability.clickhouse.standalone requires both observability.clickhouse.nativeEndpoint and observability.clickhouse.httpEndpoint to be set." -}}
  {{- end -}}
  {{- if not $ch.enabled -}}
    {{- fail "observability.clickhouse.standalone and observability.clickhouse.enabled=false are mutually exclusive: standalone already means 'use an external ClickHouse', while enabled=false means 'no ClickHouse store at all'." -}}
  {{- end -}}
{{- end -}}
{{- if and $ch.caCert $ch.caCertConfigMap -}}
  {{- fail "observability.clickhouse.caCert and observability.clickhouse.caCertConfigMap are mutually exclusive: caCert has the chart render a ConfigMap from literal PEM text, caCertConfigMap points at one you already manage." -}}
{{- end -}}
{{- /* Same default readUsername resolution as kasm.clickhouseEnv/clickhouse-configmap.yaml/
     clickhouse-statefulset.yaml: bundled ClickHouse defaults to kasm_otel_ro, external stays empty. */ -}}
{{- $effectiveReadUsername := $ch.readUsername -}}
{{- if and (not $effectiveReadUsername) $ch.enabled (not $ch.standalone) -}}
  {{- $effectiveReadUsername = "kasm_otel_ro" -}}
{{- end -}}
{{- if and $effectiveReadUsername (eq $effectiveReadUsername $ch.username) -}}
  {{- fail (printf "observability.clickhouse.readUsername (%q) must differ from observability.clickhouse.username (%q): ClickHouse's users.xml cannot define two users with the same name, and the second definition silently discards the read-only password." $effectiveReadUsername $ch.username) -}}
{{- end -}}
{{- $forwardSecretNameSet := ne $collector.gateway.forward.existingSecret.name "" -}}
{{- $forwardSecretKeySet := ne $collector.gateway.forward.existingSecret.key "" -}}
{{- if and (or $forwardSecretNameSet $forwardSecretKeySet) (not (and $forwardSecretNameSet $forwardSecretKeySet)) -}}
  {{- fail "observability.collector.gateway.forward.existingSecret requires both 'name' and 'key' to be set." -}}
{{- end -}}
{{- $chSecretNameSet := ne $ch.existingSecret.name "" -}}
{{- $chSecretKeySet := ne $ch.existingSecret.key "" -}}
{{- if and (or $chSecretNameSet $chSecretKeySet) (not (and $chSecretNameSet $chSecretKeySet)) -}}
  {{- fail "observability.clickhouse.existingSecret requires both 'name' and 'key' to be set." -}}
{{- end -}}
{{- if and (ne $ch.existingSecret.readKey "") (not $chSecretNameSet) -}}
  {{- fail "observability.clickhouse.existingSecret.readKey requires observability.clickhouse.existingSecret.name to also be set: readKey names a key inside that same Secret." -}}
{{- end -}}
{{- if or (lt (int $collector.gateway.tailSamplePercentage) 0) (gt (int $collector.gateway.tailSamplePercentage) 100) -}}
  {{- fail (printf "observability.collector.gateway.tailSamplePercentage must be between 0 and 100, got %d." (int $collector.gateway.tailSamplePercentage)) -}}
{{- end -}}
{{- /* observability.enabled with no destination and no BYO config means every span/log/metric
     the gateway receives is silently dropped. existingConfigMap is exempt: that config decides
     its own routing. */ -}}
{{- if and $obs.enabled (not $collector.gateway.existingConfigMap) (not (or $ch.enabled $ch.standalone)) (eq $collector.gateway.forward.endpoint "") -}}
  {{- fail "observability.enabled is true but the gateway has nowhere to send telemetry: set observability.clickhouse.enabled (or observability.clickhouse.standalone) to true, or set observability.collector.gateway.forward.endpoint to an external OTLP/HTTP endpoint." -}}
{{- end -}}
{{- /* Every sender exports straight to the gateway; nothing in front of it partitions traces by
     ID the way the removed forwarder's loadbalancing exporter did. A second replica would let
     tail_sampling see only some of a trace's spans and silently drop the rest. */ -}}
{{- if gt (int $ctx.Values.components.otelGateway.replicas) 1 -}}
  {{- fail (printf "components.otelGateway.replicas (%d) must be 0 (use the deploymentSize preset, always 1) or 1: every sender exports straight to the gateway, and nothing partitions traces by ID in front of it, so a second replica would make tail_sampling decide on partial traces and silently drop spans." (int $ctx.Values.components.otelGateway.replicas)) -}}
{{- end -}}
{{- end -}}

{{/*
  Compute a GOMEMLIMIT value (~80% of a Kubernetes memory limit quantity) so the Collector's Go
  runtime starts proactively GCing before memory_limiter has to act. Accepts the binary memory
  quantities (Mi/Gi suffixes) used by every resources.preset entry in this chart; any other
  suffix is treated as a plain Mi count.
  Usage:
    {{ include "kasm.gomemlimit" "512Mi" }}
*/}}
{{- define "kasm.gomemlimit" -}}
{{- $mem := . -}}
{{- $mib := 0.0 -}}
{{- if hasSuffix "Gi" $mem -}}
  {{- $mib = mulf (trimSuffix "Gi" $mem | float64) 1024 -}}
{{- else if hasSuffix "Mi" $mem -}}
  {{- $mib = trimSuffix "Mi" $mem | float64 -}}
{{- else -}}
  {{- $mib = $mem | float64 -}}
{{- end -}}
{{- printf "%dMiB" (int64 (mulf $mib 0.8)) -}}
{{- end -}}

{{/*
  Volume for the standalone-ClickHouse CA certificate, when configured. No-op for the bundled
  ClickHouse (which is trusted via the shared Kasm certificate, mounted separately) or when neither
  `caCert` nor `caCertConfigMap` is set.
  Usage:
    {{- include "kasm.clickhouseCaVolume" . | nindent 8 }}
*/}}
{{- define "kasm.clickhouseCaVolume" -}}
{{- $ch := .Values.observability.clickhouse -}}
{{- if and $ch.standalone (or $ch.caCert $ch.caCertConfigMap) }}
- name: clickhouse-ca-cert
  configMap:
    name: {{ $ch.caCertConfigMap | default (include "kasm.name" (list . "clickhouse-ca" "configmap")) }}
{{- end }}
{{- end -}}

{{/*
  Volume mount for the standalone-ClickHouse CA certificate, matching kasm.clickhouseCaVolume.
  Usage:
    {{- include "kasm.clickhouseCaVolumeMount" . | nindent 12 }}
*/}}
{{- define "kasm.clickhouseCaVolumeMount" -}}
{{- $ch := .Values.observability.clickhouse -}}
{{- if and $ch.standalone (or $ch.caCert $ch.caCertConfigMap) }}
- name: clickhouse-ca-cert
  mountPath: /etc/ssl/certs/kasm_clickhouse_ca.crt
  subPath: ca.crt
  readOnly: true
{{- end }}
{{- end -}}

{{/*
  Operator chain for the nginx JSON access log, ported (including overwrite_text: true) from
  kasm_backend/install/conf/otel/otel-collector-local.yaml. Used directly as the `operators:` list
  of the otel-sidecar's syslog/nginx_access receiver (otel-nginx-sidecar-configmap.yaml). nginx
  sends the JSON payload as the syslog message; the syslog receiver already lands it in
  attributes.message, so the chain's json_parser reads from there instead of body.
  Args (dict):
    context     = root context (.)
    serviceName = resource["service.name"]/attributes["application"] to stamp on every record
                  (e.g. "kasm-proxy", "kasm-connection-proxy")
  Usage:
    operators:
      {{- include "kasm.otelNginxAccessLogOperators" (dict "context" . "serviceName" "kasm-proxy") | nindent 8 }}

  Delegates to kasm.common.otelNginxAccessLogOperators (charts/kasm-common); see that chart's
  _helpers.tpl for the real implementation.
*/}}
{{- define "kasm.otelNginxAccessLogOperators" -}}
{{- include "kasm.common.otelNginxAccessLogOperators" . -}}
{{- end -}}

{{/*
  Operator chain for the nginx error log, ported from
  kasm_backend/install/conf/otel/otel-collector-local.yaml. See kasm.otelNginxAccessLogOperators
  for the serviceName arg this define shares and why parse_from targets attributes.message: nginx's
  syslog error_log keeps its own "date [level] pid#tid: message" text as the syslog message body, so
  the regex still matches, just against attributes.message instead of the file line.
  Args (dict):
    context     = root context (.)
    serviceName = resource["service.name"] to stamp on every record (e.g. "kasm-proxy",
                  "kasm-connection-proxy")
  Usage:
    operators:
      {{- include "kasm.otelNginxErrorLogOperators" (dict "context" . "serviceName" "kasm-proxy") | nindent 8 }}

  Delegates to kasm.common.otelNginxErrorLogOperators (charts/kasm-common); see that chart's
  _helpers.tpl for the real implementation.
*/}}
{{- define "kasm.otelNginxErrorLogOperators" -}}
{{- include "kasm.common.otelNginxErrorLogOperators" . -}}
{{- end -}}

{{/*
  Shared OTel Collector sidecar container. A sidecar runs in every pod whose telemetry can only be
  read from inside the pod, and is that pod's single egress point to the gateway:
    - Kasm Proxy and Connection Proxy (loopback syslog for nginx logs, plus stub_status metrics)
    - Kasm DB (PostgreSQL JSON log files on the data PVC)
  The caller is responsible for adding matching volumes to the pod spec:
    - a ConfigMap volume named "otel-sidecar-config" (the same name passed as .configMap)
    - an emptyDir volume named "otel-sidecar-tmp"
    - if volumeName/mountPath are given, that log volume already mounted (read-write) into the
      primary container — omit both for callers with no file-based logs to read (the nginx sidecars,
      which receive everything over loopback syslog/OTLP)
  Optional args:
    uid         = uid/gid to run as (default 10001, the collector image's user). The DB sidecar must
                  run as 70: PostgreSQL writes its log files 0600 owned by the postgres user, so any
                  other uid cannot read them.
    zone        = zone name (from kasm.zones), recorded as the kasm.zone resource attribute.
    serviceName = OTEL_SERVICE_NAME to report resource attributes under (e.g. "kasm-db"). Omit for
                  callers whose collector config already hardcodes the service name (the nginx
                  operator chains set resource["service.name"]=kasm-proxy themselves).
    volumeName/mountPath = a file-based log volume to mount read-only into the sidecar. Omit both
                  if the sidecar has no files to read (see above).
    subPath     = (optional) subPath for the log volume mount, for callers whose logs live inside a
                  larger volume (the DB PVC).
    extraVolumeMounts = (optional) YAML list of additional mounts, e.g. the DB sidecar's checkpoint
                  directory on the data PVC.
  Usage:
    {{- include "kasm.otelSidecar" (dict "context" $ "configMap" "my-cm" "volumeName" "my-logs" "mountPath" "/var/log/postgres") | nindent 8 }}
*/}}
{{- define "kasm.otelSidecar" -}}
{{- $ctx := .context -}}
{{- $volumeName := .volumeName -}}
{{- $mountPath := .mountPath -}}
{{- $constants := include "kasm.constants" $ctx | fromYaml -}}
{{- $zone := .zone | default "" -}}
{{- $uid := .uid | default 10001 -}}
{{/* This container's own exported config (kasm.common.otelOtlpExporterToGateway) forwards to the
     gateway over OTLP/gRPC, authenticated with the same bearer token the gateway's
     bearertokenauth/server extension checks. */}}
{{- $endpoint := printf "%s:%v" $constants.otel.gatewaySvc $constants.otel.otlpGrpc -}}
- name: otel-sidecar
  image: {{ $constants.otel.sidecarImage }}
  imagePullPolicy: {{ $ctx.Values.imagePullPolicy }}
  {{- include "kasm.securityContext" (list $ctx $uid "container") | nindent 2 }}
  env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: {{ $endpoint | quote }}
    - name: OTEL_BEARER_TOKEN
      valueFrom:
        secretKeyRef:
          name: {{ $constants.secrets.name }}
          key: otel-bearer-token
    {{- if .serviceName }}
    - name: OTEL_SERVICE_NAME
      value: {{ .serviceName | quote }}
    {{- end }}
    {{/* No OTEL_RESOURCE_ATTRIBUTES here: it's an SDK env var the Collector binary does not apply
         to pipeline data (see kasm.common.otelResourceProcessor). POD_NAME above and this zone var
         feed that processor's ${env:} expansion instead. */}}
    {{- if $zone }}
    - name: OTEL_KASM_ZONE
      value: {{ include "kasm.zoneName" $zone | quote }}
    {{- end }}
  {{- if $ctx.Values.components.otelSidecar.resources }}
  resources: {{- toYaml $ctx.Values.components.otelSidecar.resources | nindent 4 }}
  {{- else }}
  resources: {{- include "resources.preset" (dict "node" "otel-sidecar" "size" $ctx.Values.deploymentSize) | nindent 4 }}
  {{- end }}
  volumeMounts:
    {{- if $volumeName }}
    - name: {{ $volumeName }}
      mountPath: {{ $mountPath }}
      {{- with .subPath }}
      subPath: {{ . }}
      {{- end }}
      readOnly: true
    {{- end }}
    - name: otel-sidecar-config
      mountPath: /etc/otelcol-contrib/config.yaml
      subPath: config.yaml
    - name: otel-sidecar-tmp
      mountPath: /tmp
    {{- with .extraVolumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- if $ctx.Values.applyHealthChecks }}
  livenessProbe:
    {{- include "health.probe" (dict "root" $ctx "component" "otel-sidecar" "probeType" "livenessProbe" "type" "http" "path" "/" "port" 13133) | nindent 4 }}
  readinessProbe:
    {{- include "health.probe" (dict "root" $ctx "component" "otel-sidecar" "probeType" "readinessProbe" "type" "http" "path" "/" "port" 13133) | nindent 4 }}
  {{- end }}
{{- end -}}

{{/*
  kasm_telemetry logging env. Emitted regardless of observability.enabled: log_file_enabled
  defaults to TRUE in the library and init_logging() mkdirs the path, which fails on the chart's
  readOnlyRootFilesystem. Every workload running Kasm python needs this, Jobs included.
  Usage:
    {{- include "kasm.loggingEnv" (dict "context" $ "serviceName" "kasm-api" "component" "api") | nindent 12 }}
*/}}
{{- define "kasm.loggingEnv" -}}
{{- $ctx := .context -}}
{{- $obs := $ctx.Values.observability -}}
{{- $serviceName := required "kasm.loggingEnv requires serviceName" .serviceName -}}
{{- /*
  File logging is always off. Kasm services export their logs over OTLP, so a second, file-shaped
  copy inside the pod would only store every line twice; the sidecars exist for nginx and PostgreSQL,
  which cannot export OTLP themselves.
*/}}
- name: KASM_LOG_FILE_ENABLED
  value: "false"
- name: KASM_LOG_CONSOLE_COLOR
  value: "false"
{{- end }}
