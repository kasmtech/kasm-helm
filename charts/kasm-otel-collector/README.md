# Kasm OpenTelemetry Collector

![Version: 1.1200.0-develop](https://img.shields.io/badge/Version-1.1200.0--develop-informational?style=flat-square) ![AppVersion: 0.156.0](https://img.shields.io/badge/AppVersion-0.156.0-informational?style=flat-square)

An OpenTelemetry Collector that receives OTLP traces, metrics, and logs from the Kasm agent components and fans them out to external observability backends. Deployed as a subchart of the kasm-agent umbrella chart under the `otelCollector` alias.

**Homepage:** <https://kasm.com>

> **Part of the [`kasm-agent`](../kasm-agent/README.md) umbrella.** This collector normally ships as
> the `otelCollector` dependency of the [`kasm-agent`](../kasm-agent/README.md) chart (or the
> full-stack [`kasm-platform`](../kasm-platform/README.md) chart), not on its own. Install it
> standalone only to run a collector the agent and operator point at.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |

## Documentation

Please see our [official documentation site](https://docs.kasm.com) for more information.

> **Note:** Make sure to select the correct Kasm Workspaces version in the top-right version selector on the documentation site to ensure the guides match your deployment.

This page is the chart reference; the [documentation index](../../docs/README.md) has the tutorial and the how-to guides.

## Prerequisites

* Kubernetes 1.26 or newer — the shared floor for the whole `kasm-agent` family (older versions of Kubernetes may work, however, we try to keep this chart updated to [supported versions of Kubernetes](https://kubernetes.io/releases/))
* Helm 3.18.x or newer ([installation](https://helm.sh/docs/helm/helm_install/))
* By default, `exporters.otlp` and `exporters.clickhouse` are both disabled and `exporters.debug` is enabled, so a default install logs telemetry to the collector's own stdout instead of guessing at a backend that may not exist. To ship telemetry somewhere real, set `exporters.otlp.endpoint` (and `exporters.otlp.enabled: true`) and/or `exporters.clickhouse.endpoint` (and `exporters.clickhouse.enabled: true`) to a backend reachable from the cluster.
* When `exporters.clickhouse.enabled` is set, a Secret holding the ClickHouse password must already exist in the release namespace - see `exporters.clickhouse.existingSecret`. The collector refuses to start when that password is unresolvable.

## What this chart deploys

* A ConfigMap holding the collector's `config.yaml`, rendered from the values below.
* A Deployment running the `opentelemetry-collector-contrib` distribution, with a `checksum/config` pod annotation so a configuration change rolls the pods.
* A ClusterIP Service exposing OTLP/HTTP on 4318 and OTLP/gRPC on 4317.
* A ServiceAccount, plus a namespace-scoped Role and RoleBinding granting read access to Events - rendered only when the `k8s_events` receiver is enabled.

## Pipelines

Three pipelines are assembled from whichever exporters are enabled:

| Pipeline | Receivers | Processors | Exporters |
| --- | --- | --- | --- |
| `traces` | `otlp` | `memory_limiter`, `filter/probes`, `batch` | every enabled exporter |
| `metrics` | `otlp` | `memory_limiter`, `batch` | every enabled exporter except `clickhouse/archive` |
| `logs` | `otlp`, plus `k8s_events` when enabled | `memory_limiter`, `transform/k8s_events` and `resource/k8s_events` when `k8s_events` is enabled, `batch/logs` | every enabled exporter |

Metrics deliberately do not go to ClickHouse: Prometheus already keeps them cumulative and cheap, and ClickHouse adds nothing for that shape. The `metrics` pipeline is dropped entirely if ClickHouse is the only exporter enabled.

Templating fails if no exporter is enabled at all, and it fails if `exporters.otlp.enabled` or `exporters.clickhouse.enabled` is true with an empty `endpoint` - both would otherwise deploy a collector that silently drops every signal it receives.

## Chart value settings in `values.yaml`

## Values

<table>
	<thead>
		<th>Key</th>
		<th>Type</th>
		<th>Default</th>
		<th>Description</th>
	</thead>
	<tbody>
		<tr>
			<td id="affinity"><a href="./values.yaml#L375">affinity</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Affinity rules for the collector pod - [Kubernetes Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/). </td>
		</tr>
		<tr>
			<td id="commonAnnotations"><a href="./values.yaml#L27">commonAnnotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to apply to every resource created by this chart. </td>
		</tr>
		<tr>
			<td id="commonLabels"><a href="./values.yaml#L23">commonLabels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to apply to every resource created by this chart. </td>
		</tr>
		<tr>
			<td id="configOverride"><a href="./values.yaml#L216">configOverride</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Replace the generated collector configuration wholesale. When non-empty this string becomes the entire `config.yaml` and every other value under `receivers`, `exporters`, `processors`, and `telemetry` is ignored. Intended as an escape hatch for configurations this chart does not model. </td>
		</tr>
		<tr>
			<td id="exporters"><a href="./values.yaml#L75">exporters</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
clickhouse:
    createSchema: true
    database: otel
    enabled: false
    endpoint: tcp://clickhouse.observability.svc.cluster.local:9000?dial_timeout=10s&compress=lz4
    existingSecret: clickhouse-otel
    existingSecretKey: password
    logsTableName: otel_logs
    sendingQueueSize: 1000
    timeout: 10s
    tracesTableName: otel_traces
    ttl: 2160h
    username: otel
debug:
    enabled: true
    verbosity: basic
otlp:
    enabled: false
    endpoint: ""
    sendingQueueSize: 1000
    tlsInsecure: true
</pre>
</div>
			</td>
			<td>Backends the collector fans telemetry out to. At least one exporter must be enabled or templating fails. </td>
		</tr>
		<tr>
			<td id="exporters--clickhouse"><a href="./values.yaml#L94">exporters.clickhouse</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
createSchema: true
database: otel
enabled: false
endpoint: tcp://clickhouse.observability.svc.cluster.local:9000?dial_timeout=10s&compress=lz4
existingSecret: clickhouse-otel
existingSecretKey: password
logsTableName: otel_logs
sendingQueueSize: 1000
timeout: 10s
tracesTableName: otel_traces
ttl: 2160h
username: otel
</pre>
</div>
			</td>
			<td>Optional long-retention archive. Gets the same spans and log records the OTLP backend gets, kept for months instead of days and queryable in SQL. Metrics deliberately do not go here.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--createSchema"><a href="./values.yaml#L112">exporters.clickhouse.createSchema</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Build the traces/logs tables and their materialized views on first connect, so there is no migration step to run by hand.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--database"><a href="./values.yaml#L101">exporters.clickhouse.database</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
otel
</pre>
</div>
			</td>
			<td>ClickHouse database that holds the traces and logs tables.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--enabled"><a href="./values.yaml#L96">exporters.clickhouse.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Enable the ClickHouse archive exporter for traces and logs.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--endpoint"><a href="./values.yaml#L99">exporters.clickhouse.endpoint</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
tcp://clickhouse.observability.svc.cluster.local:9000?dial_timeout=10s&compress=lz4
</pre>
</div>
			</td>
			<td>ClickHouse native-protocol DSN, including any query parameters. Templating fails if exporters.clickhouse.enabled is true and this is empty.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--existingSecret"><a href="./values.yaml#L107">exporters.clickhouse.existingSecret</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
clickhouse-otel
</pre>
</div>
			</td>
			<td>Name of an existing Secret holding the ClickHouse password. The collector refuses to start when the resolved `CLICKHOUSE_PASSWORD` environment variable is unset, so this Secret must exist in the release namespace before install. The password is never stored in values.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--existingSecretKey"><a href="./values.yaml#L109">exporters.clickhouse.existingSecretKey</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
password
</pre>
</div>
			</td>
			<td>Key inside `exporters.clickhouse.existingSecret` holding the password.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--logsTableName"><a href="./values.yaml#L116">exporters.clickhouse.logsTableName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
otel_logs
</pre>
</div>
			</td>
			<td>Name of the ClickHouse table that receives log records.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--sendingQueueSize"><a href="./values.yaml#L128">exporters.clickhouse.sendingQueueSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1000
</pre>
</div>
			</td>
			<td>Size of the exporter's in-memory sending queue, in batches. ClickHouse prefers fewer, larger inserts; the queue absorbs a restart or a merge pause without backpressuring the OTLP path alongside it.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--timeout"><a href="./values.yaml#L124">exporters.clickhouse.timeout</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
10s
</pre>
</div>
			</td>
			<td>Deadline for a single INSERT into ClickHouse. It has to cover the largest batch the sending queue lets accumulate, and a timeout is retried with the 5s-to-30s backoff configured alongside it, so setting this too low turns an ordinary merge pause on the ClickHouse side into a retry storm rather than into a clean drop.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--tracesTableName"><a href="./values.yaml#L114">exporters.clickhouse.tracesTableName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
otel_traces
</pre>
</div>
			</td>
			<td>Name of the ClickHouse table that receives spans.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--ttl"><a href="./values.yaml#L119">exporters.clickhouse.ttl</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
2160h
</pre>
</div>
			</td>
			<td>Table-level TTL. ClickHouse drops whole expired parts on merge, so this costs nothing to enforce. The default is 90 days.</td>
		</tr>
		<tr>
			<td id="exporters--clickhouse--username"><a href="./values.yaml#L103">exporters.clickhouse.username</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
otel
</pre>
</div>
			</td>
			<td>ClickHouse user the exporter authenticates as.</td>
		</tr>
		<tr>
			<td id="exporters--debug"><a href="./values.yaml#L133">exporters.debug</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
verbosity: basic
</pre>
</div>
			</td>
			<td>Writes telemetry to the collector's own stdout. Enabled by default so a fresh install is honest about where telemetry goes: with every other exporter disabled by default, this is what keeps the collector from silently dropping every signal it receives. Turn it off once exporters.otlp and/or exporters.clickhouse are configured and you no longer want telemetry echoed into the collector's own logs.</td>
		</tr>
		<tr>
			<td id="exporters--debug--enabled"><a href="./values.yaml#L135">exporters.debug.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Enable the debug exporter on every pipeline.</td>
		</tr>
		<tr>
			<td id="exporters--debug--verbosity"><a href="./values.yaml#L138">exporters.debug.verbosity</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
basic
</pre>
</div>
			</td>
			<td>Debug exporter verbosity - one of `basic`, `normal`, or `detailed`. Defaults to `basic` so the default install is not flooded; raise it when actively debugging a new deployment.</td>
		</tr>
		<tr>
			<td id="exporters--otlp"><a href="./values.yaml#L80">exporters.otlp</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: false
endpoint: ""
sendingQueueSize: 1000
tlsInsecure: true
</pre>
</div>
			</td>
			<td>The primary OTLP/gRPC exporter, typically a Grafana LGTM stack (Tempo, Mimir/Prometheus, Loki). Disabled by default: there is no cluster-agnostic default endpoint to point this at, and shipping one would mean every default install silently exports to a host that does not exist. Set exporters.otlp.endpoint and enable this to ship telemetry somewhere; until then the debug exporter below logs it locally instead.</td>
		</tr>
		<tr>
			<td id="exporters--otlp--enabled"><a href="./values.yaml#L83">exporters.otlp.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Enable the OTLP/gRPC exporter. It receives traces, metrics, and logs. Templating fails if this is true and exporters.otlp.endpoint is empty.</td>
		</tr>
		<tr>
			<td id="exporters--otlp--endpoint"><a href="./values.yaml#L86">exporters.otlp.endpoint</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>`host:port` of the OTLP/gRPC receiver on the backend. No scheme - gRPC endpoints are bare host:port. Empty by default; required when exporters.otlp.enabled is true.</td>
		</tr>
		<tr>
			<td id="exporters--otlp--sendingQueueSize"><a href="./values.yaml#L91">exporters.otlp.sendingQueueSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1000
</pre>
</div>
			</td>
			<td>Size of the exporter's in-memory sending queue, in batches.</td>
		</tr>
		<tr>
			<td id="exporters--otlp--tlsInsecure"><a href="./values.yaml#L89">exporters.otlp.tlsInsecure</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Disable TLS on the exporter connection. Appropriate for an in-cluster backend reached over the pod network; set to false when the backend terminates TLS.</td>
		</tr>
		<tr>
			<td id="extraEnv"><a href="./values.yaml#L389">extraEnv</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Additional environment variables appended to the collector container, as a list of Kubernetes EnvVar objects. Useful for referencing secrets from a `configOverride`. </td>
		</tr>
		<tr>
			<td id="fullnameOverride"><a href="./values.yaml#L9">fullnameOverride</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Fully override the generated resource name prefix. When set, resource names are used verbatim instead of being derived from the release name and the chart name. </td>
		</tr>
		<tr>
			<td id="global"><a href="./values.yaml#L13">global</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
cattle:
    systemDefaultRegistry: ""
</pre>
</div>
			</td>
			<td>Values Helm shares with every chart in a release. Rancher fills in `global.cattle.*` on every install from its catalog; nothing here needs to be set by hand.</td>
		</tr>
		<tr>
			<td id="global--cattle--systemDefaultRegistry"><a href="./values.yaml#L19">global.cattle.systemDefaultRegistry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>The registry Rancher configured as the cluster's system default registry (air-gapped and mirrored clusters). When set, it replaces the registry part of every image this chart renders and `image.registry` is ignored, following Rancher's convention. Rancher sets it on install from its catalog; leave it empty everywhere else.</td>
		</tr>
		<tr>
			<td id="image"><a href="./values.yaml#L37">image</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
pullPolicy: IfNotPresent
registry: docker.io
repository: otel/opentelemetry-collector-contrib
tag: ""
</pre>
</div>
			</td>
			<td>The OpenTelemetry Collector container image. The `contrib` distribution is required: the `clickhouse` exporter and the `k8s_events` receiver are not present in the core distribution. </td>
		</tr>
		<tr>
			<td id="image--pullPolicy"><a href="./values.yaml#L45">image.pullPolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
IfNotPresent
</pre>
</div>
			</td>
			<td>Image pull policy for the collector container.</td>
		</tr>
		<tr>
			<td id="image--registry"><a href="./values.yaml#L39">image.registry</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
docker.io
</pre>
</div>
			</td>
			<td>Registry that hosts the collector image.</td>
		</tr>
		<tr>
			<td id="image--repository"><a href="./values.yaml#L41">image.repository</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
otel/opentelemetry-collector-contrib
</pre>
</div>
			</td>
			<td>Repository of the collector image, without the registry or tag.</td>
		</tr>
		<tr>
			<td id="image--tag"><a href="./values.yaml#L43">image.tag</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Tag of the collector image. Leave empty to fall back to the chart's `appVersion`.</td>
		</tr>
		<tr>
			<td id="imagePullSecrets"><a href="./values.yaml#L49">imagePullSecrets</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>A list of `{name: <secret>}` references used to pull the collector image from a private registry. </td>
		</tr>
		<tr>
			<td id="livenessProbe"><a href="./values.yaml#L258">livenessProbe</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
failureThreshold: 3
initialDelaySeconds: 5
periodSeconds: 15
successThreshold: 1
timeoutSeconds: 1
</pre>
</div>
			</td>
			<td>Timing for the liveness probe against the `health_check` extension on port 13133. </td>
		</tr>
		<tr>
			<td id="livenessProbe--failureThreshold"><a href="./values.yaml#L275">livenessProbe.failureThreshold</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
3
</pre>
</div>
			</td>
			<td>Consecutive liveness failures before the kubelet restarts the collector. Resist lowering this: a collector under backpressure is still healthy and still answering, and a restart discards everything sitting in the in-memory sending queues, so an over-eager liveness probe turns a temporary trace burst into permanent telemetry loss.</td>
		</tr>
		<tr>
			<td id="livenessProbe--initialDelaySeconds"><a href="./values.yaml#L262">livenessProbe.initialDelaySeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
5
</pre>
</div>
			</td>
			<td>Seconds to wait after the container starts before the first liveness check. The collector parses its configuration and starts every receiver before the `health_check` extension answers, so this only has to cover process startup, not backend connectivity.</td>
		</tr>
		<tr>
			<td id="livenessProbe--periodSeconds"><a href="./values.yaml#L266">livenessProbe.periodSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
15
</pre>
</div>
			</td>
			<td>Seconds between liveness checks. Together with `livenessProbe.failureThreshold` this sets how long a wedged collector keeps running before the kubelet restarts it - here roughly 45 seconds. Longer periods are cheaper but slower to notice a hung process.</td>
		</tr>
		<tr>
			<td id="livenessProbe--successThreshold"><a href="./values.yaml#L279">livenessProbe.successThreshold</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>Consecutive successes needed to consider the container live again after a failed check. Kubernetes requires this to be 1 for liveness probes; it is spelled out here only so the whole probe block can be replaced from values in one piece.</td>
		</tr>
		<tr>
			<td id="livenessProbe--timeoutSeconds"><a href="./values.yaml#L270">livenessProbe.timeoutSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>Seconds a single liveness check may take before it counts as a failure. The `health_check` handler replies from memory with no I/O, so a timeout means the Go runtime is not scheduling goroutines at all - which is exactly the condition a liveness probe should catch.</td>
		</tr>
		<tr>
			<td id="nameOverride"><a href="./values.yaml#L4">nameOverride</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Override the chart name used to build resource names and the `app.kubernetes.io/name` label. Leave empty to use the chart name (`kasm-otel-collector`). </td>
		</tr>
		<tr>
			<td id="nodeSelector"><a href="./values.yaml#L365">nodeSelector</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Node selector for the collector pod - [Kubernetes Node Selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector). </td>
		</tr>
		<tr>
			<td id="podAnnotations"><a href="./values.yaml#L356">podAnnotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the collector pod template. The `checksum/config` annotation is always added on top of these so a configuration change rolls the Deployment. </td>
		</tr>
		<tr>
			<td id="podLabels"><a href="./values.yaml#L360">podLabels</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom labels to add to the collector pod template. </td>
		</tr>
		<tr>
			<td id="podSecurityContext"><a href="./values.yaml#L308">podSecurityContext</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
fsGroupChangePolicy: OnRootMismatch
runAsNonRoot: true
seccompProfile:
    type: RuntimeDefault
</pre>
</div>
			</td>
			<td>Pod-level security context for the collector pod. </td>
		</tr>
		<tr>
			<td id="podSecurityContext--fsGroupChangePolicy"><a href="./values.yaml#L322">podSecurityContext.fsGroupChangePolicy</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
OnRootMismatch
</pre>
</div>
			</td>
			<td>How the kubelet recursively relabels volume ownership before the pod starts. This chart sets no `fsGroup`, so the setting is a no-op at runtime; it is stated because the repository's Kyverno gate requires it on every pod template that claims `kasm.com/security`, and because it is the value you want the moment a `fsGroup` is added.</td>
		</tr>
		<tr>
			<td id="podSecurityContext--runAsNonRoot"><a href="./values.yaml#L312">podSecurityContext.runAsNonRoot</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Refuse to start the collector if its image resolves to a root UID. The collector needs no privileges - it listens on 4317, 4318, and 13133, all above 1024 - so this costs nothing and is what the repository's Kyverno policies expect.</td>
		</tr>
		<tr>
			<td id="podSecurityContext--seccompProfile--type"><a href="./values.yaml#L317">podSecurityContext.seccompProfile.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
RuntimeDefault
</pre>
</div>
			</td>
			<td>Seccomp profile applied to the collector pod. `RuntimeDefault` uses the container runtime's own syscall filter, which the restricted Pod Security Standard requires; `Unconfined` disables filtering entirely and should only be needed on a runtime that ships no default profile.</td>
		</tr>
		<tr>
			<td id="priorityClassName"><a href="./values.yaml#L384">priorityClassName</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>PriorityClass assigned to the collector pod. Leave empty to use the cluster default. </td>
		</tr>
		<tr>
			<td id="processors"><a href="./values.yaml#L143">processors</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
batch:
    sendBatchMaxSize: 2048
    sendBatchSize: 512
    timeout: 5s
batchLogs:
    sendBatchMaxSize: 32
    sendBatchSize: 16
    timeout: 5s
deltatocumulative:
    maxStale: 5m
filterProbes:
    spans:
        - attributes["url.path"] == "/__ready"
        - attributes["url.path"] == "/__healthcheck"
memoryLimiter:
    checkInterval: 1s
    limitPercentage: 80
    spikeLimitPercentage: 20
</pre>
</div>
			</td>
			<td>Tuning for the processors shared by every pipeline. The processor set itself is fixed; these values only adjust its thresholds. </td>
		</tr>
		<tr>
			<td id="processors--batch"><a href="./values.yaml#L161">processors.batch</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
sendBatchMaxSize: 2048
sendBatchSize: 512
timeout: 5s
</pre>
</div>
			</td>
			<td>Batching applied to the traces and metrics pipelines, trading a little export latency for far fewer and larger exporter requests. Logs are batched separately and far more conservatively - see `processors.batchLogs`.</td>
		</tr>
		<tr>
			<td id="processors--batch--sendBatchMaxSize"><a href="./values.yaml#L172">processors.batch.sendBatchMaxSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
2048
</pre>
</div>
			</td>
			<td>Hard upper bound on records in a single batch; anything larger is split across sends. This is what keeps one export under the backend's gRPC max-receive-message-size, and the logs pipeline needs a far lower ceiling for exactly that reason (see `processors.batchLogs.sendBatchMaxSize`).</td>
		</tr>
		<tr>
			<td id="processors--batch--sendBatchSize"><a href="./values.yaml#L168">processors.batch.sendBatchSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
512
</pre>
</div>
			</td>
			<td>Number of spans or metric datapoints that triggers an immediate send without waiting out `processors.batch.timeout`. Larger batches compress better and cost the backend fewer requests; smaller ones get a session's spans into Tempo sooner, which matters when someone is watching a workspace start.</td>
		</tr>
		<tr>
			<td id="processors--batch--timeout"><a href="./values.yaml#L163">processors.batch.timeout</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
5s
</pre>
</div>
			</td>
			<td>Maximum time a batch is held before being sent.</td>
		</tr>
		<tr>
			<td id="processors--batchLogs"><a href="./values.yaml#L176">processors.batchLogs</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
sendBatchMaxSize: 32
sendBatchSize: 16
timeout: 5s
</pre>
</div>
			</td>
			<td>Separate, much smaller batching for logs. Log records run larger than trace/metric records once marshaled, and the shared batch ceiling produced logs batches that decompressed past the backend's default 4MiB gRPC max-recv-message-size, so every logs batch was rejected outright.</td>
		</tr>
		<tr>
			<td id="processors--batchLogs--sendBatchMaxSize"><a href="./values.yaml#L187">processors.batchLogs.sendBatchMaxSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
32
</pre>
</div>
			</td>
			<td>Hard upper bound on log records in one batch. This is the value that actually keeps a logs export under the backend's default 4MiB gRPC max-receive-message-size; the shared trace/metric ceiling of 2048 is what caused every logs batch to come back ResourceExhausted while traces and metrics on the same exporter were fine.</td>
		</tr>
		<tr>
			<td id="processors--batchLogs--sendBatchSize"><a href="./values.yaml#L182">processors.batchLogs.sendBatchSize</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
16
</pre>
</div>
			</td>
			<td>Number of log records that triggers an immediate send. Deliberately two orders of magnitude below the trace/metric equivalent, because a marshaled log record is much larger than a span and an oversized logs batch is rejected by the backend in its entirety rather than partially accepted.</td>
		</tr>
		<tr>
			<td id="processors--batchLogs--timeout"><a href="./values.yaml#L178">processors.batchLogs.timeout</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
5s
</pre>
</div>
			</td>
			<td>Maximum time a logs batch is held before being sent.</td>
		</tr>
		<tr>
			<td id="processors--deltatocumulative"><a href="./values.yaml#L190">processors.deltatocumulative</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
maxStale: 5m
</pre>
</div>
			</td>
			<td>Converts delta histograms to cumulative. Prometheus is cumulative-only and silently drops delta metrics on its OTLP receiver.</td>
		</tr>
		<tr>
			<td id="processors--deltatocumulative--maxStale"><a href="./values.yaml#L192">processors.deltatocumulative.maxStale</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
5m
</pre>
</div>
			</td>
			<td>How long a stale series is tracked before being dropped.</td>
		</tr>
		<tr>
			<td id="processors--filterProbes"><a href="./values.yaml#L195">processors.filterProbes</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
spans:
    - attributes["url.path"] == "/__ready"
    - attributes["url.path"] == "/__healthcheck"
</pre>
</div>
			</td>
			<td>Drops the kubelet probe spans (`/__ready`, `/__healthcheck`). Each is a single-span trace with a hardcoded 200, so nothing is orphaned by dropping them and nothing is learned by keeping them.</td>
		</tr>
		<tr>
			<td id="processors--filterProbes--spans"><a href="./values.yaml#L199">processors.filterProbes.spans</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
- attributes["url.path"] == "/__ready"
- attributes["url.path"] == "/__healthcheck"
</pre>
</div>
			</td>
			<td>OTTL span conditions; a span matching any of these is dropped from the traces pipeline. The agent heartbeat traces are deliberately absent - they are the only continuous signal that the agent is talking to the API server.</td>
		</tr>
		<tr>
			<td id="processors--memoryLimiter"><a href="./values.yaml#L146">processors.memoryLimiter</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
checkInterval: 1s
limitPercentage: 80
spikeLimitPercentage: 20
</pre>
</div>
			</td>
			<td>Backpressure guard. Percentage-based so it stays correct if the container's memory limit ever changes, instead of a hand-recomputed MiB value that silently drifts out of sync.</td>
		</tr>
		<tr>
			<td id="processors--memoryLimiter--checkInterval"><a href="./values.yaml#L151">processors.memoryLimiter.checkInterval</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1s
</pre>
</div>
			</td>
			<td>How often the limiter samples the collector's own heap. This is the resolution of the entire backpressure mechanism: between two samples the collector allocates unchecked, so a longer interval makes it likelier that a burst of session traces carries it past the limit and into an OOMKill before the limiter ever reacts.</td>
		</tr>
		<tr>
			<td id="processors--memoryLimiter--limitPercentage"><a href="./values.yaml#L154">processors.memoryLimiter.limitPercentage</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
80
</pre>
</div>
			</td>
			<td>Percentage of the container memory limit at which the collector starts refusing data.</td>
		</tr>
		<tr>
			<td id="processors--memoryLimiter--spikeLimitPercentage"><a href="./values.yaml#L157">processors.memoryLimiter.spikeLimitPercentage</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
20
</pre>
</div>
			</td>
			<td>Percentage of the container memory limit reserved as spike headroom.</td>
		</tr>
		<tr>
			<td id="readinessProbe"><a href="./values.yaml#L283">readinessProbe</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
failureThreshold: 3
initialDelaySeconds: 5
periodSeconds: 10
successThreshold: 1
timeoutSeconds: 1
</pre>
</div>
			</td>
			<td>Timing for the readiness probe against the `health_check` extension on port 13133. </td>
		</tr>
		<tr>
			<td id="readinessProbe--failureThreshold"><a href="./values.yaml#L300">readinessProbe.failureThreshold</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
3
</pre>
</div>
			</td>
			<td>Consecutive readiness failures before the pod is removed from the Service endpoints. Unlike the liveness threshold this is cheap to trip - the collector keeps running and keeps its queues, it simply stops receiving new OTLP traffic - so lower it if you would rather fail agent exports fast than have them block.</td>
		</tr>
		<tr>
			<td id="readinessProbe--initialDelaySeconds"><a href="./values.yaml#L287">readinessProbe.initialDelaySeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
5
</pre>
</div>
			</td>
			<td>Seconds to wait after the container starts before the first readiness check. Until the first success the pod stays out of the Service endpoints, so this is the floor on how long a rolling update leaves the collector unreachable per replica.</td>
		</tr>
		<tr>
			<td id="readinessProbe--periodSeconds"><a href="./values.yaml#L291">readinessProbe.periodSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
10
</pre>
</div>
			</td>
			<td>Seconds between readiness checks. Deliberately shorter than `livenessProbe.periodSeconds`: readiness decides how quickly a collector that stops answering is pulled out of the Service, and pulling it out early is cheap because the process keeps running.</td>
		</tr>
		<tr>
			<td id="readinessProbe--successThreshold"><a href="./values.yaml#L304">readinessProbe.successThreshold</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>Consecutive successes needed before the pod is put back into the Service endpoints. Raise it if you want a flapping collector to prove itself over more than one probe interval before agent traffic is routed back to it.</td>
		</tr>
		<tr>
			<td id="readinessProbe--timeoutSeconds"><a href="./values.yaml#L295">readinessProbe.timeoutSeconds</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>Seconds a single readiness check may take before it counts as a failure. The `health_check` extension answers from memory, so anything approaching a whole second already means the collector is starved for CPU.</td>
		</tr>
		<tr>
			<td id="receivers"><a href="./values.yaml#L65">receivers</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
k8sEvents:
    enabled: true
</pre>
</div>
			</td>
			<td>Telemetry ingestion points. The OTLP receiver (HTTP on 4318, gRPC on 4317) is always enabled; it is how the Kasm agent components report. </td>
		</tr>
		<tr>
			<td id="receivers--k8sEvents"><a href="./values.yaml#L69">receivers.k8sEvents</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
enabled: true
</pre>
</div>
			</td>
			<td>Ingests Kubernetes Events from the release namespace as log records - what Kubernetes itself is doing to a session (scheduling failures, image pulls, probe failures, OOMKills), correlated with the app traces for the same pod. Enabling this also renders the Role and RoleBinding that permit reading Events.</td>
		</tr>
		<tr>
			<td id="receivers--k8sEvents--enabled"><a href="./values.yaml#L71">receivers.k8sEvents.enabled</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Enable the `k8s_events` receiver and its namespace-scoped Events RBAC.</td>
		</tr>
		<tr>
			<td id="replicaCount"><a href="./values.yaml#L32">replicaCount</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
1
</pre>
</div>
			</td>
			<td>Number of collector replicas to run. The collector holds an in-memory sending queue, so scaling beyond one replica buys throughput, not durability. </td>
		</tr>
		<tr>
			<td id="resources"><a href="./values.yaml#L235">resources</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
limits:
    cpu: 250m
    memory: 512Mi
requests:
    cpu: 50m
    memory: 128Mi
</pre>
</div>
			</td>
			<td>Compute resources for the collector container. Both requests and limits must set cpu and memory; the repository's Kyverno policies reject workloads that omit either. The memory limit is also what `processors.memoryLimiter` computes its percentages against. </td>
		</tr>
		<tr>
			<td id="resources--limits--cpu"><a href="./values.yaml#L249">resources.limits.cpu</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
250m
</pre>
</div>
			</td>
			<td>CPU limit for the collector container. Throttling here does not drop telemetry, it backs the exporter queues up, so the first symptom of a limit set too low is growing queue depth and traces arriving late in Tempo rather than an error in the logs.</td>
		</tr>
		<tr>
			<td id="resources--limits--memory"><a href="./values.yaml#L254">resources.limits.memory</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
512Mi
</pre>
</div>
			</td>
			<td>Memory limit for the collector container, and the number `processors.memoryLimiter.limitPercentage` and `processors.memoryLimiter.spikeLimitPercentage` are percentages of. It therefore decides how large a trace burst the collector can absorb before it starts refusing data - raise this rather than the limiter percentages when the collector is shedding load under normal session churn.</td>
		</tr>
		<tr>
			<td id="resources--requests--cpu"><a href="./values.yaml#L240">resources.requests.cpu</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
50m
</pre>
</div>
			</td>
			<td>CPU request for the collector container. The collector's CPU cost is almost entirely marshaling and compression, so it tracks span and log volume rather than the number of agent pods; this floor covers a quiet agent namespace.</td>
		</tr>
		<tr>
			<td id="resources--requests--memory"><a href="./values.yaml#L244">resources.requests.memory</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
128Mi
</pre>
</div>
			</td>
			<td>Memory request for the collector container. Sized for the steady-state sending queues; the burst headroom lives in `resources.limits.memory`, which is also what the memory limiter measures against.</td>
		</tr>
		<tr>
			<td id="securityContext"><a href="./values.yaml#L326">securityContext</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
allowPrivilegeEscalation: false
capabilities:
    drop:
        - ALL
readOnlyRootFilesystem: true
runAsNonRoot: true
seccompProfile:
    type: RuntimeDefault
</pre>
</div>
			</td>
			<td>Container-level security context for the collector container. </td>
		</tr>
		<tr>
			<td id="securityContext--allowPrivilegeEscalation"><a href="./values.yaml#L330">securityContext.allowPrivilegeEscalation</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
false
</pre>
</div>
			</td>
			<td>Allow a process in the collector container to acquire more privileges than its parent, through setuid binaries or file capabilities. Nothing the collector does needs this, and leaving it false is required by the restricted Pod Security Standard.</td>
		</tr>
		<tr>
			<td id="securityContext--capabilities--drop"><a href="./values.yaml#L350">securityContext.capabilities.drop</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
- ALL
</pre>
</div>
			</td>
			<td>Linux capabilities dropped from the collector container. `ALL` is correct here - the collector binds only unprivileged ports and reads only its own ConfigMap - and dropping everything is what the restricted Pod Security Standard requires.</td>
		</tr>
		<tr>
			<td id="securityContext--readOnlyRootFilesystem"><a href="./values.yaml#L345">securityContext.readOnlyRootFilesystem</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Mount the collector's root filesystem read-only. The generated configuration arrives as a ConfigMap mount and the sending queues are in memory, so nothing this chart deploys writes to disk. Set it false only for a `configOverride` that adds a file-backed component, such as the file_storage extension used for a persistent queue.</td>
		</tr>
		<tr>
			<td id="securityContext--runAsNonRoot"><a href="./values.yaml#L335">securityContext.runAsNonRoot</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Refuse to start the collector container if its image resolves to a root UID. `podSecurityContext.runAsNonRoot` already covers the pod; this restates it at container scope so the container is restricted-compatible when read on its own, which is what Pod Security admission and the repository's Kyverno gate check.</td>
		</tr>
		<tr>
			<td id="securityContext--seccompProfile--type"><a href="./values.yaml#L340">securityContext.seccompProfile.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
RuntimeDefault
</pre>
</div>
			</td>
			<td>Seccomp profile applied to the collector container. Restates `podSecurityContext.seccompProfile.type` at container scope, for the same reason as `securityContext.runAsNonRoot`. Keep the two in step.</td>
		</tr>
		<tr>
			<td id="service"><a href="./values.yaml#L220">service</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
otlpGrpcPort: 4317
otlpHttpPort: 4318
type: ClusterIP
</pre>
</div>
			</td>
			<td>The ClusterIP Service that fronts the collector's OTLP receivers. </td>
		</tr>
		<tr>
			<td id="service--annotations"><a href="./values.yaml#L229">service.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the collector Service.</td>
		</tr>
		<tr>
			<td id="service--otlpGrpcPort"><a href="./values.yaml#L227">service.otlpGrpcPort</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
4317
</pre>
</div>
			</td>
			<td>Service port that maps to the collector's OTLP/gRPC receiver.</td>
		</tr>
		<tr>
			<td id="service--otlpHttpPort"><a href="./values.yaml#L225">service.otlpHttpPort</a></td>
			<td>
int
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
4318
</pre>
</div>
			</td>
			<td>Service port that maps to the collector's OTLP/HTTP receiver.</td>
		</tr>
		<tr>
			<td id="service--type"><a href="./values.yaml#L223">service.type</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
ClusterIP
</pre>
</div>
			</td>
			<td>Kubernetes Service type. The collector is an in-cluster telemetry sink; ClusterIP is correct unless something outside the cluster needs to report to it directly.</td>
		</tr>
		<tr>
			<td id="serviceAccount"><a href="./values.yaml#L54">serviceAccount</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
annotations: {}
create: true
name: ""
</pre>
</div>
			</td>
			<td>The ServiceAccount the collector pod runs as. The `k8s_events` receiver reads Events through this identity, so an externally managed ServiceAccount must be bound to a Role granting `get`/`list`/`watch` on events. </td>
		</tr>
		<tr>
			<td id="serviceAccount--annotations"><a href="./values.yaml#L60">serviceAccount.annotations</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
{}
</pre>
</div>
			</td>
			<td>Custom annotations to add to the collector ServiceAccount.</td>
		</tr>
		<tr>
			<td id="serviceAccount--create"><a href="./values.yaml#L56">serviceAccount.create</a></td>
			<td>
bool
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
true
</pre>
</div>
			</td>
			<td>Create a ServiceAccount for the collector. Set to false to reuse an existing one.</td>
		</tr>
		<tr>
			<td id="serviceAccount--name"><a href="./values.yaml#L58">serviceAccount.name</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
""
</pre>
</div>
			</td>
			<td>Name of the ServiceAccount to use. Generated from the release name when empty.</td>
		</tr>
		<tr>
			<td id="telemetry"><a href="./values.yaml#L205">telemetry</a></td>
			<td>
object
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
logsLevel: info
metricsLevel: basic
</pre>
</div>
			</td>
			<td>The collector's own self-observability, rendered into `service.telemetry`. </td>
		</tr>
		<tr>
			<td id="telemetry--logsLevel"><a href="./values.yaml#L207">telemetry.logsLevel</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
info
</pre>
</div>
			</td>
			<td>Log level for the collector process itself.</td>
		</tr>
		<tr>
			<td id="telemetry--metricsLevel"><a href="./values.yaml#L210">telemetry.metricsLevel</a></td>
			<td>
string
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
basic
</pre>
</div>
			</td>
			<td>Detail level of the collector's internal metrics - one of `none`, `basic`, `normal`, or `detailed`.</td>
		</tr>
		<tr>
			<td id="tolerations"><a href="./values.yaml#L370">tolerations</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Tolerations for the collector pod - [Kubernetes Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/). </td>
		</tr>
		<tr>
			<td id="topologySpreadConstraints"><a href="./values.yaml#L380">topologySpreadConstraints</a></td>
			<td>
list
</td>
			<td>
				<div style="max-width: 520px;">
<pre lang="json">
[]
</pre>
</div>
			</td>
			<td>Topology spread constraints for the collector pod - [Kubernetes Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/). </td>
		</tr>
	</tbody>
</table>

