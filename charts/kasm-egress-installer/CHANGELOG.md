# Changelog

All notable changes to the kasm-egress-installer chart are documented here.

## [Unreleased]

### Changed

- `cniBinDir` now derives from a `distro` preset (`k3s` default -> `/var/lib/rancher/k3s/data/cni`, `vanilla` -> `/opt/cni/bin`) when left empty, instead of hardcoding `/opt/cni/bin`. The old default was wrong for k3s: the shim installed where the k3s runtime never reads plugins, so it was silently never invoked (pods got no egress tunnel, with no error). An explicit `cniBinDir` still overrides the preset; an unrecognized `distro` fails rendering rather than guessing a path.

### Added

- Initial release: a privileged DaemonSet running Kasm's own egress daemon (built from `apps/kasm-egress-daemon` in kasm-monorepo, bundling the `kasm-egress-cni` shim it self-installs onto the host) that chains a CNI plugin into every node's active CNI conflist and brings up per-session OpenVPN, WireGuard, or Ziti tunnels on request. Ported from `kasm-kubernetes-operator`'s unmerged `feature/DEV-228-k8s-agent-egress` branch — see `docs/egress-installer-port-notes.md` in kasm-monorepo for the review this port was based on, including the reviewed risk profile. Lifecycle verified live on k3s: graceful shutdown/uninstall restores patched conflists from backup and removes the shim; a hard crash leaves the chain patched until the replacement pod re-installs it. The remaining risk is the no-daemon window, where the chained shim fails CNI ADD on that node.
- Wired in as an optional `kasm-agent` dependency (`egressInstaller.enabled`, off by default). `hostNetwork`/`hostPID`/`privileged` are load-bearing (arbitrary-namespace `nsenter`, `mknod`, iptables/route manipulation), so this trips the repo's `kasm-disallow-host-namespaces` Kyverno policy by design. Resolved the same way `nodePrep` resolves the PSS-baseline conflict: enabled via `tests/values-agent/infra.yaml`, which renders to `.rendered-infra/` and is deliberately excluded from the Kyverno gate — not via a Kyverno `PolicyException`, since this repo has no such mechanism and none was introduced for this.
