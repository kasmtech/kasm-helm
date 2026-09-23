# Changelog

All notable changes to the kasm-video-device-plugin chart are documented here.

## [Unreleased]

### Changed

- README no longer names a source path in another repository; the first section links the docs index. The HTML values-table template moved to the shared `_templates.gotmpl`.

### Added

- The DaemonSet runs under a ServiceAccount of its own (`serviceAccount.create`, on by default; `serviceAccount.name` to use an existing one) instead of the namespace's `default` account, so cluster policy can be granted to this workload alone. `openshift.scc.enabled` grants that account the built-in `privileged` SCC (`openshift.scc.name`) through a ClusterRole holding `use` on it and a namespaced RoleBinding, the way `oc adm policy add-scc-to-user` does; OpenShift's `restricted-v2` otherwise refuses this privileged DaemonSet and its `/dev` and kubelet device-plugin mounts. Off by default, and rendered only where the DaemonSet is.
- `global.cattle.systemDefaultRegistry`: when set, it replaces the registry part of every image the chart renders and the per-image `registry` values are ignored, following Rancher's convention for the system default registry it injects on air-gapped clusters. Empty by default, so nothing changes outside Rancher.
- Initial release: a DaemonSet running Kasm's own video-device-plugin that advertises each node's v4l2loopback video devices as the extended resource `kasm.com/video`, so Kasm Workspaces sessions with webcam support can request it and have kubelet assign a dedicated `/dev/video*` device.
