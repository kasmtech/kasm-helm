# Changelog

All notable changes to the kasm-agent-crds chart are documented here.

## [Unreleased]

### Added

- Initial release: ships the same five CustomResourceDefinitions as `charts/kasm-agent-operator/crds/` (agents, kasmworkspaces, and kasmimagepullers in the `agent.kasm.com` group; warmpools and warmpoolinstances in `pools.kasm.ai`) as ordinary Helm templates, so a release of this chart owns their lifecycle and `helm upgrade` applies schema changes — a hybrid alternative to the operator chart's bundled `crds/` install-time copy.
