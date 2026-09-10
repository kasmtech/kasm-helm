# Changelog

All notable changes to the kasm-node-prep chart are documented here.

## [Unreleased]

### Changed

- README trimmed to reference: the KMM Mode A/B runbook, the Secure Boot walkthrough, the swap kubelet prose and the builder-image Dockerfile now link their how-to pages, while the decision table, the registry rule, the safety check, sizing/force/zram, sysctls and the `sourcePath` semantics stay. `helm template` runs against the local chart, since this chart is not published; the KMM version is whatever `KMM_VERSION` pins in the Makefile. The HTML values-table template moved to the shared `_templates.gotmpl`.

### Fixed

- **Security:** chart values were interpolated into the reconcile script (a root shell in a privileged DaemonSet on every node) and into the KMM build Dockerfile without shell quoting, so a crafted `modules.*.sourceRepo`, `sourceRef`, `sourcePath`, `tuning.swap.hostPath` or `tuning.sysctls.values` entry was executed as code. Every such value is now single-quoted with embedded quotes escaped, and sysctl keys and values are validated at render time.
- **Security:** a `modules.*.sourceRepo` URL carrying `user:password@` was stored verbatim in the script ConfigMap and printed by the clone log line on every reconcile pass. Such URLs are now rejected at render time; the clone log and error lines strip any userinfo regardless.

### Added

- `modules.v4l2loopback.sourceRepoSecret` / `modules.wireguard.sourceRepoSecret`: an existing Secret (keys `username`, `password`) whose login the script hands to git through a credential helper, never through the URL (`method: build` only).
- `imagePullSecrets` for the DaemonSet, so the builder image can come from a private registry — the air-gapped path the `image.*` comments describe.

- Initial release: privileged DaemonSet that builds and loads the kernel modules Kasm Workspaces sessions depend on (v4l2loopback for webcam passthrough, WireGuard for older kernels), either compiling in-cluster (`method: build`, with airgapped/offline source support) or delegating the lifecycle to the Kernel Module Management operator (`method: kmm`).
- Adds node tuning: disabling swap and applying custom sysctls on matching nodes.
