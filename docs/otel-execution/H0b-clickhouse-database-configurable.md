# H0b — Make the ClickHouse database name configurable end to end

**Repos:** `kasm_backend` (parts 1, 3, 4) and `kasm-helm` docs (part 2).
**Depends on:** H0 (merged into the same working tree). **Blocks:** nothing, but H3/H4 must land part 2's
instructions before they are implemented.
**Size:** large — four parts, one theme.

---

## Why

We want to support an **external, multi-tenant ClickHouse**, where Kasm's telemetry lives in a
tenant-specific database rather than always `kasm_otel`. Today the name is hardcoded in five places and
the one variable that claims to control it (`KASM_CLICKHOUSE_DATABASE`) does nothing, because every
report query fully qualifies its tables.

### Verified facts — do not re-derive

Measured against the live local ClickHouse (24.12) on 2026-08-06:

| Finding | Evidence |
| ------- | -------- |
| The connect-time `database` **does** resolve unqualified table names | `_get_client()` with `database=kasm_otel` ran `SELECT count() FROM otel_logs` → 120,986 rows |
| Resolution follows the connect-time database, nothing else | Same query with `database=default` → `UNKNOWN_TABLE` |
| Two databases can hold identically-named tables, selected per connection | Temp db with its own `otel_logs` returned only its own row |
| The app user **cannot** create its own database | `GRANT ALL ON kasm_otel.*` is db-scoped; `CREATE DATABASE` → code **497** Not enough privileges |
| The app user's grants **cannot** be changed by SQL, ever | `GRANT ALL ON <newdb>.* TO kasm_otel` → code **495** `ACCESS_STORAGE_READONLY` (user comes from `users_xml`) |

The last two are the important ones. Because grants for an XML-defined user are immutable at runtime, a
mis-templated grant is **unrepairable without a config change and restart** — if the grant says
`kasm_otel.*` while the database is `tenant_a`, every report fails and no SQL can fix it. Treat the grant
templating in part 3 as load-bearing, not cosmetic.

`create_schema: true` stays on the collector exporters (decided). `GRANT ALL ON <db>.*` includes
`CREATE TABLE`, so the exporter can still create `otel_traces` and `otel_metrics_*` inside the tenant
database. For external ClickHouse that grant becomes a documented operator prerequisite.

**`kasm_otel` is both the database name and the username.** They are separate concerns
(`KASM_CLICKHOUSE_USER` / `--clickhouse-username` already exist). Do not collapse them; a tenant will
plausibly run user `kasm_otel` inside database `tenant_a`.

**No config-hash regeneration needed:** `install/conf/config_hashes.txt` only covers
`install/conf/app/*/*.app.config.yaml`, not the clickhouse or otel conf files. Leave it alone.

---

## Part 1 — Backend read path (`kasm_backend`)

### `api_server/api_server/data/clickhouse_reports.py`

Remove the database qualifier from every query so the connect-time `database` governs resolution.
There are **19** occurrences:

| Pattern | Count |
| ------- | ----- |
| `FROM kasm_otel.otel_logs` | 9 |
| `FROM kasm_otel.otel_metrics_sum` | 6 |
| `FROM kasm_otel.otel_metrics_gauge` | 3 |
| `FROM kasm_otel.otel_traces` | 1 |

Each becomes `FROM otel_logs` etc. Verify the count before and after:

```bash
grep -c "kasm_otel\." api_server/api_server/data/clickhouse_reports.py   # 19 before, 0 after
```

Keep the `"database": os.environ.get("KASM_CLICKHOUSE_DATABASE", "kasm_otel")` kwarg in `_get_client()`
exactly as it is — it becomes the real control. Do not touch the H0 CA-cert/verify logic.

Check the module docstring (it lists the tables) and any comments that name `kasm_otel` as the database;
reword so they describe tables within *the configured database* rather than a fixed one.

### `api_server/tests/test_clickhouse_reports.py`

The existing tests mock `clickhouse_connect.get_client`, so they cannot catch a re-introduced qualifier.
Add a **guard test** that inspects the query text directly:

- Iterate the SQL in `CLICKHOUSE_REPORTS` (and any other module-level query constants) and assert none
  matches a database-qualified table reference — regex on
  `\b(FROM|JOIN)\s+[A-Za-z_][A-Za-z0-9_]*\.` . Fail with the offending report name so the message is
  actionable.
- Add a test that `KASM_CLICKHOUSE_DATABASE` is passed through to `get_client` as `database=` (a
  non-default value, e.g. `tenant_a`), and that the default is `kasm_otel` when unset.

Read the file first and match its existing fixture/mocking style.

### `docs/telemetry/reference/configuration.md`

- Update the `KASM_CLICKHOUSE_DATABASE` row: it now actually selects the database the reporting queries
  read from, because queries are unqualified.
- Add a short **External / multi-tenant ClickHouse** subsection near the dedicated-role section stating
  the operator prerequisites: create the database; create the user; `GRANT ALL ON <database>.*` to it
  (needed because `create_schema: true` lets the collector create the trace and metric tables); and note
  that grants for XML-defined users cannot be altered by SQL later.

---

## Part 2 — Chart hand-off docs (`kasm-helm`, docs only)

No chart templates are written here — only the phase docs, so H3/H4/H6/H7 build the right thing.

**`docs/otel-execution/H3-clickhouse.md`**
- `users.xml`: the `GRANT ALL ON kasm_otel.*` must be templated from
  `.Values.observability.clickhouse.database`. Add the ACCESS_STORAGE_READONLY finding above as the
  reason, so nobody "simplifies" it back to a literal.
- `init-schema.sql`: `CREATE DATABASE` / `CREATE TABLE <db>.otel_logs` templated from the same value
  (already stated — make it explicit that it is required, not optional).
- Retention Job DDL: `ALTER TABLE <db>.otel_logs|otel_traces|otel_metrics_*` templated from the same
  value.

**`docs/otel-execution/H4-collector.md`**
- Currently says to port the three ClickHouse exporter blocks "unchanged". Change that: the `database:`
  key in each of `clickhouse/logs`, `clickhouse/traces`, `clickhouse/metrics` must be templated from
  `.Values.observability.clickhouse.database`. Note that leaving it literal silently splits reads from
  writes — the collector would write to `kasm_otel` while the API reads `tenant_a`, producing an empty
  UI with no error anywhere.
- Note that `create_schema: true` is retained deliberately and requires `GRANT ALL ON <db>.*`.

**`docs/otel-execution/H6-tests-e2e.md`**
- `clickhouse_test.yaml` / `otel_collector_config_test.yaml`: assert a non-default
  `observability.clickhouse.database` reaches the init schema, the grant, the retention DDL, **and** all
  three exporter `database:` keys — one assertion per site, so a partial implementation fails.
- e2e: add a non-default-database case (either a new scenario or a parameter on
  `test_12_observability.py`) that installs with `observability.clickhouse.database=kasm_tenant_a` and
  asserts reports still return rows. This is the only test that proves reads and writes agree.

**`docs/otel-execution/H7-docs-release.md`**
- `docs/observability.md` external-ClickHouse section: the operator prerequisites from part 1, the
  required grant, and that the database name must match on both sides.
- CHANGELOG: configurable ClickHouse database under **Added**.

**`docs/otel-integration-plan.md`**
- §1 parity table still lists `KASM_CLICKHOUSE_{ENDPOINT,DATABASE,USER,PASSWORD}` — fine, but add a line
  to §6 noting the database name must be threaded to reads, writes, schema, grant and retention together.

**`docs/otel-execution/PROGRESS.md`**
- Add an H0b row to the Status table and a `ClickHouse database name (configurable?)` row to the contract
  registry recording the final variable and values-key names.

---

## Part 3 — Docker installer (`kasm_backend`)

Add a `--clickhouse-database` flag and thread it everywhere. Default `kasm_otel`, so existing installs
and upgrades are unchanged.

### Placeholders to add to the conf templates

The installer substitutes placeholders with `sed`; these files need a `$CLICKHOUSE_DATABASE` token where
the name is currently literal:

| File | Sites |
| ---- | ----- |
| `install/conf/clickhouse/init-schema.sql` | `CREATE DATABASE IF NOT EXISTS`, `CREATE TABLE …otel_logs` (2) |
| `install/conf/clickhouse/users.xml` | `GRANT ALL ON kasm_otel.*` — and template the **username** element from `$CLICKHOUSE_USER` too if it is still literal; check |
| `install/conf/otel/otel-collector-local.yaml` | `database: kasm_otel` in all three exporters (3) |

Leave the `username:` lines alone where `configure_otel_external_database` already seds them.

### `install/install.sh`

- New default near `CLICKHOUSE_USER='kasm_otel'` (line ~38): `CLICKHOUSE_DATABASE='kasm_otel'`.
- Argument parsing: add `--clickhouse-database` beside `--clickhouse-username` (~line 1851).
- Help text: add a row beside `--clickhouse-username` (~line 1370).
- `copy_clickhouse_configs()`: substitute `$CLICKHOUSE_DATABASE` into `init-schema.sql` and `users.xml`,
  and into the compose `KASM_CLICKHOUSE_DATABASE` value (currently the literal `kasm_otel` in the compose
  files — either add a `$CLICKHOUSE_DATABASE` placeholder to the five compose files and sed it like
  `$CLICKHOUSE_USER`, or sed the literal; prefer the placeholder for consistency with `$CLICKHOUSE_USER`).
- `copy_otel_configs()`: substitute `$CLICKHOUSE_DATABASE` into the collector config.
- `configure_otel_external_database()`: alongside the existing
  `sed -i "s|username: kasm_otel|username: ${CLICKHOUSE_USER}|g"`, ensure the database is set from the
  flag as well.
- Install summary echoes at ~2364 and ~2440 print `username:`; add `database:` next to them.
- `validate_otel_flags()`: if a non-default `--clickhouse-database` is given with `--no-clickhouse`, warn
  that it has no effect (mirror the existing warning style).

### `install/upgrade.sh`

- New default near `CLICKHOUSE_USER='kasm_otel'` (line ~59).
- Argument parsing + help text (~line 881, ~1021) mirroring `--clickhouse-username`.
- **Recovery from the existing install**, like `ch_username` recovery at ~line 365: read the database out
  of the running collector config so an upgrade without the flag preserves a previously-customised name.
  Do not silently reset a tenant's database to `kasm_otel` on upgrade — that is a data-loss-shaped bug.
- Retention DDL at ~453/461/467/474: replace `kasm_otel.` with `${CLICKHOUSE_DATABASE}.`.
- **Fix a latent bug while here:** lines ~437 and ~446 run `clickhouse-client --user kasm_otel` with a
  literal username even though `CLICKHOUSE_USER` exists, so retention already breaks for anyone using
  `--clickhouse-username`. Use `${CLICKHOUSE_USER}`. Mention it in the report — it is a pre-existing
  defect, not something you introduced.
- `OTEL_LOCAL_FLAGS` pass-through at ~1172 adds `--clickhouse-username`; add `--clickhouse-database`.

### Documentation

- `docs/telemetry/how-to/deploy.md` and `docs/telemetry/how-to/upgrade.md`: document the new flag
  alongside `--clickhouse-username`, including the external multi-tenant recipe.
- `docs/telemetry/reference/configuration.md`: add the flag to the install-flag tables.

---

## Part 4 — bats / QA tests (`kasm_backend`)

`scripts/otel-tests/`. **Most `kasm_otel` matches in `profiles/*.bats` are the container name
`kasm_otel_collector` — leave those alone.** Only these touch the database:

| File | Sites |
| ---- | ----- |
| `lib/assertions.bash` | `_CH_USER="kasm_otel"` (~22); `--database kasm_otel` (~46, ~363) |
| `lib/otel-fixtures.bash` | exporter fixture yaml `database: kasm_otel` (~119, ~130, ~141); second-CH fixture `CLICKHOUSE_DB`, `SECOND_CH_DB`, `CH_ROLE_USER` (~233, ~260, ~320) |
| `profiles/par.bats` | direct `--database kasm_otel` (~179) |
| `qa/tc3-database.sh`, `qa/helpers.sh`, `qa/tc5-reports.sh` | check each — some are container names, some may be queries |

Changes:

1. **Centralise.** Add `_CH_DB="${KASM_OTEL_CH_DATABASE:-kasm_otel}"` next to `_CH_USER` in
   `lib/assertions.bash` and use it at both `--database` sites. Follow the file's existing convention for
   these module-level defaults (check whether `_CH_USER` is exported or referenced directly).
2. Replace the direct use in `par.bats` with the shared helper/variable.
3. Thread the same value through `lib/otel-fixtures.bash` so fixture-generated collector configs and the
   second-ClickHouse fixture agree with whatever database the install used.
4. **New profile covering the flag.** Add `profiles/p16.bats` following the shape of an existing
   single-node profile (`p1.bats` is the model; `p13`/`p14` show ClickHouse-specific assertions). It
   installs with `--clickhouse-database kasm_tenant_a` and asserts:
   - the database exists and `otel_logs` is present in it;
   - logs/traces/metrics rows actually land there (reuse the existing assertion helpers with
     `KASM_OTEL_CH_DATABASE=kasm_tenant_a`);
   - `kasm_otel` does **not** exist, proving nothing fell back to the default;
   - the Kasm UI/API read path returns non-empty report data — this is the assertion that catches a
     read/write split.
5. Register the profile: `scripts/otel-tests/Makefile` profile shortcuts, and
   `docs/telemetry/reference/test-matrix.md` (add the row and keep the table alignment — a repo coding
   rule).
6. `scripts/otel-tests/validate-configs.sh` performs static collector-config validation; check whether it
   asserts on the database name and update it if so.

Do **not** commit anything under `scripts/otel-tests/reports/` — that is gitignored junit output.

---

## Verify

```bash
cd /home/ubuntu/kasm_backend
# part 1
grep -c "kasm_otel\." api_server/api_server/data/clickhouse_reports.py   # → 0
make unit-test-quick T="tests/test_clickhouse_reports.py"
make lint
make pyright

# part 3 — the flag is wired everywhere
grep -n "CLICKHOUSE_DATABASE" install/install.sh install/upgrade.sh | wc -l   # non-trivial
bash -n install/install.sh && bash -n install/upgrade.sh                       # syntax
grep -rn "kasm_otel" install/conf/clickhouse/ install/conf/otel/otel-collector-local.yaml
# ^ every remaining hit must be a username or a container name, never a database

# part 4 — bats syntax + the new profile is registered
bash -n scripts/otel-tests/lib/assertions.bash scripts/otel-tests/lib/otel-fixtures.bash
grep -n "p16" scripts/otel-tests/Makefile docs/telemetry/reference/test-matrix.md
```

**Running the bats profiles themselves takes a long time and needs the kasm-lab DinD harness.** Do not
attempt a full `p16` run unless explicitly asked — validate syntax and registration, and state clearly in
your report that `p16` is **written but not executed**.

There is a **live local ClickHouse** (`kasm_clickhouse`, reachable on the docker network, credentials in
`/opt/kasm/current/conf/clickhouse/users.xml`) if you want to sanity-check a query by hand. Never print a
password. If you create anything, drop it afterwards and verify it is gone.

## Definition of done

- Zero database-qualified table references in `clickhouse_reports.py`; guard test prevents regression.
- `--clickhouse-database` accepted by both `install.sh` and `upgrade.sh`, defaulting to `kasm_otel`,
  threaded into the collector exporters, `init-schema.sql`, the `users.xml` grant, the compose env, and
  the retention DDL; recovered on upgrade rather than reset.
- The `--user kasm_otel` hardcoding in `upgrade.sh` fixed.
- bats helpers read the database from one place; `p16` written and registered; test-matrix updated.
- Chart phase docs H3/H4/H6/H7 updated so the templating is required rather than optional.
- `make lint`, `make pyright`, targeted unit tests green; `bash -n` clean on every edited shell file.

## Report back

- The exact flag and variable names implemented, and the values-key names you wrote into the chart docs.
- Every file changed, grouped by part.
- Verification commands run and their real results. Say explicitly which tests you did **not** execute.
- Anything you found that contradicts this doc, and any pre-existing defect you noticed but left alone.
