# OTel Helm Integration — Execution Package

> **Historical / superseded.** Execution record for `docs/otel-integration-plan.md`; several decisions here were reversed in design review (`kasm-helm-4ss`) and do not describe the shipped chart — see `charts/kasm-helm/docs/observability.md` for current behavior.

Hand-off docs for implementing `docs/otel-integration-plan.md` across several focused sessions.
Each phase is sized to be executed by one session on a mid-tier model without re-deriving design
decisions.

## Rules for every session

1. **Read `00-SHARED-CONTEXT.md` first.** It has the chart idioms, exact helper signatures,
   validation commands, and the gotchas that were expensive to find. Do not skip it.
2. **Read your own phase doc completely before editing anything.**
3. **Do not make git commits, stage files, push, or pull.** Leave the working tree dirty; the human
   reviews and commits. This applies to both repos.
4. **Stay in your phase.** If you find work that belongs to another phase, write it into
   `PROGRESS.md` under "Cross-phase findings" instead of doing it.
5. **Update `PROGRESS.md` when you finish** — status, files touched, deviations, anything the next
   phase needs to know. This is how phases talk to each other.
6. If the plan and the code disagree, **the code wins**; note the discrepancy in `PROGRESS.md`.

## Phase order and dependencies

```
H0 (kasm_backend) ──► H0b (configurable CH database)
                               │
                               ▼
H1 (values/schema/helpers) ──► H2 (service env)
                          ├──► H3 (ClickHouse) ◄── needs H0
                          ├──► H4 (Collector)
                          └──► H5 (nginx + sidecars)
                                        │
                          H6 (tests/e2e) ◄┘
                                        │
                          H7 (docs/release) ◄┘
```

| Phase                                        | Repo          | Depends on   | Parallel-safe with | Rough size |
| -------------------------------------------- | ------------- | ------------ | ------------------ | ---------- |
| [H0](H0-backend-clickhouse-tls.md)           | kasm_backend  | —            | H1                 | small      |
| [H0b](H0b-clickhouse-database-configurable.md) | kasm_backend + docs | H0     | H1                 | large      |
| [H1](H1-values-schema-helpers.md)            | kasm-helm     | —            | H0                 | medium     |
| [H2](H2-service-instrumentation.md)          | kasm-helm     | H1           | H3, H4, H5         | medium     |
| [H3](H3-clickhouse.md)                       | kasm-helm     | H1, H0       | H2, H4, H5         | large      |
| [H4](H4-collector.md)                        | kasm-helm     | H1           | H2, H3, H5         | large      |
| [H5](H5-nginx-sidecars.md)                   | kasm-helm     | H1           | H2, H3, H4         | large      |
| [H6](H6-tests-e2e.md)                        | kasm-helm     | H2–H5        | —                  | large      |
| [H7](H7-docs-release.md)                     | kasm-helm     | H2–H5        | H6                 | medium     |

**Sequential is safest.** H2–H5 touch mostly disjoint files and can run in parallel, but all four
add entries to `_helpers.tpl` and `values.yaml` was already finalised in H1, so parallel runs risk
merge conflicts in `_helpers.tpl`. If running in parallel, tell each session to append its helpers at
the end of `_helpers.tpl` and expect the human to resolve ordering.

**H5 is the riskiest phase** — it contains the `load_module` change that can stop nginx from starting,
and the host-log DaemonSet whose Pod Security implications are documented in the plan's §3a. Prefer
running it alone, with a human reviewing before H6.

## Suggested session prompts

Give each session exactly this, substituting the phase:

> Read `components/kasm-helm/docs/otel-execution/00-SHARED-CONTEXT.md` and then
> `components/kasm-helm/docs/otel-execution/H3-clickhouse.md`. Execute that phase in full, verify it
> with the commands listed in the doc, then update `PROGRESS.md`. Do not commit anything.

For H0 the working directory is the `kasm_backend` repo root; for H1–H7 it is
`components/kasm-helm`.

## Definition of done for the whole effort

- `make test` green in `kasm-helm` (lint + kubeconform + kyverno + unittest).
- `make readme-check` green; `CHANGELOG.md` updated.
- New e2e scenarios green against a kind cluster.
- `docs/otel-integration-plan.md` §11 items either done or explicitly re-listed as follow-ups in
  `PROGRESS.md`.
