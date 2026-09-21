# Kasm Workspaces Kubernetes Agent

The Kubernetes agent for Kasm Workspaces: it registers this cluster with a Kasm control plane and
runs user sessions as pods here. The chart installs the agent operator (its CustomResourceDefinitions
and cluster RBAC, and the controller that reconciles agents, sessions and image pullers), an
OpenTelemetry collector, the `Agent` resource with its session proxy, and, each off by default, the
cluster infrastructure some features need: kernel modules for webcam passthrough, the video device
plugin, per-session VPN egress, the NVIDIA GPU Operator, an rclone CSI driver for cloud storage
mappings, and an in-cluster NFS provisioner for persistent profiles.

Install it on its own when the control plane already exists: in another cluster, on virtual
machines, or hosted by Kasm. For a control plane and agent in one release, install the
`kasm-platform` chart instead.

The form asks for the three values the agent cannot guess: the manager hostname, the manager token
(from the control plane's `<release>-secrets` Secret, key `manager-token`), and the public hostname
sessions are reached on. Everything else keeps the chart defaults and can be changed in the YAML
editor; the chart README is the full value reference.

**Before installing.** The installing user needs cluster-owner rights on the target cluster; Rancher
installs the `kasm-agent-crds` chart first. The three privileged features (kernel modules, the video
device plugin, VPN egress) run privileged DaemonSets, so leave them off unless the target namespace
is exempt from Pod Security Admission. A system default registry configured on the cluster is
honoured for every Kasm image; the three third-party dependencies keep their own image values.

**After installing.** The agent registers on its own. Enable it in the control plane's admin UI and
authorize workspaces for a group, as the release notes printed after the install describe.

Documentation: https://github.com/kasmtech/kasm-helm and https://kasm.com/docs
