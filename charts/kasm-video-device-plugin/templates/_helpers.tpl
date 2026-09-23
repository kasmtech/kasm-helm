{{/*
  Chart name, honoring nameOverride. Used for the app.kubernetes.io/name label.

  The result is normalized to a DNS-safe label: Helm rewrites .Chart.Name to the dependency alias when
  this chart is consumed as a subchart, and the agreed alias ("videoDevicePlugin") is camelCase, which is
  not valid in a resource name. Case transitions become dashes and everything is lowercased, so both
  "kasm-video-device-plugin" and "videoDevicePlugin" resolve to usable names.
*/}}
{{- define "kasmVideoDevicePlugin.name" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- regexReplaceAll "([a-z0-9])([A-Z])" $name "${1}-${2}" | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Fully qualified resource name.

  Precedence:
    1. .Values.fullnameOverride if set
    2. else <release name> when it already contains the chart/override name
    3. else <release name>-<chart or override name>
*/}}
{{- define "kasmVideoDevicePlugin.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "kasmVideoDevicePlugin.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
  Chart name and version, as used by the helm.sh/chart label.
*/}}
{{- define "kasmVideoDevicePlugin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Selector labels. These are immutable on a DaemonSet, so they intentionally stay minimal.
*/}}
{{- define "kasmVideoDevicePlugin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kasmVideoDevicePlugin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: video-device-plugin
{{- end -}}

{{/*
  Common labels applied to every resource this chart creates.
*/}}
{{- define "kasmVideoDevicePlugin.labels" -}}
helm.sh/chart: {{ include "kasmVideoDevicePlugin.chart" . }}
{{ include "kasmVideoDevicePlugin.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasm-ai
{{- end -}}

{{/*
  Fully qualified device plugin image reference, joined from image.registry, image.repository and image.tag.
  A tag beginning with "@" (a bare digest) is appended without the ":" separator; a tag carrying a
  "@sha256:" suffix is passed through untouched so both "latest" and "latest@sha256:<digest>" work.
*/}}
{{- define "kasmVideoDevicePlugin.image" -}}
{{- $registry := include "kasmVideoDevicePlugin.imageRegistry" . -}}
{{- $repository := required "kasm-video-device-plugin: image.repository must be set" .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | toString -}}
{{- $name := $repository -}}
{{- if $registry -}}
{{- $name = printf "%s/%s" $registry $repository -}}
{{- end -}}
{{- if hasPrefix "@" $tag -}}
{{- printf "%s%s" $name $tag -}}
{{- else -}}
{{- printf "%s:%s" $name $tag -}}
{{- end -}}
{{- end -}}

{{/*
  The registry the image is pulled from: Rancher's global.cattle.systemDefaultRegistry when set,
  otherwise image.registry. Rancher injects the global on every install from its catalog on a
  cluster with a system default registry, and its convention is that it replaces the registry of
  every image a chart renders. A trailing slash is tolerated; the result never carries one.
*/}}
{{- define "kasmVideoDevicePlugin.imageRegistry" -}}
{{- $global := dig "cattle" "systemDefaultRegistry" "" (.Values.global | default dict) -}}
{{- if $global -}}{{ trimSuffix "/" $global }}{{- else -}}{{ trimSuffix "/" (.Values.image.registry | default "") }}{{- end -}}
{{- end -}}

{{/*
  The ServiceAccount the DaemonSet runs under: serviceAccount.name when set, else the release's own
  fullname when the chart creates one, else the namespace default. A dedicated account is what lets a
  cluster policy (an OpenShift SecurityContextConstraint, a Kyverno PolicyException) be granted to this
  DaemonSet alone rather than to every pod that uses the namespace's default account.
*/}}
{{- define "kasmVideoDevicePlugin.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "kasmVideoDevicePlugin.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
