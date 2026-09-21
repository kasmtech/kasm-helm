# Kasm Egress Installer

A privileged DaemonSet for clusters that run Kasm Workspaces sessions. On every node it chains a
CNI shim into the active CNI configuration and runs a daemon that, on request from the Kasm agent,
brings up an OpenVPN, WireGuard or Ziti tunnel inside a session's network namespace, so that one
session's traffic leaves through a VPN while its neighbours' does not.

It is also a dependency of the `kasm-agent` chart (`egressInstaller.enabled`). Install it on its own
when a platform team reviews and rolls out node-level components separately from the agent.

**Read before installing.** The container is privileged and shares the node's PID and network
namespaces, which no Pod Security Standard permits: the target namespace must be exempt from Pod
Security Admission, and on RKE2 with a CIS profile that means a namespace exemption. Once the shim
is chained in, every pod sandbox created on that node fails while no daemon is running, so plan the
rollout and the uninstall. The form asks which distribution's CNI plugin directory to install into;
on RKE2 set the directory explicitly.

Documentation: https://github.com/kasmtech/kasm-helm
