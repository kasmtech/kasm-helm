# Kasm Agent CRDs

The five CustomResourceDefinitions the Kasm agent operator owns (`agents`, `kasmworkspaces` and
`kasmimagepullers` in `agent.kasm.com`; `warmpools` and `warmpoolinstances` in `pools.kasm.ai`),
and nothing else. Rancher installs this chart automatically before `kasm-agent` or `kasm-platform`
and upgrades it with them, so CRD schema changes arrive through Helm rather than through a manual
`kubectl apply`. It has no values.

The CRDs carry the `helm.sh/resource-policy: keep` annotation: uninstalling this release leaves them
(and every Agent, session and image-puller object) in place. Remove them by hand only after the
agent releases that use them are gone.

Documentation: https://github.com/kasmtech/kasm-helm
