{{/*
  Cross-value validation for the ways this chart publishes the session proxy.
  (workspaceSecurity has its own helper, kasmAgentInstance.validateWorkspaceSecurity,
  at the end of this file.)

  Held here rather than in the templates it constrains because the rule is n-way:
  the operator-created session-proxy Service can be published five ways (an
  Ingress, a Gateway API HTTPRoute, an OpenShift Route, the chart-managed
  TLSRoute, and the operator-managed gatewayRoute), every one of them at the
  same hostname. Spread across the five templates, the rule would have to be
  repeated in each.

  Invoked once from validation.yaml, which renders no manifest of its own, so it
  runs on `helm install`, `helm upgrade`, `helm template` and `--dry-run` alike.
  This mirrors the `kasm.validateExposure` helper in the kasm-helm chart.

  Messages are prefixed `agent.` because that is the values path under the
  kasm-agent umbrella, where this chart is almost always installed from.
*/}}
{{- define "kasmAgentInstance.validateExposure" -}}
{{- $v := .Values -}}

{{- $exposure := list -}}
{{- if $v.ingress.enabled -}}{{- $exposure = append $exposure "ingress.enabled" -}}{{- end -}}
{{- if $v.httpRoute.enabled -}}{{- $exposure = append $exposure "httpRoute.enabled" -}}{{- end -}}
{{- if $v.route.enabled -}}{{- $exposure = append $exposure "route.enabled" -}}{{- end -}}
{{- if $v.tlsRoute.enabled -}}{{- $exposure = append $exposure "tlsRoute.enabled" -}}{{- end -}}
{{- if $v.gatewayRoute.enabled -}}{{- $exposure = append $exposure "gatewayRoute.enabled" -}}{{- end -}}
{{- if gt (len $exposure) 1 -}}
  {{- fail (printf "Only one session-proxy exposure method may be enabled, but agent.%s are set. The Ingress, the Gateway API HTTPRoute, the OpenShift Route, the chart-managed TLSRoute and the operator-managed gatewayRoute all publish the same session-proxy Service at the same hostname, so enabling more than one gives that hostname two owners." (join " and agent." $exposure)) -}}
{{- end -}}

{{/* gatewayRoute.parentRef.name has its own guard in kasmAgentInstance.gatewayRouteParentRefName. */}}
{{- if and $v.httpRoute.enabled (not $v.httpRoute.parentRefs) -}}
  {{- fail "agent.httpRoute.enabled is set but agent.httpRoute.parentRefs is empty - the HTTPRoute would attach to no Gateway, and the session proxy would stay unreachable from outside the cluster." -}}
{{- end -}}
{{- if and $v.tlsRoute.enabled (not $v.tlsRoute.parentRefs) -}}
  {{- fail "agent.tlsRoute.enabled is set but agent.tlsRoute.parentRefs is empty - the TLSRoute would attach to no Gateway, and the session proxy would stay unreachable from outside the cluster." -}}
{{- end -}}

{{/*
  A NodePort session proxy with neither a pinned node port nor an explicit publicPort: Kubernetes
  allocates the port at install time, the control plane dials https://<publicHostname>:<publicPort>/
  for its Hello before every launch, and the default 443 is not that port, so every session request
  would answer "No Agent slots available" while everything looks healthy. Seen live 2026-09-14.
  The relayed in-cluster case derives both hostname and port and is exempt.
*/}}
{{- if and (eq (toString $v.sessionProxy.service.type) "NodePort") (not $v.sessionProxy.service.httpsNodePort) (not $v.publicPort) (not (and (include "kasmAgentInstance.inClusterControlPlane" .) (not $v.publicHostname))) -}}
  {{- fail "agent.sessionProxy.service.type is NodePort but neither agent.sessionProxy.service.httpsNodePort nor agent.publicPort is set. The control plane reaches the session proxy at https://<publicHostname>:<publicPort>/ and a randomly allocated node port is never 443, so every launch would fail with 'No Agent slots available'. Pin agent.sessionProxy.service.httpsNodePort (publicPort then follows it), or set agent.publicPort to the port something in front of the proxy forwards to it." -}}
{{- end -}}
{{- end -}}

{{/*
  Cross-value validation for workspaceSecurity, rendered as the Agent's spec.workspaceSecurity.

  The first two pair rules repeat the Agent CRD's CEL rules, so a bad pair fails at render time
  rather than halfway through an apply. The third has no CEL counterpart - the operator would
  simply not give a host-root session a user namespace - but asking for both is a contradiction,
  and the SCC template cannot honour it either. The enum checks mirror the CRD's, and keep
  openshift-scc.yaml, which branches on rootMode and profile, from rendering a policy for a value
  the Agent would be rejected over.
*/}}
{{- define "kasmAgentInstance.validateWorkspaceSecurity" -}}
{{- $w := .Values.workspaceSecurity -}}
{{- $enums := dict "rootMode" (list "userns" "host" "forbid") "userNamespaces" (list "rootOnly" "always") "rootFeatures" (list "promote" "downgrade" "reject") "profile" (list "baseline" "restricted") "fsGroupChangePolicy" (list "OnRootMismatch" "Always") -}}
{{- range $key := list "rootMode" "userNamespaces" "rootFeatures" "profile" "fsGroupChangePolicy" -}}
{{- $value := toString (index $w $key | default "") -}}
{{- if and $value (not (has $value (index $enums $key))) -}}
  {{- fail (printf "agent.workspaceSecurity.%s is %q; it must be one of %s, or empty for the default." $key $value (join ", " (index $enums $key))) -}}
{{- end -}}
{{- end -}}
{{- if and (eq (toString $w.profile) "restricted") (eq (toString $w.rootMode) "host") -}}
  {{- fail "agent.workspaceSecurity.profile is restricted but agent.workspaceSecurity.rootMode is host - profile \"restricted\" cannot run root sessions as host root. Use rootMode userns or forbid, or profile baseline." -}}
{{- end -}}
{{- if and $w.sudo (eq (toString $w.profile) "restricted") -}}
  {{- fail "agent.workspaceSecurity.sudo is on but agent.workspaceSecurity.profile is restricted - sudo needs privilege escalation, which profile \"restricted\" forbids. Turn sudo off or use profile baseline." -}}
{{- end -}}
{{- if and (eq (toString $w.userNamespaces) "always") (eq (toString $w.rootMode) "host") -}}
  {{- fail "agent.workspaceSecurity.userNamespaces is always but agent.workspaceSecurity.rootMode is host - a session cannot run in a pod user namespace and as host root at once. Use rootMode userns (or forbid) with userNamespaces always, or userNamespaces rootOnly with rootMode host." -}}
{{- end -}}
{{- end -}}
