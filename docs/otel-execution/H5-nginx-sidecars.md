# H5 — nginx tracing, browser telemetry, host-log DaemonSet

**Repo:** `kasm-helm`. **Depends on:** H1 (and H4's Service name).
**Parallel-safe with:** H2, H3, H4. **Size:** large.

This phase contains the single most dangerous change in the effort — read §1 before touching
anything.

**Design note:** nginx log collection uses a **DaemonSet mounting `/var/log/pods`**, not a sidecar with
a shared volume. Read `docs/otel-integration-plan.md` §3, §3a and §3b before starting — they explain
the glob-scoping (which is why there is no RBAC), the Pod Security constraint (which is why the sidecar
survives as a fallback), and the deliberately-dropped nginx connection metrics.

---

## 1. THE BLOCKER: `load_module` must be re-added

The `kasmweb/proxy` image is built from `components/kasm_nginx`. Its `Dockerfile` does:

```dockerfile
COPY resources/ngx_otel_module.${TARGETARCH}.so /usr/lib/nginx/modules/ngx_otel_module.so
RUN sed -i '1i load_module modules/ngx_otel_module.so;' /etc/nginx/nginx.conf
```

The chart mounts its own `nginx.conf` over `/etc/nginx/nginx.conf` from
`nginx-shared-configmap.yaml`, which **removes that directive**. Any `otel_*` directive then produces
`unknown directive "otel_exporter"` and nginx **exits**. This takes down the proxy, i.e. the entire
deployment.

**Fix:** make `load_module modules/ngx_otel_module.so;` the first line of the `nginx.conf` key in
`nginx-shared-configmap.yaml`, unconditionally. `load_module` is only valid in the main context at the
top of the file, before `events {}`. The module is inert unless the `otel_*` directives are present,
so this is safe when telemetry is disabled.

Verify immediately after making this one change, before doing anything else:

```bash
helm template kasm-test charts/kasm-helm -n kasm-test | \
  awk '/nginx.conf: \|/{f=1;next} f{print;exit}'
# must print: load_module modules/ngx_otel_module.so;
```

Then check the other nginx-owning templates — `guac-nginx-configmap.yaml`,
`rdp-gateway-nginx-configmap.yaml`, `rdp-https-gateway-nginx-configmap.yaml`. For each, determine
whether it supplies a full `nginx.conf` (grep for `nginx.conf:`) and whether its container is built
from an image that also injects `load_module`. Add the directive wherever the chart overrides a full
`nginx.conf`; if a sidecar mounts only `conf.d` fragments, it needs nothing. Record what you found per
component.

---

## 2. nginx http-context tracing block

Source: `kasm_backend/install/conf/nginx/otel.conf`.

Add an `otel.conf` key to `nginx-shared-configmap.yaml`, gated on `observability.enabled`, and
`include /etc/nginx/otel.conf;` from inside the `http {}` block of `nginx.conf` — also gated, using the
same condition, so a disabled deployment does not reference a file that was not mounted.

Content, templated:

```
otel_exporter {
    endpoint <collector-service>:4316;
}
otel_service_name  kasm-proxy;
otel_trace          on;
otel_trace_context  propagate;
```

`<collector-service>` is the per-zone **forwarder** Service from H4 — check `PROGRESS.md` for the exact
name. It must be the forwarder, not the gateway: 4316 (unauthenticated OTLP/gRPC, the only thing
`ngx_otel_module` can speak) is exposed by the forwarders only. The gateway exposes 4317 with bearer
auth, which nginx cannot send. **Note the problem:** `nginx-shared-configmap.yaml` is *not* zone-scoped but the collector
Service *is*. Options, in order of preference:

1. Move just the `otel.conf` key into the zone-scoped `proxy-configmaps.yaml` (which already ranges
   over zones and emits a per-zone `proxy-settings` ConfigMap), and mount it from there. Cleanest.
2. Make `nginx-shared-configmap.yaml` zone-scoped. Invasive — it is mounted by four components.
3. ~~Point at a non-zone-scoped collector Service.~~ **Ruled out.** H4 does render one cluster-wide
   Service — the gateway — but it exposes 4317-with-bearer only, and deliberately not 4316. Pointing
   `otel_exporter` at it yields spans rejected for missing auth, which surfaces as "tracing silently
   does nothing", not as a config error. Do not take this route.

Pick option 1 unless something blocks it, and update `proxy-deployment.yaml`'s mounts to match. Record
the choice.

Then add the `otel_trace off;` exclusions and span attributes to `proxy-configmaps.yaml`, porting from
the backend's `install/conf/nginx/services.d/*.conf`:

| Location                        | Change                                                                 | Backend source            |
| ------------------------------- | ---------------------------------------------------------------------- | ------------------------- |
| `/api/admin/`                   | `otel_span_name "$request_method /api/admin/"` + `otel_span_attr` for method/target/status | `admin_api.conf`   |
| `/api/`                         | same shape, `/api/`                                                     | `client_api.conf`         |
| `/manager_api/`                 | same shape                                                              | `manager_api.conf`        |
| agent location (if present)     | same shape                                                              | `agent.conf`              |
| `/checkvalid`                   | `otel_trace off;`                                                       | `closest.conf`            |
| `/health`                       | `otel_trace off;`                                                       | `health.conf`             |
| internal auth subrequests (`/kasm_connect`, `/vm_connect`) | `otel_trace off;`                            | `upstream_proxy.conf`, `kasmguac.conf` |
| long-lived session tunnels (`/desktop/`, guac `vnc.html*`) | `otel_trace off;` plus `otel_span_attr kasm.kasm_id` / `kasm.kasm_user_name` where the backend has them | `upstream_proxy.conf`, `kasmguac.conf` |

Important: in the backend, several of these `otel_trace off;` lines are **commented out** pending
validation (see `upstream_proxy.conf` and `kasmguac.conf`). Match the backend's committed state — if a
directive is commented there, comment it here too and keep the explanatory comment. Do not
unilaterally enable tracing on WebSocket tunnels; that decision belongs to the backend branch.

Gate all of these on `observability.enabled`. Confirm by rendering with `observability.enabled=false`
and checking that no `otel_` directive appears anywhere.

## 3. nginx metrics endpoint (rendered, not scraped)

Source: `kasm_backend/install/conf/nginx/stub_status.conf`.

Add a `stub_status.conf` key to the proxy's config. The backend file declares a whole
`server { listen 8090; ... }` block, so it must be included at **http** level, not inside the existing
`server`. Check how `proxy-configmaps.yaml`'s `listener.conf`/`listener_http.conf` are included from
`nginx.conf` and add `stub_status.conf` the same way — **not** into `services.d/`, which is included
inside a `server` block.

Changes from the Docker version:
- Keep `listen 0.0.0.0:8090;` (a DaemonSet cannot reach pod loopback, and the sidecar fallback can
  reach either), but keep an ACL: `allow 127.0.0.1; deny all;` plus the pod CIDR is not knowable, so
  simplest correct posture is loopback-only `allow` — the only consumer today is the optional sidecar,
  which shares the pod's network namespace. Document that anything else must be explicitly allowed.
- Keep `otel_trace off;` on the location.

Add `containerPort: 8090` (name `stub-status`) to the proxy container in `proxy-deployment.yaml`, gated
on `observability.enabled`.

**Do not add an `nginx/metrics` receiver anywhere.** Per plan §3b, nginx connection metrics are
deliberately not collected in Kubernetes: a DaemonSet cannot reach pod loopback, and scraping the proxy
Service round-robins across replicas, which corrupts cumulative counters. The server block is rendered
because it is cheap and the sidecar fallback (§7) can use it. Record this as a follow-up in
`PROGRESS.md`, not as a bug.

## 4. Browser telemetry

Sources: `install/conf/nginx/services.d/otel_browser.conf` and `otel_browser_disabled.conf`.

Add an `otel_browser.conf` key to the proxy **services** ConfigMap (these are `location` blocks, so
`services.d/` is correct). Render the enabled variant when
`observability.enabled` **and** `observability.browser.enabled`; otherwise render the disabled stub.
There is always exactly one of the two — the endpoint must never 404, or the web UI logs console
errors.

Port verbatim, including:
- `/otel-config.js` returning `window.__OTEL__={"enabled":true,"endpoint":"/api/client/telemetry","serviceName":"kasm-web"};`
- `/otel-time` returning `{"server_time_ms":$msec}` with the comment explaining that `$msec` is
  seconds-with-ms-resolution and the browser multiplies by 1000
- `otel_trace off;` and `Cache-Control "no-store"` on both

The browser posts to `/api/client/telemetry/{traces,logs,metrics}`, which are ordinary API endpoints
already covered by the existing `/api/` location — no new proxy config needed for them. Confirm the
`/api/` location does not exclude them (it should not; it is a prefix match).

## 5. Force the stdout access log to JSON when telemetry is on

The DaemonSet parses the proxy's **stdout** with a `json_parser`, so the access log written there must
be `json_combined` regardless of `logFormat`.

In `nginx-shared-configmap.yaml`'s `logging.conf` key, the current line is:

```
access_log /dev/stdout {{ ternary "json_combined" "main" (eq .Values.logFormat "json") }};
error_log  /var/log/nginx/error.log warn;
```

Change to: `json_combined` when `observability.enabled`, else honour `logFormat` as today. Keep the
single `access_log` line — **no second destination, no shared volume.** For example:

```
access_log /dev/stdout {{ if .Values.observability.enabled }}json_combined{{ else }}{{ ternary "json_combined" "main" (eq .Values.logFormat "json") }}{{ end }};
```

**`error_log` must go to stderr, not a file**, so the runtime captures it for the DaemonSet:

```
error_log  /dev/stderr warn;
```

Check what depends on `/var/log/nginx/error.log` before changing it — the `kasm-proxy-log-tmp`
`emptyDir` is mounted at `/var/log/nginx` and nginx also needs that path writable for its temp
directories (`client_body_temp`, `proxy_temp`, …), so **keep the volume and the mount**; only the
`error_log` destination changes. Confirm nginx starts with `/dev/stderr` under
`readOnlyRootFilesystem: true`.

When `observability.nginxLogs.enabled` (the §7 fallback), *additionally* write both logs to files in
the shared volume — that path needs files, the DaemonSet path does not.

## 6. The host-log DaemonSet

Two new templates. Both render when `observability.enabled` **and** `observability.hostLogs.enabled`.
**Not** zone-scoped — one DaemonSet covers every node and therefore every zone's proxy pods.

### 6a. `templates/otel-collector-daemonset-configmap.yaml`

Start from `kasm_backend/install/conf/otel/otel-collector-remote.yaml` (the forward-only variant), then:

**Receivers** — one `filelog` receiver, scoped by glob:

```yaml
receivers:
  filelog/kasm_proxy:
    include:
      - /var/log/pods/{{ .Release.Namespace }}_{{ .Release.Name }}-proxy-*/*/*.log
      {{- range .Values.observability.hostLogs.extraSelectors }}
      - /var/log/pods/{{ $.Release.Namespace }}_{{ . }}/*/*.log
      {{- end }}
    exclude:
      - /var/log/pods/*/otel-collector*/*.log
    start_at: end
    include_file_path: true
    operators:
      - type: container
        add_metadata_from_filepath: true
      - type: router
        routes:
          - expr: 'attributes["log.iostream"] == "stdout"'
            output: access_json
          - expr: 'true'
            output: error_regex
      # ... access_json: the json_parser chain from otel-collector-local.yaml
      # ... error_regex:  the regex_parser chain from otel-collector-local.yaml
```

Notes that matter:

- The `container` operator parses the CRI log format **and**, with
  `add_metadata_from_filepath: true` (the default — set it explicitly for clarity), derives
  `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name` and the pod UID **from the file path**.
  That is why there is **no `k8sattributes` processor, no ServiceAccount and no RBAC** in this phase.
  Do not add them.
- Verify the exact attribute name the `container` operator uses for the stream against the collector
  version in use (`log.iostream` at the time of writing) — render the config, then confirm against the
  0.156.0 `container` operator documentation. If it differs, fix the router expression; getting this
  wrong silently sends error-log lines through the JSON parser.
- Port the `json_parser` / `severity_parser` / `add` / `move` operator chains **verbatim from
  `otel-collector-local.yaml`** (the local variant is newer than the remote one — it has
  `overwrite_text: true` on the severity parsers and the `body` composition operator). These mappings
  were iterated on; do not rewrite them. Set `service.name: kasm-proxy` and
  `application: kasm-proxy` as the local variant does.
- `start_at: end` matches the Docker behaviour (don't replay history on first start).
- The `exclude` entry is belt-and-braces; the glob already cannot match collector pods.

**Extensions** — offset persistence, gated on `hostLogs.persistOffsets`:

```yaml
extensions:
  file_storage/checkpoints:
    directory: /var/lib/otelcol/file_storage
```

and reference it from the filelog receiver's `storage:` key. Without it, a DaemonSet restart re-reads
or skips lines depending on `start_at`.

**Processors** — `memory_limiter` and `batch` only. No `tail_sampling`: there is no traces pipeline
here, and in any case sampling lives on the gateway alone (plan §3).

**Exporters** — a single `otlp` (gRPC) exporter to the **cluster gateway** Collector on 4317:

- endpoint: `{{ $constants.otel.gatewaySvc }}:4317`. The gateway is cluster-wide, so this needs **no**
  zone resolution — do not use `kasm.primaryZone` here. (An earlier revision of this doc sent the
  DaemonSet to the primary zone's collector; that was before the forwarder/gateway split. The DaemonSet
  has no zone affinity, so routing it through an arbitrary zone bought nothing.) Cross-check the name
  against H4's `PROGRESS.md` entry.
- `auth` via `bearertokenauth` with `${env:OTEL_BEARER_TOKEN}`.
- `tls: insecure: true` — in-cluster.
- When `collector.externalEndpoint` is set there is no gateway: export to that endpoint over
  OTLP/HTTP with no bearer token. Handle it, or skip rendering the DaemonSet entirely and document why.

**Pipelines** — `logs` only, from `filelog/kasm_proxy`.

### 6b. `templates/otel-collector-daemonset.yaml`

- `kind: DaemonSet`, `apiVersion: apps/v1`. Metadata via `kasm.metadata` with
  `"component" "otel-hostlogs" "resource" "daemonSet"`. **Check `kasm.metadata` handles a `daemonSet`
  resource key** — it drives the `extraAnnotations`/`extraLabels` lookup, and `values.yaml` has no
  `extraAnnotations.daemonSet`. Either add that key to `values.yaml`+schema (preferred, consistent) or
  pass an existing resource type; record which.
- Volumes:
  ```yaml
  - name: varlogpods
    hostPath:
      path: /var/log/pods
      type: Directory
  - name: otelcol-checkpoints        # only when persistOffsets
    hostPath:
      path: /var/lib/otelcol/file_storage
      type: DirectoryOrCreate
  ```
  Mount `varlogpods` **`readOnly: true`**. The checkpoint volume must be writable.
- **Security context — this one is not `kasm.securityContext`.** Reading `/var/log/pods` requires
  root, and that helper forces a non-root uid and honours `applySecurity`. Write an explicit block:
  `runAsUser: 0`, `runAsGroup: 0`, `readOnlyRootFilesystem: true`,
  `allowPrivilegeEscalation: false`, `capabilities: {drop: ["ALL"]}`, `privileged: false`,
  `seccompProfile: {type: RuntimeDefault}`. Do **not** set `hostNetwork`, `hostPID` or `hostIPC` —
  `tests/kyverno/no-host-namespaces.yaml` forbids them and they are not needed.
- `tolerations` so it schedules on every node including tainted control-plane nodes: expose
  `observability.hostLogs.tolerations` (default `[]`) and, separately, default to tolerating
  `node-role.kubernetes.io/control-plane:NoSchedule` — the API/proxy pods will not be there, so
  strictly it is optional; leave it to the values and default to `[]`.
- `nodeSelector`/`affinity`: honour the chart-wide `.Values.nodeSelector`/`.Values.affinity` like other
  workloads, plus `observability.hostLogs.nodeSelector` if you add one (optional; skip unless trivial).
- Env: `OTEL_BEARER_TOKEN` from `secretKeyRef` `$constants.secrets.name` / `otel-bearer-token`.
- Resources: `resources.preset` node `otel-sidecar` (same light profile), or
  `hostLogs.resources` when set.
- Probes on `:13133` when `applyHealthChecks`, as with the central collector.
- Config mount at `/etc/otelcol-contrib/config.yaml` (subPath `config.yaml`).
- Add the same `checksum/config` pod annotation as the central collector so config edits roll the pods.

### 6c. Mutual exclusion

`hostLogs.enabled` and `nginxLogs.enabled` both collect nginx logs; enabling both double-stores every
line. Add to `kasm.observabilityValidate` (H1):

```
fail: observability.hostLogs.enabled and observability.nginxLogs.enabled are mutually exclusive —
      hostLogs uses a node-level DaemonSet, nginxLogs uses a per-pod sidecar. Pick one.
```

## 6d. OpenShift forces the sidecar path

On OpenShift, a hostPath + `runAsUser: 0` DaemonSet needs a SecurityContextConstraint
(`hostmount-anyuid` or `privileged`) plus a ServiceAccount bound to it — which would reintroduce exactly
the RBAC the glob-scoping design avoids, and the chart ships no SCC.

**Decision: when `.Values.isOpenshift` is true, do not render the DaemonSet.** Treat it as though
`hostLogs.enabled` were false and use the §7 sidecar path instead. Two ways to implement it; pick the
first unless it reads badly:

1. Resolve an effective flag once in a helper (e.g. `kasm.hostLogsEnabled` → `and hostLogs.enabled (not
   isOpenshift)`) and gate both templates plus the mutual-exclusion check on it. Every consumer then
   agrees automatically.
2. Gate each template on `and .Values.observability.hostLogs.enabled (not .Values.isOpenshift)`.

Whichever you choose, `isOpenshift: true` with `hostLogs.enabled: true` and `nginxLogs.enabled: false`
must **not** silently collect nothing. Either auto-enable the sidecar in that combination, or `fail` with
a message telling the operator to set `nginxLogs.enabled: true`. **Prefer failing loudly** — silently
swapping a customer's telemetry topology is worse than a clear error. Record which you did.

## 7. The sidecar fallback (default off)

`hostPath` volumes and `runAsUser: 0` are both forbidden by the `baseline` and `restricted` Pod
Security Standards, and this chart advertises and e2e-tests restricted-namespace support. So the
sidecar mechanism is **retained, default off**, as the only way to collect nginx logs in a restricted
namespace.

When `observability.nginxLogs.enabled`:

- A dedicated `emptyDir` (`kasm-proxy-otel-logs`, `sizeLimit` from `nginxLogs.sizeLimit`) mounted at
  `/var/log/nginx/otel` in both the proxy container and the sidecar.
- nginx additionally writes `access_log /var/log/nginx/otel/access_json.log json_combined;` and
  `error_log /var/log/nginx/otel/error.log warn;` (§5).
- A sidecar container via the shared `kasm.otelSidecar` helper (§8), with a `filelog` config reading
  those two files. It uses the **same operator chains** as the DaemonSet minus the `container` and
  `router` operators (these are plain files, not CRI logs, and the two files are already separated), so
  factor the operator chains into a named template both configs include rather than duplicating them.
- This path *can* scrape `nginx/metrics` at `http://localhost:8090/stub_status` — include it here, so
  restricted-namespace deployments actually get the connection metrics the DaemonSet path drops.

## 8. `kasm.otelSidecar` and app-pod file logs

Add the `kasm.otelSidecar` helper to `_helpers.tpl` (H1 reserved the name):

```gotemplate
{{- include "kasm.otelSidecar" (dict "context" $ "zone" $zone.name "configMap" <name> "volumeName" <name> "mountPath" <path>) | nindent 8 }}
```

The container: `$constants.otel.image`, `kasm.securityContext (list $ 10001 "container")`,
`resources.preset` node `otel-sidecar`, the shared log volume mounted **read-only**, its own config at
`/etc/otelcol-contrib/config.yaml`, probes on 13133 when `applyHealthChecks`, no published ports.

Used by two callers: §7's nginx fallback, and `observability.fileLogs` — when that is enabled, each
component in `fileLogs.components` gets an `emptyDir` at `/opt/kasm/current/log` (`sizeLimit` from
`fileLogs.sizeLimit`) plus a sidecar whose `filelog` reads `*.log` from it and parses each line with a
`json_parser`. The file format is JSON — see `libs/telemetry/kasm_telemetry/logs.py::JsonFormatter`
for the exact fields (`timestamp`, `level`, `logger`, `module`, `line`, `message`). H2 already sets
`KASM_LOG_FILE_ENABLED=true` and `KASM_LOG_FILE_PATH` for those components; your job is the volume and
the sidecar. Guac writes `kasm_guac.<DATE>.log` via its own logger, so a `*.log` glob covers both.

---

## Verify

```bash
make lint render kubeconform kyverno unittest

# THE critical check
helm template kasm-test charts/kasm-helm -n kasm-test | awk '/nginx.conf: \|/{f=1;next} f{print;exit}'
# → load_module modules/ngx_otel_module.so;

# disabled render has no otel directives at all, but keeps load_module
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.enabled=false | grep -c 'otel_'      # → 0
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.enabled=false | grep -c load_module  # → ≥1

# DaemonSet: present by default, glob is namespace+release scoped, hostPath read-only
helm template kasm-test charts/kasm-helm -n kasm-test | grep -A2 'kind: DaemonSet'
helm template kasm-test charts/kasm-helm -n kasm-test | grep 'var/log/pods/kasm-test_kasm-test-proxy-'
helm template kasm-test charts/kasm-helm -n kasm-test | grep -B2 -A4 'hostPath' | grep readOnly
# ...and NO RBAC anywhere
helm template kasm-test charts/kasm-helm -n kasm-test | grep -cE 'kind: (ServiceAccount|ClusterRole|ClusterRoleBinding|Role|RoleBinding)'  # → 0
# ...and absent when disabled
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.hostLogs.enabled=false | grep -c 'kind: DaemonSet'  # → 0

# access log is JSON when telemetry is on, honours logFormat when off
helm template kasm-test charts/kasm-helm -n kasm-test --set logFormat=log | grep 'access_log /dev/stdout'          # → json_combined
helm template kasm-test charts/kasm-helm -n kasm-test --set logFormat=log --set observability.enabled=false \
  | grep 'access_log /dev/stdout'                                                                                  # → main

# mutual exclusion fails
helm template kasm-test charts/kasm-helm -n kasm-test \
  --set observability.hostLogs.enabled=true --set observability.nginxLogs.enabled=true 2>&1 | grep -i 'mutually exclusive'

# OpenShift: no DaemonSet
helm template kasm-test charts/kasm-helm -n kasm-test --set isOpenshift=true 2>&1 | grep -c 'kind: DaemonSet'  # → 0 (or a clear failure telling the operator to enable nginxLogs)

# sidecar fallback: off by default, on when asked
helm template kasm-test charts/kasm-helm -n kasm-test | grep -c 'otel-sidecar'   # → 0
helm template kasm-test charts/kasm-helm -n kasm-test \
  --set observability.hostLogs.enabled=false --set observability.nginxLogs.enabled=true | grep -c 'otel-sidecar'  # → ≥1

# both collector configs parse as YAML
helm template kasm-test charts/kasm-helm -n kasm-test | python3 -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind')=='ConfigMap' and ('daemonset' in d['metadata']['name'] or 'sidecar' in d['metadata']['name']):
        for k,v in d['data'].items(): yaml.safe_load(v); print('parses:', d['metadata']['name'], k)
"
```

**Two things rendering cannot check.** Say so explicitly in `PROGRESS.md` if you cannot run them:

1. **nginx config syntax.** Write the rendered config keys to a directory and run
   `docker run --rm -v /tmp/nginxconf:/etc/nginx/conf.d:ro kasmweb/proxy:1.19.0-rolling nginx -t`.
2. **`kubectl kustomize`-free PSS check.** The Kyverno baseline policy in `tests/kyverno/` may not
   cover hostPath. Confirm by hand that the DaemonSet would be rejected in a restricted namespace, and
   that `make kyverno` still passes for the rest of the chart — if the policy *does* flag the DaemonSet,
   that is correct behaviour, and the fix is to exclude the DaemonSet from that policy run (with a
   comment) rather than to weaken the DaemonSet. Record what you did.

## Definition of done

- `load_module` is line 1 of every chart-supplied full `nginx.conf`, unconditionally.
- With telemetry disabled: zero `otel_*` directives, `load_module` still present, proxy otherwise
  unchanged.
- DaemonSet + its ConfigMap render by default, with a namespace- and release-scoped include glob, a
  read-only `/var/log/pods` hostPath, an explicit root security context, and **zero RBAC objects
  anywhere in the chart**.
- Operator chains ported verbatim from `otel-collector-local.yaml`; stream routing verified against the
  collector's actual `container`-operator attribute name.
- stdout access log is `json_combined` whenever telemetry is on; `error_log` goes to stderr.
- Sidecar fallback renders only when explicitly enabled, and enabling both mechanisms fails the render.
- `isOpenshift: true` never renders the DaemonSet, and does not silently end up collecting nothing.
- Browser config endpoint always renders, in exactly one of its two variants.
- No `nginx/metrics` receiver on the DaemonSet path; present on the sidecar path.
- `make lint render kubeconform kyverno unittest` green.

## Hand-off notes

Record in `PROGRESS.md`: which templates needed `load_module`; where `otel.conf` ended up (§2 decision);
the DaemonSet's include glob exactly as rendered; the stream attribute name you verified; the
`kasm.metadata` `daemonSet` resource-key decision; whether `nginx -t` was run; the Kyverno/PSS outcome;
and any `otel_trace off;` left commented to match the backend. H6 needs the glob and the volume names.

Add to **Follow-ups**: nginx connection metrics are not collected on the default (DaemonSet) path —
options are `k8s_observer` + `receiver_creator` with pod-list RBAC, or the sidecar path.
