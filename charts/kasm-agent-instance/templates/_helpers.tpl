{{/*
  Chart name, optionally overridden by .Values.nameOverride.

  This chart deliberately does NOT reuse the `kasm.*` helpers from the kasm-helm
  chart: it is consumed as a subchart alongside them, and sharing a helper
  namespace across two independently versioned charts makes both undefinable.
*/}}
{{- define "kasmAgentInstance.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
  Fully qualified name prefix for the satellite objects this chart creates.
  The Agent custom resource itself is named by .Values.name, not by this.

  Precedence:
    1. .Values.fullnameOverride if set (used verbatim)
    2. else the release name alone, when it already contains the chart name
    3. else "<release>-<chart name>"
*/}}
{{- define "kasmAgentInstance.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
  Chart name and version, as the `helm.sh/chart` label value.
*/}}
{{- define "kasmAgentInstance.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
  Selector labels.
*/}}
{{- define "kasmAgentInstance.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kasmAgentInstance.name" . }}
app.kubernetes.io/component: agent
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
  Full label set applied to every resource this chart creates.
*/}}
{{- define "kasmAgentInstance.labels" -}}
helm.sh/chart: {{ include "kasmAgentInstance.chart" . }}
{{ include "kasmAgentInstance.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasm-ai
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
  Join a split registry/repository/tag image into a single reference.

  Call with a dict:
    image      - the {registry, repository, tag} map
    defaultTag - tag to use when image.tag is empty (pass "" for images that
                 have no sensible fallback, such as upstream nginx)
    path       - the values path, used in the failure message
*/}}
{{- define "kasmAgentInstance.joinImage" -}}
{{- $image := .image -}}
{{- $tag := default .defaultTag $image.tag -}}
{{- if not $image.repository -}}
{{- fail (printf "%s.repository is required." .path) -}}
{{- end -}}
{{- if not $tag -}}
{{- fail (printf "%s.tag is required: this image has no chart appVersion fallback." .path) -}}
{{- end -}}
{{- if $image.registry -}}
{{- printf "%s/%s:%s" $image.registry $image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $image.repository $tag -}}
{{- end -}}
{{- end }}

{{/*
  The manager hostname, which has no default.
*/}}
{{- define "kasmAgentInstance.managerHostname" -}}
{{- if .Values.manager.hostname -}}
{{- .Values.manager.hostname -}}
{{- else if .Values.inClusterControlPlane -}}
{{- printf "%s-proxy-default.%s.svc.cluster.local" .Release.Name .Release.Namespace -}}
{{- else -}}
{{- fail "agent.manager.hostname is required: set it to the hostname of the Kasm manager (or the proxy in front of it) this agent registers with. (With a kasm-helm control plane in this same release, agent.inClusterControlPlane=true derives it instead.)" -}}
{{- end -}}
{{- end }}

{{/*
  Whether the manager address is derived from a kasm-helm release alongside (inClusterControlPlane
  with no explicit hostname). The port and scheme follow the hostname: the derived target is the
  control plane's in-cluster proxy Service, plain HTTP on 8080, and only then. An explicit
  manager.hostname takes the ordinary manager.port / manager.scheme (443 / https).
*/}}
{{- define "kasmAgentInstance.managerDerived" -}}
{{- if and .Values.inClusterControlPlane (not .Values.manager.hostname) -}}true{{- end -}}
{{- end }}

{{- define "kasmAgentInstance.managerPort" -}}
{{- if include "kasmAgentInstance.managerDerived" . -}}8080{{- else -}}{{ .Values.manager.port }}{{- end -}}
{{- end }}

{{- define "kasmAgentInstance.managerScheme" -}}
{{- if include "kasmAgentInstance.managerDerived" . -}}http{{- else -}}{{ .Values.manager.scheme }}{{- end -}}
{{- end }}

{{/*
  The port the manager reaches the session proxy on. Derived to 4444, the proxy's own HTTPS
  listener, while the public hostname is derived too (relayed, in-cluster). Otherwise an explicit
  publicPort wins; with none set, a NodePort Service with a pinned httpsNodePort is reached on that
  node port (the control plane dials publicPort for its Hello, so the two must agree), and anything
  else takes 443, because then something in front of the proxy owns the port.
*/}}
{{- define "kasmAgentInstance.publicPort" -}}
{{- if and .Values.inClusterControlPlane (not .Values.publicHostname) -}}4444
{{- else if .Values.publicPort -}}{{ .Values.publicPort }}
{{- else if and (eq (toString .Values.sessionProxy.service.type) "NodePort") .Values.sessionProxy.service.httpsNodePort -}}{{ .Values.sessionProxy.service.httpsNodePort }}
{{- else -}}443
{{- end -}}
{{- end }}

{{/*
  The agent's public hostname, which has no default. Also used as the fallback
  for the session-proxy certificate's names and the HTTPRoute's hostnames.
*/}}
{{- define "kasmAgentInstance.publicHostname" -}}
{{- if .Values.publicHostname -}}
{{- .Values.publicHostname -}}
{{- else if .Values.inClusterControlPlane -}}
{{- printf "%s-session-proxy.%s.svc.cluster.local" .Values.name .Release.Namespace -}}
{{- else -}}
{{- fail "agent.publicHostname is required: set it to the externally reachable address browsers use to connect to this agent's session proxy. (With a kasm-helm control plane in this same release, agent.inClusterControlPlane=true derives it instead.)" -}}
{{- end -}}
{{- end }}

{{/*
  The Gateway name the operator-managed TLSRoute attaches to. The CRD requires
  gatewayRoute.parentRef.name (minLength 1) whenever the block is present, so an
  enabled gatewayRoute without it would be rejected by the API server; fail here
  with something more useful than a schema error instead.
*/}}
{{- define "kasmAgentInstance.gatewayRouteParentRefName" -}}
{{- if not .Values.gatewayRoute.parentRef.name -}}
{{- fail "agent.gatewayRoute.parentRef.name is required when agent.gatewayRoute.enabled is true: set it to the name of the Gateway the operator should attach the TLSRoute to." -}}
{{- end -}}
{{- .Values.gatewayRoute.parentRef.name -}}
{{- end }}

{{/*
  Name of the Secret holding the manager token.
*/}}
{{- define "kasmAgentInstance.managerTokenSecretName" -}}
{{- if .Values.manager.existingTokenSecret -}}
{{- .Values.manager.existingTokenSecret -}}
{{- else if .Values.manager.token -}}
{{- printf "%s-manager-token" (include "kasmAgentInstance.fullname" .) -}}
{{- else if .Values.inClusterControlPlane -}}
{{- printf "%s-secrets" .Release.Name -}}
{{- else -}}
{{- fail "agent.manager: no manager token configured. Set agent.manager.existingTokenSecret to the name of a Secret already holding the token (preferred), or agent.manager.token to the token itself so this chart creates one. (With a kasm-helm control plane in this same release, agent.inClusterControlPlane=true reads the token the control plane generated.)" -}}
{{- end -}}
{{- end }}

{{/*
  Key within the manager token Secret. A chart-created Secret always stores the
  token under "token"; an existing Secret uses manager.tokenSecretKey.
*/}}
{{- define "kasmAgentInstance.managerTokenSecretKey" -}}
{{- if .Values.manager.existingTokenSecret -}}
{{- .Values.manager.tokenSecretKey | default "token" -}}
{{- else if and .Values.inClusterControlPlane (not .Values.manager.token) -}}
{{- /* kasm-helm stores the registration token under "manager-token" in its secrets Secret.
       Not tokenSecretKey, which already defaults to "token" and so cannot express this;
       point at a different key by setting manager.existingTokenSecret explicitly. */ -}}
manager-token
{{- else -}}
token
{{- end -}}
{{- end }}

{{/*
  The Agent's spec.env, as a YAML list.

  Order matters only for readability: the operator merges environment variables
  by name, so a user entry in .Values.env with the same name as one generated
  here overrides it.
*/}}
{{- define "kasmAgentInstance.env" -}}
{{- $env := list -}}
{{- if .Values.otel.enabled -}}
{{- $endpoint := .Values.otel.endpoint | default (printf "http://%s-kasm-otel-collector:4318" .Release.Name) -}}
{{- $env = append $env (dict "name" "OTEL_EXPORTER_OTLP_ENDPOINT" "value" $endpoint) -}}
{{/* The SDK defaults to delta temporality; Prometheus's OTLP receiver silently
     drops delta points, so ask for cumulative at the source. */}}
{{- $env = append $env (dict "name" "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE" "value" "cumulative") -}}
{{- end -}}
{{- if .Values.gpu.enabled -}}
{{- $env = append $env (dict "name" "KASM_GPU_OPERATOR_ENABLED" "value" "true") -}}
{{- end -}}
{{- range .Values.env -}}
{{- $env = append $env . -}}
{{- end -}}
{{- if $env -}}
{{- toYaml $env -}}
{{- end -}}
{{- end }}

{{/*
  Namespace of the operator's ServiceAccount for the namespaced Role this chart stamps: an explicit
  operatorRBAC.serviceAccount.namespace, else this release's namespace (the umbrella layout, where the
  operator and the agent share one namespace).
*/}}
{{- define "kasmAgentInstance.operatorNamespace" -}}
{{- .Values.operatorRBAC.serviceAccount.namespace | default .Release.Namespace -}}
{{- end -}}

{{/*
  The operator's ServiceAccount name, required: without it the Role binds nothing and every storage
  mapping fails with Forbidden.
*/}}
{{- define "kasmAgentInstance.operatorServiceAccount" -}}
{{- $n := .Values.operatorRBAC.serviceAccount.name -}}
{{- if not $n -}}
{{- fail "agent.operatorRBAC.serviceAccount.name is required: the operator's ServiceAccount that gets Secret access in this namespace (the kasm-agent-operator chart's serviceAccount.name, controller-manager by default)" -}}
{{- end -}}
{{- $n -}}
{{- end -}}

