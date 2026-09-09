# Changelog

All notable changes to the kasm-platform chart are documented here.

## [Unreleased]

### Fixed

- NOTES.txt was wrong for the chart's own defaults. It printed the agent's manager hostname, token source and session hostname as `unset` while `inClusterControlPlane` derives all three, and its "auth domain" and "zone must use direct connections" steps would break the default relayed topology if followed. It now branches on the topology in use: the relayed default gets a "nothing more to configure" section carrying the recipe for switching to direct connections, and direct-connect installs keep the auth-domain and zone checks. It also covers how to reach the control plane when `publicAddr` is unset (the assigned LoadBalancer address or node:port read back with `lookup` from the first `helm upgrade` on, else the `kubectl` command or a port-forward), which accounts are seeded and where every generated credential lives, the two manual admin steps after the agent registers, and warns when the derived wiring cannot match the control plane (`kasm-helm.enabled=false`, a custom `kasmSecrets.name`, `kasmZones` without a zone named `default`, or an agent zone the control plane does not define). The self-signed certificate warning no longer repeats itself.

### Added

- A default install of this chart now needs **no values at all**: it wires the agent to the control plane in the same release (`kasm-agent.agent.inClusterControlPlane`, plus the in-cluster manager port and scheme and the session proxy's own port), and both halves fall back to generated self-signed certificates. Previously the render failed on three agent values with no defaults, and even once past that the pods waited on TLS Secrets nothing created. Every derived value is an ordinary default that an explicit setting overrides, and NOTES.txt warns whenever a generated certificate is in play.

- Initial release: whole-stack umbrella chart composing `kasm-helm` (the control plane) and `kasm-agent` (the Kubernetes agent) into a single release, each half independently toggleable.
- Documents publishing in the README: the `oci://registry-1.docker.io/kasmweb/kasm-platform` target, the inside-out `make deps-agent` ordering that keeps the embedded `kasm-agent` from losing its own nine dependencies, and the enforcement of the Versioning section's lockstep rule by `make version-check-agent` (`scripts/agent_versions.py`) — including the `kasm-helm` pin, which goes stale on every control plane release.
