> **Applies to:** both halves · **Prerequisite:** a values file from [Planning](../planning/README.md)

# Install and verify

## Order

1. **`kasm-agent-crds`, if you want Helm to own the CRD lifecycle.** Its own release, *before*
   anything else, and upgraded before the app releases thereafter. Skip it and the operator chart's
   `crds/` directory installs the same five schemas — but `helm upgrade` will never touch them.
   [Install order](../../charts/kasm-agent-crds/README.md#install-order) ·
   [why the split exists](../overview/architecture.md#why-the-crds-are-split-from-the-operator).
2. **Stage dependencies, or install from OCI.** From a checkout the build is **inside-out** —
   `helm dependency build charts/kasm-agent` *then* `oci://registry-1.docker.io/kasmweb/kasm-platform`, which `make deps-agent`
   does in that order. Skipping the first silently renders a control-plane-only stack. The OCI
   artifact embeds every dependency and needs neither step.
3. **Label the namespace** if any privileged chart is on:
   `kubectl label namespace <ns> pod-security.kubernetes.io/enforce=privileged`. `egressInstaller`
   needs host namespaces permitted as well.
4. **Install.** One release (`kasm-platform`), or the control plane first and then the agent — the
   agent needs the zone to exist and the token to have been copied across.
5. **Two clicks in the UI, still manual.** Infrastructure → the registered agent → **Enable** (new
   agents register disabled). Workspaces → the image → assign a group (`group_images` has no
   preseed path).

The narrated version, with measured timings, is the
[demo runbook](../../examples/kasm-agent/demo-runbook.md): ~3m30s for the single-command platform
install, ~3m41s for both installs in the two-namespace layout, ~11s to a running session on a warm
node.

## What to watch

```console
# Both halves rolled out
kubectl get pods -n <ns>

# The agent registered; Phase and the operator's conditions
kubectl get agents.agent.kasm.com -n <ns>
kubectl get agents.agent.kasm.com -n <ns> -o jsonpath='{.items[*].status.conditions}' | jq

# Webcam path only: the extended resource is actually advertised
kubectl get node <node> -o jsonpath='{.status.allocatable}' | jq '."kasm.com/video"'

# The session proxy answers — 404 with no active session is correct
curl -k -sS -o /dev/null -w '%{http_code}\n' https://<agent hostname>/

# The session really is a pod
kubectl get kasmworkspaces -n <ns>
```

`Degraded=True` with `GatewayRouteAccepted=False` means the operator cannot manage TLSRoutes —
missing RBAC, or a `TLSRoute` CRD that is missing or older than Gateway API 1.5. Everything else keeps reconciling, so sessions
stay up; only `agent.gatewayRoute` is unfulfilled. The fix, and the rest of the failure catalogue,
is in [External access and TLS → Troubleshooting](../planning/networking/README.md#troubleshooting).

Then the real test: log in at the control-plane hostname, launch a session, confirm the browser's
URL bar shows the **agent's** hostname, and confirm the session survives past 60 seconds (proof the
websocket timeout is raised).

**Decisions**

- [ ] CRD ownership chosen: `kasm-agent-crds` release, or the operator chart's `crds/` plus an out-of-band `kubectl apply --server-side` habit.
- [ ] Install source chosen: OCI artifact, or a checkout with the inside-out dependency build.
- [ ] Namespace labels applied ahead of the install where privileged charts are on.
- [ ] Install order agreed: CRDs → control plane → token copy → agent.
- [ ] Someone owns the two manual UI steps.
- [ ] Verification run: pods, `Agent` conditions, session proxy answering, one real session past 60s.

---
