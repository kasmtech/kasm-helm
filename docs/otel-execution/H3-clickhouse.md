# H3 — ClickHouse: StatefulSet, service, schema, retention

**Repo:** `kasm-helm`. **Depends on:** H1, and H0 for the TLS read path.
**Parallel-safe with:** H2, H4, H5. **Size:** large.

Deploy the telemetry store. Model it closely on the bundled Kasm DB — `db-statefulset.yaml`,
`db-service.yaml` and `db-configmap.yaml` are your templates for structure, naming, TLS and storage.

---

## Guard conditions

Every template in this phase renders **only** when:

```gotemplate
{{- if and .Values.observability.enabled .Values.observability.clickhouse.enabled (not .Values.observability.clickhouse.standalone) }}
```

`standalone: true` means the customer runs their own ClickHouse; `enabled: false` means no store at
all. Neither deploys anything here.

---

## 1. `templates/clickhouse-configmap.yaml`

One ConfigMap, three keys, ported from the backend. **Not** zone-scoped — a single ClickHouse serves
all zones.

Source files (read them, port them; do not invent schema):

| Key               | Source                                        |
| ----------------- | --------------------------------------------- |
| `config.xml`      | `kasm_backend/install/conf/clickhouse/config.xml` |
| `users.xml`       | `kasm_backend/install/conf/clickhouse/users.xml`  |
| `init-schema.sql` | `kasm_backend/install/conf/clickhouse/init-schema.sql` |

Transformations required:

**`config.xml`**
- Keep the `<logger>` block (`level: warning`, `console: 1`) and
  `max_server_memory_usage_to_ram_ratio`.
- Wrap the `<https_port>`, `<tcp_port_secure>` and `<openSSL>` blocks in
  `{{- if .Values.observability.clickhouse.tls }}` — plaintext-only when TLS is off.
- Change the cert paths from `/etc/otel/tls.crt|key` to something chart-idiomatic, e.g.
  `/etc/clickhouse-server/certs/tls.crt|key`, and mount them there in §2.
- Keep `<verificationMode>none</verificationMode>` — this is the *server* accepting connections, not
  client verification.

**`users.xml`**
- Replace the literal `$CLICKHOUSE_PASSWORD` placeholder. **Do not template the password into a
  ConfigMap.** Instead use ClickHouse's env-var substitution: set
  `<password from_env="CLICKHOUSE_PASSWORD"/>` and supply `CLICKHOUSE_PASSWORD` to the container from
  the Secret in §2. Verify the attribute name against the ClickHouse 24.12 docs — if `from_env` is
  unavailable for `<password>` in this version, fall back to rendering `users.xml` as a **Secret**
  rather than a ConfigMap, and note the change in `PROGRESS.md`. A password must never land in a
  ConfigMap.
- Template `<kasm_otel>` (the username element) from `.Values.observability.clickhouse.username`, and
  the `GRANT ALL ON kasm_otel.*` from `.database`. **This is required, not cosmetic** — measured
  against a live ClickHouse 24.12 (H0b): an XML-defined user's grants **cannot be changed by SQL at
  runtime** (`GRANT ALL ON <newdb>.* TO <user>` against such a user fails with code 495
  `ACCESS_STORAGE_READONLY`). If this grant is left as the literal `kasm_otel.*` while
  `.Values.observability.clickhouse.database` is set to something else, every report fails and there
  is no SQL fix — only a config edit and a ClickHouse restart. Do not let a future cleanup pass
  simplify this back to a literal.

**`init-schema.sql`**
- Substitute `$OTEL_LOGS_RETENTION_DAYS` → `{{ .Values.observability.clickhouse.retention.logsDays }}`
  and `$OTEL_AUDIT_LOGS_RETENTION_DAYS` → `{{ ...auditLogsDays }}`.
- Substitute the hardcoded `kasm_otel` database name from `.database` at **both** sites —
  `CREATE DATABASE IF NOT EXISTS <db>` and `CREATE TABLE IF NOT EXISTS <db>.otel_logs`. This is
  required, not optional: `create_schema: true` stays on the collector exporters (H4), and the
  exporter can only `CREATE TABLE otel_traces`/`otel_metrics_*` inside a database that already
  exists — this Job is what creates it.
- Preserve everything else **verbatim**, especially the `IsAudit MATERIALIZED` expression, the
  `PARTITION BY`/`ORDER BY` clauses, both `TTL ... DELETE WHERE` arms and
  `SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1`. This schema is load-bearing for the
  reporting queries in `clickhouse_reports.py`.
- Note in a comment that this only runs on first initialisation of an empty volume (ClickHouse's
  `docker-entrypoint-initdb.d` semantics), which is why §4 exists.

## 2. `templates/clickhouse-statefulset.yaml`

Copy the shape of `db-statefulset.yaml`. Specifics:

- `replicas: 1` hardcoded; `serviceName: {{ $constants.clickhouse.svc }}`;
  `updateStrategy.type: RollingUpdate`.
- Metadata via `kasm.metadata` with `"component" "clickhouse" "resource" "statefulSet"`.
- `kasm.securityContext (list . 101 "pod")` and `(list . 101 "container")` — uid 101 is the
  `clickhouse` user in the official image. ClickHouse needs to write to `/var/lib/clickhouse` (the
  PVC) and `/tmp`; if `readOnlyRootFilesystem: true` breaks startup, pass the 4th-arg override
  `(dict "readOnlyRootFilesystem" false)` and record why in `PROGRESS.md` — but try the read-only
  path first with `emptyDir` mounts for the writable paths, since the Kyverno PSS policy is a gate.
- Env: `CLICKHOUSE_DB` (from `.database`), `CLICKHOUSE_USER` (from `.username`),
  `CLICKHOUSE_PASSWORD` via `secretKeyRef` (`existingSecret` when set, else
  `$constants.secrets.name` / `clickhouse-password`), and
  `CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: "0"`.
- Ports: `8123`/`9000` always; `8443`/`9440` additionally when `clickhouse.tls`. Use `$constants`
  values and give each a `name` ≤15 chars (Kubernetes limit) — e.g. `ch-http`, `ch-native`,
  `ch-https`, `ch-native-tls`.
- Volume mounts:
  - PVC → `/var/lib/clickhouse`
  - `config.xml` → `/etc/clickhouse-server/config.d/kasm.xml` (subPath)
  - `users.xml` → `/etc/clickhouse-server/users.d/kasm.xml` (subPath)
  - `init-schema.sql` → `/docker-entrypoint-initdb.d/init.sql` (subPath)
  - when `tls`: the cert Secret → `/etc/clickhouse-server/certs/tls.crt` and `.../tls.key`
    (subPaths `tls.crt`/`tls.key`), `defaultMode: 0o600`, from
    `.Values.certificate.secretName | default (include "kasm.name" (list . "cert-manager" "secret"))`
    — copy the exact expression from `db-statefulset.yaml`.
- Probes, when `.Values.applyHealthChecks`:
  ```gotemplate
  livenessProbe:
    {{- include "health.probe" (dict "root" $ "component" "clickhouse" "probeType" "livenessProbe" "type" "http" "path" "/ping" "port" 8123) | nindent 12 }}
  readinessProbe:
    {{- include "health.probe" (dict "root" $ "component" "clickhouse" "probeType" "readinessProbe" "type" "http" "path" "/ping" "port" 8123) | nindent 12 }}
  ```
  Use the plaintext 8123 port for probes even when TLS is on — kubelet has no reason to deal with the
  self-signed cert. `health.probe`'s timing lookup will not find
  `components.clickhouse`, so it falls back to defaults; ClickHouse is slow to start, so pass explicit
  timing by setting sensible values in `values.yaml`'s
  `observability.clickhouse.healthCheckTiming` **defaults**? No — leave the values empty as H1 defined
  them, and instead give the liveness probe a longer `initialDelaySeconds` by wiring
  `observability.clickhouse.healthCheckTiming` into `health.probe`. `health.probe` reads
  `.Values.components.<component>.healthCheckTiming`, which won't resolve for us. **Simplest correct
  option:** extend `health.probe` with an optional `"timingParent"` dict argument that, when supplied,
  is used instead of the `components` lookup, and pass
  `.Values.observability.clickhouse.healthCheckTiming`. Do that, keep it backward-compatible, and note
  it in `PROGRESS.md` (H4 wants the same for the Collector).
- `resources`: `.Values.observability.clickhouse.resources` when set, else
  `resources.preset` with node `clickhouse`.
- `persistentVolumeClaimRetentionPolicy` from `...storage.retentionPolicy`, and a
  `volumeClaimTemplates` entry sized `{{ printf "%sGi" (.Values.observability.clickhouse.storage.pvcSize | toString) }}`
  with `storageClassName` when set — mirror `db-statefulset.yaml` exactly, including using
  `include "kasm.name"` for the claim name. **Do not** include `.Chart.AppVersion` in the claim name
  the way the DB does; that couples the volume to the Kasm version and would orphan telemetry on every
  upgrade. Use a stable name like `<release>-clickhouse-data`.
- Include `kasm.trustedCaInit` / `trustedCaVolumes` / `trustedCaVolumeMounts` for parity with other
  components, guarded the same way `db-statefulset.yaml` guards its `initContainers`.

## 3. `templates/clickhouse-service.yaml`

ClusterIP Service exposing the same ports as the StatefulSet, selector from
`kasm.metadata ... "include" "match"`. Follow `db-service.yaml`, including its `annotations`/`labels`
handling. Not zone-scoped.

## 4. `templates/clickhouse-retention-job.yaml`

`init-schema.sql` runs only on a fresh volume, so changing retention values on an existing release
must be applied with DDL.

- Helm hook annotations:
  ```yaml
  "helm.sh/hook": post-upgrade,post-install
  "helm.sh/hook-weight": "5"
  "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
  ```
  `post-install` too, so a fresh install where the volume already existed (reused PVC) converges.
- Renders only under the §Guard conditions — an external or absent ClickHouse is not ours to alter.
  This mirrors `apply_clickhouse_retention_tiers`'s self-guard in `install.sh`.
- Image: the ClickHouse image (it ships `clickhouse-client`).
- Command: wait for ClickHouse to answer `/ping`, then run `ALTER TABLE ... MODIFY TTL` for each
  signal. Read `kasm_backend/install/upgrade.sh` — search for `apply_clickhouse_retention_tiers` — and
  port the **exact same** statements rather than composing new ones. The logs table needs the two-arm
  conditional TTL (`DELETE WHERE IsAudit = 0` / `= 1`); traces and metrics take a single TTL each.
  Every `ALTER TABLE` there is `${CLICKHOUSE_DATABASE}.<table>` (as of H0b) — template that same
  qualifier from `.Values.observability.clickhouse.database` here; a literal `kasm_otel.<table>`
  would silently apply TTLs to the wrong database.
- Metrics tables: the ClickHouse exporter creates `otel_metrics_*` (one table per metric type:
  gauge, sum, histogram, exponential_histogram, summary). Handle the case where they do not exist yet
  (fresh install, nothing exported) — the upgrade script's approach is authoritative; if it iterates
  over existing tables via `system.tables`, do the same. Never let a missing table fail the Job and
  block the release.
- `restartPolicy: OnFailure`, `backoffLimit: 3`, `ttlSecondsAfterFinished` mirroring
  `dbManagement.initJobTTLSecondsAfterFinished`'s style (reuse that value rather than adding a new
  one).
- Include the pod-level security context and `resources` so the Kyverno policies pass — check
  `db-init-job.yaml` / `db-upgrade-job.yaml` for how existing Jobs satisfy `resources.required.enforce`.

---

## Verify

```bash
make lint
make render
make kubeconform
make kyverno        # PSS + probes + resources must pass for the new StatefulSet and Job
make unittest

# bundled, TLS on (default)
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/default.yaml \
  | grep -E 'kind: (StatefulSet|Service|Job|ConfigMap)' -A3 | grep -i clickhouse
# no password anywhere in a ConfigMap
helm template kasm-test charts/kasm-helm -n kasm-test | \
  awk '/kind: ConfigMap/,/^---/' | grep -i 'password' && echo "FAIL: password in ConfigMap" || echo ok
# external ClickHouse: nothing bundled, no retention job
helm template kasm-test charts/kasm-helm -n kasm-test \
  --set observability.clickhouse.standalone=true \
  --set observability.clickhouse.nativeEndpoint='tcp://ch:9440?secure=true&skip_verify=true' \
  --set observability.clickhouse.httpEndpoint=https://ch:8443 | grep -ci clickhouse-data  # → 0
# no store at all
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.clickhouse.enabled=false | grep -ci 'kind: StatefulSet.*clickhouse'
# retention values reach the schema
helm template kasm-test charts/kasm-helm -n kasm-test --set observability.clickhouse.retention.logsDays=60 | grep 'INTERVAL 60 DAY'
```

Add `tests/values/observability-external-ch.yaml` so `make render`/`kubeconform`/`kyverno` cover the
external path from now on (H6 adds the assertion suites; the values file belongs here so the render
matrix covers it immediately).

## Definition of done

- StatefulSet, Service, ConfigMap and retention Job render under the guard conditions and disappear
  under both `standalone: true` and `enabled: false`.
- **No credential appears in any ConfigMap** in any scenario.
- `init-schema.sql` is a faithful port: `IsAudit` expression, both TTL arms, and
  `ttl_only_drop_parts` intact, with retention values templated.
- Retention Job statements match `upgrade.sh`, tolerate missing metrics tables, and never block a
  release.
- `make lint render kubeconform kyverno unittest` green.

## Hand-off notes

Record in `PROGRESS.md`: the final in-cluster endpoints (scheme, host, port for both TLS on and off),
whether `users.xml` ended up a ConfigMap or a Secret, the `readOnlyRootFilesystem` outcome, the PVC
name, whether you extended `health.probe` with `timingParent`, and the exact retention DDL you ported.
H4's collector exporter DSN and H1's `clickhouseEnv` must agree with the endpoints you chose.
