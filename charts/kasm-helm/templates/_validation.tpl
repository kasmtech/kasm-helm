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

{{- define "kasm.validateExposure" -}}
{{- $v := .Values -}}

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
{{- end -}}


{{/*
  RDP Gateway publication. A TCPRoute matches on neither hostname nor SNI, so
  unlike the proxy's HTTPRoute it cannot multiplex zones onto one listener:
  every zone needs a Gateway listener of its own, selected per zone with
  parentRefs[].sectionName.
*/}}
{{- define "kasm.validateRdpExposure" -}}
{{- $v := .Values -}}

{{- if and $v.directRdpService.enabled (not $v.directRdpService.rdpAccessURL) -}}
  {{- fail "directRdpService.rdpAccessURL must be set if directRdpService.enabled is true." -}}
{{- end -}}

{{- if $v.tcpRoute.enabled -}}

  {{- if not $v.components.rdpGateway.enabled -}}
    {{- fail "tcpRoute.enabled publishes the RDP Gateway, but components.rdpGateway.enabled is false. Enable the component, or disable tcpRoute." -}}
  {{- end -}}

  {{- if $v.directRdpService.enabled -}}
    {{- fail "tcpRoute.enabled and directRdpService.enabled both publish the RDP Gateway externally. Set directRdpService.enabled=false: the RDP Gateway Service stays ClusterIP and the Gateway fronts it through the TCPRoute." -}}
  {{- end -}}

  {{- if not $v.tcpRoute.rdpAccessURL -}}
    {{- fail "tcpRoute.rdpAccessURL must be set if tcpRoute.enabled is true - it is the hostname Kasm advertises to RDP clients, and the RDP Gateway has no way to infer it from the Gateway." -}}
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


{{/*
  The hostname the RDP Gateway advertises to clients, whichever way it is
  published. Empty when the gateway is only reachable in-cluster, in which case
  the caller falls back to the Service name.
*/}}
{{- define "kasm.rdpAccessURL" -}}
{{- if .Values.directRdpService.enabled -}}
  {{- .Values.directRdpService.rdpAccessURL -}}
{{- else if .Values.tcpRoute.enabled -}}
  {{- .Values.tcpRoute.rdpAccessURL -}}
{{- end -}}
{{- end -}}
