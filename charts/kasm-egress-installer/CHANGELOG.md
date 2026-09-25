# Changelog

All notable changes to the kasm-egress-installer chart are documented here.

## [Unreleased]

### Fixed

- The ClusterRole no longer grants `get` on `nodes` and `services`. The daemon only ever reads a session's own pod (its egress annotation, and a sibling container's env for the manager address); the node and service lookups the grant covered had no callers and are gone from the daemon, so the grant is `pods` alone now.
- `containerdConfigPaths` and `containerdConfigDirs` covered only k3s and RKE2, so on kubeadm and most managed distributions the daemon never saw `/etc/containerd/config.toml`; both lists now include the standard containerd paths. `appVersion` was `latest`, which resolved the default image to a floating tag; it follows the agent family's `develop` now.

### Changed

- The default `image.repository` is `kasmweb/egress-daemon` (was `kasmweb/kasm-egress-daemon`); the monorepo apps dropped their `kasm-` prefix, and the image names follow the app names.
- The daemon image is built on Wolfi instead of `debian:12-slim`, which carried four critical and 65 high-severity CVEs with no Debian fix; the Wolfi packages carry none. OpenVPN moves from 2.6.14 to 2.7.7, and `wg-quick`'s `iptables-restore` calls use the nf_tables backend, as they did on Debian. The arm64 image now carries arm64 binaries; it previously shipped the amd64 ones.
- The daemon image bundles Ziti CLIs 2.0.6, 1.6.21 and 1.5.18 (was 2.0.0-pre7, 1.6.14 and 1.5.12), the newest stable release on each line. The old binaries carried three critical `rabbitmq/amqp091-go` CVEs and around 140 high-severity ones in older Go dependencies; the new ones have none.
- `cniBinDir` now derives from a `distro` preset (`k3s` default -> `/var/lib/rancher/k3s/data/cni`, `vanilla` -> `/opt/cni/bin`) when left empty, instead of hardcoding `/opt/cni/bin`. The old default was wrong for k3s: the shim installed where the k3s runtime never reads plugins, so it was silently never invoked (pods got no egress tunnel, with no error). An explicit `cniBinDir` still overrides the preset; an unrecognized `distro` fails rendering rather than guessing a path.
- README states the two security findings plainly, without the references to an unmerged branch and to a file in another repository; the first section links the docs index. The HTML values-table template moved to the shared `_templates.gotmpl`.

### Added

- Rancher catalog packaging: `catalog.cattle.io/*` annotations in `Chart.yaml` (display name, release name, version gates), a top-level `kubeVersion`, `app-readme.md` for the chart tile and `questions.yaml` for the install form. `make rancher-check` verifies them. Every other Helm client ignores all three.
- `global.cattle.systemDefaultRegistry`: when set, it replaces the registry part of every image the chart renders and the per-image `registry` values are ignored, following Rancher's convention for the system default registry it injects on air-gapped clusters. Empty by default, so nothing changes outside Rancher.
- Initial release: a privileged DaemonSet running Kasm's own egress daemon (built from `apps/kasm-egress-daemon` in kasm-monorepo, bundling the `kasm-egress-cni` shim it self-installs onto the host) that chains a CNI plugin into every node's active CNI conflist and brings up per-session OpenVPN, WireGuard, or Ziti tunnels on request. Ported from `kasm-kubernetes-operator`'s unmerged `feature/DEV-228-k8s-agent-egress` branch — see `docs/egress-installer-port-notes.md` in kasm-monorepo for the review this port was based on, including the reviewed risk profile. Lifecycle: graceful shutdown/uninstall restores patched conflists from backup and removes the shim; a hard crash leaves the chain patched until the replacement pod re-installs it. The remaining risk is the no-daemon window, where the chained shim fails CNI ADD on that node.
- Wired in as an optional `kasm-agent` dependency (`egressInstaller.enabled`, off by default). `hostNetwork`/`hostPID`/`privileged` are load-bearing (arbitrary-namespace `nsenter`, `mknod`, iptables/route manipulation), so this trips the repo's `kasm-disallow-host-namespaces` Kyverno policy by design. Resolved the same way `nodePrep` resolves the PSS-baseline conflict: enabled via `tests/values-agent/infra.yaml`, which renders to `.rendered-infra/` and is deliberately excluded from the Kyverno gate — not via a Kyverno `PolicyException`, since this repo has no such mechanism and none was introduced for this.
