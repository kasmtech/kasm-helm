# H6 — Unit test suites and end-to-end scenarios

**Repo:** `kasm-helm`. **Depends on:** H2, H3, H4, H5. **Size:** large.

Read `PROGRESS.md` first — the exact names, ports, volumes and endpoints the earlier phases chose are
recorded there, and every assertion here depends on them. Do not guess; grep the rendered output.

---

## 1. helm-unittest suites

New files under `charts/kasm-helm/tests/`. Follow the conventions in the existing suites
(`tests/healthchecks_test.yaml` is a good short model, `tests/kasm_zones_test.yaml` shows
multi-document handling).

Conventions that matter:
- `suite:` a short human description; `templates:` lists the templates under test.
- Zone-scoped templates emit one document per zone — use `documentIndex:` or `documentSelector:` in
  assertions, and add at least one multi-zone case per suite that renders per zone.
- Prefer `equal`/`contains`/`exists`/`notExists`/`matchRegex` over `matchSnapshot`; the chart has no
  snapshot files today and adding them creates churn.
- Use `asserts: - failedTemplate: {errorMessage: "..."}` for the validation cases.

| File                                       | Must assert                                                                                                                        |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `otel_collector_test.yaml`                 | Forwarder Deployment/Service/ConfigMap render by default; all absent when `observability.enabled=false`; all absent when `collector.externalEndpoint` set; one forwarder set per zone with two `kasmZones`; `existingConfigMap` suppresses the rendered ConfigMap and is the mounted source; external Service renders only when `externalService.enabled` and exposes only 4317; checksum annotation present. **Gateway:** exactly one Deployment/Service/ConfigMap per release regardless of zone count, `replicas: 1`, `strategy: Recreate`, and `gateway.existingConfigMap` suppresses only the gateway ConfigMap (the forwarder's still renders, and vice versa) |
| `otel_collector_config_test.yaml`           | **`tail_sampling:` appears exactly once across the whole rendered output, and each `clickhouse/{logs,traces,metrics}` exporter exactly once, asserted with two zones configured *and* with `collector.replicas=3` — this is the regression test for the split that produces silently-incomplete traces; the forwarder config must contain neither**; the forwarder's `otlp` exporter targets the gateway Service on 4317 with `${env:OTEL_BEARER_TOKEN}`; `sampling_percentage` tracks `tailSamplePercentage`; the three `ttl:` values track retention days × 24; `${env:CLICKHOUSE_PASSWORD}` and `${env:OTEL_BEARER_TOKEN}` present and **no literal credential**; `debug` exporter replaces the ClickHouse exporters when `clickhouse.enabled=false`; `otlphttp/external` appended to all three pipelines when forwarding is set; DSN uses 9440+`secure=true`+`skip_verify=true` when `clickhouse.tls=true` and 9000 when false; standalone DSN passed through verbatim; **no `filelog` or `nginx/metrics` receiver in the central config**; with a non-default `observability.clickhouse.database` (e.g. `kasm_tenant_a`), assert **all three** `clickhouse/{logs,traces,metrics}` exporters' `database:` key equal it and none is left as the literal `kasm_otel` — a partial template would split reads from writes with no error anywhere (H0b) |
| `otel_env_test.yaml`                        | each of the five workloads gets its correct `OTEL_SERVICE_NAME`; endpoint points at the per-zone collector Service; `OTEL_PYTHON_EXCLUDED_URLS` only on api+manager; `KASM_LOG_FILE_ENABLED=false` by default; **`KASM_LOG_FILE_ENABLED=false` is still emitted when `observability.enabled=false`** (regression test: the SDK vars are gated on `enabled`, these are not — `kasm_telemetry` defaults file logging to *true* and `init_logging()` mkdir/opens the path, so omitting it makes an opted-out release crash on `readOnlyRootFilesystem`); `=true` plus `KASM_LOG_FILE_PATH` under `fileLogs`; only `OTEL_SDK_DISABLED=true` when disabled; `KASM_CLICKHOUSE_*` on api+manager only and absent when there is no store; `KASM_LOG_CONSOLE_COLOR=false` |
| `nginx_load_module_test.yaml` *(new)*      | `load_module modules/ngx_otel_module.so;` is the first line of `nginx-shared-configmap.yaml`'s `nginx.conf` when `observability.enabled=true`, and **absent** when false. The absent case is a deployability regression test: an unknown `load_module` path is fatal to nginx, so the opt-out path must not require an image carrying the module |
| `otel_daemonset_test.yaml`                  | DaemonSet + its ConfigMap render by default and disappear when `hostLogs.enabled=false`; the include glob contains the templated namespace **and** `<release>-proxy-*`; `/var/log/pods` hostPath is `readOnly: true`; the checkpoint hostPath is present only when `persistOffsets=true`; security context is `runAsUser: 0` with `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, all capabilities dropped; **no `hostNetwork`/`hostPID`/`hostIPC`**; exports to the cluster gateway Service on 4317 (**not** to any zone-scoped Service); `extraSelectors` entries appear as additional globs; **the whole chart renders zero `ServiceAccount`/`Role`/`ClusterRole`/`*Binding` objects in every scenario** |
| `otel_sidecar_test.yaml`                    | **no** sidecar in the proxy pod by default; sidecar + shared `emptyDir` + `nginx/metrics` scrape present when `nginxLogs.enabled=true`; app pods have no sidecar by default; one each for the components in `fileLogs.components` when enabled; a component removed from that list gets none; sidecar mounts the log volume read-only; `hostLogs.enabled=true` + `nginxLogs.enabled=true` → render fails with the mutual-exclusion message |
| `clickhouse_test.yaml`                      | StatefulSet/Service/ConfigMap/Job render by default; PVC size and storageClass honoured; retention days substituted into `init-schema.sql` (`INTERVAL <n> DAY` for both arms); TLS ports and cert mounts present when `tls=true` and absent when false; `CLICKHOUSE_PASSWORD` from `secretKeyRef`; **no password string in any ConfigMap**; uid 101; probes on `/ping`; stable PVC name with no chart version in it; with a non-default `observability.clickhouse.database` (e.g. `kasm_tenant_a`), assert **each** of: `init-schema.sql`'s `CREATE DATABASE IF NOT EXISTS`/`CREATE TABLE ... otel_logs` both use it; `users.xml`'s `GRANT ALL ON` uses it (not `kasm_otel.*` — that grant is immutable at runtime for an XML-defined user, so this is a one-assertion-per-site check, not a single combined one); the retention Job's `ALTER TABLE` statements use it |
| `clickhouse_external_test.yaml`             | `standalone=true` renders no StatefulSet/Service/ConfigMap/Job; api+manager `KASM_CLICKHOUSE_ENDPOINT` equals `httpEndpoint`; collector DSN equals `nativeEndpoint`; `enabled=false` renders no store and no retention Job |
| `nginx_otel_test.yaml`                      | `load_module` is the **first line** of every chart-supplied `nginx.conf` (use `matchRegex` anchored at start), present even when telemetry is disabled; `otel.conf` include and content present when enabled, absent when disabled; `stub_status` server block; span attrs on the API locations; `otel_trace off` on health/checkvalid/internal locations; stdout `access_log` is `json_combined` when telemetry is on **even with `logFormat: log`**, and honours `logFormat` when telemetry is off; `error_log` goes to `/dev/stderr` on the default path; extra file destinations appear only when `nginxLogs.enabled`; zero `otel_` directives when disabled |
| `otel_browser_test.yaml`                    | `/otel-config.js` location always present; `"enabled":true` vs `"enabled":false` per `browser.enabled`; `/otel-time` present when enabled; `otel_trace off` on both |
| `otel_openshift_test.yaml`                  | `isOpenshift=true` renders no DaemonSet; the sidecar path is used instead (or the render fails with a clear message, per H5 §6d — assert whichever H5 implemented); the rest of the observability stack is unaffected |
| `negative_validation_test.yaml` *(extend)*  | `standalone=true` with one endpoint missing → fail; `standalone=true`+`enabled=false` → fail; `forward.existingSecret` half-set → fail; `externalEndpoint`+`existingConfigMap` → fail; bad `fileLogs.components` entry → fail; `tailSamplePercentage` 101 and -1 → fail. Assert on the error text so the messages stay useful. |

Also review and update, if the earlier phases did not already: `default_image_tags_test.yaml`
(two new images), `components_toggle_test.yaml`, `healthchecks_test.yaml`, `pod_security_test.yaml`,
`services_ports_test.yaml`, `deployment_size_test.yaml` (new presets), `selector_test.yaml`,
`labels_annotations_test.yaml`, `service_name_constants_test.yaml`.

## 2. Test values files

Ensure these exist in `tests/values/` (H3/H4 may have added some) so the render/kubeconform/kyverno
matrix covers every shape:

`observability-disabled.yaml`, `observability-external-ch.yaml`, `observability-byo-config.yaml`,
`observability-filelogs.yaml`, `observability-no-store.yaml`, `observability-forward.yaml`,
`observability-sidecar-logs.yaml` (the PSS fallback: `hostLogs.enabled=false`, `nginxLogs.enabled=true`).

Keep them minimal — set `publicAddr`, low `resources` like the other scenario files do, and only the
`observability.*` keys the scenario is about.

## 3. End-to-end scenarios

New files in `tests/e2e/`, following the structure of `test_01_basic_deploy.py` and
`test_10_json_logging.py`. Reuse `helpers.py` (`kubectl`, `curl_from_pod`,
`get_first_pod_by_selector`, `install_and_wait_with_retry`) and `conftest.py`'s `helm_install` /
`installer` fixtures. Mark everything `@pytest.mark.e2e`.

Keep resource requests low, as the existing scenarios do — kind clusters are small, and ClickHouse's
preset requests will not schedule without an override.

### Pointing the scenarios at DEV-31 images

This chart change depends on the DEV-31 backend, so e2e must run against branch builds. Available
locally (the host is logged in to pull them):

```
kasmweb/api-private:feature_DEV-31                 kasmweb/proxy-private:feature_DEV-31
kasmweb/manager-private:feature_DEV-31             kasmweb/rdp-gateway-private:feature_DEV-31
kasmweb/kasm-guac-private:feature_DEV-31           kasmweb/rdp-https-gateway-private:feature_DEV-31
```

**There is no `postgres-private:feature_DEV-31`**, so you cannot simply set a chart-wide
`useImageTags: feature_DEV-31` — the database would resolve to a nonexistent image. Set per-component
`image.repository` + `image.tag` for the six components above and leave `database.image` on the released
`kasmweb/postgres` tag the chart already defaults to.

Put this in a single reusable place rather than copy-pasting into five scenarios — a
`tests/values/dev31-images.yaml` passed alongside each scenario's values file is the least invasive
option, since `helm_install` already accepts a values file plus `--set` args. Check whether
`conftest.py`/`helpers.py` already have an override mechanism first (`get_api_image` honours a
`KASM_API_IMAGE` env var, which suggests a pattern to follow).

Confirm before writing the scenarios:

```bash
docker images --format '{{.Repository}}:{{.Tag}}' | grep feature_DEV-31
```

If the DEV-31 images have moved on since this doc was written, use whatever tag is actually present and
record it in `PROGRESS.md`.

### `test_12_observability.py`

1. Install with defaults plus low resources.
2. Wait for the collector Deployment and ClickHouse StatefulSet to be ready.
3. Drive some traffic: hit the login page and make an authenticated API call (copy the approach from
   `test_01_basic_deploy.py`).
4. Give the pipeline time to flush — the collector batches on a 10 s timeout, so poll rather than
   sleeping once. Retry the query for up to ~90 s.
5. Query ClickHouse from inside the cluster (exec into the ClickHouse pod and use `clickhouse-client`,
   which avoids TLS and auth plumbing from a test pod):
   - `SELECT count() FROM kasm_otel.otel_logs` > 0
   - `SELECT DISTINCT ServiceName FROM kasm_otel.otel_logs` includes `kasm-api` and `kasm-manager`
   - `SELECT count() FROM kasm_otel.otel_traces` > 0, and `ServiceName` includes `kasm-proxy`
     (this is the real proof that `ngx_otel_module` loaded and the module→collector path works)
   - `SELECT count() FROM kasm_otel.otel_logs WHERE ServiceName = 'kasm-proxy'` > 0 — proves the
     DaemonSet actually tailed `/var/log/pods` and its glob matched. Also assert that both streams
     arrived: at least one record whose `LogAttributes` carry the parsed access-log fields, and (if the
     deployment produced any) an error-log record. If no error-log line occurs naturally, request a
     deliberately bad URL to generate one.
   - `SELECT DISTINCT LogAttributes['k8s.pod.name'] FROM kasm_otel.otel_logs WHERE ServiceName='kasm-proxy'`
     returns a real proxy pod name — proves the `container` operator's filepath metadata extraction
     worked without any RBAC
   - at least one `otel_metrics_*` table exists and is non-empty
6. Assert `curl` of `/otel-config.js` through the proxy returns `"enabled":true`.
7. Assert the `IsAudit` column exists and that logging in produced at least one row with
   `IsAudit = 1` (proves the audit-retention classification works end to end). If login events do not
   reliably produce an audit-classified row, downgrade this to a schema-only assertion and note why.
8. **Non-default database case (H0b).** Either parametrize this test or add a sibling scenario that
   installs with `--set observability.clickhouse.database=kasm_tenant_a`. Repeat step 5's queries
   against `kasm_tenant_a` instead of `kasm_otel`, **and** additionally assert `kasm_otel` itself does
   not exist (`SELECT count() FROM system.databases WHERE name='kasm_otel'` = 0 — proves nothing fell
   back to the default). Then repeat step 6 (or hit the Kasm API's `get_report` directly) to prove the
   **read path** — the API's `KASM_CLICKHOUSE_DATABASE` — agrees with the **write path** — the
   collector exporters' `database:` key. This is the only test that proves reads and writes agree; a
   chart that writes to `kasm_tenant_a` but still reads `kasm_otel` would pass every other check here
   while showing an empty UI with no error anywhere.

### `test_13_observability_disabled.py`

Install with `observability.enabled=false`. Assert: no collector/ClickHouse workloads or Services
exist; every Kasm pod is Ready; the login page loads; `/otel-config.js` returns `"enabled":false`;
`kubectl logs` on the proxy shows nginx started (proving `load_module` did not break it).

### `test_14_observability_filelogs.py`

Install with `observability.fileLogs.enabled=true`. Assert: each listed component's pod has 2
containers; JSON lines exist in the shared volume (`kubectl exec ... cat /opt/kasm/current/log/*.log`,
parse a line with `json.loads`); and those records reach ClickHouse.

### `test_15_observability_sidecar_logs.py`

The PSS-restricted fallback path. Install with `observability.hostLogs.enabled=false` and
`observability.nginxLogs.enabled=true`. Assert: no DaemonSet exists; the proxy pod has 2 containers;
after driving traffic, `kasm-proxy` log records reach ClickHouse; and nginx connection metrics
(`nginx.connections_*` or whatever the receiver emits — check the rendered metric names) are present in
`otel_metrics_*`, since this is the only path that collects them.

Then extend `test_06_pod_security_standards.py` (or add a focused case) to prove the interaction: with a
`restricted` namespace and the **default** values, the DaemonSet must be rejected by admission — so the
scenario must install with `hostLogs.enabled=false`. Assert that the rest of the chart still comes up
Ready in the restricted namespace, and add a comment explaining that this is the documented carve-out
from plan §3a, not a bug. This is the test that keeps the chart's advertised restricted-PSS support
honest.

### Re-scope `test_10_json_logging.py`

H2 narrowed `logFormat`. Update this test to assert JSON stdout only for the proxy (nginx
`json_combined`) and the DB, and **remove** the api/manager/gateway assertions — their console output
is human-readable text now, by design. Add a comment pointing at
`docs/otel-integration-plan.md` §4 so the next reader does not "fix" it back.

## 4. Makefile and CI

- Add `e2e-observability`, `e2e-observability-off`, `e2e-observability-filelogs`,
  `e2e-observability-sidecar` targets following the exact shape of the existing `e2e-*` targets (`kind-prep build-pytest` deps, `pytest-docker` invocation
  with `-k`/file selection).
- Add all three to the `.PHONY` list and to the sequential `e2e` target, with `e2e-settle` between
  scenarios like the others.
- **No `images.txt` change is needed for e2e.** `make kind-load-images` derives its list from
  `helm template` of the chart (`awk '/^[[:space:]]*image:/'`), so the collector and ClickHouse images are
  picked up automatically once H3/H4 render them. `tests/e2e/images.txt` is empty and unused by that
  target; `KIND_EXTRA_IMAGES` (currently `postgres:16 nginx:1.30-alpine`) is the hook for images that do
  not appear in the render. Note ClickHouse is a large image — the first `kind-load-images` will be slow,
  not broken.
- `conftest.py` forces `imagePullPolicy=Never`, so **anything not preloaded will fail to start** with
  `ErrImageNeverPull`. If a scenario invents an image, add it to `KIND_EXTRA_IMAGES`.

## 5. Kyverno / Pod Security

`make kyverno` must pass. The policies in `tests/kyverno/` require probes, resource limits, no host
namespaces, and PSS baseline compliance.

**The host-log DaemonSet is knowingly non-compliant** with `baseline`/`restricted`: it mounts a hostPath
and runs as root (plan §3a). Two things follow:

1. If `pod-security.baseline.yaml` flags the DaemonSet, **that is correct** — do not weaken the
   DaemonSet to satisfy it. Exclude the DaemonSet from that specific policy run with a comment
   referencing plan §3a, or render the policy check against a values file with `hostLogs.enabled=false`.
   Record exactly what you did.
2. `make e2e-pss` must continue to pass, which means that scenario installs with
   `hostLogs.enabled=false`. Verify the DaemonSet is genuinely rejected when you *do* try it in a
   restricted namespace — that confirms the documentation is telling customers the truth rather than
   guessing.

For ClickHouse and the central collector, `readOnlyRootFilesystem` should hold; if not, add the
narrowest possible `emptyDir` mounts rather than relaxing the security context, and document any
unavoidable relaxation in `PROGRESS.md` and `docs/observability.md` (H7).

---

## Verify

```bash
make test                       # lint + kubeconform + kyverno + unittest — must be green
make e2e-observability
make e2e-observability-off
make e2e-observability-filelogs
make e2e-observability-sidecar  # the PSS-restricted fallback path
make e2e-pss                    # regression: restricted PSS still works (with hostLogs disabled)
make e2e-json-logging           # regression: the re-scoped test
```

If no kind cluster is available in your environment, run everything except the `e2e-*` targets, and
state clearly in `PROGRESS.md` which e2e scenarios were **written but not executed**. Do not report
them as passing.

## Definition of done

- All nine unit suites exist and pass; previously existing suites still pass.
- `make test` green.
- Four new e2e scenarios written, wired into the Makefile and `.PHONY`, images preloaded; `test_06_pod_security_standards.py` extended for the `hostLogs` carve-out.
- `test_10_json_logging.py` re-scoped with an explanatory comment.
- Every e2e scenario either executed and passing, or explicitly listed as not-yet-run.

## Hand-off notes

Record in `PROGRESS.md`: which e2e scenarios actually ran and their results, any assertion you had to
weaken and why, and any Kyverno/PSS deviation. H7 documents whatever you flag.
