# Changelog

All notable changes to the kasm-video-device-plugin chart are documented here.

## [Unreleased]

### Changed

- README no longer names a source path in another repository; the first section links the docs index. The HTML values-table template moved to the shared `_templates.gotmpl`.

### Added

- `global.cattle.systemDefaultRegistry`: when set, it replaces the registry part of every image the chart renders and the per-image `registry` values are ignored, following Rancher's convention for the system default registry it injects on air-gapped clusters. Empty by default, so nothing changes outside Rancher.
- Initial release: a DaemonSet running Kasm's own video-device-plugin that advertises each node's v4l2loopback video devices as the extended resource `kasm.com/video`, so Kasm Workspaces sessions with webcam support can request it and have kubelet assign a dedicated `/dev/video*` device.
