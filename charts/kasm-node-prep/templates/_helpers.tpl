{{/*
  Chart name, honoring nameOverride. Used for the app.kubernetes.io/name label.

  The result is normalized to a DNS-safe label: Helm rewrites .Chart.Name to the dependency alias when
  this chart is consumed as a subchart, and the agreed alias ("nodePrep") is camelCase, which is not
  valid in a resource name. Case transitions become dashes and everything is lowercased, so both
  "kasm-node-prep" and "nodePrep" resolve to usable names.
*/}}
{{- define "kasmNodePrep.name" -}}
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
{{- define "kasmNodePrep.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "kasmNodePrep.name" . -}}
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
{{- define "kasmNodePrep.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Selector labels. These are immutable on a DaemonSet, so they intentionally stay minimal.
*/}}
{{- define "kasmNodePrep.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kasmNodePrep.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: node-prep
{{- end -}}

{{/*
  Common labels applied to every resource this chart creates.
*/}}
{{- define "kasmNodePrep.labels" -}}
helm.sh/chart: {{ include "kasmNodePrep.chart" . }}
{{ include "kasmNodePrep.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasm-ai
{{- end -}}

{{/*
  Fully qualified builder image reference, joined from image.registry, image.repository and image.tag.
  A tag beginning with "@" (a bare digest) is appended without the ":" separator; a tag carrying a
  "@sha256:" suffix is passed through untouched so both "1.0" and "1.0@sha256:<digest>" work.
*/}}
{{- define "kasmNodePrep.image" -}}
{{- $registry := trimSuffix "/" (.Values.image.registry | default "") -}}
{{- $repository := required "kasm-node-prep: image.repository must be set" .Values.image.repository -}}
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
  True when at least one kernel module is enabled, whichever method delivers it. This is what makes
  an install non-empty, so it is the module half of validateEnabled -- a KMM-only install builds
  nothing on the node but the Module CR is still real work.
*/}}
{{- define "kasmNodePrep.anyModuleEnabled" -}}
{{- if or .Values.modules.v4l2loopback.enabled .Values.modules.wireguard.enabled -}}true{{- end -}}
{{- end -}}

{{/*
  True when v4l2loopback is enabled and delegated to the Kernel Module Management operator. The
  Module CR and its Dockerfile ConfigMap are rendered only when this holds, and the module drops
  out of the DaemonSet's reconcile script.
*/}}
{{- define "kasmNodePrep.v4l2loopbackKmm" -}}
{{- if and .Values.modules.v4l2loopback.enabled (eq .Values.modules.v4l2loopback.method "kmm") -}}true{{- end -}}
{{- end -}}

{{/*
  True when at least one kernel module is built on the node by this chart's DaemonSet, i.e. it is
  enabled *and* its method is "build". The whole module build machinery -- the toolchain checks, the
  source staging, the Secure Boot signing, and the /lib/modules, /usr/src and /dev host mounts -- is
  rendered only when this holds, so neither a tuning-only nor a KMM-only install carries any of it.
*/}}
{{- define "kasmNodePrep.anyBuildModuleEnabled" -}}
{{- $v4l2 := .Values.modules.v4l2loopback -}}
{{- $wireguard := .Values.modules.wireguard -}}
{{- if or (and $v4l2.enabled (eq $v4l2.method "build")) (and $wireguard.enabled (eq $wireguard.method "build")) -}}true{{- end -}}
{{- end -}}

{{/*
  True when the DaemonSet has anything to do: a module to build on the node, or host tuning to
  re-assert. A KMM-only install with tuning off renders no DaemonSet and no reconcile script at
  all -- the Module CR is the entire payload, and KMM runs its own worker pods.
*/}}
{{- define "kasmNodePrep.daemonSetNeeded" -}}
{{- if or (include "kasmNodePrep.anyBuildModuleEnabled" .) (include "kasmNodePrep.anyTuningEnabled" .) -}}true{{- end -}}
{{- end -}}

{{/*
  True when at least one tuning feature is enabled.
*/}}
{{- define "kasmNodePrep.anyTuningEnabled" -}}
{{- if or .Values.tuning.sysctls.enabled .Values.tuning.swap.enabled -}}true{{- end -}}
{{- end -}}

{{/*
  Render one tuning.sysctls.values entry into the reconcile script.

  YAML numbers reach a template as float64, and Go's default formatting switches to scientific
  notation past seven significant digits -- so a perfectly reasonable "kernel.pid_max: 4194304"
  would otherwise render as "4.194304e+06", which sysctl(8) rejects. Integral floats are therefore
  printed in full. Strings (the space separated tuples some tunables take, e.g. net.ipv4.tcp_rmem)
  and booleans pass through untouched.
*/}}
{{- define "kasmNodePrep.sysctlValue" -}}
{{- if kindIs "float64" . -}}
{{- printf "%.0f" . -}}
{{- else -}}
{{- . -}}
{{- end -}}
{{- end -}}

{{/*
  Name of the KMM Module custom resource, and of the ConfigMap holding the Dockerfile it is built
  from. Both are suffixed with the module name so a second module delegated to KMM later does not
  collide with this one.

  Deliberately much shorter than the chart's other resources: <release>-v4l2 rather than
  <release>-kasm-node-prep-v4l2loopback. KMM's admission webhook (v2.7.0) refuses a Module whose
  name and namespace together exceed 41 characters, because it has to fit both into one 63-character
  label value. The chart name pushes every realistic umbrella install past that
  (kasm-agent-kasm-node-prep-v4l2loopback in namespace kasm-agent is 48), and even the bare module
  name is too long for ordinary pairs such as kasm-agent-prod in kasm-agent-prod (43). The
  four-character suffix leaves 37 for release name plus namespace; the module it stands for is
  spelled out in spec.moduleLoader.container.modprobe.moduleName. fullnameOverride still wins when
  set, so an operator who needs a specific prefix keeps it; validateMethods then applies the same
  41-character rule at render time, so the limit surfaces from Helm rather than from the webhook.
*/}}
{{- define "kasmNodePrep.kmmNameBase" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kasmNodePrep.kmmModuleName" -}}
{{- printf "%s-v4l2" (include "kasmNodePrep.kmmNameBase" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kasmNodePrep.kmmDockerfileConfigMapName" -}}
{{- printf "%s-v4l2-dockerfile" (include "kasmNodePrep.kmmNameBase" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Fully qualified kmod image reference for the KMM kernelMapping, joined from
  modules.v4l2loopback.kmm.image.registry/.repository/.tag.

  An empty tag renders the literal string "${KERNEL_FULL_VERSION}" -- deliberately NOT a Helm or a
  shell variable. KMM itself expands it per node kernel, so it has to survive templating verbatim;
  Go templates leave "${...}" alone, and the callers quote the result so YAML does too.

  A tag beginning with "@" (a bare digest) is appended without the ":" separator, and a tag carrying
  a "@sha256:" suffix passes through untouched, matching kasmNodePrep.image.
*/}}
{{- define "kasmNodePrep.kmmImage" -}}
{{- $image := .Values.modules.v4l2loopback.kmm.image -}}
{{- $registry := trimSuffix "/" ($image.registry | default "") -}}
{{- $name := printf "%s/%s" $registry $image.repository -}}
{{- $tag := $image.tag | default "${KERNEL_FULL_VERSION}" | toString -}}
{{- if hasPrefix "@" $tag -}}
{{- printf "%s%s" $name $tag -}}
{{- else -}}
{{- printf "%s:%s" $name $tag -}}
{{- end -}}
{{- end -}}

{{/*
  Guard against installing the chart with nothing to do. Included by every template so any render
  (not just the DaemonSet) surfaces the error.

  A module delegated to KMM counts: it renders no DaemonSet, but the Module CR is the work.
*/}}
{{- define "kasmNodePrep.validateEnabled" -}}
{{- if not (or (include "kasmNodePrep.anyModuleEnabled" .) (include "kasmNodePrep.anyTuningEnabled" .)) -}}
{{- fail "kasm-node-prep: nothing is enabled, so this chart has no work to do. Enable at least one of modules.v4l2loopback.enabled (webcam support, built on the node or delegated to KMM with modules.v4l2loopback.method=kmm), modules.wireguard.enabled (VPN sidecars on kernels < 5.6), tuning.sysctls.enabled (kernel tunables) or tuning.swap.enabled (node swapfile), or disable this chart entirely (nodePrep.enabled=false on the umbrella chart)." -}}
{{- end -}}
{{- end -}}

{{/*
  Guard the modules.*.method switch and everything modules.v4l2loopback.kmm needs to render a valid
  Module CR. Included by every template, for the same reason validateEnabled is: a KMM-only install
  renders no DaemonSet, so the DaemonSet is not a reliable place to surface a values error.
*/}}
{{- define "kasmNodePrep.validateMethods" -}}
{{- $v4l2 := .Values.modules.v4l2loopback -}}
{{- $wireguard := .Values.modules.wireguard -}}
{{- if not (has $v4l2.method (list "build" "kmm")) -}}
{{- fail (printf "kasm-node-prep: modules.v4l2loopback.method must be \"build\" or \"kmm\", got %q." $v4l2.method) -}}
{{- end -}}
{{- if not (has $wireguard.method (list "build" "kmm")) -}}
{{- fail (printf "kasm-node-prep: modules.wireguard.method must be \"build\", got %q." $wireguard.method) -}}
{{- end -}}
{{- if eq $wireguard.method "kmm" -}}
{{- fail "kasm-node-prep: wireguard via KMM is not supported: kernels >= 5.6 ship WireGuard in-tree; use method: build for older kernels." -}}
{{- end -}}
{{- if include "kasmNodePrep.v4l2loopbackKmm" . -}}
{{- $kmm := $v4l2.kmm -}}
{{- if not $kmm.image.registry -}}
{{- fail "kasm-node-prep: modules.v4l2loopback.kmm.image.registry must be set when modules.v4l2loopback.method=kmm. KMM loads the module from a container image, so it needs a registry to pull it from (and, with kmm.build.enabled, to push the built image to)." -}}
{{- end -}}
{{- if not $kmm.image.repository -}}
{{- fail "kasm-node-prep: modules.v4l2loopback.kmm.image.repository must be set when modules.v4l2loopback.method=kmm. KMM loads the module from a container image, so it needs a repository to pull it from (and, with kmm.build.enabled, to push the built image to)." -}}
{{- end -}}
{{- $moduleName := include "kasmNodePrep.kmmModuleName" . -}}
{{- $combined := add (len $moduleName) (len .Release.Namespace) -}}
{{- if gt $combined 41 -}}
{{- fail (printf "kasm-node-prep: the KMM Module name %q and its namespace %q have a combined length of %d characters, and KMM's admission webhook refuses more than 41 (it has to fit both into one label value). Use a shorter release name or namespace, or set fullnameOverride to something shorter." $moduleName .Release.Namespace $combined) -}}
{{- end -}}
{{- if $v4l2.sourcePath -}}
{{- fail "kasm-node-prep: modules.v4l2loopback.sourcePath applies to method=build only -- it points at a source tree inside this chart's builder image, which a KMM build pod never runs. A KMM in-cluster build clones modules.v4l2loopback.sourceRepo; for an airgapped fleet set modules.v4l2loopback.kmm.build.enabled=false and pull prebuilt per-kernel images instead." -}}
{{- end -}}
{{- if $kmm.sign.enabled -}}
{{- if not $kmm.sign.keySecret -}}
{{- fail "kasm-node-prep: modules.v4l2loopback.kmm.sign.keySecret must be set when modules.v4l2loopback.kmm.sign.enabled is true. It names the Secret holding the private Machine Owner Key that KMM signs the built module with." -}}
{{- end -}}
{{- if not $kmm.sign.certSecret -}}
{{- fail "kasm-node-prep: modules.v4l2loopback.kmm.sign.certSecret must be set when modules.v4l2loopback.kmm.sign.enabled is true. It names the Secret holding the public certificate matching modules.v4l2loopback.kmm.sign.keySecret." -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
  Shell-quote one value for the reconcile script: single-quoted, with any embedded single quote closed,
  escaped and reopened ('\''). Nothing expands inside single quotes, so a value such as
  https://example.com/x$(id).git or a sysctl key carrying ";" is a literal string in the script, never code.
  Every chart value that lands in shell text goes through this.
*/}}
{{- define "kasmNodePrep.shq" -}}'{{ . | toString | replace "'" "'\\''" }}'{{- end -}}

{{/*
  Reject values that must never reach the reconcile script or the pod log as written:
  - credentials embedded in modules.*.sourceRepo (they would be stored in the ConfigMap and printed by the
    clone log line): use modules.*.sourceRepoSecret instead;
  - modules.*.sourceRepoSecret together with method: kmm (a KMM build clones inside its Dockerfile, where
    no Secret is injected);
  - tuning.sysctls.values keys and values outside the character set sysctl itself accepts. The script
    single-quotes them anyway; this just turns a typo into a render error instead of a runtime one.
  Included by every template so a kmm-only install (no DaemonSet) still surfaces the error.
*/}}
{{- define "kasmNodePrep.validateInputs" -}}
{{- range $name, $m := (dict "v4l2loopback" .Values.modules.v4l2loopback "wireguard" .Values.modules.wireguard) -}}
{{- if and $m.enabled (regexMatch "^[A-Za-z][A-Za-z0-9+.-]*://[^/]*@" ($m.sourceRepo | toString)) -}}
{{- fail (printf "kasm-node-prep: modules.%s.sourceRepo carries credentials in the URL. They would be written into the ConfigMap and printed in the pod log; put them in a Secret with keys username and password and set modules.%s.sourceRepoSecret instead." $name $name) -}}
{{- end -}}
{{- if and $m.enabled $m.sourceRepoSecret (eq $m.method "kmm") -}}
{{- fail (printf "kasm-node-prep: modules.%s.sourceRepoSecret applies to method=build only; a KMM in-cluster build clones inside its Dockerfile and cannot use a Secret. Use an internal mirror that needs no login, or method: build." $name) -}}
{{- end -}}
{{- end -}}
{{- if .Values.tuning.sysctls.enabled -}}
{{- range $key, $value := .Values.tuning.sysctls.values -}}
{{- if not (regexMatch "^[A-Za-z0-9._/-]+$" $key) -}}
{{- fail (printf "kasm-node-prep: tuning.sysctls.values key %q is not a valid sysctl name (allowed: letters, digits, . _ / -)." $key) -}}
{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9._:/ -]*$" (include "kasmNodePrep.sysctlValue" $value)) -}}
{{- fail (printf "kasm-node-prep: tuning.sysctls.values[%q] has an unexpected value %q (allowed: letters, digits, . _ : / space -)." $key (include "kasmNodePrep.sysctlValue" $value)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
