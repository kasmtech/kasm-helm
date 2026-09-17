# kasm-otel-router

A single-Deployment OpenTelemetry Collector that sits in front of several Kasm installs' own
`otel-gateway` collectors, routes each sender's telemetry to the right install by namespace, and
optionally tees a copy elsewhere (a SIEM, for example).

This chart has no components of its own beyond the router Deployment — no API, Manager, or DB.
It exists for the "several Kasm installs, central collection" case: pointing every install at one
router instead of managing per-install export destinations by hand, and giving an operator one
place to add a SIEM tee or centralize Kubernetes event collection across installs.

## 1. What it does

- Receives OTLP (logs, metrics, traces) on the same two ports every `kasm-helm` gateway does:
  gRPC `:4317` and HTTP `:4318`, both bearer-token authenticated.
- Routes each record to the right Kasm install's gateway by the `service.namespace` resource
  attribute the record already carries — every Kasm sender stamps this today (app services via
  `OTEL_RESOURCE_ATTRIBUTES`, Collector sidecars via a resource processor), so no sender-side
  change is needed to use this chart.
- Optionally tees a copy of *everything*, regardless of namespace, to a second OTLP destination
  (`tee.enabled`) — e.g. a SIEM.
- Optionally collects Kubernetes Events from each registered namespace and routes them through
  the same per-namespace table (`k8sEvents.enabled`).
- Telemetry whose `service.namespace` matches no registration is not dropped silently: it falls
  through to an unrouted sink that logs it and counts it in the router's own self-metrics
  (`otelcol_exporter_sent_*{exporter="debug/unrouted"}` on its `:8888` Prometheus endpoint), so a
  misconfigured or forgotten registration is something you can alert on.

## 2. Registering an install

Each entry in `registrations` is one Kasm install this router forwards to:

```yaml
registrations:
  - namespace: kasm-prod
    endpoint: "otel-gateway.kasm-prod.svc.cluster.local:4317"
    tokenSecret:
      name: kasm-prod-secrets
      key: otel-bearer-token
    insecure: true
```

`namespace` is the routing key — it must match the `service.namespace` value that install's own
senders stamp, not the Kubernetes namespace the router itself runs in. `endpoint` is that
install's gateway; `tokenSecret` must point at a Secret, in the router's own release namespace,
holding **that install's own gateway ingest token** (the same value the target install injects
into its own gateway as `OTEL_BEARER_TOKEN`). The router authenticates to each gateway as a
client using that install's credential — it does not create or store gateway tokens itself.

### The TLS trap

**An in-cluster `kasm-helm` gateway terminates no TLS on its receivers.** A registration's
exporter defaults to `insecure: false`, i.e. verifying TLS. Point a registration at a plaintext
in-cluster gateway without setting `insecure: true` and it will route correctly, present a
`grpc://` or HTTP endpoint, and then simply never deliver — TLS verification fails silently from
the operator's point of view, with nothing in the router's own logs pointing at "wrong flag."
Set `insecure: true` deliberately for every in-cluster registration. Only leave it `false` for a
registration whose endpoint actually terminates TLS (e.g. an out-of-cluster gateway behind a real
certificate). `tests/e2e/test_14_otel_router.py` shows the working in-cluster shape end to end.

## 3. Trust model

Read this before deploying across teams or tenants:

- The bearer token in `ingestAuth` is shared by **every** sender that talks to this router — it
  is one credential, not one per registration.
- The routing key, `service.namespace`, is an attribute the **sender itself sets**. The router
  trusts it. Anything holding the shared ingest token can set `service.namespace` to any
  registered value and have its telemetry routed to that registration's gateway, using that
  registration's own credential.
- Consequently, this chart is for Kasm installs under **one operator's control** who accept that
  any sender can claim any registered namespace. It is not a boundary between mutually
  distrusting tenants — anyone with the ingest token can read into, or inject into, any
  registration's telemetry stream.

## 4. Optional: centralizing Kubernetes Events

`k8sEvents.enabled: true` adds a `k8s_objects` receiver that watches core Events in every
`registrations[].namespace` and routes them like any other signal (or, per registration, to a
different destination via `registrations[].events`).

This requires RBAC the router does not otherwise need: it writes a **Role and RoleBinding into
each registered namespace**, granting only `get`/`list`/`watch` on Events to the router's own
ServiceAccount. Those namespaces are not otherwise managed by this chart's release. `helm
uninstall` removes them normally, but if you disable `k8sEvents` or remove a registration without
uninstalling the whole release, that namespace's Role/RoleBinding are orphaned and must be
cleaned up by hand:

```bash
kubectl delete role,rolebinding -n <namespace> -l app.kubernetes.io/instance=<release>
```

## 5. Render guards

The chart fails the render, rather than deploying something broken, in three cases:

- `registrations` is empty — the router would have nowhere to send anything.
- `replicaCount` is set above 1 while `k8sEvents.enabled` is true — each replica would
  independently watch and forward the same events, duplicating every event downstream. Routing
  is otherwise a stateless per-record operation, so `replicaCount` has no correctness reason to
  be pinned when `k8sEvents` is off; 1 is just the sane default for optional, low-volume
  infrastructure.
- Two `registrations` entries name the same `namespace` while `k8sEvents.enabled` is true — this
  would render a duplicate Role/RoleBinding name in that namespace.

## 6. Values

See `values.yaml` for the full, commented reference — every field above (`image`, `service`,
`replicaCount`, `resources`, `ingestAuth`, `registrations[]`, `k8sEvents`, `tee`) is documented
there with its default.

## 7. Validation

`make otel-validate` runs this chart's rendered Collector config through the pinned
`otel/opentelemetry-collector-contrib` binary (the same one the Deployment runs), so a config
that renders but doesn't parse is caught before it ships. `make e2e-router` (kind cluster
required) installs this chart alongside a registered `kasm-helm` release and proves telemetry and
Kubernetes events actually arrive at that install's ClickHouse through the router — see
`tests/e2e/test_14_otel_router.py`.
