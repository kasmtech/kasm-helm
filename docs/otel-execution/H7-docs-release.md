# H7 — Documentation, examples, release plumbing

**Repo:** `kasm-helm`. **Depends on:** H2–H5 (H6 in parallel). **Size:** medium.

Read `PROGRESS.md` in full first — this phase documents what was actually built, including every
deviation from the plan.

---

## 1. `examples/otel-collector-*.yaml`

Three example ConfigMaps for `observability.collector.forwarder.existingConfigMap`. Each must be a
**complete, applyable** `kind: ConfigMap` with the config under the key `config.yaml`, plus a header
comment explaining what it does and how to use it:

```yaml
# Apply with:  kubectl apply -n <namespace> -f examples/otel-collector-splunk.yaml
# Then set:    observability.collector.forwarder.existingConfigMap: kasm-otel-collector-splunk
```

Generate each starting from the chart's own rendered output so they cannot drift into fiction:

```bash
helm template kasm-test charts/kasm-helm -n kasm-test -f tests/values/default.yaml \
  | python3 -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind')=='ConfigMap' and 'otel-collector' in d['metadata']['name'] and 'sidecar' not in d['metadata']['name']:
        print(d['data']['config.yaml'])
"
```

| File                             | Content                                                                                                     |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `otel-collector-custom.yaml`     | The rendered default config, with a comment block listing every value the chart normally substitutes (`${env:CLICKHOUSE_PASSWORD}`, `${env:OTEL_BEARER_TOKEN}`, TTLs, sampling percentage, ClickHouse DSN) and warning that the env-var references only resolve because the chart's Deployment supplies them |
| `otel-collector-splunk.yaml`     | Same, plus a `splunk_hec/logs` exporter and a `logs/splunk` pipeline alongside the ClickHouse one. Port the shape from the commented block in `kasm_backend/install/conf/otel/otel-collector-local.yaml` (search `SPLUNK_HEC_EXPORTER_START`) — token, endpoint, `source: kasm`, `sourcetype: kasm:otel`, `tls.insecure_skip_verify`, retry and queue settings |
| `otel-collector-debug.yaml`      | Same, plus a `debug` exporter with `verbosity: detailed` appended to all three pipelines, so collected telemetry is printed to the collector pod's stdout for an existing cluster log scraper to pick up. Comment it clearly as the not-recommended logging path |

Credentials in the Splunk example must be obvious placeholders (`REPLACE_ME`), never realistic-looking
values.

## 2. `charts/kasm-helm/docs/observability.md`

New customer-facing page. `docs/otel-integration-plan.md` is internal — this is not a copy of it. Write
for an operator installing the chart. Suggested structure:

1. **What you get** — logs, traces, metrics from every Kasm service; nginx as the trace root; browser
   telemetry; ClickHouse-backed reporting in the Kasm UI. One diagram (ASCII is fine; align it per the
   repo's formatting rule).
2. **What gets deployed** — the collector Deployment (one per zone), the ClickHouse StatefulSet and its
   PVC, the proxy-pod sidecar. Note the resource and storage cost up front.
3. **Getting logs into your own tooling** — the three paths from the plan's §4, in the same order, with
   the recommendation stated plainly and a values snippet for each. Be explicit that API/Manager console
   output is human-readable text and that `logFormat: json` no longer changes that.
4. **How nginx logs are collected, and the Pod Security trade-off** — this needs its own section and
   plain language, because it is the one place where a default cannot satisfy every cluster:
   - By default a DaemonSet reads the container runtime's log files from each node
     (`/var/log/pods`), scoped to this release's proxy pods only. It needs no ServiceAccount and no
     cluster permissions.
   - That DaemonSet mounts a hostPath and runs as root, so it **cannot run in a namespace enforcing the
     `baseline` or `restricted` Pod Security Standards.** Give the exact values for that case
     (`hostLogs.enabled: false`, `nginxLogs.enabled: true`) and say what changes: a sidecar in the proxy
     pod, a shared volume, and — as a bonus — nginx connection metrics, which the DaemonSet path does not
     collect.
   - Note that nginx *traces* work identically on both paths.
   - State the known gap plainly: on the default path, nginx connection metrics
     (`connections active/accepted/handled`) are not collected. Request rate, latency and status codes
     all still come from the access logs and spans.
5. **Using your own ClickHouse** — the `standalone` recipe with both endpoints, the credential Secret,
   and a note that the two endpoints are different interfaces (native for writes, HTTP for reads) and are
   both required. Cover `observability.clickhouse.database` here too (H0b): it is a separate concern from
   the username — a tenant may run user `kasm_otel` inside a differently-named database — and the
   operator must, before install: (1) create the database (the app cannot create it itself); (2) create
   or reuse a user and grant it access; (3) `GRANT ALL ON <database>.* TO <user>`, which is required, not
   optional, because `create_schema: true` relies on `CREATE TABLE` to create `otel_traces`/
   `otel_metrics_*` in that database on first write. State plainly that grants for an operator-managed
   (XML-defined) ClickHouse user cannot be changed by SQL later — get the database name and the grant
   right before first install, because fixing a mismatch afterward means editing the user config and
   restarting ClickHouse, not running a `GRANT` statement.
6. **Storage and retention sizing** — the four retention values, what drives volume growth (sessions,
   traffic, sampling), how to change retention on a live release (values change + `helm upgrade` runs the
   retention Job), and the ClickHouse caveat that reducing retention frees space only on the next TTL
   merge.
7. **Trace sampling** — errors and slow (≥1 s) requests always kept, 10 % of the rest by default; say
   this plainly so nobody reports missing traces as a bug.
8. **Forwarding to an external backend** — `collector.forward.*`, with the Secret-based token.
9. **Bringing your own collector config** — `existingConfigMap`, the `config.yaml` key requirement,
   which values become inert, and pointers to `examples/`.
10. **Disabling telemetry** — `observability.enabled: false`, and exactly what stops working (reporting
   views return empty).
11. **Troubleshooting** — collector pod logs; the `:13133` health endpoint; how to confirm data is
    arriving (`clickhouse-client` query against `otel_logs`); what "no data" usually means (SDK disabled,
    wrong endpoint, ClickHouse unreachable → warn-and-skip); how to spot the `debug` exporter path.
12. **Upgrading from 1.19 or earlier** — the Splunk migration note from §4 below, and the `logFormat`
    change.

Cross-link it from `charts/kasm-helm/README.md.gotmpl` if that file has a docs index (check; the
generated `README.md` links `docs/preseed.md` and the default-users pages, so follow whatever mechanism
puts those links there — it may be `README.md.gotmpl` or the values comments).

## 3. Regenerate the README

```bash
make readme
make readme-check     # must pass
```

`make readme` runs `helm-docs`, which rebuilds the values table in `charts/kasm-helm/README.md` from the
`values.yaml` comments. If the diff looks wrong, the fault is in the values comments — fix those, not the
generated file.

Do **not** pass `CHART_VERSION`/`APP_VERSION` unless the human asks; version bumps are their call.

## 4. CHANGELOG

```bash
make changelog
```

Then edit `charts/kasm-helm/CHANGELOG.md`'s `[Unreleased]` section by hand. It must cover, in the file's
existing style and grouping:

**Added**
- OpenTelemetry Collector and ClickHouse telemetry store, enabled by default
- nginx distributed tracing and connection metrics
- browser telemetry for the Kasm web UI
- `observability.*` values tree, external-ClickHouse support, forwarding, retention controls
- configurable ClickHouse database name (`observability.clickhouse.database`, default `kasm_otel`),
  threaded through the collector exporters, schema init, the ClickHouse user's grant, and the Kasm API
  read path, so telemetry can live in a tenant-specific database on a multi-tenant external ClickHouse
- optional file-based JSON logging with a log-tailing sidecar
- a node-level log-collection DaemonSet for the Kasm Proxy's nginx logs, with a sidecar alternative for
  namespaces enforcing the `baseline`/`restricted` Pod Security Standards

**Changed** — the customer-visible behaviour changes, called out prominently:
- `logFormat: json` no longer affects the API and Manager services; their console output is
  human-readable text and their structured logs are exported over OpenTelemetry. Customers scraping JSON
  from those pods' stdout must switch to OTLP collection or enable `observability.fileLogs`.
- New PVC and new workloads per deployment (collector, ClickHouse, and a DaemonSet on every node) —
  resource and storage impact on upgrade.
- The Kasm Proxy's stdout access log is JSON whenever `observability.enabled` is true, regardless of
  `logFormat`, because the log collector parses it as JSON.
- nginx connection metrics are not collected on the default log-collection path; enable
  `observability.nginxLogs` if you need them.
- Splunk HEC settings previously stored in the Kasm database are no longer read; move them into a
  collector ConfigMap (`examples/otel-collector-splunk.yaml`).

**Removed**
- the `api-app-config` and `manager-app-config` ConfigMaps (dead configuration)

Anything H6 flagged as a known deviation belongs here too — in particular, state clearly that the
DaemonSet is incompatible with `baseline`/`restricted` namespaces and how to deploy there.

## 4b. `images.txt` and version fields

- `charts/kasm-helm/images.txt` — H1 added the two third-party images. Confirm they are there and that
  the Kasm rows still read `1.19.0-rolling`: **do not** bump those to a 1.20 tag as part of this work;
  that is a release-time change the humans own.
- **Do not touch** `Chart.yaml`'s `version: 1.1200.0-develop` or `appVersion: develop`. Chart versions
  track Kasm releases and `1.1200.0-develop` correctly targets **Kasm 1.20**. The README badges and the
  "This branch" line already say 1.20 and are checked by `scripts/set_versions.py --check`.
- A future change will swap the collector and ClickHouse images to internal Kasm-hosted tags. Leave a
  one-line comment in `images.txt` noting that, so it is not forgotten.
- Airgapped/offline bundling is **explicitly out of scope** for this change. Do not add offline tooling;
  if you notice a place where offline installs would need these images, record it under Follow-ups.

## 5. Top-level README

Check whether the repo-root `README.md` enumerates chart components, images, or requirements — it has
version badges and install snippets maintained by `scripts/set_versions.py`. If it lists deployed
components, add the collector and ClickHouse. Run `python3 scripts/set_versions.py --check` (part of
`make readme-check`) to confirm you did not break it.

## 5b. OpenShift note

`docs/observability.md` must state plainly that on OpenShift the log-collection DaemonSet is not used —
`isOpenshift: true` forces the sidecar path, because a hostPath/root DaemonSet there would need a
SecurityContextConstraint the chart does not ship. Put it next to the Pod Security carve-out in the
nginx-logs section; it is the same shape of trade-off and customers hit it the same way. Confirm against
`PROGRESS.md` whether H5 made this automatic or a hard failure, and document what actually happens.

## 6. Backend-side documentation

Two small updates in `kasm_backend` (this is the one phase that touches both repos):

1. `docs/telemetry/prompts/public-docs-update.md` — add a line noting that the Helm chart now ships the
   stack, so the public docs need a Kubernetes column in the configuration tables. Do not write the
   public docs themselves; that is tracked separately.
2. `docs/telemetry/how-to/deploy.md` — the "For Kubernetes or environments without writable log
   volumes" paragraph should now point at the Helm chart's `docs/observability.md` for the Kubernetes
   story instead of leaving it implicit.

Keep both edits to a few lines.

## 7. Plan hygiene

Update `docs/otel-integration-plan.md`'s §11 in place: mark each decision as implemented, and move
anything not done into a short "Follow-ups" list at the end of `PROGRESS.md`. Do not rewrite the plan's
history — it is the design record.

Delete nothing from `docs/otel-execution/`; the phase docs plus `PROGRESS.md` are the audit trail for
how this was built.

---

## Verify

```bash
make readme-check
make lint
python3 scripts/set_versions.py --check
# every example is valid YAML and a real ConfigMap with the right key
for f in examples/otel-collector-*.yaml; do
  python3 -c "
import yaml,sys
d=yaml.safe_load(open('$f'))
assert d['kind']=='ConfigMap', '$f is not a ConfigMap'
assert 'config.yaml' in d['data'], '$f missing config.yaml key'
yaml.safe_load(d['data']['config.yaml'])
print('ok $f')
"
done
# no realistic-looking secrets in examples
grep -rniE 'token: *"?[a-z0-9]{20,}' examples/ && echo "FAIL: possible real credential" || echo ok
make changelog-check    # will pass only once CHANGELOG.md differs from the base branch
```

## Definition of done

- Three examples exist, each a valid ConfigMap whose `config.yaml` parses, with placeholder credentials.
- `docs/observability.md` covers all twelve sections, written for operators rather than implementers.
- `make readme-check` green; CHANGELOG `[Unreleased]` covers Added/Changed/Removed including the two
  breaking behaviour changes.
- Backend doc pointers updated; plan §11 marked up.
- `make lint` green.

## Hand-off notes

Final `PROGRESS.md` entry should include a **Follow-ups** section listing everything deliberately left
undone — at minimum the installer wiring for `KASM_CLICKHOUSE_CA_CERT` on the Docker `app`/`all` role
(from H0), nginx connection metrics on the DaemonSet path (`k8s_observer` + `receiver_creator`, which
would add pod-list RBAC), the public documentation Kubernetes column, and anything H6 could not
execute. That list is
what the human turns into tickets.
