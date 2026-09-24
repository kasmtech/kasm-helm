# Session environment: Docker agent vs Kubernetes

> **Applies to:** agent

The manager computes a session's environment once and hands the same set to whichever agent runs
it. A Docker agent passes it to `docker run -e`; the Kubernetes operator translates it into the pod
spec. This page is what survives that translation, and what the operator adds. Which Kasm features
work on Kubernetes at all is in [What works on Kubernetes](../reference/feature-matrix.md).

**Nothing is dropped in translation** - all 25 manager-computed variables (`KASM_API_HOST`,
`KASM_API_JWT`, `KASM_ID`, the `KASM_SVC_*` feature flags, `VNC_PW`, `VNC_RESOLUTION`, `PROXYPATH`,
locale and `TZ`) appear unchanged in the pod. The operator **adds** twelve the manager never sends:

| Variable | Value | Why |
| -------- | ----- | --- |
| `XDG_RUNTIME_DIR` | `/tmp/runtime-kasm-user` | writable paths - a session pod cannot assume a writable `$HOME` or `/run` the way a Docker container can |
| `XDG_CACHE_HOME` | `/tmp/.cache` | " |
| `XDG_CONFIG_HOME` | `/home/kasm-user/.config` | " |
| `XDG_DATA_HOME` | `/home/kasm-user/.local/share` | " |
| `TMPDIR` | `/tmp` | " |
| `PULSE_RUNTIME_PATH` | `/var/run/pulse` | audio socket location |
| `DBUS_SESSION_BUS_ADDRESS` | `unix:path=/dev/null` | stops clients trying to spawn a session bus |
| `FONTCONFIG_PATH` | `/etc/fonts` | font discovery |
| `LIBGL_ALWAYS_SOFTWARE` | `1` | software rendering - **relevant to GPU workspaces**, where a Docker agent with passthrough would not want it |
| `NO_AT_BRIDGE` | `1` | quiets the accessibility bridge |
| `BREAKPAD_DISABLE` | `1` | quiets crash reporting |
| `STOP_TIMEOUT_SECONDS` | `300` | graceful termination window |

Measured on a live session by comparing `kasms.docker_environment` (what the manager computed)
against the running pod's environment. What this does not rule out is a Docker agent adding
variables of its own beyond the manager's set - that would need a `docker inspect` on a
Docker-agent session to confirm.

## Who the session runs as

| | Docker agent | Kubernetes |
| --- | --- | --- |
| Session user | `kasm-user`, uid 1000, the image's own `USER` | `kasm-user`, uid 1000: `runAsNonRoot`, no privilege escalation, `drop: ALL` plus the profile's capabilities (`agent.workspaceSecurity.profile`) |
| Root when an image asks for it (`user: root` run config) | the container runs as root on the host | host root by default, as on Docker (`rootMode: host`), uid 0 inside a pod user namespace with `rootMode: userns`, refused with `forbid`; the pod's `kasm.com/run-mode` label says which |
| Root `exec_configs` (start and stop commands with `user: root`) | `docker exec -u root` into the running uid-1000 container | no equivalent exec as another user: the session is promoted to a root run mode (`rootFeatures: promote`, the default), kept at uid 1000 with the commands run as `kasm-user` (`downgrade`), or refused (`reject`) |
| Session recording | the recorder switches to its own user inside the container | needs root the same way, so it follows `rootFeatures` too |
| `sudo` inside the session | works if the image's sudoers allows it | only with `agent.workspaceSecurity.sudo` (escalation and `SETUID`/`SETGID` back on) |
| Device groups (`/dev/dri`, `/dev/video*`) | `group_add` in the run config | the run config's `group_add`, plus `agent.workspaceSecurity.supplementalGroups` Agent-wide |

The reasons and the Pod Security level each mode reaches are in
[Security posture](security-posture.md#session-run-identity).
