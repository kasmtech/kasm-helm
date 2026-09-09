> **Applies to:** both halves

# Uninstall

Always in this order — `helm uninstall` would otherwise delete the `Agent` and the operator that
clears its finalizer at the same time, hanging the deletion (or worse, letting a later operator
install process a stale deletion and tear down a live agent):

```console
kubectl delete kasmworkspaces.agent.kasm.com --all -n <ns> --wait   # end live sessions first
kubectl delete agents.agent.kasm.com --all -n <ns> --wait
helm uninstall <release> -n <ns>
```

CRDs survive by design, whichever path installed them — the `kasm-agent-crds` templates carry
`helm.sh/resource-policy: keep`, and Helm never removes a `crds/` CRD. So do the control plane's
PersistentVolumeClaims. Delete both deliberately, and know that deleting a CRD cascades to every
custom resource of that kind in every namespace.
[The `keep` annotation](../../charts/kasm-agent-crds/README.md#the-keep-annotation) ·
[kasm-platform → Uninstall, in two steps](../../charts/kasm-platform/README.md#uninstall-in-two-steps).

If a cluster already has these CRDs from a `crds/`-directory install and you now want the Helm-owned
release, they have to be adopted first — label and annotate, then install:
[Adopting CRDs that Helm did not install](../../charts/kasm-agent-crds/README.md#adopting-crds-that-helm-did-not-install).
