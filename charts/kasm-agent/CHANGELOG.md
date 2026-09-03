# Changelog

All notable changes to the kasm-agent chart are documented here.

## [Unreleased]

### Added

- Initial release: umbrella chart for the Kasm Workspaces Kubernetes agent stack, composing the operator, telemetry collector, agent instance, node prep, and video device plugin subcharts, plus optional third-party cluster infrastructure (`csi-driver-rclone`, `gpu-operator`, `nfs-server-provisioner`).
- Adds baseline namespace `NetworkPolicies` (`networkPolicies.enabled`) for the agent stack and a cluster preparation checklist (GPU support, persistent-profile storage, workspace network isolation) documented in the README.
- Adds the `kasm-egress-installer` subchart as an optional dependency (`egressInstaller.enabled`, off by default) for per-session OpenVPN/WireGuard/Ziti egress routing.
- Documents publishing in the README: the `oci://registry-1.docker.io/kasmweb/` target, which four of the ten charts are published standalone and why the other five are not, the inside-out `make deps-agent` ordering that packaging depends on, the `file://` pin lockstep rule enforced by `make version-check-agent` (`scripts/agent_versions.py`), and the `FORCE_REPUBLISH` guard on re-pushing a preview version.
