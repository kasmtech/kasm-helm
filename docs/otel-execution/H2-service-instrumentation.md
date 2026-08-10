# H2 — Instrument the Kasm services

**Repo:** `kasm-helm`. **Depends on:** H1. **Parallel-safe with:** H3, H4, H5.
**Size:** medium.

Wire the OTel SDK env into every Kasm workload and remove the now-dead JSON-logging ConfigMaps.

---

## 1. Add telemetry env to each workload

Use the `kasm.otelEnv` helper from H1 (read its final signature in `PROGRESS.md` first). Insert the
include at the **end** of each container's existing `env:` list, so existing env ordering — which
some tests assert on by index — is unchanged.

| Template                                | Container            | `serviceName`              | `python` flag | `component` |
| --------------------------------------- | -------------------- | -------------------------- | ------------- | ----------- |
| `api-deployment.yaml`                   | api                  | `kasm-api`                 | true          | `api`       |
| `manager-deployment.yaml`               | manager              | `kasm-manager`             | true          | `manager`   |
| `guac-statefulset.yaml`                 | guac                 | `kasm-guac`                | false         | `guac`      |
| `rdp-gateway-deployment.yaml`           | rdp-gateway          | `kasm-rdp-gateway`         | false         | —           |
| `rdp-https-gateway-statefulset.yaml`    | rdp-https-gateway    | `kasm-rdp-https-gateway`   | false         | —           |

The **proxy** gets no `OTEL_SERVICE_NAME` env — `kasm-proxy` is injected by the Collector's receivers.
Do not add telemetry env to `proxy-deployment.yaml` in this phase (H5 owns the proxy).

Each of these templates is zone-scoped (`range` over `kasm.zones`), so pass
`"zone" $zone.name` — the collector Service is per-zone.

Also add the ClickHouse read-path env to **api and manager only**:

```gotemplate
{{- include "kasm.clickhouseEnv" (dict "context" $) | nindent 12 }}
```

Manager needs it too: it runs the system-metrics collection job.

### nginx sidecars in the gateway pods

`guac-statefulset.yaml`, `rdp-gateway-deployment.yaml` and `rdp-https-gateway-statefulset.yaml` each
run an nginx sidecar container. Those sidecars get **no** telemetry env — they are covered by H5's
nginx work. Make sure you add env to the *application* container in each pod, not the nginx one.

## 2. Guac logging env

`guac_server/gclient/config.js` in the backend now reads three new env vars. Add them to the guac
container in `guac-statefulset.yaml` so log file naming is predictable and matches the sidecar's
`filelog` glob in H5:

```yaml
- name: LOG_FILE_NAME_PATTERN
  value: "kasm_guac.<DATE>.log"
- name: LOG_DATE_FORMAT
  value: "YYYY.MM.DD"
- name: LOG_TIMESTAMP_FORMAT
  value: "YYYY-MM-DD HH:mm:ss.SSS"
```

Only emit these when `observability.fileLogs.enabled` and `guac` is in
`observability.fileLogs.components`; otherwise the defaults in `config.js` are fine and the env is
noise. (Guac writes log files unconditionally today, to a path inside the container — leave that
behaviour alone.)

## 3. Delete the dead app ConfigMaps

**Read `docs/otel-integration-plan.md` §4 before doing this** — the reasoning matters.

`api_server/api_server/server.py` on `feature/DEV-31` no longer calls
`logging.config.dictConfig(app_config['logging']['api_server'])`, so the `logging:` blocks in these
ConfigMaps are mounted and ignored.

### 3a. Verify equivalence first

Before deleting, confirm the non-`logging:` keys really are equivalent to the image defaults:

```bash
cd /home/ubuntu/kasm_backend
# what the chart mounts, minus the logging block:
sed -n '/^    database:/,/^    logging:/p' components/kasm-helm/charts/kasm-helm/templates/api-app-configmap.yaml
sed -n '/^    manager:/,$p'                components/kasm-helm/charts/kasm-helm/templates/api-app-configmap.yaml
# what the image ships:
grep -v -A0 '' install/conf/app/api/api.app.config.yaml | sed -n '/^database:/,/^logging:/p'
sed -n '/^manager:/,$p' install/conf/app/api/api.app.config.yaml
```

The `database`, `server`, `manager` and `share` keys should match the image's baked config, and every
one of them is overridden at runtime by the env vars already set in `api-deployment.yaml` /
`manager-deployment.yaml` (`POSTGRES_*`, `SERVER_*`, `KASM_*`). If you find a value that differs from
the image default **and** has no corresponding env var, stop: do not delete that ConfigMap, keep it
with only that key, and record the finding in `PROGRESS.md`.

### 3b. Delete

- `rm charts/kasm-helm/templates/api-app-configmap.yaml`
- `rm charts/kasm-helm/templates/manager-app-configmap.yaml`
- In `api-deployment.yaml`: remove the `{{- if eq $.Values.logFormat "json" }}` volumeMount block
  (mountPath `/opt/kasm/current/conf/app/api/api.app.config.yaml`) and the matching `volumes` entry
  (`kasm-api-app-config`).
- In `manager-deployment.yaml`: the same for `kasm-manager-app-config`.

Grep for stragglers:

```bash
grep -rn "app-config\|app.config.yaml" charts/kasm-helm/ tests/
```

`tests/configmaps_content_test.yaml` and `tests/log_format_test.yaml` almost certainly reference
these. Update them in this phase: remove assertions about the deleted ConfigMaps, and re-scope
`log_format_test.yaml` to what `logFormat` still controls (nginx `json_combined` access log format in
`nginx-shared-configmap.yaml`, and the Postgres JSON symlink `command`/`args` in
`db-statefulset.yaml`). Leave the e2e test to H6.

## 4. `logFormat` documentation

In `values.yaml`, update the `logFormat` comment to state the narrowed meaning:

```yaml
# logFormat -- Log format written to the console by the Kasm Proxy (nginx) and Kasm DB. Valid options
# are: json, log
#
# NOTE: This no longer affects the API and Manager services. Their console output is always
# human-readable text; their structured logs are exported over OpenTelemetry instead. See
# `observability` and [Observability](./docs/observability.md) for how to collect them.
#
logFormat: log
```

Mirror the new text into `values.schema.json`'s `logFormat.description`.

---

## Verify

```bash
make lint
make render
make unittest
# confirm env landed on every service, in every scenario
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/default.yaml \
  | grep -E 'OTEL_SERVICE_NAME|KASM_LOG_FILE_ENABLED|KASM_CLICKHOUSE_ENDPOINT' | sort | uniq -c
# confirm the SDK is off when disabled, and nothing else leaks
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.enabled=false \
  | grep -E 'OTEL_|KASM_CLICKHOUSE_'
# confirm the deleted configmaps are gone
helm template kasm-test charts/kasm-helm -n kasm-test --set logFormat=json | grep -c 'app.config.yaml' # → 0
```

Expected: five distinct `OTEL_SERVICE_NAME` values, `KASM_LOG_FILE_ENABLED=false` on api/manager/guac,
`KASM_CLICKHOUSE_ENDPOINT` on api and manager only. With `observability.enabled=false`, the only
`OTEL_` output should be `OTEL_SDK_DISABLED`.

## Definition of done

- All five workloads carry telemetry env; api and manager carry ClickHouse env.
- Both app ConfigMaps deleted along with their mounts and volumes; no dangling references.
- `logFormat`'s narrowed meaning documented in values + schema.
- `make lint render unittest` green, with `configmaps_content_test.yaml` and `log_format_test.yaml`
  updated rather than deleted.

## Hand-off notes

Record in `PROGRESS.md`: the equivalence check result from §3a, which existing test suites you had to
change and how, and confirmation of whether `KASM_LOG_FILE_ENABLED` ended up `false` everywhere by
default. H6 writes the replacement e2e coverage and needs to know exactly what `logFormat` means now.
