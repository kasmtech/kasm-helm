# Changelog

All notable changes to the kasm-platform chart are documented here.

## [Unreleased]

### Added

- Initial release: whole-stack umbrella chart composing `kasm-helm` (the control plane) and `kasm-agent` (the Kubernetes agent) into a single release, each half independently toggleable.
- Documents publishing in the README: the `oci://registry-1.docker.io/kasmweb/kasm-platform` target, the inside-out `make deps-agent` ordering that keeps the embedded `kasm-agent` from losing its own nine dependencies, and the enforcement of the Versioning section's lockstep rule by `make version-check-agent` (`scripts/agent_versions.py`) — including the `kasm-helm` pin, which goes stale on every control plane release.
