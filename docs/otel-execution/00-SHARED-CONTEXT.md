# Shared Context — read before any phase

Everything here was verified against the code on 2026-08-04. If code and doc disagree, code wins.

---

## 1. Repos and paths

| Thing                       | Path                                                                 |
| --------------------------- | -------------------------------------------------------------------- |
| Backend (source of truth)   | `/home/ubuntu/kasm_backend` — branch `feature/DEV-31`                |
| Helm chart (work happens here) | `/home/ubuntu/kasm_backend/components/kasm-helm` — **separate git repo**, branch `develop` |
| Chart root                  | `components/kasm-helm/charts/kasm-helm`                              |
| Design plan                 | `components/kasm-helm/docs/otel-integration-plan.md`                 |
| Backend telemetry docs      | `kasm_backend/docs/telemetry/`                                       |

**Reference material in the backend** — read these, don't re-derive:

| File                                                | What it gives you                                   |
| --------------------------------------------------- | --------------------------------------------------- |
| `install/conf/otel/otel-collector-local.yaml`        | The collector config to port (H4)                   |
| `install/conf/otel/otel-collector-remote.yaml`       | Forward-only collector variant (H4/H5 sidecars)     |
| `install/conf/clickhouse/{config.xml,users.xml,init-schema.sql}` | ClickHouse configs to port (H3)          |
| `install/conf/nginx/otel.conf`                       | nginx http-context tracing block (H5)               |
| `install/conf/nginx/stub_status.conf`                 | nginx metrics endpoint (H5)                         |
| `install/conf/nginx/services.d/otel_browser{,_disabled}.conf` | Browser telemetry locations (H5)            |
| `install/docker/docker-compose-all.yaml`              | The authoritative per-service env var list (H2)     |
| `docs/telemetry/reference/configuration.md`           | Every env var and its default                       |

### Environment — verified 2026-08-06, do not re-check

| Fact | Detail |
| ---- | ------ |
| Tooling | **Already installed.** `bin/` has `helm`, `kubectl`, `kind`, `kubeconform`, `kyverno`, `crane`, `helm-docs`, `cloud-provider-kind`; `helm-unittest` is in `.helm/plugins/`. **Do not run `make tools`.** |
| Branch | kasm-helm is already on **`feature/DEV-31`** — the same branch name as the backend. Work there; do not create a branch, and do not commit. |
| Chart version | `1.1200.0-develop` is **correct** — chart versions track Kasm releases and this targets **Kasm 1.20**. Leave `Chart.yaml`, the README badges, and `scripts/set_versions.py` alone. |
| Test images | The DEV-31 backend is a prerequisite, so e2e must run against branch builds. Present locally: `kasmweb/{api,manager,kasm-guac,proxy,rdp-gateway,rdp-https-gateway,agent}-private:feature_DEV-31`. The host is logged in to pull them. |
| **No DEV-31 postgres build** | There is no `postgres-private:feature_DEV-31`. `database.image` must stay `kasmweb/postgres` on a released tag, so e2e cannot just set a chart-wide `useImageTags` — see H6. |
| Airgap | **Out of scope for now.** The two third-party images will move to internal tags later. Still update `images.txt` and anything else normal build/deploy needs. |
| OpenShift | When `isOpenshift: true`, **force the sidecar log path** — see H5. |

`make e2e-*` works on this host: `kind-load-images` derives its image list from `helm template` of the
chart, so the collector and ClickHouse images are picked up automatically; `KIND_EXTRA_IMAGES` (currently
`postgres:16 nginx:1.30-alpine`) is the hook for anything not in the render. `conftest.py` forces
`imagePullPolicy=Never`, so **every** image must be preloaded into kind before a scenario runs.

---

## 2. Hard rules

- **No git operations.** No `git add`, `commit`, `push`, `pull`, `checkout`, `stash`. Leave the tree
  dirty. Both repos.
- **Do not touch** `charts/kasm-helm/Chart.yaml` version fields (the human bumps those via
  `make readme CHART_VERSION=...`), `tests/schemas/`, or anything under `.rendered/`.
- **Do not reformat** files you're editing. The chart mixes 2-space YAML with tabs inside nginx
  config heredocs; match whatever is already in the block you're editing.
- **Never hardcode a release name.** Always `{{ include "kasm.name" ... }}` or
  `$constants.<x>.svc`.
- **Never hardcode an image tag.** Use the `kasm.imageTag` pattern (§4).

---

## 3. Validation commands

Run from `components/kasm-helm`. Tooling lives in `bin/` and is version-pinned in the `Makefile`.

```bash
# make tools       # ALREADY DONE on this host — do not re-run
make lint           # helm lint
make unittest       # helm-unittest suites in charts/kasm-helm/tests/
make render         # renders every tests/values/*.yaml into .rendered/
make kubeconform    # schema-validate the rendered manifests
make kyverno        # policy-check rendered manifests (PSS baseline, probes, resources)
make test           # all of the above — THE GATE
make readme-check   # helm-docs drift check (CI gate)
```

Useful one-liners while iterating:

```bash
# render one scenario and grep
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/default.yaml | grep -A20 'kind: StatefulSet'
# run a single unittest suite
HELM_PLUGINS=$(pwd)/.helm/plugins bin/helm unittest charts/kasm-helm -f 'tests/clickhouse_test.yaml'
```

---

## 4. Chart idioms — exact signatures

All defined in `charts/kasm-helm/templates/_helpers.tpl`.

### Constants

```gotemplate
{{- $constants := (include "kasm.constants" . | fromYaml) -}}
```

Gives `$constants.<key>` with `component`, `svc`, `portName`, `image`, `port` (varies). Existing
keys: `secrets`, `api`, `manager`, `proxy`, `db`, `guac`, `rdpGateway`, `rdpHttpsGateway`.
`$constants.secrets.name` is the Kasm password Secret name.

### Names

```gotemplate
{{ include "kasm.name" (list $ "component" "resource" $zone.name "extra") }}
{{/* → <release>-<component>[-<zone>][-<extra>]; args 3-5 optional */}}
```

### Metadata (name + labels + annotations)

```gotemplate
{{- include "kasm.metadata" (dict "context" $ "component" "api" "resource" "deployment" "zone" $zone.name "include" "all") | indent 2 }}
{{/* include: "all" = name+labels+annotations, "la" = labels+annotations only, "match" = selector labels only */}}
{{/* resource: deployment|statefulSet|service|pod|configMap|secret|job|cronJob|pvc — drives extraAnnotations/extraLabels lookup */}}
```

### Images

```gotemplate
image: {{ printf "%s/%s:%s" .Values.observability.collector.image.registry .Values.observability.collector.image.repository (include "kasm.imageTag" (list . .Values.observability.collector.image.tag "collector")) }}
```

`kasm.imageTag` takes `(list <ctx> <componentTag> <componentName>)`. **Caveat:** if both the
component tag and `.Values.useImageTags` are empty it calls `fail` with a message naming
`.Values.components.<componentName>.image.tag`. Our new images are third-party and pinned by default
(`tag: "0.156.0"` / `"24.12-alpine"`), so the fallback path never fires — but *keep those defaults
non-empty* in `values.yaml` or the chart will fail to render with a misleading message.

### Replicas and resources

```gotemplate
{{- $replicas := ternary .Values.observability.collector.forwarder.replicas (include "replicas.preset" (dict "node" "otel-collector" "size" .Values.deploymentSize)) (gt (int .Values.observability.collector.forwarder.replicas) 0) -}}
resources: {{- include "resources.preset" (dict "node" "otel-collector" "size" $.Values.deploymentSize) | nindent 12 }}
```

Both helpers `fail` on an unknown `node` key, so **you must add preset entries** for any new
component before referencing them (H1 does this for `otel-collector` and `clickhouse`).

### Probes

```gotemplate
livenessProbe:
  {{- include "health.probe" (dict "root" $ "component" "collector" "probeType" "livenessProbe" "type" "http" "path" "/" "port" 13133) | nindent 12 }}
```

`type`: `http` | `https` | `tcp` | `command`. `http`/`https` need `path` plus `port` **or**
`portName`. `command` needs `command` (string or list). Timing overrides are read from
`.Values.components.<component>.healthCheckTiming` — for `db` it reads `.Values.database`. **For our
new components the lookup path won't exist under `components`**, so `health.probe` will fall back to
defaults (5/10/30/3/1) via its `| default dict` chain. That is fine; do not add fake `components.*`
entries just to satisfy it.

### Security context

```gotemplate
{{- include "kasm.securityContext" (list $ 1000 "pod") | nindent 6 }}         {{/* pod-level */}}
{{- include "kasm.securityContext" (list $ 1000 "container") | nindent 10 }}   {{/* container-level */}}
{{- include "kasm.securityContext" (list $ 101 "container" (dict "readOnlyRootFilesystem" false)) | nindent 10 }}
```

Arg 2 is the uid/gid. Defaults to `readOnlyRootFilesystem: true`; pass the 4th arg to relax it.
Honours `.Values.applySecurity` and `.Values.isOpenshift`. **uids to use:** collector `10001`,
ClickHouse `101`.

### Zones

```gotemplate
{{- range $idx, $zone := (include "kasm.zones" $ | fromYamlArray) }}
---
... {{ $zone.name }} ...
{{- end }}
```

Yields one entry named `default` when `kasmZones` is empty. Note the leading `---` **inside** the
range — every zone-scoped template emits a document separator per iteration. Use
`include "kasm.zoneName" $zone.name` when embedding a zone in a resource name.

### Extra volumes/containers merge

```gotemplate
{{- $merged := fromYaml (include "kasm.mergedValues" (dict "root" . "componentName" "proxy")) -}}
{{/* → .volumes .containerMounts .initMounts .extraContainers .extraInitContainers .nginxSidecarMounts */}}
```

`componentName` must be a key under `.Values.components` (or the literal `"database"`). **Our new
components are not under `components`**, so don't call `mergedValues` for them — global
`extraVolumes`/`extraContainers` are not expected to apply to the observability workloads.

### Trusted CA bundle

```gotemplate
{{- include "kasm.trustedCaInit" (list $ "api") | nindent 8 }}
{{- include "kasm.trustedCaEnv" $ | indent 12 }}
{{- include "kasm.trustedCaVolumeMounts" $ | nindent 12 }}
{{- include "kasm.trustedCaVolumes" $ | nindent 8 }}
```

---

## 5. Values and schema conventions

`values.schema.json` has **`"additionalProperties": false` at the root**. Adding a top-level
`observability:` key to `values.yaml` without also adding it to the schema makes `helm lint` and
every `helm template` fail. **They must land in the same change.**

`README.md` is generated by `helm-docs` from `values.yaml` comments. The comment format is
load-bearing:

```yaml
# observability.enabled -- Master switch for the Kasm observability stack.
# Extra prose lines that are not the `key -- desc` line become part of the description.
enabled: true
```

Rules: one `# <full.dotted.path> -- <description>` line immediately above the key; keep the
`#`-prefixed continuation lines; end each block with a bare `#` line where the surrounding file does.
Mirror the description text into `values.schema.json`'s `description` field (the existing entries do
this, sometimes with `\n` for line breaks).

Schema entry style:

```json
"observability": {
  "additionalProperties": false,
  "description": "Kasm observability (OpenTelemetry) settings",
  "title": "observability",
  "type": "object",
  "properties": { "...": {} }
}
```

Use `"enum"` for constrained strings, `"default"` for defaults, `"additionalProperties": true` only
on free-form maps (annotations/labels).

---

## 6. Paid-for gotchas

These cost real debugging time. Do not rediscover them.

1. **nginx `load_module` (H5).** *Verified 2026-08-06:* `kasmweb/proxy-private:feature_DEV-31` does
   contain `/usr/lib/nginx/modules/ngx_otel_module.so`, has `load_module` as line 1 of its
   `nginx.conf`, and passes `nginx -t`. A **released** proxy image predating DEV-31 does **not** have
   the module, which is why the DEV-31 image set is a hard prerequisite. The `kasmweb/proxy` image injects
   `load_module modules/ngx_otel_module.so;` as line 1 of its `/etc/nginx/nginx.conf`. The chart
   mounts its own `nginx.conf` over that path from `nginx-shared-configmap.yaml`, which removes the
   directive — and then every `otel_*` directive is an "unknown directive" **fatal** error and nginx
   will not start. The chart must emit the `load_module` line itself, unconditionally, as the first
   line. The module is inert without `otel.conf`, so this is safe when telemetry is off.

2. **Dead logging config (H2).** `api_server/api_server/server.py` no longer calls
   `logging.config.dictConfig`, so the `logging:` blocks in `api-app-configmap.yaml` /
   `manager-app-configmap.yaml` are ignored. Both templates get deleted in H2.

3. **File logging must be off by default (H2).** Containers run with
   `readOnlyRootFilesystem: true` and no log volume. `kasm_telemetry`'s `init_logging()` does
   `mkdir(parents=True)` + opens `/opt/kasm/current/log/<svc>.log` at startup, so it will crash the
   container unless `KASM_LOG_FILE_ENABLED=false`.

4. **`hostPath` is forbidden by the `baseline` and `restricted` Pod Security Standards**, and reading
   `/var/log/pods` needs `runAsUser: 0`, which `restricted` also forbids. The chart advertises and
   **e2e-tests** restricted-namespace support (`tests/e2e/test_06_pod_security_standards.py`,
   `make e2e-pss`, `tests/kyverno/pod-security.baseline.yaml`). The host-log DaemonSet therefore cannot
   run in such a namespace, which is why the sidecar mechanism survives as a default-off fallback. See
   plan §3a.

5. **The chart creates zero RBAC objects today** — no ServiceAccount, ClusterRole, or Role anywhere in
   `templates/`. The DaemonSet is designed to keep it that way: because its include glob is already
   scoped to the release's own pods, the `container` operator can derive pod metadata from the log file
   path and no `k8sattributes` processor (and therefore no API access) is needed. **Do not add RBAC**
   without flagging it as a deviation.

6. **ClickHouse TLS read path (H0/H3).** `clickhouse_reports.py::_get_client()` passes no
   `verify`/`ca_cert`, so `https://` against Kasm's self-signed cert fails verification. H0 fixes
   this; H3 depends on it.

7. **`kasm.zones` emits `---` per iteration.** When adding a new zone-scoped template, copy the
   `range` + `---` shape from `api-deployment.yaml` exactly, or you'll emit invalid multi-doc YAML.

8. **Collector port 4316 is deliberate.** nginx's `ngx_otel_module` is gRPC-only and cannot present
   a bearer token, so it gets its own unauthenticated receiver. Don't "simplify" it onto 4317.

9. **`helm-unittest` asserts on one rendered document at a time.** For zone-scoped templates that
   emit multiple docs, use `documentIndex:` or `documentSelector:` in the assertion. Existing
   examples: `tests/kasm_zones_test.yaml`.

---

## 7. Facts you'll need repeatedly

**Ports**

| Component        | Port    | Purpose                                        |
| ---------------- | ------- | ---------------------------------------------- |
| Collector        | `4318`  | OTLP/HTTP — all Kasm services send here        |
| Collector        | `4317`  | OTLP/gRPC + bearer auth — out-of-cluster/sidecars |
| Collector        | `4316`  | OTLP/gRPC, **no auth** — nginx only            |
| Collector        | `13133` | health check                                   |
| Collector        | `8888`  | collector self-metrics (Prometheus)            |
| ClickHouse       | `8123`  | HTTP — Kasm reporting read path                |
| ClickHouse       | `9000`  | native — collector write path                  |
| ClickHouse       | `8443`  | HTTPS                                          |
| ClickHouse       | `9440`  | native TLS                                     |
| nginx stub_status| `8090`  | rendered; scraped **only** on the sidecar fallback path (plan §3b) |

**Service names** (`OTEL_SERVICE_NAME`)

`kasm-api`, `kasm-manager`, `kasm-agent`, `kasm-guac`, `kasm-rdp-gateway`,
`kasm-rdp-https-gateway`, `kasm-web` (browser), `kasm-proxy` (injected by the collector, **not** an
env var on the proxy container).

**Images**

`otel/opentelemetry-collector-contrib:0.156.0`, `clickhouse/clickhouse-server:24.12-alpine`

**ClickHouse identity**: database `kasm_otel`, user `kasm_otel`.

**Host log path**: `/var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container>/*.log` — written by the
container runtime (containerd/CRI-O, which is what kind uses). The DaemonSet's include glob is
templated as `/var/log/pods/{{ .Release.Namespace }}_{{ .Release.Name }}-proxy-*/*/*.log`.

**Retention defaults**: logs 30 d, audit logs 365 d, traces 7 d, metrics 90 d.
The collector wants **hours** (`720h`), `init-schema.sql` wants **days** — convert with `mul 24`.

**Sampling default**: 10 % of non-error, non-slow traces; errors and ≥1000 ms always kept.

---

## 8. Per-phase reporting

Append to `PROGRESS.md` when you finish:

```markdown
### H<n> — <name>
- **Status:** done | done-with-deviations | blocked
- **Files added/changed/deleted:** <list>
- **Verification:** which commands you ran and their result
- **Deviations from the phase doc:** <what and why, or "none">
- **Notes for later phases:** <anything H6/H7 must know>
- **Cross-phase findings:** <out-of-scope problems you spotted, or "none">
```
