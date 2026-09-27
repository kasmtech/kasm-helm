{{/*
  Chart name, honoring nameOverride. Used for the app.kubernetes.io/name label.

  The result is normalized to a DNS-safe label: Helm rewrites .Chart.Name to the dependency alias when
  this chart is consumed as a subchart, and a camelCase alias is not valid in a resource name. Case
  transitions become dashes and everything is lowercased.
*/}}
{{- define "kasmEgressInstaller.name" -}}
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
{{- define "kasmEgressInstaller.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "kasmEgressInstaller.name" . -}}
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
{{- define "kasmEgressInstaller.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Selector labels. These are immutable on a DaemonSet, so they intentionally stay minimal.
*/}}
{{- define "kasmEgressInstaller.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kasmEgressInstaller.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: egress-installer
{{- end -}}

{{/*
  Common labels applied to every resource this chart creates.
*/}}
{{- define "kasmEgressInstaller.labels" -}}
helm.sh/chart: {{ include "kasmEgressInstaller.chart" . }}
{{ include "kasmEgressInstaller.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasm-ai
{{- end -}}

{{/*
  Fully qualified egress daemon image reference, joined from image.registry, image.repository and image.tag.
  A tag beginning with "@" (a bare digest) is appended without the ":" separator; a tag carrying a
  "@sha256:" suffix is passed through untouched so both "latest" and "latest@sha256:<digest>" work.
*/}}
{{- define "kasmEgressInstaller.image" -}}
{{- $registry := include "kasmEgressInstaller.imageRegistry" . -}}
{{- $repository := required "kasm-egress-installer: image.repository must be set" .Values.image.repository -}}
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
{{- define "kasmEgressInstaller.imageRegistry" -}}
{{- $global := dig "cattle" "systemDefaultRegistry" "" (.Values.global | default dict) -}}
{{- if $global -}}{{ trimSuffix "/" $global }}{{- else -}}{{ trimSuffix "/" (.Values.image.registry | default "") }}{{- end -}}
{{- end -}}

{{/*
  Host CNI plugin bin dir the shim is installed into. An explicit .Values.cniBinDir always wins; otherwise
  it is derived from .Values.distro. k3s reads plugins from its data dir, not /opt/cni/bin — getting this
  wrong makes the runtime silently never invoke the shim, so an unrecognized distro fails loudly here rather
  than defaulting to a path that may be wrong.
*/}}
{{- define "kasmEgressInstaller.cniBinDir" -}}
{{- if .Values.cniBinDir -}}
{{- .Values.cniBinDir -}}
{{- else if eq .Values.distro "k3s" -}}
/var/lib/rancher/k3s/data/cni
{{- else if eq .Values.distro "vanilla" -}}
/opt/cni/bin
{{- else if eq .Values.distro "openshift" -}}
/var/lib/cni/bin
{{- else -}}
{{- fail (printf "kasm-egress-installer: distro %q has no built-in CNI bin dir. Set cniBinDir explicitly, or use distro: k3s | vanilla | openshift." (.Values.distro | toString)) -}}
{{- end -}}
{{- end -}}

{{/*
  The CNI mode: `mode` when set, else `attachment` for distro openshift and `chain` everywhere else.
*/}}
{{- define "kasmEgressInstaller.mode" -}}
{{- $mode := .Values.mode | default (ternary "attachment" "chain" (eq .Values.distro "openshift")) -}}
{{- if not (has $mode (list "chain" "attachment")) -}}
{{- fail (printf "kasm-egress-installer: mode %q is not one of chain, attachment." $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end -}}
