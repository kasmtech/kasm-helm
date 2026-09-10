# Install the CRDs as their own release

> **Applies to:** agent

## Why this is needed

The operator chart's `crds/` directory installs the five CRDs, but `helm upgrade` never touches a
`crds/` CRD. The `kasm-agent-crds` chart ships the same five schemas as ordinary templates, so a
release of it owns their lifecycle and upgrades them with Helm.
[Why the CRDs are split](../../explanation/why-the-crds-are-split.md) has the reasoning.

## Before you start

- Decide whether Helm should own the CRDs at all. For a single cluster installed once and upgraded
  by hand, the operator's `crds/` directory plus `kubectl apply --server-side` out of band is
  enough; skip this page.
- If the cluster already has the CRDs from a `kasm-agent`, `kasm-platform` or `kasm-agent-operator`
  install, they carry no Helm ownership metadata and must be adopted first (step 2).

## Steps

1. **Fresh cluster: install this release first**, before `kasm-agent` or `kasm-platform`. The CRDs
   are cluster-scoped, so the namespace is immaterial.

   ```console
   helm install kasm-agent-crds oci://registry-1.docker.io/kasmweb/kasm-agent-crds -n kasm-system --create-namespace
   ```

2. **Existing cluster: adopt, then install.** Label and annotate the five CRDs so Helm recognises
   them as this release's, then run the same install:

   ```console
   for crd in agents.agent.kasm.com kasmimagepullers.agent.kasm.com kasmworkspaces.agent.kasm.com \
              warmpools.pools.kasm.ai warmpoolinstances.pools.kasm.ai; do
     kubectl label crd "$crd" app.kubernetes.io/managed-by=Helm --overwrite
     kubectl annotate crd "$crd" meta.helm.sh/release-name=kasm-agent-crds \
       meta.helm.sh/release-namespace=kasm-system --overwrite
   done
   helm install kasm-agent-crds oci://registry-1.docker.io/kasmweb/kasm-agent-crds -n kasm-system --create-namespace
   ```

   This is metadata only; no schema is rewritten and no stored object is touched.

3. **Install the app release.** Its embedded `crds/` directory is harmless: Helm skips a CRD that
   already exists. Add `--skip-crds` if the app release should never reason about CRDs.

   ```console
   helm install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent --create-namespace -f values.yaml
   ```

4. **On every upgrade, this release goes first.** A new operator expects its new schema.

   ```console
   helm upgrade kasm-agent-crds oci://registry-1.docker.io/kasmweb/kasm-agent-crds -n kasm-system
   helm upgrade kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent -f values.yaml
   ```

5. **Never `helm rollback` this release.** It reinstates an older schema underneath objects stored in
   the newer one, and the API server prunes the fields the restored schema does not define,
   silently. Fix the schema and upgrade again instead.

## Verify

```console
kubectl get crd -l app.kubernetes.io/managed-by=Helm | grep kasm
```

Expected: five rows, `agents`, `kasmimagepullers` and `kasmworkspaces` in `agent.kasm.com`,
`warmpools` and `warmpoolinstances` in `pools.kasm.ai`.

```console
helm list -A | grep kasm-agent-crds
```

Expected: one release, `STATUS deployed`.

## Chart values

This chart has none. Its templates are static manifests, byte for byte the schemas the operator
repository generates; `make crds-sync-check` fails the build if the two copies diverge.

## Troubleshooting

`rendered manifests contain a resource that already exists … invalid ownership metadata` on install
means step 2 was skipped, or the release name and namespace in the annotations do not match the
`-n` of the install. Otherwise [Troubleshooting](../../reference/troubleshooting.md).

## Decisions

- [ ] CRD ownership chosen: this release, or the operator's `crds/` directory plus a `kubectl apply --server-side` habit.
- [ ] On an existing cluster, the five CRDs adopted before the install.
- [ ] Upgrade order written down where whoever runs upgrades will see it: CRDs, then operator, then agent.
- [ ] "Never roll back the CRD release" understood by everyone with upgrade rights.
- [ ] Understood that `helm uninstall` of this release keeps the CRDs (`helm.sh/resource-policy: keep`).
