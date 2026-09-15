{{/*
  Cross-value validation for the ways this chart publishes its Services.

  These checks live here, not in the templates they constrain, because they are
  n-way: the Kasm proxy can be published four ways (Ingress, OpenShift Route,
  Gateway API HTTPRoute, Gateway API TLSRoute) plus the Service itself, and the
  RDP Gateway two (a LoadBalancer/NodePort Service, or a Gateway API TCPRoute).
  Held in the individual templates, every rule would have to be repeated in
  every template it touches.

  Invoked once from validation.yaml, which renders no manifest of its own.

  Two messages below are reproduced verbatim from the templates they moved out
  of, because they are asserted by tests/negative_validation_test.yaml and have
  been user-facing since before the Gateway API options existed.
*/}}

{{/*
  Zone list consistency. Zones sharing one region_name deploy to one cluster
  (kasm.isInPrimaryRegion groups them for the session-plane fan-out), so a
  seedOnly zone in a deployed zone's region is a contradiction: it would be
  silently dropped from that fan-out instead of deployed alongside its region.
*/}}
{{- define "kasm.validateZones" -}}
{{- $zones := (include "kasm.configuredZones" . | fromYamlArray) | default list -}}
{{- range $zone := $zones -}}
  {{- if and (dig "seedOnly" false $zone) $zone.region_name -}}
    {{- range $other := $zones -}}
      {{- if and (not (dig "seedOnly" false $other)) $other.region_name (eq $other.region_name $zone.region_name) -}}
        {{- fail (printf "kasmZones[%s] is marked 'seedOnly: true' but shares region_name %q with deployed zone %q. Zones in one region deploy to one cluster: remove 'seedOnly: true' from %s, or give it a different region_name." $zone.name $zone.region_name $other.name $zone.name) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "kasm.validateExposure" -}}
{{- $v := .Values -}}
{{- include "kasm.validateZones" . -}}

{{- if and $v.ingress.enabled $v.route.enabled -}}
  {{- fail "The ingress.enabled and route.enabled cannot both be set. Either configure an Ingress or an OpenShift Route, not both." -}}
{{- end -}}

{{- $proxyExposure := list -}}
{{- if $v.ingress.enabled -}}{{- $proxyExposure = append $proxyExposure "ingress.enabled" -}}{{- end -}}
{{- if $v.route.enabled -}}{{- $proxyExposure = append $proxyExposure "route.enabled" -}}{{- end -}}
{{- if $v.httpRoute.enabled -}}{{- $proxyExposure = append $proxyExposure "httpRoute.enabled" -}}{{- end -}}
{{- if $v.tlsRoute.enabled -}}{{- $proxyExposure = append $proxyExposure "tlsRoute.enabled" -}}{{- end -}}
{{- if gt (len $proxyExposure) 1 -}}
  {{- fail (printf "Only one proxy exposure method may be enabled, but %s are set. The Ingress, the OpenShift Route, the Gateway API HTTPRoute and the Gateway API TLSRoute all publish the same Kasm proxy Service, so enabling more than one gives the same hostname two owners." (join " and " $proxyExposure)) -}}
{{- end -}}

{{- if and (or $v.ingress.enabled $v.route.enabled) (eq $v.proxyService.type "LoadBalancer") -}}
  {{- fail "The service.type must not be LoadBalancer when using an ingress or a route - any load balancer or Route should be provisioned using the Ingress/Route settings. Set service.type=ClusterIP or mark ingress.enabled or route.enabled to disabled." -}}
{{- end -}}
{{- if and (or $v.httpRoute.enabled $v.tlsRoute.enabled) (eq $v.proxyService.type "LoadBalancer") -}}
  {{- fail "The proxyService.type must not be LoadBalancer when the proxy is published through the Gateway API - the Gateway owns the external address. Set proxyService.type=ClusterIP, or disable httpRoute.enabled / tlsRoute.enabled." -}}
{{- end -}}
{{- if and (eq $v.proxyService.type "LoadBalancer") $v.kasmZones -}}
  {{- fail "The service.type must not be LoadBalancer when using a Multi-Zone Kasm deployment - any load balancer or Route should be provisioned using the Ingress/Route settings. Set service.type=ClusterIP or remove your kasmZones settings." -}}
{{- end -}}

{{/* NodePort publishes the proxy externally exactly as LoadBalancer does, so it carries
     the same two restrictions. Separate messages, because the LoadBalancer wording above
     predates NodePort being renderable at all. */}}
{{- if and (eq $v.proxyService.type "NodePort") (or $v.ingress.enabled $v.route.enabled $v.httpRoute.enabled $v.tlsRoute.enabled) -}}
  {{- fail "proxyService.type must not be NodePort when an Ingress, OpenShift Route or Gateway API route already publishes the proxy - that would be a second door onto the same Service carrying none of the front end's TLS, timeouts or host routing. Set proxyService.type=ClusterIP, or disable the front end." -}}
{{- end -}}
{{- if and (eq $v.proxyService.type "NodePort") $v.kasmZones -}}
  {{- fail "proxyService.type must not be NodePort in a Multi-Zone deployment: a node port cannot route by hostname, so each zone would be unreachable. Use an Ingress, an OpenShift Route or the Gateway API, with proxyService.type=ClusterIP." -}}
{{- end -}}

{{- if and $v.httpRoute.enabled (not $v.httpRoute.parentRefs) -}}
  {{- fail "httpRoute.enabled is set but httpRoute.parentRefs is empty - the route would attach to no Gateway, and the proxy would stay unreachable from outside the cluster." -}}
{{- end -}}
{{- if and $v.tlsRoute.enabled (not $v.tlsRoute.parentRefs) -}}
  {{- fail "tlsRoute.enabled is set but tlsRoute.parentRefs is empty - the route would attach to no Gateway, and the proxy would stay unreachable from outside the cluster." -}}
{{- end -}}

{{- include "kasm.validateRdpExposure" . -}}
{{- include "kasm.validateUpstreamAuthExposure" . -}}
{{- end -}}

{{/*
  Upstream auth (management) endpoint publication. Deliberately independent of the
  front-door exposure rules above: the whole point of the endpoint is to ride a
  separate data path (front-door Ingress for users plus an internal upstreamAuth
  LoadBalancer for agents is the headline combination), so the only mutual
  exclusion is among the upstreamAuth publishers themselves. Missing per-zone
  hostnames fail inside the publisher templates via
  kasm.zoneUpstreamAuthAddressRequired, mirroring the front door.
*/}}
{{- define "kasm.validateUpstreamAuthExposure" -}}
{{- $ua := .Values.upstreamAuth -}}

{{- $uaExposure := list -}}
{{- if $ua.service.enabled -}}{{- $uaExposure = append $uaExposure "upstreamAuth.service.enabled" -}}{{- end -}}
{{- if $ua.ingress.enabled -}}{{- $uaExposure = append $uaExposure "upstreamAuth.ingress.enabled" -}}{{- end -}}
{{- if $ua.route.enabled -}}{{- $uaExposure = append $uaExposure "upstreamAuth.route.enabled" -}}{{- end -}}
{{- if $ua.httpRoute.enabled -}}{{- $uaExposure = append $uaExposure "upstreamAuth.httpRoute.enabled" -}}{{- end -}}
{{- if $ua.tlsRoute.enabled -}}{{- $uaExposure = append $uaExposure "upstreamAuth.tlsRoute.enabled" -}}{{- end -}}
{{- if gt (len $uaExposure) 1 -}}
  {{- fail (printf "Only one upstream auth exposure method may be enabled, but %s are set. The Service, the Ingress, the OpenShift Route, the Gateway API HTTPRoute and the Gateway API TLSRoute all publish the same upstream auth endpoint, so enabling more than one gives the same hostname two owners." (join " and " $uaExposure)) -}}
{{- end -}}

{{- if and $ua.httpRoute.enabled (not (or $ua.httpRoute.parentRefs $ua.httpRoute.zones)) -}}
  {{- fail "upstreamAuth.httpRoute.enabled is set but neither upstreamAuth.httpRoute.parentRefs nor upstreamAuth.httpRoute.zones is populated - the routes would attach to no Gateway, and the upstream auth endpoint would stay unreachable from outside the cluster." -}}
{{- end -}}
{{- if and $ua.tlsRoute.enabled (not (or $ua.tlsRoute.parentRefs $ua.tlsRoute.zones)) -}}
  {{- fail "upstreamAuth.tlsRoute.enabled is set but neither upstreamAuth.tlsRoute.parentRefs nor upstreamAuth.tlsRoute.zones is populated - the routes would attach to no Gateway, and the upstream auth endpoint would stay unreachable from outside the cluster." -}}
{{- end -}}

{{- $deployedZones := (include "kasm.deployedZones" . | fromYamlArray) -}}

{{- if and $ua.service.enabled (eq $ua.service.type "NodePort") $ua.service.nodePort (gt (len $deployedZones) 1) -}}
  {{- fail (printf "upstreamAuth.service.nodePort is pinned but %d zones deploy in this cluster, and every zone's upstream auth Service would claim the same node port. Remove the pin, or deploy a single zone per cluster." (len $deployedZones)) -}}
{{- end -}}

{{/* One hostname, one owner: two zones resolving to the same upstream auth
     address would give one host two backends (undefined routing on the L7
     publishers, wrong zone registration everywhere). */}}
{{- if $uaExposure -}}
  {{- $seen := dict -}}
  {{- range $zone := $deployedZones -}}
    {{- $address := include "kasm.zoneUpstreamAuthAddress" (list $ $zone) -}}
    {{- if $address -}}
      {{- if hasKey $seen $address -}}
        {{- fail (printf "kasmZones[%s] and kasmZones[%s] both resolve their upstream auth address to %q. Every deployed zone needs its own address, since each routes to its own proxy Service." (get $seen $address) $zone.name $address) -}}
      {{- end -}}
      {{- $seen = set $seen $address $zone.name -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}


{{/*
  RDP Gateway publication. The rdp-gateway app runs inside the connection-proxy
  StatefulSet, and every replica has to advertise its own externally reachable
  address: directRdpService does that with one Service per replica. A TCPRoute
  matches on neither hostname nor SNI, so it cannot tell replicas apart, and
  unlike the proxy's HTTPRoute it cannot multiplex zones onto one listener
  either: tcpRoute therefore requires exactly one connection-proxy replica per
  zone, targets that replica's per-pod RDP Service, and needs a Gateway
  listener of its own per zone, selected with parentRefs[].sectionName.
  directRdpService's own checks (entry count versus replicas, the legacy
  singular URL) live in connection-proxy-services.yaml.
*/}}
{{- define "kasm.validateRdpExposure" -}}
{{- $v := .Values -}}

{{/* directRdpService's own rules (perServiceSettings shape, entry counts, legacy
     rdpAccessURL restrictions) live in kasm.directRdpServiceValidateZone, invoked
     from connection-proxy-services.yaml. Only the tcpRoute rules live here. */}}
{{- if $v.tcpRoute.enabled -}}

  {{- if not (and $v.components.connectionProxy.enabled $v.components.connectionProxy.rdpGateway.enabled) -}}
    {{- fail "tcpRoute.enabled publishes the RDP Gateway, but components.connectionProxy.enabled or components.connectionProxy.rdpGateway.enabled is false. Enable the component, or disable tcpRoute." -}}
  {{- end -}}

  {{- if $v.directRdpService.enabled -}}
    {{- fail "tcpRoute.enabled and directRdpService.enabled both publish the RDP Gateway externally. Set directRdpService.enabled=false: the per-replica RDP Service stays ClusterIP and the Gateway fronts it through the TCPRoute." -}}
  {{- end -}}

  {{- if not $v.tcpRoute.rdpAccessURL -}}
    {{- fail "tcpRoute.rdpAccessURL must be set if tcpRoute.enabled is true - it is the hostname Kasm advertises to RDP clients, and the RDP Gateway has no way to infer it from the Gateway." -}}
  {{- end -}}

  {{/* tcpRoute advertises ONE hostname (per zone), so only one rdp-gateway instance
       per zone can register it. connection-proxy scales 1/2/3 by deploymentSize; a
       TCPRoute cannot fan per-replica hostnames out the way perServiceSettings does. */}}
  {{- $constants := include "kasm.constants" . | fromYaml -}}
  {{- $cp := $v.components.connectionProxy -}}
  {{- $cpReplicas := ternary $cp.replicas (include "replicas.preset" (dict "node" $constants.connectionProxy.component "size" $v.deploymentSize)) (gt (int $cp.replicas) 0) -}}
  {{- if gt (int $cpReplicas) 1 -}}
    {{- fail (printf "tcpRoute.enabled advertises a single RDP hostname, but components.connectionProxy resolves to %d replicas - every replica would register the same address. Set components.connectionProxy.replicas=1, or publish per-replica addresses with directRdpService.perServiceSettings instead of the TCPRoute." (int $cpReplicas)) -}}
  {{- end -}}

  {{- $zones := (include "kasm.primaryRegionZones" . | fromYamlArray) -}}
  {{- if gt (len $zones) 1 -}}
    {{- $configured := dict -}}
    {{- range $z := $v.tcpRoute.zones -}}
      {{- $configured = set $configured $z.name true -}}
    {{- end -}}
    {{- $missing := list -}}
    {{- range $z := $zones -}}
      {{- if not (hasKey $configured $z.name) -}}
        {{- $missing = append $missing $z.name -}}
      {{- end -}}
    {{- end -}}
    {{- if $missing -}}
      {{- fail (printf "tcpRoute.zones has no entry for zone(s) %s. A TCPRoute matches on neither hostname nor SNI, so the zones cannot share one Gateway listener: give every zone its own entry, using parentRefs[].sectionName to select that zone's listener." (join ", " $missing)) -}}
    {{- end -}}
  {{- else if not (or $v.tcpRoute.parentRefs $v.tcpRoute.zones) -}}
    {{- fail "tcpRoute.enabled is set but neither tcpRoute.parentRefs nor tcpRoute.zones is populated - the route would attach to no Gateway." -}}
  {{- end -}}

{{- end -}}
{{- end -}}


