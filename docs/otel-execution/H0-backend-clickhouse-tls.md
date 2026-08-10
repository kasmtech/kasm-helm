# H0 — Backend: let the ClickHouse read path verify TLS

**Repo:** `kasm_backend` (working directory = repo root, branch `feature/DEV-31`)
**Depends on:** nothing. **Blocks:** H3.
**Size:** small (one function, one test, two doc rows).

---

## Why

`api_server/api_server/data/clickhouse_reports.py::_get_client()` builds the ClickHouse client
without telling it how to verify the server certificate:

```python
return clickhouse_connect.get_client(
    interface=endpoint.scheme or "http",
    host=endpoint.hostname or "kasm_clickhouse",
    port=endpoint.port or (8443 if endpoint.scheme == "https" else 8123),
    database=os.environ.get("KASM_CLICKHOUSE_DATABASE", "kasm_otel"),
    username=os.environ.get("KASM_CLICKHOUSE_USER", "kasm_otel"),
    password=os.environ.get("KASM_CLICKHOUSE_PASSWORD", ""),
)
```

`clickhouse_connect` defaults to `verify=True` against the system trust store. Kasm presents a
**self-signed** certificate on 8443 — both in the Helm chart (H3) and on the dedicated
`--role clickhouse` node that **already ships in the Docker installer**. So any `https://`
`KASM_CLICKHOUSE_ENDPOINT` fails certificate verification and every report query errors out.

This is a real bug in the shipped Docker multi-node topology, not just a Helm prerequisite.

## Scope

Add two environment variables, honour them in `_get_client()`, test them, document them. Nothing
else. Do **not** change `install.sh`, the collector configs, or the docker-compose files — the
installer wiring is deliberately out of scope for this phase.

---

## Changes

### 1. `api_server/api_server/data/clickhouse_reports.py`

Extend `_get_client()` to honour, in this precedence order:

| Env var                      | Type   | Default | Effect                                                              |
| ---------------------------- | ------ | ------- | ------------------------------------------------------------------- |
| `KASM_CLICKHOUSE_CA_CERT`    | path   | unset   | Passed as `ca_cert=<path>` — verification succeeds against that cert |
| `KASM_CLICKHOUSE_VERIFY`     | bool   | `true`  | `false` → `verify=False`, skipping verification entirely             |

Rules:

- Only pass `ca_cert` when the variable is set **and non-empty**; passing `ca_cert=None` explicitly is
  fine but prefer building a kwargs dict so unset means "don't pass it at all".
- `KASM_CLICKHOUSE_CA_CERT` wins over `KASM_CLICKHOUSE_VERIFY=false`: if a CA is supplied, verify with
  it. Log at `warning` if both are set in a contradictory way.
- Parse the boolean permissively — accept `true/false`, `1/0`, `yes/no`, case-insensitive. Check
  whether the repo already has a helper for this (`grep -rn "def str_to_bool\|strtobool" api_server/ libs/`)
  and reuse it if so rather than adding another one.
- These only matter for `https`; passing them for plain `http` is harmless, so don't branch on scheme.
- Follow the repo's guard-clause style (early return / flat success path) and keep comments minimal —
  one short comment explaining *why* the self-signed default needs this is enough.

This file is legacy-grandfathered for lint but **new code must still pass** `make lint`. Check
whether `clickhouse_reports.py` is in the `ruff.toml` per-file-ignores ledger before assuming
formatting is relaxed.

### 2. `api_server/tests/test_clickhouse_reports.py`

The suite exists. Add tests near the existing client-construction tests (read the file first to match
its mocking style — it should already patch `clickhouse_connect.get_client`):

- default env → no `ca_cert` kwarg, `verify` either absent or `True`
- `KASM_CLICKHOUSE_CA_CERT=/etc/ssl/certs/clickhouse.crt` → `ca_cert` passed with that value
- `KASM_CLICKHOUSE_VERIFY=false` → `verify=False`
- both set → `ca_cert` wins, verification not disabled
- `KASM_CLICKHOUSE_VERIFY` garbage value (e.g. `maybe`) → treated as default `true`, no crash

Use `monkeypatch.setenv` and remember `_get_client` may be module-level cached — check for
`@cache`/`@lru_cache` and clear it between tests if present.

### 3. `docs/telemetry/reference/configuration.md`

Add two rows to the **Kasm-Specific Variables (`KASM_` prefix)** table, directly after
`KASM_CLICKHOUSE_PASSWORD`, matching the existing column style:

```
| `KASM_CLICKHOUSE_CA_CERT` | — | Path to a PEM CA/certificate used to verify the ClickHouse TLS certificate. Required when connecting to a `https://` endpoint presenting Kasm's self-signed certificate. |
| `KASM_CLICKHOUSE_VERIFY` | `true` | Set `false` to skip ClickHouse TLS certificate verification. Ignored when `KASM_CLICKHOUSE_CA_CERT` is set. |
```

Then, in the **Dedicated ClickHouse Role (`clickhouse`)** section of the same file, extend the
`Credentials`/`TLS` discussion with one sentence: the app node needs `KASM_CLICKHOUSE_CA_CERT` (or
`KASM_CLICKHOUSE_VERIFY=false`) to read reports from a dedicated node over `https://`, because no CA
is distributed between nodes.

---

## Verify

```bash
cd /home/ubuntu/kasm_backend
make unit-test-quick T="tests/test_clickhouse_reports.py"
make lint
make pyright
```

`make pyright` is a blocking CI gate. If `clickhouse_reports.py` is outside the strict-typed trees
(`routes/`, `libs/`) it may not be checked — run it anyway and don't introduce new errors.

## Definition of done

- New tests pass; existing `test_clickhouse_reports.py` tests still pass.
- `make lint` and `make pyright` clean.
- Both env vars documented.
- No changes to `install.sh`, compose files, or collector configs.

## Hand-off notes

In `PROGRESS.md`, record the **exact** env var names and semantics you implemented — H3 mounts the
certificate and sets these variables on the API and Manager pods, and will build the wrong thing if
the names drift.

Also flag for the human: the installer still does not set these on the `app`/`all` role when
`--clickhouse-http-endpoint` is an `https://` URL, so the Docker dedicated-ClickHouse topology stays
broken until that wiring is added. That is deliberately outside this phase — make sure it is written
down as a follow-up rather than silently fixed.
