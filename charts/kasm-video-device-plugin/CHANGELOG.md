# Changelog

All notable changes to the kasm-video-device-plugin chart are documented here.

## [Unreleased]

### Fixed

- The plugin stops at once on SIGTERM (image fix). It used to wait on kubelet's open `ListAndWatch` stream until killed at the end of the grace period, so every rollout left the resource at zero for 30s per node.

### Changed

- The default `image.repository` is `kasmweb/video-device-plugin` (was `kasmweb/kasm-video-device-plugin`); the monorepo apps dropped their `kasm-` prefix, and the image names follow the app names.
- `appVersion` is `develop` rather than `latest`, so the device plugin image defaults to `kasmweb/kasm-video-device-plugin:develop` like every other chart in this family — it was the only one resolving to a floating `latest`, which also disagreed with the tag CI publishes. `image.tag` still overrides it to pin a specific build.
- README no longer names a source path in another repository; the first section links the docs index. The HTML values-table template moved to the shared `_templates.gotmpl`.

### Added

- A `dri` plugin publishes its node's GPUs and what each can do (the `kasm.com/dri-devices` annotation and `kasm.com/dri.dri3|egl|vaapi|vulkan` labels) for the agent to report to the Kasm manager and place sessions by. The chart grants it `get`/`patch` on Nodes and mounts its token, in `dri` mode only. `driCapabilities` overrides the by-driver capability rule.
- `deviceKind: dri` advertises GPU render nodes (`/dev/dri/renderD*`) instead of `/dev` entries: a container allocated one gets the render node, its card node and `allocateEnvVar` set to the render node. `deviceShares` advertises each device that many times so several containers share it, placing each on the device with the most shares free; `driDevicePlugin` in `kasm-agent` is this chart set up that way. `driDrivers` limits `dri` to GPUs bound to the listed kernel drivers. Unset, the webcam plugin renders as before.
- The DaemonSet runs under a ServiceAccount of its own (`serviceAccount.create`, on by default; `serviceAccount.name` to use an existing one) instead of the namespace's `default` account, so cluster policy can be granted to this workload alone. `openshift.scc.enabled` grants that account the built-in `privileged` SCC (`openshift.scc.name`) through a ClusterRole holding `use` on it and a namespaced RoleBinding, the way `oc adm policy add-scc-to-user` does; OpenShift's `restricted-v2` otherwise refuses this privileged DaemonSet and its `/dev` and kubelet device-plugin mounts. Off by default, and rendered only where the DaemonSet is.
- `global.cattle.systemDefaultRegistry`: when set, it replaces the registry part of every image the chart renders and the per-image `registry` values are ignored, following Rancher's convention for the system default registry it injects on air-gapped clusters. Empty by default, so nothing changes outside Rancher.
- Initial release: a DaemonSet running Kasm's own video-device-plugin that advertises each node's v4l2loopback video devices as the extended resource `kasm.com/video`, so Kasm Workspaces sessions with webcam support can request it and have kubelet assign a dedicated `/dev/video*` device.
