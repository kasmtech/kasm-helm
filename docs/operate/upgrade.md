> **Applies to:** both halves

# Upgrade

**Order: CRDs → operator → agent.** A new operator expects its new schema, so the app release that
carries it must land on a cluster whose CRDs already accept the fields it writes. The reverse order
leaves a window in which the operator writes fields the stored schema prunes.
[Upgrade discipline](../../charts/kasm-agent-crds/README.md#upgrade-discipline). In the normal case
the last two steps are one release — the `kasm-agent` umbrella carries both — and separate only
where a second agent runs with `operator.enabled=false`, in which case the operator's release goes
first.

**Version lockstep.** `make version-check-agent` (backed by `scripts/agent_versions.py --check`)
fails when any `file://` dependency pin in `kasm-agent` or `kasm-platform` drifts from the subchart's
own `Chart.yaml`, and CI runs it on every pipeline; `scripts/agent_versions.py --bump` moves the whole
family together. The two rules it does *not* encode still have to be held by hand:

* `kasm-platform`'s `Chart.yaml` pins **both** dependency versions. Bump the `kasm-helm` dependency
  there whenever the control-plane chart's version moves, and re-run
  `helm dependency update charts/kasm-platform` — without both, `helm dependency build` cannot
  resolve the local dependency.
* The control plane's `manager/agent_version` setting gates which agent builds it accepts, so an
  agent image tag out of step with the control plane surfaces as a **registration failure**, not a
  runtime error.
* `python3 scripts/set_versions.py --check` keeps the root README's version references honest with
  `charts/kasm-helm/Chart.yaml`.

**CRD schema changes** land one of two ways, and it depends on the choice made in
[7.1](install-and-verify.md#order): `helm upgrade` of the `kasm-agent-crds` release, or
`kubectl apply --server-side -f charts/kasm-agent-operator/crds/` out of band. A `crds/`-installed
CRD is never touched by `helm upgrade`.

**Do not roll back the CRD release.** `helm rollback` will reinstate an older schema underneath
objects already stored in the newer one; the API server prunes the fields the restored schema does
not define, silently and irreversibly. Roll forward instead.
