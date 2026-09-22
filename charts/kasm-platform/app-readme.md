# Kasm Workspaces

Kasm Workspaces streams browsers, desktops and applications to users as isolated, disposable
container sessions, delivered through a web browser. This chart installs the whole stack in one
release: the control plane (`kasm-helm`: web UI, API, manager, session proxy, Guacamole, RDP
gateways, bundled PostgreSQL) and the Kubernetes agent (`kasm-agent`: the operator that runs
sessions as pods, its telemetry collector, the agent registration and its session proxy). Each half
has its own toggle, so the same chart installs a control plane alone, or an agent that registers
with a control plane elsewhere.

The form covers what an install cannot guess: the public hostname, how the control plane is
published (a LoadBalancer Service by default, or an Ingress; from Rancher the default is a NodePort
Service instead, because RKE2 ships no LoadBalancer implementation), the certificate, and the hostname
sessions are reached on. Everything else keeps the chart defaults and can be changed in the YAML
editor; the chart README is the full value reference.

**Before installing.** The agent installs CustomResourceDefinitions and cluster RBAC, so the
installing user needs cluster-owner rights on the target cluster; Rancher installs the
`kasm-agent-crds` chart first. Three optional features (kernel modules for webcam passthrough, the
video device plugin, per-session VPN egress) run privileged DaemonSets. Leave them off unless the
target namespace is exempt from Pod Security Admission; on RKE2 with a CIS profile that means a
namespace exemption. A system default registry configured on the cluster is honoured for every
Kasm image.

**After installing.** Sign in at `https://<public hostname>` as `admin@kasm.local`; the password is
in Secret `<release>-secrets`, key `admin-password`. The agent registers on its own; enable it in
the admin UI and authorize workspaces for a group, as the release notes printed after the install
describe.

Documentation: https://github.com/kasmtech/kasm-helm and https://kasm.com/docs
