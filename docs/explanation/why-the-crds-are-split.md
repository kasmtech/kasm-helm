# Why the CRDs are split from the operator

> **Applies to:** agent

The five CustomResourceDefinitions the operator owns (`agents`, `kasmworkspaces` and
`kasmimagepullers` in `agent.kasm.com`; `warmpools` and `warmpoolinstances` in `pools.kasm.ai`)
exist in this repository twice, on purpose. Helm has two ways to install a CRD, and each gives up
something the other has.

| | The operator chart's `crds/` directory | The `kasm-agent-crds` chart |
| --- | --- | --- |
| Applied | before the release manifest is rendered and validated | as ordinary templates, in the same pass as everything else |
| What that buys | a one-command install of an umbrella that also creates `Agent` and `KasmImagePuller` resources of those kinds | a release that owns the CRDs, so `helm upgrade` applies schema changes |
| What it costs | `helm upgrade` never touches a `crds/` CRD; schema changes go in with `kubectl apply --server-side` out of band | it cannot supply the schema the same release's custom resources are validated against, so it must be a separate release installed first |
| Removed by | nothing: `helm uninstall` leaves them | nothing: every CRD carries `helm.sh/resource-policy: keep` |

Reach for `kasm-agent-crds` when a fleet's CRD versions should move through the same review,
promotion and rollout machinery as everything else deployed with Helm. Skip it for a single cluster
installed once and upgraded by hand. The `kubectl apply --server-side` side channel stays valid
either way.

Both copies originate in `config/crd/bases/` of the operator repository, and `make crds-sync-check`
fails the build the moment they differ. Procedure:
[Install the CRDs as their own release](../how-to/install/crds.md).
