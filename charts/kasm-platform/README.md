# kasm-platform

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: develop](https://img.shields.io/badge/AppVersion-develop-informational?style=flat-square)

The complete Kasm Workspaces stack for Kubernetes: the control plane and the Kubernetes agent in one release, each independently switchable

**Homepage:** <https://kasm.com>

A Kasm Workspaces deployment has two halves. The **control plane** is what users log in to: the web
UI, the manager and API services, the session proxy, Guacamole, the RDP gateways, and the database.
The **agent** is what runs sessions: an operator, an `Agent` custom resource, and a session proxy.
Each half has a chart of its own, `kasm-helm` and `kasm-agent`, and each installs on its own.

This chart installs both as one release, with either half switchable off, and wires the agent to
the control plane beside it so that a default install needs no values at all. It adds no machinery
of its own: no hook Jobs, nothing that reaches into a running deployment.

This page is the chart reference. The [documentation index](../../docs/README.md) has the tutorial,
the how-to guides and the explanations; [Get started](../../docs/tutorials/get-started.md) is the
no-values install, end to end.

## What this chart installs

Neither dependency is aliased, so each keeps its own chart name as its values key and every value
either chart documents is set here nested under that key.

| Key | Chart | Default | What it is |
| --- | ----- | ------- | ---------- |
| `kasm-helm` | `kasm-helm` | enabled | The Kasm Workspaces control plane: web UI, manager/API, session proxy, Guacamole, RDP gateways, PostgreSQL. |
| `kasm-agent` | `kasm-agent` | enabled | The Kubernetes agent umbrella: agent operator, OpenTelemetry collector, `Agent` resource and its session proxy, plus the optional per-feature cluster infrastructure. |

On top of those, this chart owns exactly one thing of its own: an `extraObjects` escape hatch.

### The toggle matrix

| `kasm-helm.enabled` | `kasm-agent.enabled` | What you get |
| --- | --- | --- |
| `true` | `true` | The full stack in one release. The default, and what the quickstart below installs. |
| `true` | `false` | Control plane only, identical to installing `kasm-helm` on its own. Use it when agents live in other clusters, or are VM agents, or are added later; they register with `kasm-helm.publicAddr` and the `manager-token` key of Secret `<release>-secrets`. |
| `false` | `true` | Agent only, identical to installing `kasm-agent` on its own, for a second agent cluster registering with a manager that already exists (another cluster, a VM deployment, a Kasm-hosted one). Set `kasm-agent.agent.inClusterControlPlane: false` and give the manager hostname, a token and `publicHostname` explicitly. |
| `false` | `false` | Nothing but `extraObjects`. |

Because neither dependency is aliased, the dependencies *inside* `kasm-agent` keep their own
aliases and conditions, and those stay reachable from the top: `kasm-agent.operator.enabled`,
`kasm-agent.nodePrep.enabled`, `kasm-agent.gpuOperator.enabled`, and so on all work from a
top-level values file.

The operator's five CustomResourceDefinitions arrive with the install, from the operator chart's
`crds/` directory: created once, never upgraded by a later `helm upgrade`. To put them under Helm's
control instead, install the [`kasm-agent-crds`](../kasm-agent-crds) chart as its own release
**before** this one and upgrade it first thereafter. See [Install the CRDs](../../docs/how-to/install/crds.md).

## Quickstart: the relayed default

Install with no values:

```console
helm install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
  --version 0.1.0 -n kasm --create-namespace --timeout 20m
```

The `--timeout 20m` covers database initialization and the first image pulls on a cold cluster.

What comes up is the **relayed** topology: browsers talk only to the control plane, and its proxy
reaches the session proxy inside the cluster at `<agent>-session-proxy.<namespace>.svc.cluster.local:4444`.
`kasm-agent.agent.inClusterControlPlane: true`, this chart's default, derives the three values the
agent cannot otherwise guess from the control plane in the same release:

| Derived value | From |
| --- | --- |
| `kasm-agent.agent.manager.hostname` | `<release>-proxy-default.<namespace>.svc.cluster.local`, port 8080, http |
| the manager token | Secret `<release>-secrets`, key `manager-token` |
| `kasm-agent.agent.publicHostname` | `<agent name>-session-proxy.<namespace>.svc.cluster.local` |

No auth domain, no zone change, no second hostname and no trusted certificate is needed. Both halves
generate a self-signed TLS Secret (`<release>-cert-manager` and `kasm-session-proxy-tls`); a Secret
of either name that already exists is used as-is, so pre-create your own before the first install to
bring your own certificate.

Find the control plane's address. The proxy Service is a `LoadBalancer` by default; the install
NOTES print this command on the first install and the real `https://` URL from the first
`helm upgrade` on:

```console
kubectl get svc -n kasm kasm-proxy-ext-default
```

Sign in as `admin@kasm.local` with the password in the credentials Secret (`user@kasm.local` and
`user-password` are the non-admin pair):

```console
kubectl get secret -n kasm kasm-secrets -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Two admin steps remain, which no chart can make: **Infrastructure** → the new agent → **Enable**
(agents register disabled; the manager setting `auto_agent`, "Automatically Enable Agents", skips
this click, see [Enable agents automatically](../../docs/how-to/enable-agents-automatically.md)),
and **Workspaces** → the image → assign it to a group.

### A hostname and a real certificate

Give the control plane its public hostname, and optionally a `kubernetes.io/tls` Secret created
before the first install:

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  certificate:
    secretName: kasm-tls   # omit to keep the generated self-signed certificate
```

To publish it through an Ingress, a Gateway API route or an OpenShift Route instead of the
LoadBalancer Service, see the exposure table in the
[`kasm-helm` README](../kasm-helm/README.md#publishing-kasm-outside-the-cluster) and the networking
how-to guides, starting with [Ingress](../../docs/how-to/networking/ingress.md).

### Verify

```console
kubectl get pods -n kasm
kubectl get agents.agent.kasm.com -n kasm   # PHASE reaches Ready once the manager accepts the agent
```

### Switching to direct connections

Relayed sends every session byte through the control plane's proxy. Direct connections let
browsers reach the session proxy on its own hostname, which is what `kasm-agent.agent.ingress`,
`httpRoute`, `route`, `tlsRoute`, `gatewayRoute` and `sessionProxy.service` publish. That takes a
second hostname under the same parent domain as `publicAddr`, the zone switched to
`proxy_connections: false` with `upstream_auth_address`, and `kasm-helm.kasmConfig.authDomain` set
to the parent domain (a preseed value on a fresh install; the admin UI on an existing database).
See [Switch to direct connections](../../docs/how-to/networking/direct-connect.md), and
[Topologies](../../docs/explanation/topologies.md) for what each topology fixes.

### Namespace requirements

No namespace label is required for sessions. The operator's per-workspace NetworkPolicy admits the
session proxy **by podSelector**, and all session and manager traffic flows through it. Label the
namespace `kasm.com/role=manager` only if something in it genuinely needs *direct* ingress to
workspace pods; neither chart sets the label.

If `kasm-agent.nodePrep`, `kasm-agent.videoDevicePlugin` or `kasm-agent.egressInstaller` is
enabled, the namespace has to permit the `privileged` Pod Security Standard, which in this shared
namespace then covers the control-plane pods too. `egressInstaller` asks for more: its DaemonSet
runs with `hostPID: true` and `hostNetwork: true`, so an admission policy that blanket-disallows
host namespaces rejects it even in a `privileged` namespace. See
[Privileged workloads](../../docs/how-to/nodes/privileged-workloads.md), and the
[`kasm-egress-installer` README](../kasm-egress-installer/README.md) before enabling that one.

```console
kubectl label namespace kasm pod-security.kubernetes.io/enforce=privileged --overwrite
```

For the **two-namespace** layout (control plane and agent as separate releases, with the umbrella's
NetworkPolicies enforced) see [Install in two namespaces](../../docs/how-to/install/two-namespaces.md).

## Going deeper

This chart is a composition, so almost every question about it is really a question about one of
its two dependencies:

* **[`charts/kasm-helm/README.md`](../kasm-helm/README.md)**: every value under `kasm-helm:`,
  sizing, ingress and routes, certificates, the database (in-cluster or external), backups, the
  preseed, trusted CA bundles, OpenShift.
* **[`charts/kasm-agent/README.md`](../kasm-agent/README.md)**: every value under `kasm-agent:`,
  the cluster preparation checklist, and the registry override block for a private registry.
* The how-to guides for what sits between the two:
  [Install in two namespaces](../../docs/how-to/install/two-namespaces.md),
  [Switch to direct connections](../../docs/how-to/networking/direct-connect.md),
  [Node tuning and swap](../../docs/how-to/nodes/tuning-and-swap.md),
  [Webcam kernel modules](../../docs/how-to/nodes/webcam-kernel-modules.md) and
  [Registries and airgap](../../docs/how-to/registries-and-airgap.md).

## Versioning

The two dependencies are pinned to exact versions in `Chart.yaml`. `kasm-helm` is versioned on its
own release cadence, so **when the control plane chart's version is bumped, the `kasm-helm`
dependency version here has to be bumped in lockstep**, and `helm dependency update
charts/kasm-platform` run to refresh `Chart.lock`. Without both, `helm dependency build` fails to
resolve the local dependency.

## Uninstall, in two steps

`helm uninstall` deletes the `Agent` custom resources and the operator that clears their finalizers
at the same time. If the operator goes first, the deletions hang — or worse, a later operator
install processes the stale deletion and tears down a live agent. Always delete the custom
resources first and let the operator clean them up:

```console
# End any live sessions first — KasmWorkspace resources carry an operator-cleared finalizer too.
kubectl delete kasmworkspaces.agent.kasm.com --all -n kasm --wait
kubectl delete agents.agent.kasm.com --all -n kasm --wait
helm uninstall kasm -n kasm
```

The control plane's PersistentVolumeClaims (the database, and any backup volume) are not removed by
`helm uninstall`. Delete them deliberately, once you are sure.

Upgrade, backup and restore, and the full uninstall procedure are [Day 2 operations](../../docs/how-to/day-2.md).

## Publishing

See [Publish the charts](../../docs/how-to/publish-charts.md).

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://../kasm-agent | kasm-agent | 0.1.0 |
| file://../kasm-helm | kasm-helm | 1.1190.7 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| extraObjects | list | `[]` | Deploy additional Kubernetes manifests alongside this release. This field is expected to be either a list of strings or a list of objects. Each entry is rendered through `tpl`, so Helm templating may be used inside it.  |
| kasm-agent | object | `{"agent":{"inClusterControlPlane":true},"enabled":true}` | The Kasm Kubernetes agent (the `kasm-agent` umbrella chart). The agent operator, the OpenTelemetry collector, the `Agent` custom resource and its session proxy, and the optional per-feature cluster infrastructure.  ALL of that chart's values nest under this key, its own aliased subcharts included, so its subchart conditions stay reachable from here (`kasm-agent.operator.enabled`, `kasm-agent.nodePrep.enabled`, `kasm-agent.gpuOperator.enabled`, ...). This chart adds only `enabled` and restates nothing else. For example, the three values the agent cannot be installed without are set from here as:    kasm-agent:     agent:       manager:         hostname: kasm.example.com         token: "<the control plane's manager-token>"       publicHostname: sessions.example.com  See `charts/kasm-agent/README.md` for the full value reference, and its "Running alongside the kasm-helm control plane" section for what has to line up between the two halves.  |
| kasm-agent.enabled | bool | `true` | Install the Kasm Kubernetes agent with this release. Set to false to install only the control plane, and add agents (Kubernetes or otherwise) separately.  |
| kasm-helm | object | `{"enabled":true}` | The Kasm Workspaces control plane (the `kasm-helm` chart). The web UI, the manager/API services, the session proxy, Guacamole, the RDP gateways, and the PostgreSQL database.  ALL of that chart's values nest under this key — this chart adds only `enabled` and restates nothing else, so every default in `charts/kasm-helm/values.yaml` still applies. For example, the chart's own `publicAddr` and `ingress.enabled` are set from here as:    kasm-helm:     publicAddr: kasm.example.com     ingress:       enabled: true       ingressClassName: traefik  See `charts/kasm-helm/README.md` for the full value reference.  |
| kasm-helm.enabled | bool | `true` | Install the Kasm control plane with this release. Set to false to install only the Kubernetes agent, registering it with a Kasm manager that already exists elsewhere (another cluster, a VM deployment, or a Kasm-hosted one).  |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Kasm Technologies, Inc. |  | <https://github.com/kasmtech/kasm-helm> |
