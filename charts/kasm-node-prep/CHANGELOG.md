# Changelog

All notable changes to the kasm-node-prep chart are documented here.

## [Unreleased]

### Added

- Initial release: privileged DaemonSet that builds and loads the kernel modules Kasm Workspaces sessions depend on (v4l2loopback for webcam passthrough, WireGuard for older kernels), either compiling in-cluster (`method: build`, with airgapped/offline source support) or delegating the lifecycle to the Kernel Module Management operator (`method: kmm`).
- Adds node tuning: disabling swap and applying custom sysctls on matching nodes.
