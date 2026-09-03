# Changelog

All notable changes to the kasm-video-device-plugin chart are documented here.

## [Unreleased]

### Added

- Initial release: a DaemonSet running Kasm's own video-device-plugin (built from `apps/kasm-video-device-plugin` in kasm-monorepo) that advertises each node's v4l2loopback video devices as the extended resource `kasm.com/video`, so Kasm Workspaces sessions with webcam support can request it and have kubelet assign a dedicated `/dev/video*` device.
