# OTEL architecture reversals — decision record

This is the durable in-repo copy of bead `kasm-helm-4ss` ("Decision record: OTEL architecture
reversals"), reached in two design reviews — 2026-08-11 and a 2026-08-14 grill session (items
11–22) — that overturned parts of the plan executed in `H1`–`H5`. It is a faithful transcription
of the bead's numbered items, edited only for markdown, not for meaning. Three items have since
been overtaken again; each carries an inline **SUPERSEDED/AMENDED (2026-09-15)** note verified
against the current tree. See `PROGRESS.md`'s "Architecture reversals" section for a shorter,
prose summary aimed at readers of the H-phase docs.

## 2026-08-11 review

1. Forwarder DaemonSet proposal REJECTED: DaemonSet cannot be zone-scoped, node-local routing
   needs `internalTrafficPolicy: Local` (blackhole risk) or `hostPort` (PSS violation), and it does
   not change gateway throughput. Instead: de-zoned single forwarder Deployment.
2. Zone-scoped forwarders REVERSED (H1 amendment): zone identity lived only in endpoint selection,
   never recorded in telemetry; single cluster-wide forwarder Deployment is sufficient. `kasm.zone`
   resource attribute added to preserve zone info properly.
3. Gateway single-replica constraint LIFTED: `loadbalancing` exporter with `routing_key: traceID`
   partitions traces across replicas so `tail_sampling` stays correct. `dns` resolver (headless
   Service) chosen over `k8s` resolver to keep chart RBAC-free. Default stays 1 replica, smaller
   base resources; scaling is horizontal via the `replicas` knob.
4. `hostLogs` DaemonSet default REVERSED (plan 3a/3b): sidecar-only nginx log collection,
   unconditional on `observability.enabled`. PSS-restricted-clean and OpenShift-clean single code
   path. Caveat documented: nginx output predating config load appears only in `kubectl logs`.
5. guac/rdp-gateway/rdp-https-gateway consolidated into `connection-proxy` StatefulSet (backend
   models the VM paradigm: one nginx, one FQDN, three registrations).
6. Sidecars export to forwarder, not gateway (fewer gateway ingress points, no bearer sprawl,
   single flip point for future loadbalancing changes).
7. HPA rejected for now (simplicity).
8. `fileLogs` deleted (nothing depends on file-shaped logs in api/manager).
9. `logFormat` deleted (console always human-readable; structured logs via sidecars/OTLP). Root
   schema is permissive so upgrades no-op silently; CHANGELOG note required.
10. DB metrics via `postgresql` receiver over loopback trust (`pg_hba` trusts 127.0.0.1); username
    from `POSTGRES_USER`, no new role, no secret. Overrides ship for hardened `pg_hba`. Security
    note: loopback trust gives any container in the DB pod passwordless DB access (pre-existing,
    documented not fixed). **AMENDED (2026-09-15):** the `postgresql` metrics receiver was
    deferred at bead `jg7.6` close — the DB sidecar ships logs only today (verified:
    `charts/kasm-helm/templates/otel-db-sidecar-configmap.yaml:8`, "There are no metrics here yet.
    A postgresql receiver would need database credentials in this pod...").

## 2026-08-14 grill session (additions and supersessions)

11. Per-tier images RESTORED (supersedes epic "delete per-tier image duplication"):
    `components.otelForwarder`/`otelGateway`/`otelSidecar` each carry their own image. Rationale:
    Kasm Engineering swaps the forwarder for Grafana Alloy while leaving gateway and sidecars on
    otelcol. Alloy swap needs config mount path, probe port 12345, and args overrides that the
    chart will NOT provide; Engineering handles it via `extraObjects` + image override.
12. Values restructure: `components.<name>` owns deployment concerns (image, resources, replicas,
    storage, labels/annotations, extraVolumes via `mergedValues`); `observability` owns telemetry
    behavior only. `components.{otelForwarder,otelGateway,otelSidecar,clickhouse}` added;
    `observability.clickhouse.storage` moves to `components.clickhouse.storage`. `database.*`
    deferred to its own change (it shipped in 1.19; needs deprecation shim).
13. `tailSamplePercentage` and `forward` move under `observability.collector.gateway`.
    `externalEndpoint` moves to `observability.collector.forwarder.externalEndpoint` and means
    FORWARDER REPLACEMENT ONLY: gateway, ClickHouse, and retention Job still render; customer must
    forward to `<release>-otel-gateway:4317` with the bearer token or reporting is empty
    (undetectable at render time, documented).
14. External ingest Service terminates TLS using `certificate.secretName`. Plaintext bearer over a
    LoadBalancer leaks a long-lived credential.
15. Sidecar receiver set (one shared ConfigMap for both nginx pods): filelog access+error,
    nginx/metrics on `localhost:8090`, otlp gRPC `127.0.0.1:4316` (nginx traces), otlp HTTP
    `127.0.0.1:4318` (guac/rdp/rdp-https). Loopback binds only, no containerPort, no Service.
    Exports otlphttp to `forwarder:4318`. **AMENDED (2026-09-15):** filelog was replaced by syslog
    receivers on 5140/5141 in the same commit that superseded item 17 (verified:
    `charts/kasm-helm/templates/otel-nginx-sidecar-configmap.yaml:46-56`, `syslog/nginx_access` /
    `syslog/nginx_error` receivers on `127.0.0.1:{{ $constants.otel.syslogAccess }}` /
    `...syslogError`).
16. Forwarder's 4316 receiver DELETED (supersedes `00-SHARED-CONTEXT` 6.8 "port 4316 is
    deliberate"). nginx now speaks to its pod-local sidecar, so no unauthenticated receiver is
    exposed cluster-wide. `otel.conf` returns to `nginx-shared-configmap.yaml` with endpoint
    `localhost:4316`; the primary-zone bug at `connection-proxy-configmaps.yaml:69` disappears
    rather than being fixed. `stub_status` added to connection-proxy nginx.
17. nginx log transport: files on shared emptyDir (NOT syslog) for now. Syslog-to-loopback deferred
    pending measurement of nginx's ~1024-byte syslog truncation against `json_combined`.
    `sizeLimit` retained: bounded failure (pod eviction, self-healing) beats unbounded node
    ephemeral storage. Rotation unsolved and tracked separately. **SUPERSEDED (2026-09-15):**
    syslog-to-loopback shipped in commit `d67904a` ("feat: ship nginx logs over loopback syslog to
    the otel sidecar"; bd `kasm-helm-dak`/`ann` closed), measured with no 1024B truncation against
    `json_combined` (verified: `git log --oneline -3` shows `d67904a` at HEAD~2;
    `charts/kasm-helm/templates/otel-nginx-sidecar-configmap.yaml:10,19` describe the syslog/UDP,
    loopback-only, no-Service design that replaced the file-based path).
18. DB logging: `log_destination='stderr,jsonlog'`, `logging_collector` on, `postgresql.log`
    symlinked to `/dev/stdout` for human console, sidecar tails the JSON on the PVC as uid 70
    (files are 0600 owned by 70; the 10001 sidecar uid cannot read them).
    `log_truncate_on_rotation=on`.
19. filelog offsets persisted via `file_storage`: `otel-sidecar-tmp` emptyDir for nginx sidecars,
    on the DB PVC for the DB sidecar (its logs outlive the pod, so in-memory offsets lose the
    restart window).
20. `observability.fileLogs` deleted; guac exports to OTEL directly (`fileLogs` for guac was a
    misunderstanding).
21. Item 9 (ClickHouse RO user for api/manager) DEFERRED: dev team owns the RO-user
    implementation. Chart keeps one `kasm_otel` user today.
    **SUPERSEDED (2026-09-15):** deferral lifted at owner direction; the chart now ships a
    read-only user for api/manager (bd kasm-helm-hvx) — on by default for the bundled
    ClickHouse, writer fallback for external deployments.
22. CORRECTION to decision 9's premise: `values.schema.json` root really is
    `additionalProperties: true` (CLAUDE.md and `00-SHARED-CONTEXT` say false; the file wins), so
    removing `logFormat` is a silent no-op on upgrade. CHANGELOG note still required.
