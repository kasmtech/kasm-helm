# The charts

> **Applies to:** both halves

Ten charts. Four are published to `oci://registry-1.docker.io/kasmweb/<chart>` and installed by
name; the other six are subcharts of `kasm-agent`, configured through it and never published on
their own. Each README is that chart's value reference, generated from its `values.yaml`.

| Chart | Install it? | One line | Values reference |
| ----- | ----------- | -------- | ---------------- |
| `kasm-platform` | Yes, published | The whole stack in one release: `kasm-helm` plus `kasm-agent`, each half switchable with `kasm-helm.enabled` / `kasm-agent.enabled` | [charts/kasm-platform/README.md](../../charts/kasm-platform/README.md) |
| `kasm-helm` | Yes, published, also at `https://helm.kasm.com` | The control plane: web UI, manager and API, proxy, Guacamole, RDP gateways, bundled PostgreSQL. Creates no cluster-scoped objects | [charts/kasm-helm/README.md](../../charts/kasm-helm/README.md) |
| `kasm-agent` | Yes, published | The Kubernetes agent umbrella: nine dependencies, six Kasm subcharts (aliased `operator`, `otelCollector`, `agent`, `nodePrep`, `videoDevicePlugin`, `egressInstaller`) and three third-party ones (`csiRclone`, `gpuOperator`, `nfs-server-provisioner`) | [charts/kasm-agent/README.md](../../charts/kasm-agent/README.md) |
| `kasm-agent-crds` | Yes, published, as its own release first | The five CRDs as Helm-owned templates, for fleets that upgrade CRDs with Helm. No values | [charts/kasm-agent-crds/README.md](../../charts/kasm-agent-crds/README.md) |
| `kasm-egress-installer` | Yes, published; normally via `kasm-agent.egressInstaller.*` | Privileged DaemonSet chaining a CNI shim into every node for per-session OpenVPN, WireGuard or Ziti egress. Off by default | [charts/kasm-egress-installer/README.md](../../charts/kasm-egress-installer/README.md) |
| `kasm-agent-operator` | No, subchart (`operator.*`) | The controller, the CRDs in its `crds/` directory and cluster RBAC. One per cluster | [charts/kasm-agent-operator/README.md](../../charts/kasm-agent-operator/README.md) |
| `kasm-agent-instance` | No, subchart (`agent.*`) | The `Agent` resource, the session proxy the operator creates for it, and the exposure options | [charts/kasm-agent-instance/README.md](../../charts/kasm-agent-instance/README.md) |
| `kasm-otel-collector` | No, subchart (`otelCollector.*`) | The OpenTelemetry collector the operator, agent and sessions report to; exports OTLP and/or ClickHouse | [charts/kasm-otel-collector/README.md](../../charts/kasm-otel-collector/README.md) |
| `kasm-node-prep` | No, subchart (`nodePrep.*`) | Privileged DaemonSet that builds and loads kernel modules (`v4l2loopback`, WireGuard) and applies node tuning. Off by default | [charts/kasm-node-prep/README.md](../../charts/kasm-node-prep/README.md) |
| `kasm-video-device-plugin` | No, subchart (`videoDevicePlugin.*`) | Advertises `/dev/video*` as the schedulable resource `kasm.com/video` for webcam sessions. Off by default | [charts/kasm-video-device-plugin/README.md](../../charts/kasm-video-device-plugin/README.md) |

Which combination to install is [Deployment topologies](../explanation/topologies.md); how they
depend on one another is [Architecture](../explanation/architecture.md); how they are packaged
and pushed is [Publish the charts](../how-to/publish-charts.md). Each published chart also carries
the three files Rancher's Apps catalog reads (`catalog.cattle.io/*` annotations, `app-readme.md`,
`questions.yaml`); installing from there is [Install from the Rancher catalog](../how-to/install/rancher.md).
