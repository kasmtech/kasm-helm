{{/*
  Cross-value validation for the ways this chart publishes its front-door proxy
  and the upstream auth (management) endpoint. These checks are n-way (four
  front-door publishers, five upstream auth publishers), so they live here
  instead of being repeated across every template they constrain.

  Invoked once from validation.yaml, which renders no manifest of its own.
*/}}

{{- define "kasm.validateFrontDoorExposure" -}}
{{- $v := .Values -}}

{{- $proxyExposure := list -}}
{{- if $v.ingress.enabled -}}{{- $proxyExposure = append $proxyExposure "ingress.enabled" -}}{{- end -}}
{{- if $v.route.enabled -}}{{- $proxyExposure = append $proxyExposure "route.enabled" -}}{{- end -}}
{{- if $v.httpRoute.enabled -}}{{- $proxyExposure = append $proxyExposure "httpRoute.enabled" -}}{{- end -}}
{{- if $v.tlsRoute.enabled -}}{{- $proxyExposure = append $proxyExposure "tlsRoute.enabled" -}}{{- end -}}
{{/* The plain ingress+route combination is already caught by route.yaml's own
     inline check, with the same wording tests/negative_validation_test.yaml
     pins to that template; only fire here for combinations involving one of
     the two Gateway API routes, which have no inline check of their own. */}}
{{- if and (gt (len $proxyExposure) 1) (or $v.httpRoute.enabled $v.tlsRoute.enabled) -}}
  {{- fail (printf "Only one proxy exposure method may be enabled, but %s are set. The Ingress, the OpenShift Route, the Gateway API HTTPRoute and the Gateway API TLSRoute all publish the same Kasm proxy Service, so enabling more than one gives the same hostname two owners." (join " and " $proxyExposure)) -}}
{{- end -}}

{{- if and $v.httpRoute.enabled (not $v.httpRoute.parentRefs) -}}
  {{- fail "httpRoute.enabled is set but httpRoute.parentRefs is empty - the route would attach to no Gateway, and the proxy would stay unreachable from outside the cluster." -}}
{{- end -}}
{{- if and $v.tlsRoute.enabled (not $v.tlsRoute.parentRefs) -}}
  {{- fail "tlsRoute.enabled is set but tlsRoute.parentRefs is empty - the route would attach to no Gateway, and the proxy would stay unreachable from outside the cluster." -}}
{{- end -}}

{{- if and (or $v.httpRoute.enabled $v.tlsRoute.enabled) (eq $v.proxyService.type "LoadBalancer") -}}
  {{- fail "The proxyService.type must not be LoadBalancer when the proxy is published through the Gateway API - the Gateway owns the external address. Set proxyService.type=ClusterIP, or disable httpRoute.enabled / tlsRoute.enabled." -}}
{{- end -}}
{{- end -}}

{{/*
  RDP Gateway publication via tcpRoute, as an alternative to directRdpService. A
  TCPRoute matches on neither hostname nor SNI, so - unlike httpRoute - it cannot
  multiplex zones onto one listener: every primary-region zone needs its own
  entry in tcpRoute.zones, selected with parentRefs[].sectionName.
*/}}
{{- define "kasm.validateRdpExposure" -}}
{{- $v := .Values -}}
{{- if $v.tcpRoute.enabled -}}

{{- if $v.directRdpService.enabled -}}
  {{- fail "tcpRoute.enabled and directRdpService.enabled both publish the RDP Gateway externally. Set directRdpService.enabled=false: the RDP Gateway Service stays ClusterIP and the Gateway fronts it through the TCPRoute." -}}
{{- end -}}

{{- if not $v.components.rdpGateway.enabled -}}
  {{- fail "tcpRoute.enabled is set but components.rdpGateway.enabled is false - the TCPRoute would have no RDP Gateway Service to route to. Set components.rdpGateway.enabled=true, or disable tcpRoute.enabled." -}}
{{- end -}}

{{- $zones := (include "kasm.primaryRegionZones" . | fromYamlArray) -}}
{{- $zoneNames := dict -}}
{{- range $z := $zones -}}{{- $zoneNames = set $zoneNames $z.name true -}}{{- end -}}

{{/* The unknown-zone membership check below is deliberately against ALL
     deployed zones (kasm.zones), not just primary-region ones: an entry
     naming a real zone in another region is valid and simply ignored below
     (tcproute.yaml only ranges over primary-region zones), matching how the
     upstreamAuth guard treats the same situation. Only a typo'd or
     never-deployed zone name is an error. */}}
{{- $allZones := (include "kasm.zones" . | fromYamlArray) -}}
{{- $allZoneNames := dict -}}
{{- range $z := $allZones -}}{{- $allZoneNames = set $allZoneNames $z.name true -}}{{- end -}}

{{/* Same override-map construction tcproute.yaml uses to resolve each zone's
     effective parentRefs, plus guards tcproute.yaml has no reason to carry
     itself: an entry naming a zone that isn't deployed, or naming the same
     zone twice, silently renders one fewer TCPRoute than expected. */}}
{{- $zoneRefs := dict -}}
{{- $seenZoneEntry := dict -}}
{{- range $z := $v.tcpRoute.zones -}}
  {{- if not (hasKey $allZoneNames $z.name) -}}
    {{- fail (printf "tcpRoute.zones has an entry for zone %q, but no deployed zone has that name. Check kasmZones for the correct name, or remove this entry." $z.name) -}}
  {{- end -}}
  {{- if hasKey $seenZoneEntry $z.name -}}
    {{- fail (printf "tcpRoute.zones has more than one entry for zone %q - each zone may appear once." $z.name) -}}
  {{- end -}}
  {{- $seenZoneEntry = set $seenZoneEntry $z.name true -}}
  {{- $zoneRefs = set $zoneRefs $z.name $z.parentRefs -}}
{{- end -}}

{{- if gt (len $zones) 1 -}}
  {{- $missing := list -}}
  {{- range $z := $zones -}}
    {{- if not (hasKey $zoneRefs $z.name) -}}
      {{- $missing = append $missing $z.name -}}
    {{- end -}}
  {{- end -}}
  {{- if $missing -}}
    {{- fail (printf "tcpRoute.zones has no entry for zone(s) %s. A TCPRoute matches on neither hostname nor SNI, so the zones cannot share one Gateway listener: give every zone its own entry, using parentRefs[].sectionName to select that zone's listener." (join ", " $missing)) -}}
  {{- end -}}
{{- else if not (or $v.tcpRoute.parentRefs $v.tcpRoute.zones) -}}
  {{- fail "tcpRoute.enabled is set but neither tcpRoute.parentRefs nor tcpRoute.zones is populated - the route would attach to no Gateway." -}}
{{- end -}}

{{/* Resolve each zone's EFFECTIVE refs exactly as tcproute.yaml does (per-zone
     override, else the global fallback) and fail if any zone would still
     render with an empty parentRefs - an entry can be present above yet carry
     an empty list, or fall through to a global that is itself empty. */}}
{{- $empty := list -}}
{{- range $z := $zones -}}
  {{- $refs := (get $zoneRefs $z.name) | default $v.tcpRoute.parentRefs -}}
  {{- if not $refs -}}
    {{- $empty = append $empty $z.name -}}
  {{- end -}}
{{- end -}}
{{- if $empty -}}
  {{- fail (printf "tcpRoute resolves to empty parentRefs for zone(s) %s - neither a per-zone override nor tcpRoute.parentRefs is populated, so the TCPRoute would attach to no Gateway." (join ", " $empty)) -}}
{{- end -}}

{{- end -}}
{{- end -}}

{{/*
  Upstream auth (management) endpoint publication. Deliberately independent of
  the front-door exposure rules above: the whole point of the endpoint is to
  ride a separate data path, so the only mutual exclusion is among the
  upstreamAuth publishers themselves. Missing per-zone hostnames fail inside the
  publisher templates via kasm.zoneUpstreamAuthAddressRequired, mirroring the
  front door.
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

{{- $zones := (include "kasm.zones" . | fromYamlArray) -}}
{{- $zoneNames := dict -}}
{{- range $z := $zones -}}{{- $zoneNames = set $zoneNames $z.name true -}}{{- end -}}

{{/* Resolve each route kind's EFFECTIVE parentRefs exactly as
     upstream-auth-httproute.yaml / upstream-auth-tlsroute.yaml do (per-zone
     override, else the global fallback), rejecting overrides that name no
     deployed zone or repeat a zone, and failing if any zone would still
     render with empty parentRefs. */}}
{{- range $kind, $route := (dict "httpRoute" $ua.httpRoute "tlsRoute" $ua.tlsRoute) -}}
{{- if $route.enabled -}}
  {{- $zoneRefs := dict -}}
  {{- $seenZoneEntry := dict -}}
  {{- range $z := $route.zones -}}
    {{- if not (hasKey $zoneNames $z.name) -}}
      {{- fail (printf "upstreamAuth.%s.zones has an entry for zone %q, but no deployed zone has that name. Check kasmZones for the correct name, or remove this entry." $kind $z.name) -}}
    {{- end -}}
    {{- if hasKey $seenZoneEntry $z.name -}}
      {{- fail (printf "upstreamAuth.%s.zones has more than one entry for zone %q - each zone may appear once." $kind $z.name) -}}
    {{- end -}}
    {{- $seenZoneEntry = set $seenZoneEntry $z.name true -}}
    {{- $zoneRefs = set $zoneRefs $z.name $z.parentRefs -}}
  {{- end -}}
  {{- $empty := list -}}
  {{- range $z := $zones -}}
    {{- $refs := (get $zoneRefs $z.name) | default $route.parentRefs -}}
    {{- if not $refs -}}
      {{- $empty = append $empty $z.name -}}
    {{- end -}}
  {{- end -}}
  {{- if $empty -}}
    {{- fail (printf "upstreamAuth.%s resolves to empty parentRefs for zone(s) %s - neither a per-zone override nor upstreamAuth.%s.parentRefs is populated, so the route would attach to no Gateway." $kind (join ", " $empty) $kind) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- if and $ua.service.enabled $ua.service.nodePort (ne $ua.service.type "NodePort") -}}
  {{- fail (printf "upstreamAuth.service.nodePort is set but upstreamAuth.service.type is %q, not NodePort. Either set upstreamAuth.service.type=NodePort or clear the nodePort pin." $ua.service.type) -}}
{{- end -}}

{{- if and $ua.service.enabled (eq $ua.service.type "NodePort") $ua.service.nodePort (gt (len $zones) 1) -}}
  {{- fail (printf "upstreamAuth.service.nodePort is pinned but %d zones deploy in this cluster, and every zone's upstream auth Service would claim the same node port. Remove the pin, or deploy a single zone per cluster." (len $zones)) -}}
{{- end -}}

{{/* One hostname, one owner: two zones resolving to the same upstream auth
     address would give one host two backends. */}}
{{- if $uaExposure -}}
  {{- $seen := dict -}}
  {{- range $zone := $zones -}}
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
