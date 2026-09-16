# OTel Helm Integration — Progress Board

> **Historical / superseded.** Execution record for `docs/otel-integration-plan.md`; several decisions here were reversed in design review (`kasm-helm-4ss`) and do not describe the shipped chart — see `charts/kasm-helm/docs/observability.md` for current behavior.

Shared state between phase sessions. **Append your entry when you finish a phase.** Later phases read
this to get the names, ports, endpoints and deviations they depend on — treat it as the contract
between phases, not a diary.

Template:

```markdown
### H<n> — <name>
- **Status:** done | done-with-deviations | blocked
- **Files added/changed/deleted:** <list>
- **Verification:** commands run + results
- **Deviations from the phase doc:** <what and why, or "none">
- **Notes for later phases:** <names, ports, endpoints, helper signatures>
- **Cross-phase findings:** <out-of-scope problems spotted, or "none">
```

## Resolved before kickoff (2026-08-06)

Do not re-litigate these; they are answers from the maintainer, not defaults.

| Question | Answer |
| -------- | ------ |
| Tooling | Installed on this host — `bin/` populated, `helm-unittest` plugin present. Do **not** run `make tools`. |
| Branch | Already on `feature/DEV-31` in kasm-helm. No new branch, no commits. |
| Chart version | `1.1200.0-develop` is correct (targets Kasm **1.20**). Leave version fields alone. |
| Test images | Run e2e against `kasmweb/*-private:feature_DEV-31`; host is logged in. **No postgres DEV-31 build** — see H6. |
| OpenShift | `isOpenshift: true` forces the sidecar log path; no DaemonSet, no SCC. |
| Airgap | Out of scope. Update `images.txt` and normal build/deploy paths only. Internal image tags come later. |
| nginx OTel module | Verified present in `proxy-private:feature_DEV-31` (`nginx -t` passes). Released pre-DEV-31 images do **not** have it. |

---

## Status

| Phase | Name                          | Status      | Session |
| ----- | ----------------------------- | ----------- | ------- |
| H0    | Backend ClickHouse TLS        | done        | —       |
| H0b   | Configurable CH database      | done        | —       |
| H1    | Values, schema, helpers       | done        | —       |
| H2    | Service instrumentation       | done        | —       |
| H3    | ClickHouse                    | done        | —       |
| H4    | Collector                     | done        | —       |
| H5    | nginx + sidecars              | done        | —       |
| H6    | Tests + e2e                   | done-with-deviations | — |
| H7    | Docs + release                | done-with-deviations | — |

---

## Contract registry

Fill these in as they are decided. Later phases **must** read from here rather than re-deriving.
Everything below is a placeholder until the owning phase fills it in.

| Item                                  | Value | Decided by |
| ------------------------------------- | ----- | ---------- |
| `kasm.otelEnv` argument dict          | `(dict "context" $ "serviceName" "kasm-api" "zone" $zone.name "component" "api" "python" true)` — `context`/`serviceName` required; `zone` optional (defaults to `"default"` endpoint suffix when omitted); `component` optional (fileLogs membership test, e.g. `"api"`/`"manager"`/`"guac"` — omit for guac/rdp-gateway/rdp-https-gateway since they're not gated by a `component` string in the doc, though guac IS a valid fileLogs member, so H2 should still pass `"component" "guac"` for it); `python` optional bool, pass `true` only for api/manager. | H1         |
| `kasm.clickhouseEnv` argument dict    | `(dict "context" $)` — no other keys. Emits nothing when `observability.enabled` is false, or when `clickhouse.enabled` is false and `clickhouse.standalone` is false. | H1         |
| `kasm.otelSidecar` argument dict      | TBD   | H1/H5      |
| ClickHouse endpoint helpers (if added)| Added both: `kasm.clickhouseHttpEndpoint (dict "context" $)` and `kasm.clickhouseNativeDsn (dict "context" $)`. Both read `.Values.observability.clickhouse` off the passed context and return a bare string (no env-var wrapping) so H3/H4/the retention Job can reuse them directly. | H1         |
| `kasm.observabilityValidate` call     | `{{ include "kasm.observabilityValidate" $ }}` — takes the **root context directly** (not a dict), mirroring `kasm.nginxResolver`'s calling convention. Not yet wired into any template (H4 wires it into `templates/otel-collector-configmap.yaml` per the phase doc). | H1         |
| Collector tier topology               | **Two tiers.** Per-zone *forwarder*: Deployment/Service `<release>-otel-collector-<zone>` (zone-suffixed, `-default` when no `kasmZones`), constant `$constants.otel.svc`, presets node `otel-collector`, values `collector.forwarder.{existingConfigMap,replicas,resources,externalService}`. Cluster *gateway*: `<release>-otel-gateway` (**not** zone-scoped), constant `$constants.otel.gatewaySvc`, component `otel-gateway`, presets node `otel-gateway` (1 at every size), values `collector.gateway.{existingConfigMap,replicas,resources}`. `tail_sampling` + the three ClickHouse exporters live on the gateway **only**; forwarders run `memory_limiter`+`batch` and export `otlp`→gateway:4317 with the bearer token. nginx spans → zone forwarder :4316 (gateway has no 4316). Host-log DaemonSet → gateway:4317 directly, no zone resolution. | H1 + human (2026-08-06) |
| ClickHouse HTTP endpoint, TLS on/off  | Unchanged from H1's `kasm.clickhouseHttpEndpoint`: bundled, TLS off → `http://<release>-clickhouse:8123`; bundled, TLS on → `https://<release>-clickhouse:8443`. Matches the StatefulSet/Service ports H3 actually rendered — no fix needed. | H3 (confirms H1) |
| ClickHouse native DSN, TLS on/off     | Unchanged from H1's `kasm.clickhouseNativeDsn`: bundled, TLS off → `tcp://<release>-clickhouse:9000`; bundled, TLS on → `tcp://<release>-clickhouse:9440?secure=true`. Matches the StatefulSet/Service ports H3 actually rendered — no fix needed. | H3 (confirms H1) |
| ClickHouse PVC name                   | `<release>-clickhouse-data` (via `kasm.name (list . "clickhouse" "data")`) — stable across upgrades, deliberately **not** suffixed with `.Chart.AppVersion` the way the DB's PVC is (that coupling would orphan telemetry on every Kasm version bump). | H3 |
| `users.xml` as ConfigMap or Secret    | **ConfigMap**, per the doc's preferred option. Verified against a live `clickhouse/clickhouse-server:24.12-alpine`: `<password from_env="KASM_CLICKHOUSE_PASSWORD"/>` on the `<password>` element works — ClickHouse's `from_env` substitution is generic, not limited to documented top-level params. The actual secret value never appears in the ConfigMap; only the env-var *name* does. | H3 |
| ClickHouse `readOnlyRootFilesystem`   | **`true`** — the read-only path works, but needed three things the phase doc didn't anticipate, all verified against the real image: (1) `CLICKHOUSE_SKIP_USER_SETUP: "1"` env var, or the entrypoint tries to write `/etc/clickhouse-server/users.d/default-user.xml` (fails on read-only root) whenever `CLICKHOUSE_USER != "default"` or `CLICKHOUSE_PASSWORD` is set — both of which the doc's own env list requires; (2) an `emptyDir` mounted at `/var/log/clickhouse-server` (the entrypoint chowns/creates this even when logging to console); (3) an `emptyDir` mounted at `/tmp` (both the server process and the retention Job's `clickhouse-client` need a writable `$HOME`). `/var/lib/clickhouse` (the PVC) covers the data/tmp/user_files/format_schemas subdirectories the entrypoint also creates. | H3 |
| `health.probe` `timingParent` added?  | **Yes.** New optional `timingParent` dict arg on `health.probe` (`_helpers.tpl`), checked before the `component == "db"` special-case and the `components.<component>` lookup. When supplied it's used directly as the `healthCheckTiming` parent, so components outside `.Values.components` (ClickHouse, and per the doc's note, the Collector in H4) can still get configurable probe timing. Backward-compatible: no existing caller passes this key. Verified via `--set observability.clickhouse.healthCheckTiming.livenessProbe.initialDelaySeconds=120` reaching the rendered probe. | H3 |
| Collector Service names as rendered   | Forwarder: `<release>-otel-collector-<zone>` (`-default` suffix with no `kasmZones`), matches `kasm.otelEnv`'s `OTEL_EXPORTER_OTLP_ENDPOINT` exactly — no fix needed, H1 got it right. Forwarder external Service (when `forwarder.externalService.enabled`): `<release>-otel-collector-<zone>-external`. Gateway: `<release>-otel-gateway`, equals `$constants.otel.gatewaySvc`. | H4         |
| Collector ConfigMaps as rendered      | Forwarder: `<release>-otel-collector` (one, unzoned, mounted by every zone's forwarder Deployment). Gateway: `<release>-otel-gateway`. | H4         |
| Collector container port names        | Forwarder: `otlp-http` (4318), `otlp-grpc` (4317), `otlp-nginx` (4316), `health` (13133), `self-metrics` (8888). Gateway: `otlp-grpc`, `health`, `self-metrics` only (no `otlp-http`/`otlp-nginx` — nothing addresses the gateway directly). All ≤15 chars. | H4         |
| `otel.conf` location (zone-scoped?)   | Option 1 (doc's preference): moved into the per-zone `proxy-settings` ConfigMap (`proxy-configmaps.yaml`), mounted at `/etc/nginx/conf.d` and already globbed by `nginx.conf`'s existing `include /etc/nginx/conf.d/*.conf;` — no extra explicit `include` line needed, no new mount. Endpoint built inline per zone: `printf "%s-otel-collector-%s" $.Release.Name (include "kasm.zoneName" $zone.name)`, matching H4's forwarder Service name exactly. | H5 |
| DaemonSet include glob (as rendered)  | `/var/log/pods/{{ .Release.Namespace }}_{{ .Release.Name }}-proxy-*/*/*.log` — verified via `helm template`: `/var/log/pods/kasm-test_kasm-test-proxy-*/*/*.log`. `hostLogs.extraSelectors` entries add `/var/log/pods/{{ .Release.Namespace }}_{{ . }}/*/*.log` each. | H5 |
| Stream attribute name (`log.iostream`?)| Used as specified (`attributes["log.iostream"] == "stdout"`) in the router `expr`. Verified the merged config parses and passes `otelcol validate` against the real pinned `0.156.0` image; **not** independently verified against a live collector actually processing real CRI log lines (no running cluster in this session) — if a future collector bump renames this attribute, error-log lines would silently route through the JSON parser instead of the regex one. Flagged in the ConfigMap's own comment as the first thing to check if that pipeline stops populating. | H5 |
| `kasm.metadata` `daemonSet` resource key| Passed `"resource" "daemonSet"` (camelCase) to the top-level `kasm.metadata` call — matches the existing `extraAnnotations.daemonSet`/`extraLabels.daemonSet` values keys, which merge in correctly (case-sensitive `get` lookup). The pod-template `kasm.metadata` call uses `"resource" "pod"`, same as every other workload, which **still** picks up `kasm.com/healthcheck`/`kasm.com/security` regardless of the DaemonSet resource-key casing (that special-case list gates on `"pod"`, not the workload's own resource key) — this surfaced a real conflict with `kasm-pod-security-restricted`, since the DaemonSet's container must run as root. See the Kyverno row below for the fix; the annotation was **not** suppressed. | H5 |
| Kyverno/PSS handling of the DaemonSet | `make kyverno` initially failed 2 rules (`require-workload-pod-security-context`, `require-workload-container-hardening`) because the DaemonSet legitimately can't satisfy `runAsNonRoot`. Fixed by adding a named `exclude: resources.kinds: [DaemonSet], names: ["*-otel-hostlogs"]` block to just those two rules in `tests/kyverno/pod-security.baseline.yaml`, with a comment explaining why — not by weakening the DaemonSet or dropping its `kasm.com/security` annotation, per the phase doc's explicit instruction. All other policies (`no-host-namespaces`, `resources.required`, `probes.required`) apply to the DaemonSet unmodified and pass; hostPath itself is not checked by any Kyverno policy in this repo (confirmed by reading all four policy files), so real Pod Security Standard admission (a live cluster concern) is the only thing that would reject it in a `restricted` namespace — matching the doc's expectation. | H5 |
| nginx sidecar log volume + mount path | `kasm-proxy-otel-logs` emptyDir (`sizeLimit` from `nginxLogs.sizeLimit`), mounted at `/var/log/nginx/otel` in both the proxy container and the `otel-sidecar` container added via the new `kasm.otelSidecar` helper. | H5 |
| Env var names for ClickHouse TLS      | `KASM_CLICKHOUSE_CA_CERT` (path, unset default), `KASM_CLICKHOUSE_VERIFY` (bool, default `true`); `CA_CERT` set wins over `VERIFY=false` | H0 |
| Standalone-ClickHouse TLS-trust surface (values + wiring) | New `observability.clickhouse.{caCert,caCertConfigMap,tlsVerify}` (all under the existing `clickhouse` object). `caCert` (literal PEM) renders `templates/clickhouse-ca-configmap.yaml`, a non-zone-scoped ConfigMap (`<release>-clickhouse-ca`, key `ca.crt`) mounted into api+manager at `/etc/ssl/certs/kasm_clickhouse_ca.crt` via new helpers `kasm.clickhouseCaVolume`/`kasm.clickhouseCaVolumeMount` (appended at the end of `_helpers.tpl`, called from `api-deployment.yaml`/`manager-deployment.yaml` only). `caCertConfigMap` names an existing ConfigMap (key `ca.crt`) instead — mutually exclusive with `caCert`, enforced as a `fail` in `kasm.observabilityValidate`. `kasm.clickhouseEnv`'s precedence, matching H0's backend contract: bundled+tls → `KASM_CLICKHOUSE_CA_CERT=/etc/ssl/certs/kasm_clickhouse.crt` (unchanged); else standalone+(caCert or caCertConfigMap) → `KASM_CLICKHOUSE_CA_CERT=/etc/ssl/certs/kasm_clickhouse_ca.crt`; else standalone+`tlsVerify: false` → `KASM_CLICKHOUSE_VERIFY=false`; else neither var is emitted (system trust store, verified). Chosen over reusing `trustedCaBundle`/`kasm.trustedCaEnv` because those only set `SSL_CERT_FILE`/`REQUESTS_CA_BUNDLE`, which `clickhouse_connect` ignores (per H0/Follow-ups) — a dedicated ConfigMap + explicit env var was the only design that actually reaches the client's `ca_cert` kwarg. | H2 |
| ClickHouse database: flag + values key | Backend: `--clickhouse-database <name>` (install.sh/upgrade.sh), env var `KASM_CLICKHOUSE_DATABASE`/`CLICKHOUSE_DATABASE` shell var, default `kasm_otel`. Chart (for H3/H4 to implement): `.Values.observability.clickhouse.database`, same default, independent of `.Values.observability.clickhouse.username`. Must reach: collector exporters' `database:` (×3), `init-schema.sql` (`CREATE DATABASE`/`CREATE TABLE`), `users.xml`'s `GRANT ALL ON <db>.*`, retention Job `ALTER TABLE`, and api/manager's `KASM_CLICKHOUSE_DATABASE` env. | H0b |

---

## Entries

### H0 — Backend ClickHouse TLS
- **Status:** done
- **Files added/changed/deleted:**
  - Changed: `api_server/api_server/data/clickhouse_reports.py` (`_get_client()` now honours TLS env vars; added `_str_to_bool()` helper)
  - Changed: `api_server/tests/test_clickhouse_reports.py` (added `_get_client` TLS test section + `from data import clickhouse_reports` import)
  - Changed: `docs/telemetry/reference/configuration.md` (two new env var rows + one sentence in the Dedicated ClickHouse Role section)
- **Verification:**
  - `make unit-test-quick T="tests/test_clickhouse_reports.py"` → `17 passed` (12 pre-existing deprecation warnings, unrelated to this change)
  - `make lint` → `All checks passed!`
  - `make pyright` → `0 errors, 0 warnings, 0 informations`
- **Deviations from the phase doc:** No repo-wide `str_to_bool`/`strtobool` helper existed (`grep -rn "def str_to_bool\|strtobool" api_server/ libs/` found nothing), so a small module-local `_str_to_bool()` was added in `clickhouse_reports.py` as the doc allowed. `clickhouse_reports.py` is fully covered by the `KASM-TECHDEBT` ledger (`api_server/api_server/data/**/*.py = ["ALL"]` in `ruff.toml`), so lint would have passed regardless of style; code was still written to guard-clause/flat style per CLAUDE.md. `_get_client()` has no caching decorator, so no cache-clearing was needed in tests.
- **Notes for later phases:** Exact contract for H3 — env vars are `KASM_CLICKHOUSE_CA_CERT` (path, unset by default; passed as `ca_cert=<path>` kwarg to `clickhouse_connect.get_client()` when non-empty) and `KASM_CLICKHOUSE_VERIFY` (permissive bool string: `true/false`, `1/0`, `yes/no`, case-insensitive; unrecognized values fall back to default `true`). Precedence: if `KASM_CLICKHOUSE_CA_CERT` is set (non-empty), `ca_cert` is passed and `verify` is never set explicitly (verification proceeds against that CA) — this wins even if `KASM_CLICKHOUSE_VERIFY=false` is also set (a `logger.warning` fires noting the contradiction). Only when `KASM_CLICKHOUSE_CA_CERT` is unset/empty AND `KASM_CLICKHOUSE_VERIFY` parses to `false` does the client get `verify=False`. Both vars apply regardless of `http`/`https` scheme (harmless no-op on `http`). H3 should mount its cert somewhere and set `KASM_CLICKHOUSE_CA_CERT` to that mount path on API/Manager pods (or `KASM_CLICKHOUSE_VERIFY=false` if no CA distribution is planned).
- **Cross-phase findings:** none beyond what's already tracked in the Follow-ups section below (installer wiring for `--role clickhouse` topology, which this phase deliberately left untouched).

---

### H1 amendment — forwarder/gateway split (human, 2026-08-06)
- **Status:** done
- **Why:** reviewing whether the DaemonSet could subsume all collection surfaced that the planned
  topology put `tail_sampling` on every per-zone Collector, each writing to ClickHouse. That is a
  correctness bug in two independent ways: (a) a trace crossing zones is split across N samplers, and
  (b) `replicas.preset` gives `otel-collector` **2** replicas at medium/large, so a ClusterIP Service
  splits traces across replicas even in a single-zone install. Each sampler votes on a fragment, so
  traces land with spans missing and `tailSamplePercentage` stops meaning what it says. It fails
  silently — data still arrives, it is just wrong. Docker already gets this right
  (`otel-collector-remote.yaml` forwards without sampling; `otel-collector-local.yaml` samples once),
  so the fix also makes the chart a closer port instead of a divergence.
- **Files changed (chart):**
  - `values.yaml` — `collector` restructured into one sub-tree per tier — `collector.forwarder.{existingConfigMap,replicas,resources,externalService}` and `collector.gateway.{existingConfigMap,replicas,resources}`. `externalEndpoint`/`image` stay at the `collector` level (they apply to both tiers), and so do `tailSamplePercentage`/`forward`. **The rule:** tier sub-trees hold *deployment* concerns (how many, how big, which ConfigMap, which Service); the `collector` level holds *pipeline behaviour*, so a customer configuring sampling need not know which tier implements it. The flat `collector.{replicas,resources,existingConfigMap,externalService}` keys H1 originally shipped **no longer exist** — free to rename since nothing is released (pre-release churn needs no compat shim)
  - `values.schema.json` — matching `collector.gateway` object (`additionalProperties: false`) and the
    three re-descriptions. Diff is **purely additive** (zero deleted lines) — a `json.dumps` round-trip
    initially reformatted four unrelated inline arrays and one over-indented block elsewhere in the file;
    those were reverted by hand. If you edit this file, prefer targeted string edits over re-dumping it.
  - `_helpers.tpl` — `$constants.otel.gatewayComponent` / `.gatewaySvc` (`<release>-otel-gateway`,
    deliberately **not** zone-scoped); `replicas.preset` node `otel-gateway` = 1/1/1 with the reason in
    the define's doc comment; `resources.preset` node `otel-gateway` sized above the forwarders
    (tail_sampling buffers whole traces for `decision_wait`, and it is the only ClickHouse writer)
- **Files changed (docs):** `otel-integration-plan.md` §1 parity rows, §3 title/prose/diagram, §4 file
  list, §11 decision 4 (records the revision *and* the rejected DaemonSet-only option and why);
  `H4-collector.md` substantially restructured into forwarder (§1, §2, §3) + gateway (§1b, §3b) with the
  "sampling lives in exactly one place" rule stated up front and a `grep -c 'tail_sampling:'` → 1
  regression check; `H5-nginx-sidecars.md` DaemonSet exporter retargeted to the gateway and the
  "point at a non-zone-scoped Service" option explicitly ruled out (the gateway has no 4316, and
  pointing nginx at it fails as silent no-op tracing, not a config error); `H6-tests-e2e.md` assertions.
- **Verification:** `make lint` clean, `make render` all 19 scenarios, `make unittest` **517/517,
  44/44** — unchanged from the H1 baseline, since no template consumes any of this yet.
- **Deviations:** none — but note this *adds* two workloads to H4's scope (`otel-gateway-configmap.yaml`,
  `otel-gateway-deployment.yaml`, `otel-gateway-service.yaml`). H4 is now the largest phase.
- **Notes for later phases:** read the "Collector tier topology" contract row before touching H4 or H5.
  **Do not "simplify" the gateway to a single cluster-wide Collector that services talk to directly, and
  do not raise its replica count** — the forwarder tier exists so that services keep a zone-local
  endpoint, and `replicas: 1` on the gateway is correctness, not sizing.
- **Cross-phase findings:** `observability.collector.forward.endpoint` now belongs on the **gateway**, so
  a forwarded copy reflects the sampling decision rather than duplicating unsampled spans. Recorded in
  H4 §1's forwarder-exporters note.

---

### H2 amendment — logging env must not be gated on observability.enabled (human, 2026-08-06)
- **Status:** done. Found while verifying H2; **the root cause was an error in the H1 phase doc, which H2
  implemented faithfully.** Not an H2 defect.
- **The bug:** `kasm.otelEnv` emitted *only* `OTEL_SDK_DISABLED` when `observability.enabled: false`, per
  the H1 spec. But `KASM_LOG_FILE_ENABLED` is not an OTel setting — `libs/telemetry/kasm_telemetry/config.py`
  defaults `log_file_enabled: bool = Field(True)`, and `logs.py::init_logging()` then does
  `log_path.parent.mkdir(parents=True, exist_ok=True)` followed by opening the file. The chart runs api and
  manager with `readOnlyRootFilesystem: true` and mounts nothing at `/opt/kasm/current/log` (only
  `tmp-data` at `/tmp`), so that raises `OSError` and the container dies at startup. Net effect:
  **`observability.enabled: false` rendered an un-deployable release** — the one setting a customer uses to
  opt out of all of this. It would have passed every render, lint, kubeconform, kyverno and unit-test
  check, and failed only on a real cluster.
- **Fix:** in `kasm.otelEnv`, the `OTEL_*` vars stay inside the `observability.enabled` gate;
  `KASM_LOG_FILE_ENABLED` and `KASM_LOG_CONSOLE_COLOR` are now emitted **unconditionally**.
  `$fileLoggingEnabled` additionally requires `$obs.enabled`, so disabling observability can never select
  the file-logging branch. A comment in the helper explains why, to stop a future reader "tidying" the vars
  back inside the gate.
- **Verification:** `observability.enabled=false` now emits `OTEL_SDK_DISABLED` +
  `KASM_LOG_FILE_ENABLED=false` + `KASM_LOG_CONSOLE_COLOR=false` on all five workloads;
  `fileLogs.enabled=true` still yields three `true` values (api/manager/guac). `make lint` clean,
  `make render`/`kubeconform`/`kyverno` all clean, `make unittest` **513/513, 44/44**.
- **For H6:** add a unit test asserting `KASM_LOG_FILE_ENABLED=false` is present **when
  `observability.enabled=false`**. The existing planned assertion only covers the enabled case, which is
  exactly why this slipped through. This is a deployability regression test, not a cosmetic one.

---

### H5 amendment — `load_module` gated on observability.enabled (human, 2026-08-06)
- **Status:** done. H5 emitted `load_module modules/ngx_otel_module.so;` unconditionally as line 1 of
  `nginx-shared-configmap.yaml`'s `nginx.conf`. Correct for the supported matrix, but it left
  `observability.enabled: false` with no escape hatch: an unknown `load_module` path is **fatal** to
  nginx, so any proxy image predating `ngx_otel_module` (anything before 1.20) would fail to start
  outright, and turning telemetry off would not help. Same principle as the H2 amendment — the opt-out
  path must stay deployable.
- **Decision (maintainer):** the chart targets `1.1200.0` and forward, so pre-1.20 images are out of
  contract — but gating costs almost nothing, so gate it.
- **Change:** wrapped the line in `{{- if .Values.observability.enabled }}` with a comment explaining
  why, so it does not get "tidied" back. Verified this is the **only** otel-dependent thing in the
  disabled path: no `otel_*` directives render at all, and `/otel-config.js` serves the
  `{"enabled":false}` stub.
- **Verification:** `enabled=true` → `load_module` is line 1; `enabled=false` → absent, first line is
  `user nginx;`. **`nginx -t` run against `kasmweb/proxy:develop` for both states** (config extracted
  from the rendered ConfigMaps into the real mount layout — shared config at `/etc/nginx`, settings at
  `/etc/nginx/conf.d`, services at `/etc/nginx/conf.d/services.d`, upstreams stubbed to 127.0.0.1, a
  throwaway self-signed cert) → *"configuration file /etc/nginx/nginx.conf test is successful"* in both.
  `make lint render kubeconform kyverno` clean; `make unittest` **514/514, 44/44**.
- **For H6:** assert `load_module` is present when `observability.enabled=true` and **absent** when
  false. The absent case is the deployability regression test.

---

### H7 amendment — pre-created Secret example was missing the two new keys (human, 2026-08-06)
- **Status:** done. Found while verifying H7.
- **The gap:** `examples/kasm-secrets.yaml` is the template customers copy when they run with
  `kasmSecrets.create: false`, in which case `kasm-password-secret.yaml` renders **no Secret at all** and
  the pre-created one is the only source. H1 added `clickhouse-password` and `otel-bearer-token` to
  `$knownKeys`, but the example was never updated. A customer following it would get the ClickHouse
  StatefulSet, both Collector tiers, and api/manager stuck in `CreateContainerConfigError` on missing
  `secretKeyRef` keys — pods never start, and nothing in `helm template`/lint/kubeconform/kyverno flags it
  because the chart is correct; only the example is wrong.
- **Fix:** both keys added to the example with a comment saying they are required whenever
  `observability.enabled` is true (the default) and omittable only when it is false.
- **Verification:** file parses as YAML; `make test` still 662/662, 55/55; `make readme-check` passes.
- **Also independently re-verified in this pass:** all three `examples/otel-collector-*.yaml` extracted
  and run through `otelcol validate` in a throwaway `otel/opentelemetry-collector-contrib:0.156.0`
  container → **exit 0 for all three**. Credentials in them are `${env:...}` throughout, except the Splunk
  HEC token which is an explicit `REPLACE_ME_SPLUNK_HEC_TOKEN` placeholder with instructions to switch it
  to `${env:SPLUNK_HEC_TOKEN}`.

---

### Post-H7 — first e2e run: one test bug fixed, one robustness gap closed (human, 2026-08-07)
- **Status:** done. `make e2e-observability` failed on its first real run; both causes addressed.
- **Bug 1 — e2e harness (deterministic, was guaranteed to fail):** `test_12_observability.py`'s
  `_clickhouse_query()` passed `"${CLICKHOUSE_USER}"` / `"${KASM_CLICKHOUSE_PASSWORD}"` as literal argv
  entries. `kubectl exec ... --` builds argv with no shell, so ClickHouse received `${CLICKHOUSE_USER}`
  verbatim → `Code: 516 ... AUTHENTICATION_FAILED`. Fixed by dropping `--user`/`--password` entirely and
  relying on the container's `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD` env, which is what the function's own
  docstring already claimed — and which also keeps a password off a command line. Verified both directions
  against a throwaway `clickhouse-server:24.12-alpine`: env-only returns `kasm_otel`; the literal form
  reproduces the exact error from the run.
- **Bug 2 — gateway crash-loop:** `cannot start pipelines: failed to start "clickhouse/logs" exporter:
  create database: dial tcp: lookup <release>-clickhouse ... server misbehaving` (CoreDNS SERVFAIL),
  restarts=3, backoff 40s+. **Not** a chart wiring fault: ClickHouse was `ready=True restarts=0` throughout
  and the Service selector matches the StatefulSet pod labels. Also **not** a permissions wall — measured
  that `GRANT ALL ON <db>.*` includes `CREATE DATABASE` scoped to that database, so the exporter's startup
  DDL is allowed (an earlier reading of the H0b finding suggested otherwise; it does not apply here).
  Root cause is a startup-ordering fragility: the ClickHouse exporter runs `CREATE DATABASE` during
  pipeline start and the Collector **exits** on failure, so a momentarily unresolvable ClickHouse becomes a
  CrashLoopBackOff that outlasts the install's readiness window.
  **Fix:** an initContainer on the gateway polls ClickHouse's `/ping` (unauthenticated — no credentials
  needed) using the ClickHouse image, which is already a chart dependency and ships `wget`. Renders only
  when `clickhouse.enabled` or `standalone`; 10-minute cap then fails loudly.
- **Harness diagnosability:** `cleanup_release` uninstalled unconditionally, so every failed run destroyed
  its own evidence. Added a `pytest_runtest_makereport` hook plus: a diagnostics dump on failure (describe,
  per-pod logs including `--previous`, events) into `E2E_ARTIFACT_DIR` (default `/e2e/artifacts` →
  `tests/e2e/artifacts/`, gitignored), and `E2E_KEEP=1` (always keep) / `E2E_KEEP=onfail` (keep only after a
  failure). Both plumbed through the `pytest-docker` target.
- **Note for whoever runs e2e:** pytest writes **no log file** — `--rm` container, `log_cli=true`, stdout
  only. Pipe through `tee`. `make -n` is not a safe dry run for e2e targets: GNU Make executes recipe lines
  containing `$(MAKE)` even under `-n`.
- **Verification:** `make lint render kubeconform kyverno` clean; `make unittest` **664/664, 55/55** (+2 new
  assertions covering the initContainer present/absent cases); `make readme-check` passes. The e2e suite
  itself has **not** been re-run — that is the human's next step.

---

### Post-H7 — second e2e run: images wired, two test-expectation bugs fixed (human, 2026-08-10)
- **Status:** done (chart unchanged; all three fixes are in the e2e harness). e2e **not re-run yet.**
- **initContainer fix confirmed working:** the gateway now logs *"Everything is ready. Begin running
  and processing data."* with 0 restarts. No crash-loop. The earlier DNS SERVFAIL did not recur.
- **Confirmed working end-to-end on a real cluster:** nginx traces reach ClickHouse via
  `ngx_otel_module` (`otel_traces` ServiceName `kasm-proxy`); the hostLogs DaemonSet tails
  `/var/log/pods` (155 `kasm-proxy` log rows); the configurable database works (`kasm_tenant_a`
  exists with `otel_logs`/`otel_traces` populated, `kasm_otel` does **not** exist).
- **Bug 3 — `dev31-images.yaml` was never applied.** It was referenced only in a Makefile *comment*;
  every install ran on `kasmweb/{api,manager,proxy}:develop`. Proven decisive: `docker run --rm
  kasmweb/api:develop python3 -c "import kasm_telemetry"` → **ModuleNotFoundError**. The released/develop
  api and manager images contain no telemetry code, so `kasm-api`/`kasm-manager` can never appear in
  `otel_logs` — which was the actual assertion failure. Root cause of it never being wired: `tests/values`
  is not mounted into the pytest container, so the file was unreachable.
  **Fix:** `pytest-docker` now mounts `tests/values` at `/e2e-values` and passes `E2E_IMAGE_VALUES`;
  `helm_install()` layers that file last (and fails loudly if the path is missing); the four
  `e2e-observability*` targets set it. `kind-load-images` now unions the image list from **two**
  `helm template` passes (with and without the override) so both released and DEV-31 images get loaded.
  Tags corrected to the six `*-private:feature_DEV-31` images actually present on this host — the
  previously recorded `x86_64-` prefixed rdp-gateway tags are stale.
- **Bug 4 — the access-log attribute assertion was wrong, not the pipeline.** The test asserted
  `mapContains(LogAttributes,'http.request.method')`. Collector operators treat a dotted path
  (`attributes.http.request.method`) as a **nested** field, so ClickHouse stores
  `LogAttributes['http'] = '{"request":{"method":"GET"},"response":{"status_code":"200"}}'` and
  `LogAttributes['url'] = '{"path":"/..."}'`. No flat key exists, and **Docker behaves identically** —
  same operator chain, so this is not a Kubernetes divergence. Measured on the live release: 439 rows
  match the corrected predicate. Fixed to use `JSONExtractString(LogAttributes['http'],'request','method')`
  and `JSONExtractString(LogAttributes['url'],'path')`, with the nesting explained in a comment.
- **Verification:** `helm template -f tests/values/dev31-images.yaml` resolves all six private images;
  the kind-load union is 15 images; conftest and test_12 compile. Static suite unaffected.
- **Still open:** re-run `make e2e-observability E2E_KEEP=onfail`. `kind-load-images` must run first so
  the private images are in the cluster (`imagePullPolicy=Never`).

---

### Post-H7 — third e2e run: real chart bug in the db Jobs (human, 2026-08-10)
- **Status:** chart fixed; e2e **not re-run yet**.
- **Image wiring confirmed working:** all six `*-private:feature_DEV-31` images were actually deployed
  this run, so the `E2E_IMAGE_VALUES` plumbing is proven.
- **Bug 5 (REAL CHART BUG, found only on a live cluster):** every pod except ClickHouse/db/collectors sat
  `Pending` because `db-init` crash-looped 5 times with
  `OSError: [Errno 30] Read-only file system: '/opt/kasm/current/log'` from
  `kasm_telemetry/logs.py::init_logging()`. **Same root cause as the H2 amendment, in a place H2 did not
  cover:** H2 added the logging env only to the long-running Deployments/StatefulSets. The `db-init`,
  `db-upgrade` and `db-upgrade-backup` Jobs all run `$constants.api.image` and execute `server.py`
  (which calls `init_telemetry()`), so they need `KASM_LOG_FILE_ENABLED=false` too. Without it, seeding
  never completes and **the whole release never comes up** — with `dbManagement.initialize: true` this
  would have broken a real customer install, not just a test.
- **Fix, done as a refactor rather than a fourth copy of the logic:** extracted `kasm.loggingEnv`
  (`dict "context" $ "serviceName" <name>` + optional `"component"`), had `kasm.otelEnv` delegate to it,
  and called it from the three Jobs' `env:` blocks. `component` is deliberately omitted for Jobs, so they
  always resolve to `KASM_LOG_FILE_ENABLED=false` regardless of `fileLogs`. **Proved the refactor is
  behaviour-preserving** by diffing full `helm template` output before/after: identical except the
  per-render random Secret values.
- **Not fixed (correctly):** `clickhouse-retention-job` runs `clickhouse-client`, not python, so it needs
  no logging env.
- **Verification:** `make lint render kubeconform kyverno` clean; `make readme-check` passes;
  `make unittest` **666/666, 55/55** (+2: db Job disables file logging, and still does so with
  `observability.enabled=false`).
- **Note:** the earlier `otel-gateway` restarts (2) this run were the ClickHouse-wait initContainer doing
  its job while the DB was thrashing; the gateway ended `Running`/ready.

---

### Post-H7 — fourth e2e run: db-init fix confirmed; audit-TTL race found (human, 2026-08-10)
- **Status:** two more e2e-harness fixes applied; **one real product gap recorded as a follow-up, not
  fixed.** e2e not re-run since.
- **The db-init fix is confirmed:** all 11 pods `Running`/`Ready`, **0 restarts**, release fully up. Every
  service now reports telemetry — `otel_logs` ServiceNames: `kasm-api kasm-guac kasm-manager kasm-proxy
  kasm-rdp-gateway kasm-rdp-https-gateway`; `otel_traces`: all of those except manager. 391 log rows,
  78 trace rows, 62 rows with parsed nginx access-log attributes, `/otel-config.js` → 200.
- **Bug 6 — `k8s.pod.name` asserted on the wrong column (test bug, chart correct).** The `container`
  operator's `add_metadata_from_filepath` writes `k8s.*` to **ResourceAttributes**, not LogAttributes —
  correct, since they describe the source entity rather than the record. Measured:
  `ResourceAttributes['k8s.pod.name'] = kasm-e2e-proxy-default-774bcbd46f-b2rn8`. Assertion fixed to read
  ResourceAttributes. **This confirms the RBAC-free filepath metadata extraction works as designed.**
- **Bug 7 — tests were not hermetic (test bug).** `cleanup_release` uninstalls but the ClickHouse **PVC is
  retained** (`retentionPolicy.whenDeleted: Retain`, the chart default). ClickHouse only runs
  `/docker-entrypoint-initdb.d/init.sql` when the data directory is empty — pod log confirms *"ClickHouse
  Database directory appears to contain a database; Skipping initialization"* — so test 2 started on test
  1's volume, `init-schema.sql` never ran, and the **exporter** created `otel_logs` instead (identifiable
  by its `__otel_materialized_*` columns). Fixed by setting
  `observability.clickhouse.storage.retentionPolicy` to `Delete` in the observability tests' values. Also
  scoped the `IsAudit` `system.columns` probe to `database='kasm_otel'` so it cannot false-positive on
  another database's table.
- **FOLLOW-UP (real, compliance-relevant, NOT fixed) — the audit-TTL tier can be silently lost.**
  `otel_logs` gets its `IsAudit MATERIALIZED` column and two-tier TTL (30d app / 365d audit) from
  `init-schema.sql`, which only runs on a **fresh** ClickHouse volume. The `clickhouse-retention` Job is
  the intended repair path and does the right DDL (`ADD COLUMN IF NOT EXISTS IsAudit` then a conditional
  `MODIFY TTL`), but it is a `post-install,post-upgrade` hook that runs **before any telemetry has
  flowed**, so when the table does not yet exist both statements fail and are swallowed by
  `|| echo "Warning: ..."`. The exporter then creates `otel_logs` itself with a **flat 30-day TTL and no
  IsAudit** — verified on the live release via `SHOW CREATE TABLE`. Nothing repairs it afterwards.
  **Trigger:** an existing ClickHouse volume where the target database's `otel_logs` does not exist —
  most realistically **changing `observability.clickhouse.database` on an existing deployment**, which is
  exactly what test 2 does. Effect: audit logs are deleted after 30 days instead of 365, silently.
  **DECISION (maintainer, 2026-08-10): document the limitation and require a fresh volume when changing
  the database name.** A better fix (have the retention Job create the table from the init schema when
  missing, or re-run the DDL once telemetry has started) is deferred, not rejected.
  **Documented in:** `charts/kasm-helm/docs/observability.md` §6 — a "Changing the database name needs an
  empty volume" subsection giving the uninstall/delete-PVC/reinstall procedure, an explicit warning that
  it discards telemetry history, and a `SHOW CREATE TABLE ... | grep -c IsAudit` check for an existing
  deployment (`0` = audit logs are on the short window). Also flagged inline on the
  `observability.clickhouse.database` values key, so it is visible at the point of change and not only in
  the long-form docs. README regenerated.

---

### H0b — Configurable ClickHouse database
- **Status:** done
- **Files added/changed/deleted (kasm_backend):**
  - Changed: `api_server/api_server/data/clickhouse_reports.py` — stripped all 19 `kasm_otel.` table qualifiers so the connect-time `database` kwarg governs resolution
  - Changed: `api_server/tests/test_clickhouse_reports.py` — added a guard test scanning module source for database-qualified `FROM`/`JOIN` references, two `_get_client()` database pass-through tests, and fixed one pre-existing assertion (`"kasm_otel.otel_logs" in query` → `"FROM otel_logs" in query`) that the qualifier strip broke
  - Changed: `docs/telemetry/reference/configuration.md` — added the `KASM_CLICKHOUSE_DATABASE` env var row (it did not exist before this phase) and a new "External / Multi-Tenant ClickHouse" section
  - Changed: `install/install.sh` — new `CLICKHOUSE_DATABASE='kasm_otel'` default; `--clickhouse-database` flag parsing + help text; `copy_clickhouse_configs()`/`copy_otel_configs()` substitute it into `users.xml`/`init-schema.sql`/collector config/compose; install-summary echoes; `validate_otel_flags()` warns when set with `--no-clickhouse`
  - Changed: `install/upgrade.sh` — new default, flag parsing + help text, **recovery from the existing collector config** (reads `database:` back so an unset flag never resets a customised name), retention DDL now uses `${CLICKHOUSE_DATABASE}.<table>`, `OTEL_LOCAL_FLAGS` always forwards `--clickhouse-database`, and the pre-existing `--user kasm_otel` hardcoding in `apply_clickhouse_retention_tiers` fixed to `--user "${CLICKHOUSE_USER}"`
  - Changed: `install/conf/clickhouse/init-schema.sql` — `$CLICKHOUSE_DATABASE` placeholder at both the `CREATE DATABASE` and `CREATE TABLE` sites
  - Changed: `install/conf/clickhouse/users.xml` — username element and `GRANT ALL ON` both templated (`$CLICKHOUSE_USER`, `$CLICKHOUSE_DATABASE`); this closes a latent bug where the XML user element was never templated at all
  - Changed: `install/conf/otel/otel-collector-local.yaml` — `database:` templated to `$CLICKHOUSE_DATABASE` in all three ClickHouse exporters
  - Changed: `install/docker/docker-compose-{app,all,api}.yaml` — `KASM_CLICKHOUSE_DATABASE` env now `"$CLICKHOUSE_DATABASE"` instead of the literal `"kasm_otel"` (5 sites)
  - Changed: `docs/telemetry/how-to/deploy.md` — flag table row + a new "External / Multi-Tenant ClickHouse" recipe section
  - Changed: `docs/telemetry/how-to/upgrade.md` — flag table row noting recovery behaviour
  - Changed: `scripts/otel-tests/lib/assertions.bash` — added `_CH_DB="${KASM_OTEL_CH_DATABASE:-kasm_otel}"`, used at both `--database` sites (`_ch_exec`, `assert_ch_role_node_has_signal`)
  - Changed: `scripts/otel-tests/lib/otel-fixtures.bash` — `collector_ext_start`/`second_ch_start` read `KASM_OTEL_CH_DATABASE` (default `kasm_otel`) instead of hardcoding it
  - Changed: `scripts/otel-tests/profiles/par.bats` — GA-node query now uses `${_CH_DB}` instead of the literal
  - Added: `scripts/otel-tests/profiles/p16.bats` — new profile: installs with `--clickhouse-database kasm_tenant_a`, asserts the database and `otel_logs` exist, `kasm_otel` does *not* exist, all three signals land, and UI reports return data (the read/write-split check)
  - Changed: `scripts/otel-tests/qa/helpers.sh` — `ch()` reads `CH_DB` back from the collector config instead of hardcoding `kasm_otel`
  - Changed: `scripts/otel-tests/validate-configs.sh` — added the missing `$CLICKHOUSE_DATABASE` substitution to `render_local()` (needed once the placeholder was introduced, or `otelcol validate` would choke on the literal token)
  - Changed: `scripts/otel-tests/recovery/helpers.bash` — `fresh_vars()` gets `CLICKHOUSE_DATABASE='kasm_otel'`; `scenario_external_db`'s mock conf gets a `database: tenant_x` line
  - Changed: `scripts/otel-tests/recovery/recovery.bats` — 3 new tests: default-install database stays `kasm_otel`, external-DB install recovers `tenant_x`, and an explicit `--clickhouse-database` flag wins over recovery
  - Changed: `docs/telemetry/reference/test-matrix.md` — new `P16` row (install profiles table), new `--clickhouse-database` row (coverage map), realigned table padding
- **Files changed (kasm-helm, docs only):**
  - `docs/otel-execution/H3-clickhouse.md` — made the `users.xml` grant templating explicitly load-bearing (cites the `ACCESS_STORAGE_READONLY` finding), made `init-schema.sql`'s `CREATE DATABASE`/`CREATE TABLE` templating explicit and required, added the `.database` qualifier requirement to the retention Job's `ALTER TABLE` guidance
  - `docs/otel-execution/H4-collector.md` — replaced "port unchanged" with an explicit requirement to template all three exporters' `database:` key, with the read/write-split failure mode spelled out
  - `docs/otel-execution/H6-tests-e2e.md` — added database-templating assertions to the `otel_collector_config_test.yaml` and `clickhouse_test.yaml` rows, added a non-default-database e2e step (#8) to `test_12_observability.py`
  - `docs/otel-execution/H7-docs-release.md` — added the external/multi-tenant operator-prerequisites paragraph to the `observability.md` outline (item 5) and a CHANGELOG **Added** bullet
  - `docs/otel-integration-plan.md` — added a `§6` behaviour-parity row for the database threading requirement
  - `docs/otel-execution/PROGRESS.md` — this entry, the Status row, and the Contract registry row
- **Verification:**
  - `grep -c "kasm_otel\." api_server/api_server/data/clickhouse_reports.py` → `0` (was 19)
  - `make unit-test-quick T="tests/test_clickhouse_reports.py"` → `20 passed`
  - `make lint` → `All checks passed!`
  - `make pyright` → `0 errors, 0 warnings, 0 informations`
  - `grep -n "CLICKHOUSE_DATABASE" install/install.sh install/upgrade.sh | wc -l` → `20`
  - `bash -n install/install.sh && bash -n install/upgrade.sh` → clean
  - `grep -rn "kasm_otel" install/conf/clickhouse/ install/conf/otel/otel-collector-local.yaml` → every remaining hit is a username or comment prose, never a database
  - `bash -n scripts/otel-tests/lib/assertions.bash scripts/otel-tests/lib/otel-fixtures.bash scripts/otel-tests/qa/helpers.sh scripts/otel-tests/validate-configs.sh` → clean
  - `bats --count` on `p16.bats` (13), `par.bats` (8), `recovery.bats` (38) → all parse
  - `make otel-recovery-test` → **actually executed**, 38/38 pass (includes the 3 new database-recovery tests, which exercise the real `upgrade.sh` recovery code, not a mock) — no DinD required, CI-safe
  - `bash scripts/otel-tests/validate-configs.sh` → **actually executed** against the real pinned `otel/opentelemetry-collector-contrib:0.156.0` image; all 5 rendered variants (`local-default`, `local-forward`, `local-no-db`, `local-splunk`, `remote-default`) PASS `otelcol validate`, confirming the new `$CLICKHOUSE_DATABASE` placeholder substitution is correct
  - `grep -n "p16" docs/telemetry/reference/test-matrix.md` → present; `scripts/otel-tests/Makefile` has no textual profile registry to grep (see Deviations) — verified instead via `make -C scripts/otel-tests list | grep p16` → `p16`
  - **Not executed:** the `p16.bats` scenario itself (needs the kasm-lab DinD harness and takes a long time) — **written but not run**, per the task's explicit instruction not to attempt a full profile run
- **Deviations from the phase doc:**
  - `docs/telemetry/reference/configuration.md` had **no** `KASM_CLICKHOUSE_DATABASE` row at all before this phase (the doc said "update" it, implying it existed) — added it fresh instead of editing an existing row.
  - `scripts/otel-tests/Makefile` profile shortcuts are auto-discovered from `profiles/*.bats` (`PROFILES := $(basename $(notdir $(wildcard $(SUITE_DIR)/profiles/*.bats)))`) — there is no per-profile line to add or grep for. Creating `p16.bats` alone makes `make p16` and `make list` work; the doc's verify command (`grep -n "p16" scripts/otel-tests/Makefile`) will find nothing by design. Confirmed via `make list | grep p16`.
  - Went beyond the doc's explicit file list in `scripts/otel-tests/recovery/` (`helpers.bash`, `recovery.bats`) — this CI-safe, no-Docker bats suite directly unit-tests `upgrade.sh`'s `recover_otel_config()`, so it was the natural place to prove the new database-recovery code path (and the "explicit flag wins over recovery" contract) without needing DinD. Not called out by name in the phase doc's Part 4 file list, but squarely in scope of "recovered on upgrade" from the Definition of Done.
  - Chose `clickhouse-database` (not `configurable-clickhouse-database`) as the P16 profile short name so it fits the existing fixed-width column alignment in `test-matrix.md`'s install-profiles table without re-padding all 16 rows.
- **Notes for later phases:** Values key for H1/H3/H4 to implement: `.Values.observability.clickhouse.database`, default `kasm_otel`, independent of `.Values.observability.clickhouse.username`. Must reach five sites (see Contract registry row above) — H3 and H4 docs now say this explicitly rather than "port unchanged". The backend recovery pattern (`upgrade.sh`) is the reference for how H6's `test_12_observability.py` non-default-database case should assert read/write agreement.
- **Cross-phase findings:** `install/docker/docker-compose-api.yaml` has `KASM_CLICKHOUSE_USER: "kasm_otel"` as a **literal**, unlike `docker-compose-app.yaml`/`docker-compose-all.yaml` which use `"$CLICKHOUSE_USER"`. Not touched (out of scope for this phase — it's a username inconsistency, not a database one), but a real latent bug: an `api`-role install with a custom `--clickhouse-username` would get the wrong username in that one compose file. Left for a future pass; noted here rather than silently fixed.

---

### H1 — Values, schema, helpers
- **Status:** done
- **Files added/changed/deleted:**
  - Changed: `charts/kasm-helm/values.yaml` — new `observability:` tree (enabled, collector, fileLogs, hostLogs, nginxLogs, clickhouse, browser) inserted between `components:` and the `#### Extra Kubernetes config settings ####` banner, in the file's `# <path> -- <desc>` comment style; `daemonSet: {}` added to both `extraAnnotations` and `extraLabels`; `clickhouse-password`/`otel-bearer-token` added (empty string) to `kasmSecrets.passwords`
  - Changed: `charts/kasm-helm/values.schema.json` — matching `observability` object added under root `properties` (between `components` and `database`), `additionalProperties: false` at every object level; `daemonSet` added to `extraAnnotations`/`extraLabels` properties + `required` arrays; `clickhouse-password`/`otel-bearer-token` added under `kasmSecrets.passwords.properties`
  - Changed: `charts/kasm-helm/templates/_helpers.tpl` — `otel` and `clickhouse` constants blocks added to `kasm.constants` (after `rdpHttpsGateway`); `otel-collector` added to `replicas.preset`; `otel-collector`, `clickhouse`, `otel-sidecar` added to `resources.preset` (with `ephemeral-storage` on the first two, per the Kyverno `resources.required` policy); five new helpers appended at end of file: `kasm.otelEnv`, `kasm.clickhouseHttpEndpoint`, `kasm.clickhouseNativeDsn`, `kasm.clickhouseEnv`, `kasm.observabilityValidate`
  - Changed: `charts/kasm-helm/templates/kasm-password-secret.yaml` — `clickhouse-password`, `otel-bearer-token` added to `$knownKeys`
  - Changed: `charts/kasm-helm/templates/db-preseed-secret.yaml` — `clickhouse-password`, `otel-bearer-token` added to `$knownPasswordKeys` (see Deviations — the phase doc left this as an open question, this phase resolved it to "yes, add them")
  - Changed: `charts/kasm-helm/images.txt` — appended `otel/opentelemetry-collector-contrib:0.156.0` and `clickhouse/clickhouse-server:24.12-alpine`
- **Verification:**
  - `python3 -c "import json;json.load(open('charts/kasm-helm/values.schema.json'));print('ok')"` → `ok`
  - `make lint` → `1 chart(s) linted, 0 chart(s) failed`
  - `make render` → all 19 scenarios rendered with no errors
  - `make unittest` → `Charts: 1 passed, 1 total` / `Test Suites: 44 passed, 44 total` / `Tests: 517 passed, 517 total` — identical to the pre-phase baseline, no existing suite touched or broken
  - `make kubeconform` → every rendered scenario `Invalid: 0, Errors: 0`
  - `make kyverno` → every rendered scenario `fail: 0, error: 0`
  - `helm template kasm-test charts/kasm-helm -n kasm-test --set observability.bogusKey=1` → fails with `additional properties 'bogusKey' not allowed`, proving the schema is wired up
  - `helm template kasm-test charts/kasm-helm -n kasm-test --set observability.enabled=false` → renders successfully (`ok`)
  - `grep -rl "clickhouse-password\|otel-bearer-token" .rendered/` → present in all 19 rendered scenarios' `kasm-secrets` Secret (the only rendered-output change, as required by the Definition of Done)
  - `make readme-check` → fails (stale line-number references only), as expected; not run `make readme` per instructions
- **Deviations from the phase doc:**
  - **`clickhouse.svc` decision:** kept it as the in-cluster Service name unconditionally (`<release>-clickhouse`), never a standalone URL — the doc offered this as the preferred option "if it reads more cleanly," and it does: `kasm.clickhouseHttpEndpoint`/`kasm.clickhouseNativeDsn` are the single source of truth for "how do I reach ClickHouse" (in-cluster or standalone), so nothing needs to branch on `$constants.clickhouse.svc` for the standalone case.
  - **Preseed secret path:** the doc left "does preseed need the two new keys" open. Resolved: **yes**, added to `db-preseed-secret.yaml`'s `$knownPasswordKeys` too. Reasoning: that file's Secret-rendering loop writes any key present in `kasmSecrets.passwords` that is *not* in the known-keys list, unconditionally, once per render — including the empty-string defaults this phase adds to `values.yaml`. Without this change, a `kasmConfig.generatePreseed: true` deployment would render `clickhouse-password: ""` / `otel-bearer-token: ""` (base64 of empty string) into the Secret instead of a proper random value, the same latent-bug shape H0b's Cross-phase findings entry flagged for `KASM_CLICKHOUSE_USER`. Adding both keys to `$knownPasswordKeys` routes them through the existing random-generation-with-lookup-preservation loop instead, matching the non-preseed path's behavior exactly.
  - **RESOLVED post-phase (human, 2026-08-06): the Collector *is* zone-scoped.** The DaemonSet decision
    replaced the nginx log *sidecar*, not the per-zone Collector Deployment — plan §3 keeps both (N zone
    Collector Deployments + 1 cluster-wide DaemonSet exporting to the primary zone's Collector). So
    `kasm.otelEnv`'s zone-scoped endpoint was right and `kasm.constants.otel.svc` was the wrong one.
    `otel.svc` has been corrected to the chart's established per-zone convention, mirroring
    `guac`/`rdpGateway`/`rdpHttpsGateway` exactly: primary-zone suffix when `kasmZones` is set,
    `-default` suffix otherwise. **H4 must render one Collector Service per zone named
    `<release>-otel-collector-<zone>` and must not "simplify" this back to a single cluster-wide
    Service.** Re-verified after the change: `make lint` clean, `make unittest` 517/517, 44/44.
  - **`kasm.otelEnv` zone-endpoint format:** implemented literally as the doc specified (`http://<release>-otel-collector-<zone>:4318`, zone-name-normalized via `kasm.zoneName`, falling back to `"default"` when no zone is passed) even though the Collector Service's actual naming/zone-scoping is explicitly TBD, owned by H4 (see Contract registry). If H4 decides the Collector is **not** zone-scoped (a single cluster-wide Service, which the `kasm.constants.otel.svc` value in this phase already assumes — it has no zone parameter), H4 must update `kasm.otelEnv` to match and note the change here.
  - **`kasm.observabilityValidate` calling convention:** implemented to take the root context directly (`{{ include "kasm.observabilityValidate" $ }}`) rather than a `dict`, since it needs no other inputs and this matches `kasm.nginxResolver`'s existing single-arg convention. Not called from any template yet (per the phase doc — H4 wires it in).
  - Everything else in the phase doc (values tree shape, schema conventions, constants block, presets, `otelEnv`/`clickhouseEnv` field-by-field behavior, secret-key list, `images.txt`) was implemented as written; no other discrepancies found between doc and code.
- **Notes for later phases:** see the Contract registry rows above for exact helper signatures. Additional detail:
  - `kasm.otelEnv`'s `component` argument is a plain string compared against `observability.fileLogs.components` via `has` — pass `"api"`, `"manager"`, or `"guac"`; omit (or pass `""`) for rdp-gateway/rdp-https-gateway, which are not valid `fileLogs.components` entries and will `fail` in `kasm.observabilityValidate` if ever added there.
  - `kasm.clickhouseHttpEndpoint`/`kasm.clickhouseNativeDsn` do **not** validate that a `standalone` endpoint is non-empty — that check lives in `kasm.observabilityValidate` (which H4 must actually call for it to take effect). Callers in H3/H4 should call `kasm.observabilityValidate` before relying on these being non-empty in standalone mode.
  - `tests/e2e/images.txt` referenced by the phase doc does not exist in this checkout (only the one `charts/kasm-helm/images.txt` was found) — nothing to update there; noted as a doc/code discrepancy, code wins.
  - `default_image_tags_test.yaml` asserts on `useImageTags` precedence for the seven existing Kasm components only; it does not enumerate `images.txt` contents, so it needed no changes for the two new pinned images.
  - Kyverno's `resources.required` policy is why `otel-collector`/`clickhouse`/`otel-sidecar` all carry `ephemeral-storage` in both `requests` and `limits`, mirroring every existing `resources.preset` entry.
- **Cross-phase findings:** none beyond what's already recorded in the top-level Cross-phase findings section below.

---

### H4 — Collector
- **Status:** done
- **Files added/changed/deleted:**
  - Added: `charts/kasm-helm/templates/otel-collector-configmap.yaml` — per-zone forwarder Collector
    config (one rendered ConfigMap shared by every zone), ported from
    `otel-collector-remote.yaml`. `otlp/local` (4318), `otlp/remote` (4317, bearer-auth), `otlp/nginx`
    (4316); `batch`+`memory_limiter` only, no `tail_sampling`; single `otlp` exporter to
    `$constants.otel.gatewaySvc:4317` with `${env:OTEL_BEARER_TOKEN}`, `tls.insecure: true`,
    `retry_on_failure`/`sending_queue` ported verbatim. Calls `kasm.observabilityValidate` at the top.
  - Added: `charts/kasm-helm/templates/otel-gateway-configmap.yaml` — cluster-wide gateway config,
    ported from `otel-collector-local.yaml` minus the nginx `filelog`/`nginx/metrics` receivers
    (H5's territory). Only `otlp/remote` receiver; `batch`+`memory_limiter`+`tail_sampling`
    (`sampling_percentage` templated from `tailSamplePercentage`, rest verbatim including the
    `decision_wait` comments); three ClickHouse exporters with `database`/`username` templated from
    `observability.clickhouse.{database,username}` and `password` via `${env:CLICKHOUSE_PASSWORD}`,
    TTLs templated (`mul retention.<x>Days 24`), `create_schema: true` retained; DSN built from
    `kasm.clickhouseNativeDsn` plus the `skip_verify`/`dial_timeout` query-param rules from the H4
    doc's endpoint table (all three bundled/standalone-verbatim/standalone-bare-host cases verified
    against that table); `debug` exporter substitution when `not (clickhouse.enabled or standalone)`;
    optional `otlphttp/external` stacked onto all three pipelines when `collector.forward.endpoint`
    is set, with a Bearer header only when a token/existingSecret is configured. No Splunk block
    ported (deferred to H7's `examples/`).
  - Added: `charts/kasm-helm/templates/otel-collector-deployment.yaml` — per-zone forwarder
    Deployment (`RollingUpdate`), uid 10001, `OTEL_BEARER_TOKEN` env only, `GOMEMLIMIT` from the
    resolved resources via the new `kasm.gomemlimit` helper, ports `otlp-http`/`otlp-grpc`/
    `otlp-nginx`/`health`/`self-metrics`, `checksum/config` annotation over the forwarder ConfigMap
    (skipped when `existingConfigMap` is set).
  - Added: `charts/kasm-helm/templates/otel-collector-service.yaml` — always-on ClusterIP
    `<release>-otel-collector-<zone>` (5 ports) plus an optional `.../…-external` Service (4317
    only) when `forwarder.externalService.enabled`.
  - Added: `charts/kasm-helm/templates/otel-gateway-deployment.yaml` — single Deployment,
    `replicas` hardcoded via the `otel-gateway` preset (1 at every size) with a doc comment
    explaining why, `strategy: Recreate`, `OTEL_BEARER_TOKEN` + (conditionally) `CLICKHOUSE_PASSWORD`
    + (conditionally) `OTEL_FORWARD_TOKEN`, `GOMEMLIMIT`, ports `otlp-grpc`/`health`/`self-metrics`
    only, `checksum/config` over the gateway ConfigMap.
  - Added: `charts/kasm-helm/templates/otel-gateway-service.yaml` — single ClusterIP
    `<release>-otel-gateway`, no external variant.
  - Changed: `charts/kasm-helm/templates/_helpers.tpl` — appended `kasm.gomemlimit` (computes
    ~80% of a Mi/Gi memory-limit string as `<n>MiB`) at the very end of the file, per instructions.
    Also two small **targeted** insertions inside the existing `kasm.metadata` define (not a
    rewrite): (1) an `otel-collector-ext` label/annotation merge branch mirroring the existing
    `proxy`/`proxy-ext` pattern, so the forwarder's external Service can carry
    `forwarder.externalService.{labels,annotations}` without a duplicate YAML key; (2) a generic
    `.extraAnnotations` merge point (a `with`-guarded no-op for every existing caller, since none
    pass this key) so a template can hand `kasm.metadata` a computed annotation — e.g. the
    `checksum/config` line — to be merged into the *same* `annotations:` block instead of emitted
    as a second one. See Deviations for why this was necessary.
  - Added: `charts/kasm-helm/tests/values/observability-disabled.yaml`,
    `charts/kasm-helm/tests/values/observability-byo-config.yaml` — added to the render matrix per
    the phase doc's Definition of Done.
- **Verification (commands actually run, this session):**
  - `make lint` → `1 chart(s) linted, 0 chart(s) failed`
  - `make unittest` → `Charts: 1 passed, 1 total` / `Test Suites: 44 passed, 44 total` /
    `Tests: 517 passed, 517 total` — unchanged from baseline (H4 adds no new suites; that's H6).
  - Per instructions, did **not** run `make render`/`kubeconform`/`kyverno` (shared `.rendered/`,
    concurrent H3 session). Instead rendered scenarios individually with
    `./bin/helm template ... > /tmp/h4-*.yaml` and ran `./bin/kubeconform`/`./bin/kyverno` directly
    against those private files, with the same flags/policies the Makefile targets use:
    - `kubeconform -strict -ignore-missing-schemas -summary` on `default.yaml`,
      `multizone-config.yaml`, `observability-disabled.yaml`, `observability-byo-config.yaml` →
      all `Invalid: 0, Errors: 0` (35/42/28/32 resources respectively).
    - `kyverno apply <4 policy files> -r <file>` on the same four → all `fail: 0, error: 0`
      (49/69/39/49 pass).
  - No-credentials check:
    `helm template ... | awk '/otel-collector-config/,/^---/' | grep -E 'password|token'` → only
    `${env:OTEL_BEARER_TOKEN}` references, no literal value.
  - Templating check: `--set observability.clickhouse.retention.logsDays=60 --set
    observability.collector.tailSamplePercentage=50` → `ttl: 1440h` and `sampling_percentage: 50`
    both present.
  - No-database check: `--set observability.clickhouse.enabled=false` → `debug:` present,
    `clickhouse/logs` absent.
  - External-collector check: `--set observability.collector.externalEndpoint=http://alloy:4318` →
    `grep -ciE 'otel-collector|otel-gateway'` → `0`.
  - **THE CRITICAL ONE**, run against `tests/values/multizone-config.yaml` (2 zones): `grep -c
    'tail_sampling:'` → **1**; `grep -c 'clickhouse/traces:'` → **1**.
  - Gateway replicas check (Python over `helm template` output) → `gateway replicas: 1`.
  - BYO forwarder ConfigMap: `--set observability.collector.forwarder.existingConfigMap=my-collector`
    → Deployment mounts `my-collector`, no chart-rendered forwarder ConfigMap.
  - Both rendered `config.yaml` bodies parse as YAML (`yaml.safe_load` over the ConfigMap `data`
    key) in the default scenario.
  - External forwarder Service smoke test: `--set
    observability.collector.forwarder.externalService.{enabled,type,annotations.foo,labels.team}`
    → name `<release>-otel-collector-default-external`, `type: LoadBalancer`, custom label/annotation
    present exactly once each (confirms the `otel-collector-ext` metadata branch works and does not
    duplicate keys).
- **Deviations from the phase doc:**
  - **Found and fixed a real duplicate-YAML-key bug the doc didn't anticipate.** `kasm.metadata`'s
    `include: "la"` always emits an `annotations:` block for `resource: pod` when
    `applyHealthChecks`/`applySecurity` are on (the chart-wide default) — it adds
    `kasm.com/healthcheck`/`kasm.com/security` unconditionally. The doc's literal instruction
    ("add a checksum annotation... if none [idiom] do, it is still correct to add here") led to a
    naive second `annotations:` map key under the same pod `metadata:`, which rendered as a
    duplicate key in every scenario (caught by manually inspecting rendered output — `helm
    template` does not itself error on this, and `kubeconform`/`kyverno`/PyYAML's `safe_load_all`
    also did not flag it, since each parses to a single dict keyed by string and the second
    `annotations:` silently wins in Go's YAML decoding — so the checksum landed, but the
    `kasm.com/healthcheck`/`kasm.com/security` annotations HW everyone else depends on would have
    been quietly dropped whenever a config checksum was present, on both new Deployments). Fixed by
    adding a generic `.extraAnnotations` merge point to `kasm.metadata` instead of a second
    annotations block — see the `_helpers.tpl` entry above. Re-verified with `grep -n
    'annotations:'` over the rendered pod template block: exactly one `annotations:` line, with all
    three keys (`checksum/config`, `kasm.com/healthcheck`, `kasm.com/security`) under it.
  - **Forwarder external Service labels/annotations**: the doc says to follow
    `proxy-service-external.yaml`'s type/annotations handling, but doesn't mention that a literal
    `{{- with ... }}annotations: ...{{- end }}` block appended after `kasm.metadata`'s own `"all"`
    include has the identical duplicate-key problem whenever `kasm.metadata` itself emits
    labels (which it always does — `$labels` is never empty). Resolved by giving the external
    Service its own component name (`otel-collector-ext`, mirroring the chart's existing
    `proxy`/`proxy-ext` split) and adding two small merge branches to `kasm.metadata`, exactly
    parallel to the existing `proxyService.labels`/`proxyService.annotations` branches. The
    Service's `spec.selector` still targets the real `otel-collector` component/zone labels so it
    reaches the right pods; only the metadata (name/labels/annotations) uses `otel-collector-ext`.
  - **ClickHouse exporter `username`**: the doc only explicitly required templating `database:`
    (per H0b); it says nothing about `username:`. Templated it too, from
    `observability.clickhouse.username`, for consistency with `kasm.clickhouseEnv` (which already
    passes the same value to the api/manager containers as `KASM_CLICKHOUSE_USER`) — leaving it as
    the literal `kasm_otel` would silently break a customer who changes `clickhouse.username` but
    not `clickhouse.database`. No test asserts on this either way; flagging as a deliberate
    beyond-the-letter-of-the-doc addition rather than a silent one.
  - **`OTEL_FORWARD_TOKEN` sourcing** (self-caught during implementation, not a doc problem): first
    draft mistakenly fell back to reading the `otel-bearer-token` secret key when
    `forward.existingSecret.name` was unset — wrong secret entirely (that key authenticates
    forwarder→gateway traffic, unrelated to the external forward target). Fixed to read the literal
    `observability.collector.forward.token` value directly in that case, matching
    `values.yaml`'s own documented (if less-preferred) plaintext-token option.
  - Everything else — receiver/processor/exporter shapes, the two-tier topology, port lists,
    Service names, ConfigMap-per-tier semantics, `existingConfigMap` independence, resource/replica
    preset wiring, security context uid 10001, probe wiring — implemented exactly as the doc
    specified; no other discrepancies found between doc and code.
- **Notes for later phases:**
  - Forwarder Service (per zone): `<release>-otel-collector-<zone>` (5 ports: `otlp-http` 4318,
    `otlp-grpc` 4317, `otlp-nginx` 4316, `health` 13133, `self-metrics` 8888). H2 should point
    Kasm services' `OTEL_EXPORTER_OTLP_ENDPOINT` here via `kasm.otelEnv` (already does, per H1).
  - Gateway Service (cluster-wide): `<release>-otel-gateway` (3 ports: `otlp-grpc` 4317, `health`
    13133, `self-metrics` 8888) — equals `$constants.otel.gatewaySvc`. **H5's host-log DaemonSet
    exports straight here**, not through a zone forwarder (no `otlp/nginx`/4316 on the gateway).
  - `GOMEMLIMIT` approach: new helper `kasm.gomemlimit` in `_helpers.tpl` (appended, not inserted
    mid-file) takes a bare Mi/Gi memory-limit string (e.g. `"512Mi"`, `"1Gi"`) and returns `"<n>MiB"`
    at ~80% of that value, using sprig's `mulf`/`float64`/`int64`. Both Deployments compute the
    effective `resourcesObj` (custom override or the `otel-collector`/`otel-gateway` preset) once
    at the top of the template and pass `dig "limits" "memory" "<default>" $resourcesObj` into it.
  - `existingConfigMap` split confirmed independent per the doc: `collector.forwarder.existingConfigMap`
    only affects `otel-collector-configmap.yaml`/`-deployment.yaml`'s volume; `collector.gateway.existingConfigMap`
    only affects the gateway pair. Verified by rendering each alone.
  - The new `kasm.metadata` `.extraAnnotations` key and the `otel-collector-ext` component name are
    now part of the chart's public helper surface — H5 (nginx sidecar, DaemonSet) may find
    `.extraAnnotations` useful for its own checksum annotations if it hits the same duplicate-key
    trap on the DaemonSet or sidecar-bearing pod templates using `applyHealthChecks`/`applySecurity`.
  - Splunk (`splunk_hec`) exporter/pipeline blocks were **not** ported anywhere, per the doc —
    H7 owns `examples/otel-collector-splunk.yaml`.
- **Cross-phase findings:** none beyond the `kasm.metadata` duplicate-annotations-key bug, which
  was fixed in-phase (a shared helper, not H4-specific config) rather than deferred, since leaving
  it in place would have silently broken `kasm.com/healthcheck`/`kasm.com/security` annotations on
  both new Deployments — not something to hand off half-fixed.

---

### H5 — nginx tracing, browser telemetry, host-log DaemonSet
- **Status:** done
- **Files added/changed/deleted:**
  - Changed: `charts/kasm-helm/templates/nginx-shared-configmap.yaml` — `load_module
    modules/ngx_otel_module.so;` as the unconditional first line of `nginx.conf`; `logging.conf`'s
    `access_log` forced to `json_combined` whenever `observability.enabled` (else honours
    `logFormat` as before); an extra `access_log`/`error_log` pair to
    `/var/log/nginx/otel/{access_json.log,error.log}` gated on `nginxLogs.enabled`; `error_log`
    destination changed from a file to `/dev/stderr` (kept the `kasm-proxy-log-tmp` volume/mount —
    nginx still needs `/var/log/nginx` writable for temp dirs).
  - Changed: `charts/kasm-helm/templates/proxy-configmaps.yaml` — added `otel.conf` (http-context
    tracing, per-zone forwarder endpoint) and `stub_status.conf` (loopback-only, gated on
    `observability.enabled`) to the per-zone `proxy-settings` ConfigMap; added
    `otel_span_name`/`otel_span_attr` to `admin_api.conf`/`client_api.conf`/`manager_api.conf`,
    `otel_trace off;` to `health.conf`/`closest.conf`, a commented-out `otel_trace off;` (matching
    the backend's own pending-validation comment) plus active `otel_trace off;` +
    `otel_span_attr kasm.kasm_id`/`kasm.kasm_user_name` on `upstream_proxy.conf`'s `/desktop/`
    location; added `otel_browser.conf` (always renders exactly one of the enabled/disabled
    variants) to the proxy-services ConfigMap. All otel directives gated on
    `observability.enabled`.
  - Changed: `charts/kasm-helm/templates/proxy-deployment.yaml` — `stub-status` containerPort 8090
    gated on `observability.enabled`; `kasm-proxy-otel-logs` volume/mount and an `otel-sidecar`
    container (via the new `kasm.otelSidecar` helper) gated on `observability.nginxLogs.enabled`.
  - Changed: `charts/kasm-helm/templates/guac-nginx-configmap.yaml` — added an `otel.conf` key to
    `guac-nginx-settings` (see Deviations — required to make the location-level directives below
    valid at all); ported `otel_span_attr kasm.kasm_user_name` (commented `otel_trace off;`,
    matching backend) to `/guac_connect/vnc/` and `/guac_connect/vnc/vnc.htmlguaclite`, and active
    `otel_trace off;` to `/vm_connect`.
  - Changed: `charts/kasm-helm/templates/api-deployment.yaml`, `manager-deployment.yaml`,
    `guac-statefulset.yaml` — added the `observability.fileLogs`-gated log volume (new
    `kasm-filelogs-data` emptyDir for api/manager; the existing `kasm-guac-log-data` emptyDir made
    writable instead of read-only for guac) plus an `otel-sidecar` container per component via
    `kasm.otelSidecar`.
  - Added: `charts/kasm-helm/templates/otel-collector-daemonset-configmap.yaml`,
    `otel-collector-daemonset.yaml` — the hostLogs DaemonSet and its Collector config. Merged
    single `filelog/kasm_proxy` receiver (`container` + `router` operators splitting
    stdout/stderr) with explicit unique operator `id`s and an explicit `output: []` terminator on
    the error chain (needed once both chains share one operators array — see Deviations).
    Exports to the cluster gateway on 4317 with the bearer token (or `otlphttp` to
    `collector.externalEndpoint`, no auth, when set). `runAsUser: 0` hand-written security context
    (not `kasm.securityContext`), `hostPath` `/var/log/pods` (read-only) +
    optional `/var/lib/otelcol/file_storage` (`persistOffsets`), gated on `observability.enabled`,
    `hostLogs.enabled`, and `not isOpenshift`.
  - Added: `charts/kasm-helm/templates/otel-nginx-sidecar-configmap.yaml` — the §7 sidecar
    fallback's Collector config: two plain-file `filelog` receivers (access/error, reusing the new
    `kasm.otelNginxAccessLogOperators`/`kasm.otelNginxErrorLogOperators` helpers verbatim, no
    `container`/`router` needed since these are real files not CRI logs) plus an `nginx/metrics`
    receiver scraping `localhost:8090/stub_status` (the one thing the DaemonSet path can't reach).
    Not zone-scoped — the exporter endpoint comes from `OTEL_EXPORTER_OTLP_ENDPOINT`, set per-pod
    by `kasm.otelSidecar`.
  - Added: `charts/kasm-helm/templates/otel-filelogs-sidecar-configmap.yaml` — the §8
    `observability.fileLogs` sidecar's Collector config: one `filelog` receiver reading
    `/opt/kasm/current/log/*.log`, `json_parser` matching `kasm_telemetry`'s `JsonFormatter`
    fields (`timestamp`, `level`, `logger`, `module`, `line`, `message`), `resource["service.name"]`
    set from `${env:OTEL_SERVICE_NAME}` so one shared ConfigMap covers api/manager/guac.
  - Changed: `charts/kasm-helm/templates/_helpers.tpl` — appended (all at end, per instructions):
    `kasm.otelNginxAccessLogOperators`/`kasm.otelNginxErrorLogOperators` (shared filelog operator
    chains, ported verbatim from `otel-collector-local.yaml`), `kasm.otelSidecar` (the shared
    sidecar container define — image, security context, env `OTEL_EXPORTER_OTLP_ENDPOINT`/
    `OTEL_SERVICE_NAME`, `otel-sidecar` resource preset, probes; caller supplies the log volume,
    `otel-sidecar-config` ConfigMap volume, and `otel-sidecar-tmp` emptyDir); one new fail case in
    `kasm.observabilityValidate` for `isOpenshift: true` + `hostLogs.enabled` + `not
    nginxLogs.enabled` (fail-loud, per §6d's "prefer failing loudly" instruction, rather than
    silently swapping to the sidecar path).
  - Changed: `tests/kyverno/pod-security.baseline.yaml` — added a named `exclude` (by DaemonSet
    name, with a comment) to the two rules the hostLogs DaemonSet cannot satisfy (`runAsNonRoot`
    is incompatible with reading `/var/log/pods`), per the doc's explicit "exclude, don't weaken"
    instruction.
  - Changed: `tests/values/route-openshift.yaml` — added `observability.hostLogs.enabled: false` +
    `observability.nginxLogs.enabled: true`, now required by the new OpenShift fail-loud check
    (this scenario predates H5 and had no observability overrides at all).
  - Changed: `charts/kasm-helm/tests/log_format_test.yaml` — the two pre-existing "default"/"json"
    nginx `logFormat` assertions now also set `observability.enabled: false` (H5 makes
    `observability.enabled: true`, the chart default, force `json_combined` regardless of
    `logFormat`); added a third test asserting that forcing behavior explicitly
    (`logFormat: log` + `observability.enabled` at its default `true` → still `json_combined`).
    +1 net test (513 → 514), not a new suite.
  - No new `values.yaml`/`values.schema.json` keys were needed — every value H5 reads
    (`hostLogs.*`, `nginxLogs.*`, `fileLogs.*`, `browser.enabled`, `collector.externalEndpoint`)
    already exists from H1.
- **Verification (commands actually run, this session):**
  - `make lint` → `1 chart(s) linted, 0 chart(s) failed`.
  - `make render` → all 19 scenarios (after fixing `route-openshift.yaml`, see Deviations).
  - `make kubeconform` → every scenario `Invalid: 0, Errors: 0`.
  - `make kyverno` → every scenario `fail: 0, error: 0` (initially 2 failures on the DaemonSet, see
    the Contract registry row and Deviations for the fix).
  - `make unittest` → `Charts: 1 passed, 1 total` / `Test Suites: 44 passed, 44 total` /
    `Tests: 514 passed, 514 total` (513 baseline **+1** from the `log_format_test.yaml` fix above;
    H5 adds no new suites, per instructions).
  - **THE critical check**, against a real render:
    `awk '/nginx.conf: \|/{f=1;next} f{print;exit}'` → `load_module modules/ngx_otel_module.so;`.
  - **`nginx -t` actually run**, against `kasmweb/proxy-private:feature_DEV-31` (confirmed present
    locally beforehand; also pulled fresh to be sure), for **three** distinct rendered config sets,
    laid out on disk to mirror the real mount paths and with a throwaway self-signed cert standing
    in for the cert-manager Secret:
    1. Main proxy, `observability.enabled: true` (default) — `nginx: configuration file
       /etc/nginx/nginx.conf syntax is ok` / `test is successful` (one unrelated `ssl_stapling`
       warning, expected — the throwaway cert has no issuer chain).
    2. Main proxy, `observability.enabled: false` — same pass, confirming the module stays inert
       and harmless.
    3. Guac's nginx sidecar, `observability.enabled: true` — **initially failed twice**, both real
       bugs the doc's own note ("this is the riskiest phase") anticipated; see Deviations for both
       and the fixes. Passes clean after the fixes.
    4. rdp-gateway's nginx sidecar (no otel directives added there) — passes unmodified, confirming
       the `load_module` line alone is harmless for sidecars this phase doesn't otherwise touch.
    (Upstream hostnames were swapped for `127.0.0.1` in the test copies only, since there's no
    cluster DNS in this sandbox to resolve `kasm-test-api-default`; this doesn't touch otel syntax.)
  - **`otelcol validate` actually run**, against the real pinned `otel/opentelemetry-collector-contrib:0.156.0`
    image, for all three new Collector configs (DaemonSet, nginx sidecar, fileLogs sidecar) plus
    the DaemonSet's `externalEndpoint`+`persistOffsets:false` variant — all four `exit: 0`. Caught
    and fixed one real bug (`file_storage` extension needs `create_directory: true` or a
    pre-existing directory — see Deviations).
  - Mutual exclusion: `--set observability.hostLogs.enabled=true --set
    observability.nginxLogs.enabled=true` → fails with the expected message.
  - OpenShift fail-loud: `--set isOpenshift=true` (defaults: `hostLogs.enabled: true`,
    `nginxLogs.enabled: false`) → fails with the expected message; `--set isOpenshift=true --set
    observability.hostLogs.enabled=false --set observability.nginxLogs.enabled=true` → renders,
    zero `kind: DaemonSet`, `otel-sidecar` present (×6).
  - DaemonSet default-on: `kind: DaemonSet` count 1 by default; absent when `hostLogs.enabled=false`;
    glob `var/log/pods/kasm-test_kasm-test-proxy-*/*/*.log` present; `readOnly` on the `hostPath`
    mount confirmed; `grep -cE 'kind: (ServiceAccount|ClusterRole|ClusterRoleBinding|Role|RoleBinding)'`
    → `0`.
  - Sidecar fallback: `otel-sidecar` count `0` by default; `6` with `nginxLogs.enabled=true`
    (proxy's own sidecar) or `--set observability.fileLogs.enabled=true` (api+manager+guac
    sidecars, `kasm-filelogs-data`/`kasm-guac-log-data` present, `kubeconform`+`kyverno` still
    clean).
  - Browser stub: exactly one `/otel-config.js` location present, in every combination of
    `observability.enabled`/`observability.browser.enabled` tried.
  - Access log format: `logFormat=log` + observability default-on → `json_combined`; `logFormat=log`
    + `observability.enabled=false` → `main`.
  - `stub_status.conf` renders with the loopback-only ACL and `otel_trace off;`, gated correctly.
  - The disabled-scenario `otel_` grep is **imprecise as the doc states it** (see Deviations) —
    used a directive-scoped grep instead and got a clean `0`.
- **Deviations from the phase doc:**
  - **Real bug found via `nginx -t`, not anticipated by the doc:** `ngx_otel_module` requires an
    `otel_exporter` block to be configured *somewhere* in an nginx instance's config before
    **any** `otel_trace`/`otel_span_attr` directive can be used there — using them without one is a
    fatal `"otel_exporter" block is missing` error, not a warning. Guac's nginx sidecar has its own
    separate nginx process (not part of the traced main proxy), so porting the backend's
    `kasmguac.conf` span attributes verbatim, as the doc's table literally instructs, would have
    taken guac's nginx down. Fixed by adding a minimal `otel.conf` to `guac-nginx-settings`
    (`otel_exporter` pointed at the **primary zone's** forwarder — this ConfigMap isn't zone-scoped,
    shared across every zone's guac StatefulSet, so it can't reference "this pod's own zone"
    without much larger surgery; a cross-zone hop for guac pods in a non-primary zone within the
    same region is a minor inefficiency, not a correctness bug) and `otel_trace off;` at http level
    (so guac's traffic isn't traced by default; only the explicitly-annotated locations get
    `otel_span_attr`). Recorded as its own `otel.conf`-per-nginx-instance requirement — **not**
    anticipated by H1's "Collector tier topology" contract, which only reasoned about Kasm services
    and the main proxy.
  - **Second real bug, same `nginx -t` pass:** the backend's `kasmguac.conf` sets
    `otel_span_attr kasm.kasm_id "$connect_kasm_id"` inside an auth-request flow
    (`/kasm_connect`) that sets `$connect_kasm_id` via `auth_request_set`. This chart's guac nginx
    sidecar has **no such auth_request flow** in those locations (`/guac_connect/vnc/`,
    `/guac_connect/vnc/vnc.htmlguaclite` — no `auth_request`/`auth_request_set` at all), so
    `$connect_kasm_id` is an undefined variable there and nginx fails to start
    (`unknown "connect_kasm_id" variable`). Dropped that one attribute (kept
    `kasm.kasm_user_name`, which is a standard nginx cookie variable and needs no
    `auth_request_set`), with a comment explaining why. This is a case where the backend's routing
    topology (one nginx, one auth flow) doesn't map onto the chart's (guac has its own nginx,
    different auth path) — the doc's instruction to "port verbatim" doesn't apply to a variable
    that was never defined here; flagging per the CLAUDE.md "code wins" rule.
  - **`otelcol validate` bug**, not anticipated: the `file_storage/checkpoints` extension refuses
    to start if its directory doesn't already exist, unless `create_directory: true` is set.
    The DaemonSet's `hostPath` volume is `type: DirectoryOrCreate` so this is a non-issue at real
    runtime (the directory is guaranteed to exist by the time the container starts), but
    `create_directory: true` was added anyway — cheap insurance against any ordering assumption,
    and it's what let local `otelcol validate` (which doesn't know about Kubernetes volume
    semantics) pass cleanly.
  - **The doc's own disabled-scenario check is imprecise**, discovered while verifying: `grep -c
    'otel_'` will never be `0` once `load_module modules/ngx_otel_module.so;` is unconditionally
    present, because that filename literally contains the substring `otel_` (`ngx_` + `otel_module`).
    Verified with a directive-scoped pattern instead
    (`grep -cE 'otel_(trace|exporter|span_name|span_attr|service_name|trace_context)'` → `0`) and
    confirmed by hand that the only two `otel_` hits in the disabled render are `load_module` itself
    and the `otel_browser.conf` ConfigMap *key name* (not a directive). Flagging so H6/H7 don't
    reuse the doc's literal command and get a false failure, matching the precedent H2 set for a
    similar doc-command inaccuracy.
  - **`kasm.metadata`'s `daemonSet` vs `daemonset` case mismatch** (pre-existing, in the
    `kasm.com/healthcheck`/`kasm.com/security` special-case list, unrelated to the
    `extraAnnotations`/`extraLabels` lookup which is exact-key and unaffected): passing
    `"resource" "daemonSet"` to the *top-level* `kasm.metadata` call does **not** hit that
    lowercase-only list, but the **pod-template** `kasm.metadata` call — like every other
    workload's — uses `"resource" "pod"`, which *does* match, so `kasm.com/security: "true"` is
    added regardless. This produced a real Kyverno failure (see the Contract registry row); fixed
    by excluding the DaemonSet from the two conflicting rules by name rather than touching the
    shared `kasm.metadata` special-case list (which every other workload in the chart relies on).
    Left the lowercase/camelCase mismatch itself unfixed — it's dead code today (nothing else passes
    `"resource" "daemonset"` or `"daemonSet"` to the top-level call) and fixing it is out of this
    phase's scope; noted here rather than silently touched.
  - **`kasm.otelSidecar`'s `configMap` argument is caller-informational only** — the helper's own
    `volumeMounts` reference a fixed volume name (`otel-sidecar-config`), and the caller is
    responsible for adding a matching `volumes:` entry pointing at whatever ConfigMap it passed in
    `.configMap`. This matches the doc's documented usage signature exactly but means the argument
    isn't actually consumed inside the define; documented in the helper's own doc comment so a
    future reader doesn't go looking for where it's used internally.
  - Everything else — `load_module` placement and scope (confirmed it's needed in exactly one
    template, `nginx-shared-configmap.yaml`, since all four nginx-owning workloads — proxy, guac,
    rdp-gateway, rdp-https-gateway — mount its `nginx.conf` and all four run `$constants.proxy.image`
    for their nginx container/sidecar), the `/api/` location already covering
    `/api/client/telemetry/*` with no changes needed, the DaemonSet's lack of any
    `k8sattributes`/RBAC, `stub_status.conf`'s loopback-only ACL, the browser config's exact
    response bodies, and the §5 access/error log destination changes — implemented exactly as the
    doc specified; no other discrepancies found.
- **Notes for later phases:**
  - DaemonSet ConfigMap: `kasm-test-otel-hostlogs` (component `otel-hostlogs`); DaemonSet itself
    same name/component. Include glob and stream-attribute caveat are in the Contract registry
    above.
  - nginx sidecar ConfigMap: `<release>-otel-nginx-sidecar` (component `otel-nginx-sidecar`, not
    zone-scoped). fileLogs sidecar ConfigMap: `<release>-otel-filelogs-sidecar` (component
    `otel-filelogs-sidecar`, not zone-scoped, shared by api/manager/guac).
  - `kasm.otelSidecar` is now on the chart's helper surface with the exact signature documented in
    its own comment block in `_helpers.tpl` (`context`, `volumeName`, `mountPath` required;
    `configMap` documented but caller-consumed only; `zone`/`serviceName` optional).
  - H6 should add unit-test coverage for: the DaemonSet's presence/absence and glob content, the
    mutual-exclusion and OpenShift fail-loud validate errors, `otel-sidecar` presence/absence for
    both the nginxLogs and fileLogs paths, and the `load_module`-is-line-1 invariant across a
    render (a `matchRegex`/`equal` assertion, not just this session's manual `awk`).
  - H7's docs should mention that on OpenShift, `observability.nginxLogs.enabled: true` is
    mandatory whenever `observability.hostLogs.enabled` would otherwise be left at its default
    `true` — the chart fails the render rather than silently collecting nothing, matching the
    "prefer failing loudly" instruction.
- **Cross-phase findings:**
  - Confirmed the Follow-ups entry "nginx connection metrics on the default (DaemonSet) log path"
    remains accurate and unresolved — the sidecar fallback (§7) is the only path that collects
    them (`nginx/metrics` receiver in `otel-nginx-sidecar-configmap.yaml`), exactly as designed.
  - None beyond what's already recorded in the top-level Cross-phase findings section below.

---

### H3 — ClickHouse
- **Status:** done
- **Files added/changed/deleted:**
  - Added: `charts/kasm-helm/templates/clickhouse-configmap.yaml` — one ConfigMap (`config.xml`,
    `users.xml`, `init-schema.sql`), not zone-scoped, ported verbatim from
    `kasm_backend/install/conf/clickhouse/*` with `$CLICKHOUSE_DATABASE`/retention-day
    placeholders replaced by `{{ }}` templating and the `https_port`/`tcp_port_secure`/`openSSL`
    block wrapped in `{{- if .Values.observability.clickhouse.tls }}`. `users.xml`'s username
    element and grant target are templated from `.username`/`.database`; the password is never
    templated — `<password from_env="KASM_CLICKHOUSE_PASSWORD"/>` instead.
  - Added: `charts/kasm-helm/templates/clickhouse-statefulset.yaml` — modeled on
    `db-statefulset.yaml`. `replicas: 1`, uid 101, `readOnlyRootFilesystem: true` (see Contract
    registry row for the three things that took to make that work), TLS-gated extra ports/cert
    mounts, `health.probe`'s new `timingParent` wired to `observability.clickhouse.healthCheckTiming`,
    a `checksum/config` pod annotation over the ConfigMap, stable PVC name
    `<release>-clickhouse-data`.
  - Added: `charts/kasm-helm/templates/clickhouse-service.yaml` — headless (`clusterIP: None`),
    not zone-scoped, exposes `ch-http`/`ch-native` always and `ch-https`/`ch-native-tls` when
    `tls: true`.
  - Added: `charts/kasm-helm/templates/clickhouse-retention-job.yaml` — `post-install,post-upgrade`
    Helm hook Job, statements ported verbatim from `upgrade.sh`'s
    `apply_clickhouse_retention_tiers()` (including its per-statement `|| echo Warning` tolerance
    for tables that don't exist yet), connecting over the always-plaintext native port (9000) so
    TLS never needs to be dealt with in-cluster. `clickhouse-client` reads `CLICKHOUSE_PASSWORD`
    from its environment natively — verified against the real client — so the password is never a
    CLI argument.
  - Changed: `charts/kasm-helm/templates/_helpers.tpl` — added an optional `timingParent` dict arg
    to `health.probe` (checked before the `db` special-case and the `components.<component>`
    lookup), for components like ClickHouse that don't live under `.Values.components`. Purely
    additive; no existing caller is affected.
  - Added: `tests/values/observability-external-ch.yaml` — standalone-ClickHouse render scenario
    per the phase doc's Definition of Done, so `make render`/`kubeconform`/`kyverno` cover the
    external path going forward.
- **Verification (commands actually run, this session):**
  - Per instructions, did **not** run `make render`/`kubeconform`/`kyverno` (shared `.rendered/`,
    concurrent H4 session). Rendered scenarios individually with `./bin/helm template ... >
    /tmp/h3-*.yaml` and ran `./bin/kubeconform`/`./bin/kyverno` directly against those private
    files:
    - `default.yaml`: `kubeconform -strict -ignore-missing-schemas -summary` → `39 resources,
      Invalid: 0, Errors: 0`; `kyverno apply` (all 4 policy files) → `pass: 58, fail: 0, error: 0`.
    - TLS off (`--set observability.clickhouse.tls=false`): `38 resources, Invalid: 0, Errors: 0`.
    - `tests/values/observability-external-ch.yaml` (standalone): `34 resources, Invalid: 0,
      Errors: 0`; `kyverno` → `pass: 49, fail: 0, error: 0`; confirmed **0** ClickHouse
      StatefulSets/PVCs rendered.
    - `tests/values/trustedca-enabled.yaml`: `40 resources, Invalid: 0, Errors: 0`; `kyverno` →
      `pass: 58, fail: 0, error: 0`; confirmed the ClickHouse StatefulSet still renders alongside
      the trusted-CA init container.
    - `--set observability.clickhouse.enabled=false`: confirmed 0 ClickHouse StatefulSets/Services
      /ConfigMaps/Jobs (only the always-present `clickhouse-password` Secret key and unrelated H4
      collector comments matched a `grep -i clickhouse`).
    - `--set observability.enabled=false`: confirmed 0 ClickHouse resources of any kind.
  - No-credentials check: `awk '/kind: ConfigMap/,/^---/' | grep -i password | grep -v -E
    'from_env|\$\{env:|supplied by the from_env|never a ConfigMap'` → no output (only `from_env`/
    `${env:}` references and doc-comment prose match `password` at all; H4's collector ConfigMap
    contributes the `${env:CLICKHOUSE_PASSWORD}` hits).
  - Retention templating: `--set observability.clickhouse.retention.logsDays=60` →
    `INTERVAL 60 DAY DELETE WHERE IsAudit = 0` present in the rendered `init-schema.sql`.
  - `health.probe` `timingParent`: `--set
    observability.clickhouse.healthCheckTiming.livenessProbe.initialDelaySeconds=120` → rendered
    liveness probe shows `initialDelaySeconds: 120`.
  - `make lint` → `1 chart(s) linted, 0 chart(s) failed`.
  - `make unittest` → `Charts: 1 passed, 1 total` / `Test Suites: 44 passed, 44 total` /
    `Tests: 517 passed, 517 total` — unchanged from baseline (H3 adds no new suites; that's H6).
  - **Docker-based end-to-end verification against the real pinned image**
    (`clickhouse/clickhouse-server:24.12-alpine`, already present on the host), independent of the
    shared kind/k8s state, run before committing to the design:
    1. `from_env` on `<password>` — confirmed a client can authenticate as the XML-defined user
       with the env-sourced password, and that user can `CREATE DATABASE`/`CREATE TABLE`
       (grant works pre-existing-database, per the doc's `ACCESS_STORAGE_READONLY` warning).
    2. Full `readOnlyRootFilesystem: true` boot, with the exact mount/env-var set the StatefulSet
       now uses (`--read-only --user 101:101`, PVC-equivalent bind mount, `/tmp` and
       `/var/log/clickhouse-server` emptyDir-equivalent mounts, `CLICKHOUSE_SKIP_USER_SETUP=1`) —
       boots clean, client login succeeds.
    3. `docker-entrypoint-initdb.d/init.sql` (with real placeholders substituted) — creates the
       database and `otel_logs` table with the correct `IsAudit` MATERIALIZED expression and both
       TTL arms (`SHOW CREATE TABLE` output diffed against the source file by eye).
    4. `ALTER TABLE ... IF EXISTS` — **does not exist** in ClickHouse 24.12 (`Code: 62,
       SYNTAX_ERROR`); confirms the retention Job must tolerate missing tables via `|| echo
       Warning` (matching `upgrade.sh`) rather than an `IF EXISTS` clause, and rules out the
       phase doc's alternate `system.tables`-iteration suggestion as unnecessary (`upgrade.sh`
       doesn't do that either — code wins, ported literally).
    5. The full retention Job script, run in a container talking to a running ClickHouse over a
       Docker network by hostname (mirroring the in-cluster Service), including the `/ping` wait
       loop — exits 0, and `SHOW CREATE TABLE` confirms the TTL values it set (60/400 days)
       actually landed.
    6. `clickhouse-client` reads `CLICKHOUSE_PASSWORD` from its process environment without a
       `--password` flag — confirmed empirically, which is why the retention Job never puts the
       password on the command line.
- **Deviations from the phase doc:**
  - **`readOnlyRootFilesystem` needed three things the doc didn't anticipate**, found only by
    booting the real image (see Verification #2 above): `CLICKHOUSE_SKIP_USER_SETUP: "1"`, and
    `emptyDir` mounts at `/var/log/clickhouse-server` and `/tmp`. The doc's own suggested env list
    (`CLICKHOUSE_DB`/`CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD`) is what *triggers* the entrypoint's
    default-user.xml write attempt in the first place; `CLICKHOUSE_SKIP_USER_SETUP=1` is the
    documented ClickHouse escape hatch and was kept alongside those three vars rather than
    dropping them, since removing them would also disable the `CREATE DATABASE` step of
    `docker-entrypoint-initdb.d` processing on some code paths. All four vars are set; the
    combination is what was actually verified working, not a subset.
  - **The doc's Hand-off notes template asked "whether you extended `health.probe` with
    `timingParent`"** — yes, exactly as it suggested, with no changes needed to the suggestion
    itself.
  - Everything else — file list, guard conditions, port names, TLS wrapping, `users.xml`'s
    ConfigMap-not-Secret resolution, the retention Job's hook annotations/statements, the PVC
    naming rule (no `.Chart.AppVersion` suffix) — implemented exactly as the doc specified; no
    other discrepancies found between doc and code.
- **Notes for later phases:**
  - Endpoints are unchanged from what H1 already implemented in `kasm.clickhouseHttpEndpoint`/
    `kasm.clickhouseNativeDsn` — H3 confirms them against the actual rendered Service/StatefulSet
    ports rather than changing them. H4's gateway ConfigMap (which already consumes
    `kasm.clickhouseNativeDsn`) needs no changes on account of this phase.
  - The retention Job always connects over the **plaintext** native port (9000), never 9440,
    regardless of `observability.clickhouse.tls` — matching the probes' existing "plaintext 8123
    even when TLS is on" precedent, since in-cluster traffic has no reason to deal with the
    self-signed cert.
  - `health.probe`'s new `timingParent` arg is available for H4's Collector probes too, per the
    phase doc's own note ("H4 wants the same for the Collector") — pass
    `observability.collector.<tier>` (or similar) as `timingParent` rather than adding a
    `components.otel-collector`/`components.otel-gateway` values entry that `kasm.mergedValues`
    would then try (and fail) to resolve.
  - `CLICKHOUSE_SKIP_USER_SETUP=1` and the `KASM_CLICKHOUSE_PASSWORD` (not `CLICKHOUSE_PASSWORD`)
    `from_env` variable name are both load-bearing and easy to "simplify" away in a future cleanup
    pass — don't. Removing either breaks the StatefulSet under `readOnlyRootFilesystem: true`.
- **Cross-phase findings:**
  - The Follow-ups entry "No TLS-trust surface for a standalone ClickHouse... H3 should own this"
    is more precisely **H2's** to own, not H3's: there is nothing in H3's actual scope (the
    bundled ClickHouse StatefulSet/Service/ConfigMap/Job) that touches a *standalone* instance at
    all — that path only ever runs through `kasm.clickhouseEnv`, which is consumed by the api/manager
    containers H2 builds. Re-filed below with that correction; H3 did not implement it, since doing
    so means adding a mount to containers this phase doesn't render.
  - `kasm.clickhouseEnv`'s `KASM_CLICKHOUSE_CA_CERT` value (`/etc/ssl/certs/kasm_clickhouse.crt`,
    emitted for the **bundled** ClickHouse with `tls: true`) is an api/manager-side mount path;
    H3's ClickHouse StatefulSet has no reason to reference it and doesn't. Confirming for H2: the
    source Secret for the actual cert bytes is the same one the StatefulSet mounts —
    `.Values.certificate.secretName | default (include "kasm.name" (list . "cert-manager"
    "secret"))`, key `tls.crt` — since ClickHouse's TLS setup (per the ported `config.xml` comment)
    deliberately reuses "the shared kasm_nginx pair," the same cert already trusted elsewhere in
    the chart.

---

### H2 — Service instrumentation
- **Status:** done
- **Files added/changed/deleted:**
  - Changed: `charts/kasm-helm/templates/api-deployment.yaml` — appended `kasm.otelEnv` (serviceName
    `kasm-api`, `zone` `$zone.name`, `component` `api`, `python` true) and `kasm.clickhouseEnv` to
    the container's `env:` list; removed the `logFormat: json` `kasm-api-app-config` volumeMount
    and volume; added `kasm.clickhouseCaVolumeMount`/`kasm.clickhouseCaVolume` (new-this-phase,
    below) alongside the existing `trustedCaVolumeMounts`/`trustedCaVolumes` calls.
  - Changed: `charts/kasm-helm/templates/manager-deployment.yaml` — same shape: `kasm.otelEnv`
    (serviceName `kasm-manager`, `component` `manager`, `python` true), `kasm.clickhouseEnv`,
    `kasm-manager-app-config` mount/volume removed, ClickHouse CA volume/mount added.
  - Changed: `charts/kasm-helm/templates/guac-statefulset.yaml` — appended `kasm.otelEnv`
    (serviceName `kasm-guac`, `component` `guac`, no `python`) to the guac application container
    (not the nginx sidecar); added the three `LOG_FILE_NAME_PATTERN`/`LOG_DATE_FORMAT`/
    `LOG_TIMESTAMP_FORMAT` env vars, gated on `observability.fileLogs.enabled` and `"guac"` being in
    `observability.fileLogs.components`.
  - Changed: `charts/kasm-helm/templates/rdp-gateway-deployment.yaml` — appended `kasm.otelEnv`
    (serviceName `kasm-rdp-gateway`, no `component`/`python`) to the rdp-gateway application
    container (not its nginx sidecar).
  - Changed: `charts/kasm-helm/templates/rdp-https-gateway-statefulset.yaml` — same, serviceName
    `kasm-rdp-https-gateway`.
  - Deleted: `charts/kasm-helm/templates/api-app-configmap.yaml`,
    `charts/kasm-helm/templates/manager-app-configmap.yaml` — dead config per
    `docs/otel-integration-plan.md` §4 (`api_server/server.py` no longer calls
    `logging.config.dictConfig`).
  - Added: `charts/kasm-helm/templates/clickhouse-ca-configmap.yaml` — new, not zone-scoped
    ConfigMap (`<release>-clickhouse-ca`, key `ca.crt`) rendered only when
    `observability.clickhouse.standalone`, `.caCert` is set, and `.caCertConfigMap` is not. Holds
    only public certificate bytes (never a password), so a ConfigMap is the right primitive.
  - Changed: `charts/kasm-helm/templates/_helpers.tpl` —
    - Extended `kasm.clickhouseEnv`'s `KASM_CLICKHOUSE_CA_CERT`/`KASM_CLICKHOUSE_VERIFY` branch
      in-place (targeted edit, not a rewrite) with two new cases for the standalone path, matching
      H0's backend precedence exactly (see the Contract registry row).
    - Appended two new helpers at the end of the file: `kasm.clickhouseCaVolume` and
      `kasm.clickhouseCaVolumeMount` (the standalone-CA ConfigMap volume/mount pair, called only
      from `api-deployment.yaml`/`manager-deployment.yaml`).
    - Added a mutual-exclusion `fail` for `caCert`+`caCertConfigMap` both set, inside
      `kasm.observabilityValidate`.
  - Changed: `charts/kasm-helm/values.yaml` — added `observability.clickhouse.{caCert,
    caCertConfigMap,tlsVerify}` (after the existing `tls` key, before `image`); narrowed the
    `logFormat` top-level comment to state it no longer affects api/manager.
  - Changed: `charts/kasm-helm/values.schema.json` — matching schema entries for the three new
    `clickhouse` keys; updated `logFormat`'s `description` to match.
  - Changed: `charts/kasm-helm/tests/log_format_test.yaml` — removed the `api-app-configmap`/
    `manager-app-configmap` suites (6 tests: 3 each); re-scoped the suite's `templates:` list to
    drop the two deleted templates and add `templates/db-statefulset.yaml`; added 2 new tests
    asserting the postgres JSON-log-to-stdout `command`/`args` override (logFormat's other
    remaining runtime behavior, alongside the nginx/db-configmap assertions already there).
  - `charts/kasm-helm/tests/configmaps_content_test.yaml` needed **no changes** — despite matching
    a broad `app-config` grep, it only references `rdp-gateway-configmap.yaml`'s
    `passthrough.app.config.yaml`, an unrelated, still-live ConfigMap.
- **Equivalence check (doc §3a) result:** `database`/`manager`/`share` blocks in the deleted
  ConfigMaps matched the image's baked-in `install/conf/app/api/api.app.config.yaml` byte-for-byte.
  The `server` block was **missing** `thread_pool`/`thread_pool_log_interval` (present in the image
  default, absent from the chart's rendered ConfigMap) — but both are already overridden by
  `KASM_THREAD_POOL`/`KASM_THREAD_POOL_LOG_INTERVAL` env vars already set in `api-deployment.yaml`,
  satisfying the doc's "every value is overridden at runtime by an existing env var" condition. No
  key differed from the image default without a corresponding override, so deletion proceeded per
  §3b without keeping either ConfigMap around.
- **Verification (commands actually run, this session):**
  - `python3 -c "import json;json.load(open('values.schema.json'));print('ok')"` → `ok`
  - `make lint` → `1 chart(s) linted, 0 chart(s) failed`
  - `make render` → all 23 scenarios rendered with no errors
  - `make test` (lint+render+unittest+kubeconform+kyverno, run as one gate) → every scenario
    `Invalid: 0, Errors: 0` (kubeconform) and `fail: 0, error: 0` (kyverno); `helm-unittest` →
    `Charts: 1 passed, 1 total` / `Test Suites: 44 passed, 44 total` / **`Tests: 513 passed, 513
    total`** — down from the 517 baseline by exactly 4: **-6** for the deleted
    `api-app-configmap`/`manager-app-configmap` suites (3 tests each) **+2** for the new
    `db-statefulset.yaml` JSON-symlink tests. Net change fully accounted for; no suite silently
    broke.
  - `helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/default.yaml | grep -E
    'OTEL_SERVICE_NAME|KASM_LOG_FILE_ENABLED|KASM_CLICKHOUSE_ENDPOINT'` → 5 distinct
    `OTEL_SERVICE_NAME` values (`kasm-api`, `kasm-manager`, `kasm-guac`, `kasm-rdp-gateway`,
    `kasm-rdp-https-gateway`); `KASM_LOG_FILE_ENABLED=false` × 5 (default `fileLogs.enabled: false`,
    so every workload reports `false`, confirming "false everywhere by default" from the doc's
    hand-off question); `KASM_CLICKHOUSE_ENDPOINT` × 2 (api + manager only,
    `https://kasm-test-clickhouse:8443`).
  - `--set observability.enabled=false` → only `OTEL_SDK_DISABLED` (×5) matches `OTEL_|KASM_CLICKHOUSE_`,
    exactly as the doc's Definition of Done specifies.
  - `--set logFormat=json | grep -c 'kasm-api-app-config\|kasm-manager-app-config'` → **0** (the
    doc's own suggested command, `grep -c 'app.config.yaml'`, returns 9 instead of 0 — see
    Deviations, this is a doc bug, not a leftover reference).
  - Standalone-TLS scenario (`--set observability.clickhouse.standalone=true` +
    `nativeEndpoint`/`httpEndpoint` + literal `caCert`): renders a `kasm-test-clickhouse-ca`
    ConfigMap with only the PEM text under `ca.crt`; both api and manager get
    `KASM_CLICKHOUSE_CA_CERT=/etc/ssl/certs/kasm_clickhouse_ca.crt` and the matching
    `clickhouse-ca-cert` volume/mount; no `KASM_CLICKHOUSE_VERIFY` var present in this case.
  - `tlsVerify: false` (no `caCert`) standalone scenario → `KASM_CLICKHOUSE_VERIFY="false"` on both
    containers, no CA ConfigMap rendered, no `KASM_CLICKHOUSE_CA_CERT`.
  - `caCert` + `caCertConfigMap` both set → `Error: ... observability.clickhouse.caCert and
    observability.clickhouse.caCertConfigMap are mutually exclusive`, confirming the new
    `kasm.observabilityValidate` guard fires (via the forwarder Collector ConfigMap, which H4 wires
    the validator into and which renders in every non-`externalEndpoint` scenario).
  - No-credential check on the new ConfigMap: PEM text is the only content of `data.ca.crt`; no
    password field exists on this resource at all.
- **Deviations from the phase doc:**
  - **The doc's own `logFormat=json` verify command is too broad.** `grep -c 'app.config.yaml'`
    also matches `rdp-gateway-configmap.yaml`'s `passthrough.app.config.yaml`,
    `rdp-https-gateway-app-configmap.yaml`'s `rdp_https_gateway.app.config.yaml`, and the
    `db-upgrade-job.yaml`/`db-init-job.yaml` `--cfg` flag path (which points at the **image's own
    baked-in** default file — those Jobs never mounted the deleted ConfigMaps in the first place).
    None of those three are related to the two ConfigMaps this phase deletes. Verified deletion
    instead with a name-scoped grep (`kasm-api-app-config`/`kasm-manager-app-config`), which returns
    0 as expected. Flagging so H6/H7 don't reuse the doc's literal command and get a false failure.
  - Everything else — which templates get `kasm.otelEnv`, the `component`/`python` argument table,
    zone-scoping, guac's three logging env vars and their gate condition, the app-ConfigMap
    deletion + mount/volume removal, `logFormat`'s narrowed values/schema documentation — matches
    the phase doc exactly; no other discrepancies found.
- **Notes for later phases:**
  - `KASM_LOG_FILE_ENABLED` is `false` on api/manager/guac by default (verified above), since
    `observability.fileLogs.enabled` defaults to `false`. H6's e2e coverage for `logFormat` should
    assert against `nginx-shared-configmap.yaml`'s access-log format and `db-statefulset.yaml`'s
    command/args override, not against the API/Manager services at all — those are permanently out
    of `logFormat`'s scope now, per the doc's own narrowed description.
  - The new `observability.clickhouse.{caCert,caCertConfigMap,tlsVerify}` surface is independent of
    the bundled ClickHouse's own `tls`/certificate wiring (H3's territory) — the two paths share no
    code except both ultimately populating `KASM_CLICKHOUSE_CA_CERT`/`KASM_CLICKHOUSE_VERIFY` on
    api/manager via the same `kasm.clickhouseEnv` block.
  - H5/H6: when writing e2e or additional unit coverage for the standalone-ClickHouse path, the
    new ConfigMap name is `<release>-clickhouse-ca` (via `kasm.metadata` with component
    `clickhouse-ca` — deliberately distinct from the bundled ClickHouse's own `clickhouse`
    component name, to avoid a naming collision with `clickhouse-configmap.yaml`).
- **Cross-phase findings:** none beyond what's already recorded in the top-level Cross-phase
  findings section below.

---

### H6 — Tests + e2e
- **Status:** done-with-deviations. Part A (helm-unittest) fully implemented and green. Part B
  (e2e) written per the phase's explicit scope split, but **not executed** — no kind cluster was
  created, no images were pulled/loaded, and no `make e2e*`/`make kind-*` target was run for real
  in this session (see the one accidental near-miss under Deviations).
- **Files added/changed/deleted:**
  - Added (helm-unittest suites, `charts/kasm-helm/tests/`): `otel_collector_test.yaml`,
    `otel_collector_config_test.yaml`, `otel_env_test.yaml`, `nginx_load_module_test.yaml`,
    `otel_daemonset_test.yaml`, `otel_sidecar_test.yaml`, `clickhouse_test.yaml`,
    `clickhouse_external_test.yaml`, `nginx_otel_test.yaml`, `otel_browser_test.yaml`,
    `otel_openshift_test.yaml` — 11 new suite files.
  - Changed: `charts/kasm-helm/tests/negative_validation_test.yaml` — added 11 new
    `kasm.observabilityValidate` fail-message cases (standalone-endpoint-missing,
    standalone+enabled=false, caCert+caCertConfigMap, forward.existingSecret half-set ×2,
    externalEndpoint+forwarder/gateway existingConfigMap ×2, hostLogs+nginxLogs both true,
    isOpenshift+hostLogs, tailSamplePercentage out-of-range ×2), plus a documentation-only note for
    the fileLogs.components-enum case (see Deviations).
  - Reviewed, not changed: `components_toggle_test.yaml`, `healthchecks_test.yaml`,
    `pod_security_test.yaml`, `services_ports_test.yaml`, `deployment_size_test.yaml`,
    `selector_test.yaml`, `labels_annotations_test.yaml`, `service_name_constants_test.yaml`,
    `default_image_tags_test.yaml` — none reference otel/clickhouse; none needed changes to stay
    green (confirmed via `make unittest`). Extending these with observability-specific assertions
    (e.g. a `deployment_size_test.yaml` case pinning the new `otel-collector`/`otel-gateway`/
    `clickhouse`/`otel-sidecar` preset values) is real, useful follow-on work but was not the
    "must assert" list for this phase — noted under Notes for later phases below rather than
    silently skipped.
  - Added (test values, `tests/values/`): `observability-filelogs.yaml`,
    `observability-no-store.yaml`, `observability-forward.yaml`,
    `observability-sidecar-logs.yaml`, `dev31-images.yaml` (e2e-only branch-build image
    overrides, not part of the render/kubeconform/kyverno matrix).
  - Added (e2e, `tests/e2e/`, written but **not executed**): `test_12_observability.py`,
    `test_13_observability_disabled.py`, `test_14_observability_filelogs.py`,
    `test_15_observability_sidecar_logs.py`.
  - Changed (e2e): `test_06_pod_security_standards.py` — added
    `observability.hostLogs.enabled: false` / `nginxLogs.enabled: true` to the existing scenario's
    values (this scenario predated H5 and, left at defaults, would now try to schedule the
    hostLogs DaemonSet — hostPath + `runAsUser: 0` — into a `restricted` namespace and fail before
    ever reaching the original pod-security assertions); added a second, focused test function
    (`test_observability_hostlogs_daemonset_rejected_in_restricted_namespace`) that renders just
    the DaemonSet via `helm template --show-only` and applies it directly to a restricted
    namespace to prove admission really does reject it, without paying for a full chart install.
  - Changed (e2e): `test_10_json_logging.py` — re-scoped the JSON-log assertion list to `proxy`
    and `db` only, per H2's narrowing (api_server/server.py no longer calls
    `logging.config.dictConfig`, so api/manager's console output is text regardless of
    `logFormat`; rdp-gateway/rdp-https-gateway's sampled container was never `logFormat`-controlled
    to begin with). Removed the now-dead `release` variable. Added a comment pointing future
    readers at `docs/otel-integration-plan.md` §4.
  - Changed: `Makefile` — added `e2e-observability`, `e2e-observability-off`,
    `e2e-observability-filelogs`, `e2e-observability-sidecar` targets (same `kind-prep build-pytest`
    + `pytest-docker` shape as every existing `e2e-*` target); added all four to `.PHONY` and to the
    sequential `e2e` target with `e2e-settle`/`kind-clean-namespace` between scenarios, in the same
    position pattern as the existing entries.
- **Verification (commands actually run, this session):**
  - Iterated each new suite individually while writing it:
    `HELM_PLUGINS=$(pwd)/.helm/plugins ./bin/helm unittest charts/kasm-helm -f 'tests/<file>.yaml'`
    — every suite reached PASS before moving to the next.
  - `make unittest` (final, whole-chart run) →
    **`Charts: 1 passed, 1 total` / `Test Suites: 55 passed, 55 total` / `Tests: 662 passed, 662
    total`**. Baseline was 514 tests / 44 suites (per the H5 amendment entry) — this phase added
    **11 new suites and 148 new tests**, with zero pre-existing suites broken.
  - `make lint render kubeconform kyverno` → `1 chart(s) linted, 0 chart(s) failed`; all 22
    rendered scenarios (19 pre-existing + `observability-filelogs`/`observability-no-store`/
    `observability-forward`/`observability-sidecar-logs` added this phase) show
    `Invalid: 0, Errors: 0` (kubeconform) and `fail: 0, error: 0, error: 0` (kyverno).
  - `make test` (the full gate, re-run once at the end) → same 55/662 unittest result, same clean
    lint/kubeconform/kyverno.
  - Chart-wide zero-RBAC check: `for f in .rendered/*.yaml; do grep -cE '^kind:
    (ServiceAccount|Role|ClusterRole|RoleBinding|ClusterRoleBinding)$' "$f"; done` summed to **0**
    across all 22 rendered scenarios.
  - `helm template kasm-test charts/kasm-helm -n kasm-test --set
    'observability.fileLogs.components={api,not-a-real-component}'` → fails with `value must be
    one of 'api', 'manager', 'guac'` (the schema-validation case `negative_validation_test.yaml`
    documents but can't assert directly — see Deviations).
  - `python3 -m pyflakes` over all six new/changed e2e test files → no findings (unused imports,
    undefined names). `python3 -c "import ast; ast.parse(...)"` over the same six → all parse
    clean. No e2e test was executed against a live cluster.
- **Deviations from the phase doc:**
  - **helm-unittest has no `matchRegexCount`/count-based regex assertion.** The phase doc's
    critical "`tail_sampling:` exactly once" and "each `clickhouse/{logs,traces,metrics}` exactly
    once" checks needed a different technique: pair a positive `matchRegex` (proves at least one
    occurrence) with a `notMatchRegex` on a dotall pattern that only matches if the token appears
    **twice** in the same document (`(?s)tail_sampling:.*tail_sampling:`) — together they prove
    exactly one. Used throughout `otel_collector_config_test.yaml`. Also hit Go's RE2 engine not
    supporting lookahead (`(?!...)`) — one "no literal credential" assertion was rewritten as a
    plain negated-character-class pattern instead.
  - **`kasm.observabilityValidate`'s `fileLogs.components` enum check is unreachable in practice**:
    `values.schema.json` already enforces the same enum (`api`/`manager`/`guac`) at
    schema-validation time, which runs *before* template rendering and therefore before
    `kasm.observabilityValidate`'s own `fail` ever executes. helm-unittest's `failedTemplate`
    assertion is scoped to template-execution errors, not schema-validation ones, so this case
    could not be asserted as a `failedTemplate` case at all (tried; it errors at the suite level
    instead of the per-assertion level). Documented the manual `helm template ... --set
    observability.fileLogs.components='{api,not-a-real-component}'` verification command as a
    comment in `negative_validation_test.yaml` instead, matching the precedent H1 set for
    `observability.bogusKey`. The render-time check in `kasm.observabilityValidate` is still
    correct to keep as defense-in-depth (e.g. for `--disable-openapi-validation` callers) — not
    removing it, just noting its test coverage lives in the render-time verification pass, not a
    unit suite.
  - **PVC name discrepancy (code wins).** PROGRESS.md's H3 entry describes the ClickHouse PVC name
    as `<release>-clickhouse-data`. The actual rendered name is `<release>-clickhouse` —
    `kasm.name (list . "clickhouse" "data")`'s third argument ("data") is captured by the helper
    but never actually appended to the output (only the 4th/5th zone/extra arguments are). This is
    not a functional bug (the name is still stable, unique, and version-free — exactly what H3's
    Definition of Done needed), just a stale claim in the phase doc. `clickhouse_test.yaml` asserts
    against what actually renders, with a comment recording the discrepancy; not fixing the helper
    or renaming the PVC, since doing so is out of this phase's scope and would be a breaking change
    for anyone already using an early build of this chart.
  - **DEV-31 image tags have moved on from what H6-tests-e2e.md assumed.** `docker images | grep
    feature_DEV-31` on this host shows only `kasmweb/proxy-private:feature_DEV-31` matching the
    doc's assumed tag exactly; `rdp-gateway-private`/`rdp-https-gateway-private` are present but
    under an `x86_64-feature_DEV-31` tag instead; and no `api-private`/`manager-private`/
    `kasm-guac-private` image exists under any `feature_DEV-31`-derived tag at all (only unrelated
    `:develop`-tagged non-private images). `tests/values/dev31-images.yaml` records this exactly
    and uses the confirmed tags where present; the three unconfirmed components keep the doc's
    originally-assumed tag with an inline comment flagging it as unconfirmed. The human must
    resolve this (build/pull the missing images, or edit the three tags) before running
    `make e2e-observability*` for real.
  - **Near-miss: do not `make -n e2e`.** While preparing the Makefile changes, `make -n e2e` was
    run to sanity-check the new target wiring, on the assumption `-n` is inert. GNU Make's
    documented behaviour is that any recipe line containing the literal `$(MAKE)` is executed for
    real even under `-n` (so that dry-run output can recurse into sub-makes) — since almost every
    `e2e-*` recipe in this Makefile is exactly `$(MAKE) pytest-docker ...`, this cascaded into a
    real (harmless, in the end) chain of sub-make invocations, including one compound recipe line
    (`e2e-multizone`, which bundles a non-`$(MAKE)` shell script together with a trailing
    `$(MAKE)` call on one logical line) that actually ran `./tests/e2e/install_ingress_nginx.sh`
    for real. That script attempted to start `cloud-provider-kind` and failed immediately
    (`.kind/cloud-provider-kind.pid`/`.log` don't exist, since no cluster was ever created) — no
    process kept running, no `.kind/` directory, no kind cluster, no Docker container, and no
    `git status` changes resulted (verified all four immediately after). Recorded here as a
    warning for future sessions: never `make -n` a target whose recipe chain is built from
    `$(MAKE)` calls in this repo; inspect the diff or use `make -p`/manual reading instead.
  - Everything else — suite conventions (`documentIndex`, zone-scoped multi-document handling,
    `tests/values/*.yaml` reuse), the e2e file naming/structure (`test_1N_*.py`, `@pytest.mark.e2e`,
    `installer`/`temp_workdir` fixtures, `install_and_wait_with_retry`), and the Makefile target
    shape — implemented exactly as the doc specified; no other discrepancies found.
- **Notes for later phases:**
  - Final counts for H7 to cite: **662 unit tests / 55 suites** (up from 514/44), **4 new e2e
    scenarios** (test_12–15) plus one extended existing scenario (test_06) and one re-scoped
    existing scenario (test_10).
  - e2e scenarios are **written but unexecuted**. Before running them for real, a human needs to:
    1. Resolve the DEV-31 image-tag situation in `tests/values/dev31-images.yaml` (see Deviations
       above) — either build/pull the three unconfirmed `-private:feature_DEV-31` images, or edit
       the file to point at whatever tags actually exist.
    2. Run, in order (each creates and tears down its own namespace, same as every other `e2e-*`
       target):
       ```
       make e2e-observability            # test_12_observability.py
       make e2e-observability-off        # test_13_observability_disabled.py
       make e2e-observability-filelogs   # test_14_observability_filelogs.py
       make e2e-observability-sidecar    # test_15_observability_sidecar_logs.py
       make e2e-pss                      # test_06_pod_security_standards.py (now also covers the hostLogs carve-out)
       make e2e-json-logging             # test_10_json_logging.py (now re-scoped to proxy+db only)
       ```
       Or run the full `make e2e` to exercise every scenario (including these six) in sequence.
    3. `test_12_observability.py`'s two test functions don't yet pass `dev31-images.yaml`'s
       `--set`/`-f` overrides through `install_and_wait_with_retry` — the values dict built by
       `_low_resource_values()` only carries per-component `resources`. A human wiring this up for
       a real run should merge `dev31-images.yaml`'s `components.*.image` block into that dict (or
       pass it as a second `-f` alongside the generated `values.yaml`) before invoking
       `install_and_wait_with_retry`; the other three new e2e files (`test_13`/`14`/`15`) need the
       same treatment. This was deliberately left as the human's wiring step rather than guessed at
       blind, since it directly depends on resolving the image-tag question above first.
  - `otel_collector_config_test.yaml`'s exactly-once technique (paired `matchRegex`/dotall-doubled
    `notMatchRegex`) is reusable for any future "this token must appear in exactly one rendered
    location" regression test in this chart — worth lifting into `00-SHARED-CONTEXT.md`'s chart
    idioms section if H7 or a later phase touches that doc again.
  - Real, useful follow-on (not done here, in scope for a future pass, not urgent): extend
    `deployment_size_test.yaml` to pin the new `otel-collector`/`otel-gateway`/`clickhouse`/
    `otel-sidecar` `resources.preset`/`replicas.preset` values the same way it already does for
    every pre-existing component, and extend `service_name_constants_test.yaml` similarly for
    `$constants.otel`/`$constants.clickhouse`.
- **Cross-phase findings:** the ClickHouse PVC name discrepancy above (PROGRESS.md said
  `<release>-clickhouse-data`, code renders `<release>-clickhouse`) is the only one; recorded in
  the top-level Cross-phase findings section below as well since it touches H3's own entry, not
  just this phase's tests.

---

### H7 — Docs, examples, release plumbing
- **Status:** done-with-deviations. Every Definition-of-Done item is done and verified except
  `make changelog-check`, which cannot pass without a commit — see Deviations.
- **Files added/changed/deleted (kasm-helm):**
  - Added: `examples/otel-collector-custom.yaml`, `examples/otel-collector-splunk.yaml`,
    `examples/otel-collector-debug.yaml` — see Deviations for why these are **gateway**
    (`observability.collector.gateway.existingConfigMap`) examples, not forwarder ones as the
    phase doc's §1 header literally says.
  - Added: `charts/kasm-helm/docs/observability.md` — new 12-section customer-facing page per the
    phase doc's outline (architecture diagram, deployed workloads, the three logging paths, the
    nginx/Pod-Security trade-off incl. OpenShift, standalone ClickHouse, retention sizing, trace
    sampling, forwarding, BYO config, disabling, troubleshooting, 1.19→1.20 upgrade notes).
    Cross-linked from `values.yaml`'s `observability:` section comment (`./docs/observability.md`)
    — that link already existed from H1, so no change was needed there — and from the repo-root
    `README.md` (see below).
  - Changed: `charts/kasm-helm/README.md` — regenerated via `make readme` (helm-docs). Diff is the
    full `observability.*` values table (previously absent — H1–H6 were explicitly told not to run
    this) plus the `logFormat` description update from H2's narrowing.
  - Changed: `charts/kasm-helm/CHANGELOG.md` — hand-written `[Unreleased]` section (Added/Changed/
    Removed) per the phase doc's required content list, since `make changelog` found zero commits
    to draft from (everything in H1–H7 is still uncommitted, per every phase's "no git operations"
    rule) — see Deviations.
  - Changed: `charts/kasm-helm/images.txt` — one-line comment above the two third-party images
    noting the future move to internal Kasm-hosted tags. Confirmed the Kasm component rows still
    read `1.19.0-rolling` (untouched).
  - Changed: `README.md` (repo root) — added a sentence to "About This Chart" naming the
    observability stack alongside the existing PostgreSQL mention, plus a new bullet in the
    "things to know up front" list linking `charts/kasm-helm/docs/observability.md`. Verified
    `python3 scripts/set_versions.py --check` still passes (badge line, both `--version` snippets,
    and the "This branch" sentence are untouched — the new prose sits outside all three regexes).
  - Changed: `docs/otel-integration-plan.md` — §11's six decision-record items each got a
    **Status: implemented** tag (with a one-line pointer to which phase/PROGRESS.md entry, where
    relevant) and item 6's wording was corrected to the two-key `{forwarder,gateway}
    .existingConfigMap` shape per decision 4's amendment. Did not rewrite the plan's history/prose
    otherwise, per the phase doc's explicit instruction.
  - Deleted: nothing under `docs/otel-execution/`, per instructions.
- **Files added/changed (kasm_backend, the one phase that touches both repos):**
  - Changed: `docs/telemetry/prompts/public-docs-update.md` — added a bullet to the "Remaining HOLD
    items" list noting the Helm chart now ships the stack and that the public docs' configuration
    tables need a Kubernetes column or cross-reference; pointed at the chart's own
    `docs/observability.md` as the source of truth for the chart-side facts. Did not write the
    public docs themselves, per instructions.
  - Changed: `docs/telemetry/how-to/deploy.md` — the "Disable file logging" / Kubernetes paragraph
    now points at the Helm chart's `docs/observability.md` instead of leaving the Kubernetes story
    implicit.
- **Verification (commands actually run, this session):**
  - `make readme` → regenerated cleanly; `git diff --stat charts/kasm-helm/README.md` shows the
    expected `observability.*` table addition only.
  - `make readme-check` → **PASS**: `OK: README.md and values.yaml version references match
    Chart.yaml (chart=1.1200.0-develop, app=develop)`, no drift reported.
  - `make lint` → `1 chart(s) linted, 0 chart(s) failed`.
  - `make test` (lint+render+kubeconform+kyverno+unittest, the full static gate) → every rendered
    scenario `Invalid: 0` (kubeconform) and `fail: 0, error: 0` (kyverno); helm-unittest →
    **`Charts: 1 passed, 1 total` / `Test Suites: 55 passed, 55 total` / `Tests: 662 passed, 662
    total`** — unchanged from H6's baseline; H7 touches no templates or test suites, only docs/
    examples/release files, so an identical count is the expected (and confirmed) result.
  - `python3 scripts/set_versions.py --check` → `OK` (also part of `readme-check`).
  - Example ConfigMaps: `python3 -c "yaml.safe_load(...)"` over all three confirms
    `kind: ConfigMap`, a `config.yaml` key, and that `config.yaml`'s contents themselves parse as
    YAML.
  - Placeholder-credential check: `grep -rniE 'token: *"?[a-z0-9]{20,}' examples/` → no output
    (`ok`) — the Splunk example's token is the literal string `REPLACE_ME_SPLUNK_HEC_TOKEN`.
  - **`otelcol validate` actually run** against the real pinned
    `otel/opentelemetry-collector-contrib:0.156.0` image (`docker run --rm ... validate
    --config=/cfg.yaml`, throwaway container, `OTEL_BEARER_TOKEN`/`CLICKHOUSE_PASSWORD` set to
    dummy values so the `${env:...}` references resolve) for all three examples' `config.yaml`
    bodies extracted to disk — all three exit 0.
  - `make changelog` → ran; reported `No commits found since 'develop'. Nothing to add.` (expected,
    see Deviations) — the `[Unreleased]` section was then written by hand instead.
  - `make changelog-check` → **fails** (`ERROR: charts/kasm-helm/CHANGELOG.md has not been
    updated.`) even though the file **is** updated on disk — the check diffs
    `origin/develop...HEAD` via git, and nothing in this session was committed (every phase's "no
    git operations" rule), so git sees no difference yet. This is expected to flip to PASS the
    moment the human commits; not a defect in the CHANGELOG content itself. See Deviations.
- **Deviations from the phase doc:**
  - **Examples target the gateway tier, not the forwarder tier the doc's §1 literally names.**
    The doc's file table asks each example to include "TTLs, sampling percentage, ClickHouse DSN"
    and a Splunk/debug exporter — all three are exclusively gateway-side concerns per H1's amended
    two-tier topology (confirmed by rendering both tiers' ConfigMaps: the forwarder has no
    ClickHouse exporter, no `tail_sampling`, and forwards everything to the gateway over
    `otlp:4317`). The forwarder's own `existingConfigMap` would need none of the content the doc
    asks for. This phase doc predates the H1 amendment (2026-08-06) that split the single-tier
    Collector into forwarder+gateway — H4's and H5's phase docs were explicitly rewritten for that
    split (per the H1 amendment entry above); H7's was not. Per the top-level instruction that
    code/PROGRESS.md wins over a stale phase doc, all three examples are gateway
    `existingConfigMap` examples, generated from the chart's actual rendered gateway ConfigMap, with
    header comments corrected to say `observability.collector.gateway.existingConfigMap` and to
    cross-reference the separate, unrelated forwarder `existingConfigMap` key.
  - **`make changelog-check` cannot be made to pass in this session.** It compares
    `git diff --name-only origin/{base}...HEAD` and every phase (including this one) is forbidden
    from committing. The CHANGELOG content itself is complete and correct per the phase doc's
    required Added/Changed/Removed list; the gate will pass as soon as the human commits this
    branch's work. Flagging explicitly rather than silently leaving it in a "did I forget this"
    state.
  - **`make changelog`'s non-LLM mode produced nothing to edit**, since it drafts from commits and
    there are none yet on this branch. Wrote the `[Unreleased]` section by hand instead, following
    the file's existing per-version Added/Changed/Removed grouping and prose style (no per-line
    hash comments, since those are stamped only by the commit-driven script and there is no commit
    to stamp with).
  - **Root `README.md`'s existing docs-index mechanism is per-values-comment, not a
    `README.md.gotmpl` docs list** — checked `README.md.gotmpl` for a docs index (per the phase
    doc's instruction to "check whichever mechanism puts those links there"): the Preseed/
    Default-Users links actually come from `values.yaml`'s own `# key -- description` comments
    (e.g. `kasmConfig.config`'s description links `./docs/preseed.md`), which helm-docs renders
    into the generated values table — not from `README.md.gotmpl` itself. The observability
    section's equivalent link (`./docs/observability.md`) was already present in `values.yaml` from
    H1, so no change was needed there; confirmed it rendered into `charts/kasm-helm/README.md` by
    `make readme`.
  - Everything else — example structure (complete, applyable ConfigMaps under `config.yaml`), the
    12-section `observability.md` outline, the OpenShift note placement, the CHANGELOG's required
    Added/Changed/Removed content (including both breaking-behavior callouts —
    `logFormat`/API-Manager and the Splunk-database migration note), `images.txt`'s one-line
    comment, and the two backend doc pointers — implemented as the phase doc specified; no other
    discrepancies found.
- **Notes for later phases:** none — H7 is the last planned phase in this execution sequence. A
  human resolving the Follow-ups list below is the next step, not another lettered phase.
- **Cross-phase findings:** none beyond what's already recorded in the top-level Cross-phase
  findings section below.

---

## Cross-phase findings

Out-of-scope problems noticed during implementation. Do not fix them in-phase; record them here.

- **H3's ClickHouse PVC name claim is stale (found in H6).** H3's entry and the Contract registry
  both say the PVC is named `<release>-clickhouse-data`. The actual rendered name (confirmed via
  `helm template` and asserted in `clickhouse_test.yaml`) is `<release>-clickhouse` —
  `kasm.name`'s third positional argument is accepted but never appended to the output; only the
  4th (zone) and 5th (extra) arguments affect the rendered name. Not a functional bug (the name is
  still stable and version-free), just a documentation/contract-registry inaccuracy. Left
  unfixed — renaming the PVC now would be a breaking change for any existing install of this
  chart; H7 should scrub the `<release>-clickhouse-data` phrasing out of any docs it writes.

---

## Follow-ups

Deliberately-not-done work, for the human to ticket. This list is final as of H7.

- **Installer wiring for the ClickHouse TLS read path.** H0 adds `KASM_CLICKHOUSE_CA_CERT` /
  `KASM_CLICKHOUSE_VERIFY` support to the backend, but `install.sh` does not set either on the
  `app`/`all` role when `--clickhouse-http-endpoint` is an `https://` URL. Until it does, the shipped
  Docker `--role clickhouse` topology still fails TLS verification on report queries. Not a Helm
  problem; needs its own change in `kasm_backend`.
- **nginx connection metrics on the default (DaemonSet) log path.** `stub_status` is rendered but not
  scraped: a DaemonSet cannot reach pod loopback, and scraping the proxy Service round-robins across
  replicas, corrupting cumulative counters. Options are `k8s_observer` + `receiver_creator` in the
  DaemonSet (correct, but adds a ServiceAccount and pod list/watch RBAC to a chart that currently has no
  RBAC at all), or the `observability.nginxLogs` sidecar path, which already collects them. See plan §3b.
  Documented as a known, permanent gap in `charts/kasm-helm/docs/observability.md` §4 rather than
  something pending — a human should still ticket the `k8s_observer` option if it's ever wanted.
- ~~**No TLS-trust surface for a *standalone* ClickHouse.**~~ **Resolved in H2.** New
  `observability.clickhouse.{caCert,caCertConfigMap,tlsVerify}` + `templates/clickhouse-ca-configmap.yaml`
  + `kasm.clickhouseCaVolume`/`kasm.clickhouseCaVolumeMount` helpers. See the Contract registry row
  "Standalone-ClickHouse TLS-trust surface (values + wiring)" and H2's Entry below for the full design.
- **Public documentation Kubernetes column.** The observability configuration tables in
  `components/kasm-workspaces-docs` describe the Docker install only. Tracked in
  `kasm_backend/docs/telemetry/prompts/public-docs-update.md`, which H7 updated with a pointer to
  this chart's `docs/observability.md` as the source of chart-side facts.
- **e2e scenarios are written but unexecuted (H6).** `test_12_observability.py` through
  `test_15_observability_sidecar_logs.py`, the extended `test_06_pod_security_standards.py`, and the
  re-scoped `test_10_json_logging.py` all need a human to: (1) resolve the DEV-31 image-tag situation
  in `tests/values/dev31-images.yaml` (three of the seven `-private:feature_DEV-31` component images
  were unconfirmed on the host at the time H6 wrote that file), (2) wire `dev31-images.yaml`'s
  `components.*.image` overrides into each new e2e test's `install_and_wait_with_retry` call (not done
  by H6 — see H6's Notes for later phases), and (3) then actually run `make e2e-observability*` /
  `make e2e-pss` / `make e2e-json-logging` against a real kind cluster. H7 did not attempt any of this
  — running `make e2e*`/`make kind-*` was explicitly out of scope for every phase in this execution,
  H7 included.
- **`make changelog-check` will fail until the human commits.** The gate diffs
  `git diff --name-only origin/develop...HEAD`; every phase in this execution (H0–H7) was forbidden
  from committing, so the CHANGELOG's `[Unreleased]` section — complete and correct on disk — will
  not satisfy the gate until this branch's work is actually committed. Not an outstanding task, just
  a sequencing note for whoever commits this work.
- **Test coverage for the new `resources.preset`/`replicas.preset` values (H6).** Extend
  `deployment_size_test.yaml` to pin the `otel-collector`/`otel-gateway`/`clickhouse`/`otel-sidecar`
  preset values the same way it already does for every pre-existing component, and extend
  `service_name_constants_test.yaml` similarly for `$constants.otel`/`$constants.clickhouse`. Real,
  useful, not urgent — flagged by H6, not done by H6 or H7.
- **`docker-compose-api.yaml` username inconsistency (found in H0b).** `KASM_CLICKHOUSE_USER` is a
  hardcoded literal `"kasm_otel"` in that one compose file, unlike `docker-compose-app.yaml`/
  `docker-compose-all.yaml` which use `"$CLICKHOUSE_USER"`. A real latent bug (an `api`-role install
  with a custom `--clickhouse-username` gets the wrong username in that file) but out of scope for
  every phase in this execution; needs its own small fix in `kasm_backend`.
- **`kasm.metadata`'s `daemonSet`/`daemonset` case mismatch (found in H5).** Dead code today (nothing
  passes the lowercase form to the top-level call), left unfixed since fixing it wasn't in scope for
  any phase. Worth a cleanup pass whenever `kasm.metadata` is next touched.

## Architecture reversals (post-H7, docs sweep)

The design review recorded in bead `kasm-helm-4ss` (Decision record: OTEL architecture reversals,
2026-08-11 / amended 2026-08-14) reversed several of the plan's and H1–H5's decisions after this
package's phases were executed. The chart as it exists on `feature/DEV-31` reflects the reversed
architecture, not the plan text in `H1`–`H5` or `docs/otel-integration-plan.md` §3 (now marked
superseded). Reversals, for anyone reading the H-phase docs after the fact:

1. **Zone-scoped forwarders → single cluster-wide forwarder.** H1/H4 specified one forwarder
   Deployment per zone, selected by endpoint. Reversed: zone identity was never recorded on the
   telemetry itself under that design, only implied by which endpoint a sender used. The chart now
   runs one de-zoned forwarder Deployment for the whole release and records zone as the `kasm.zone`
   resource attribute via `kasm.otelEnv`/`kasm.otelSidecar` instead.
2. **`hostLogs` DaemonSet default → unconditional sidecar.** H5 proposed a `hostPath`-mounting
   DaemonSet as the default nginx log path, with a sidecar as the PSS-restricted/OpenShift fallback.
   Reversed before it shipped: a DaemonSet can't be zone-scoped, node-local routing needs
   `internalTrafficPolicy: Local` (blackhole risk) or `hostPort` (PSS violation), and it doesn't
   change gateway throughput. The sidecar is now the only path, unconditional on
   `observability.enabled`, with no DaemonSet ever rendered.
3. **`observability.fileLogs` deleted.** H1/H5 added a JSON-file-plus-sidecar logging path as a
   third option alongside OTLP and DaemonSet/stdout scraping. Reversed: nothing in api/manager
   depends on file-shaped logs, and it duplicated the sidecar mechanism for no real use case
   (`kasm-helm-4ss` item 8/20).
4. **`logFormat` deleted for API/Manager.** Originally the plan narrowed `logFormat`'s effect on
   those services; the review deleted the value's effect on them outright rather than partially
   honoring it — console output is always human-readable text, structured logs are OTLP-only.
   Because the root values schema is permissive (`additionalProperties: true`), a leftover
   `logFormat` value from an old release is a silent no-op on upgrade, not a render failure
   (`kasm-helm-4ss` items 9 and the correction in item 22).
5. **Gateway single-replica constraint lifted.** The plan and H4 hard-required
   `replicas: 1` on the gateway as a correctness property of `tail_sampling`. Reversed: the
   forwarder now reaches the gateway through a `loadbalancing` exporter (DNS resolver over the
   gateway's headless Service, hashed on `traceID` for the traces pipeline), so every span of a
   trace still lands on one gateway pod with more than one replica. `replicas: 1` is now only the
   *default*, raised via `components.otelGateway.replicas`.
6. **Forwarder's port-4316 receiver deleted.** H4's forwarder rendered an unauthenticated
   `otlp/nginx` receiver on 4316, reachable cluster-wide, so `ngx_otel_module` (which cannot send a
   bearer token) could reach it directly. Reversed: nginx now sends its spans to its own pod-local
   sidecar over loopback only; the forwarder has no 4316 receiver at all, closing that
   unauthenticated cluster-wide surface.

See `kasm-helm-4ss` for the full decision record, `charts/kasm-helm/docs/observability.md` for the
as-built architecture, and `docs/otel-integration-plan.md` §3 for the superseded-topology marker.
The full 22-item decision record, with supersession annotations, is transcribed at
`docs/otel-execution/DECISION-RECORD.md`.
