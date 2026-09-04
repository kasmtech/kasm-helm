# Kasm Workspaces on Kubernetes

![Version: 1.1190.6](https://img.shields.io/badge/Version-1.1190.6-informational?style=flat-square) ![AppVersion: 1.19.0](https://img.shields.io/badge/AppVersion-1.19.0-informational?style=flat-square) ![Type: Application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Kasm Workspaces streams desktops, browsers and applications into an ordinary web browser. A Kasm
deployment has two halves: a **control plane**, which people sign in to, and an **agent**, which
runs the sessions. This repository holds the Helm charts for both.

There are two ways in:

* **[Path A](#path-a--the-whole-stack-on-one-cluster)** — you have nothing yet. Install both halves
  on one Kubernetes cluster.
* **[Path B](#path-b--add-a-kubernetes-agent-to-a-kasm-you-already-run)** — you already run Kasm
  somewhere. Add a Kubernetes cluster to it as a new agent.

## Quickstart

### Before you start

| You need | Check it with |
| --- | --- |
| A Kubernetes cluster, 1.26 or newer | `kubectl version` |
| Helm 3.18 or newer | `helm version` |
| A default StorageClass — some distributions ship none, RKE2 among them | `kubectl get storageclass` (look for `(default)`) |
| An ingress controller | `kubectl get ingressclass` |
| Two DNS names pointing at your cluster: one for the login page, one for sessions | `dig +short kasm.example.com sessions.example.com` |
| A TLS certificate and private key covering both names, as PEM files | `openssl x509 -in tls.crt -noout -ext subjectAltName` |
| **Path B only:** your Kasm deployment's manager token | It is the `manager` → `token` global setting, under **Settings** in the Kasm admin UI |

**The two hostnames must share a parent domain**, like `kasm.example.com` and
`sessions.example.com` under `example.com`. Browsers stream sessions straight from the agent's
hostname, and Kasm's login cookie is scoped to the shared parent so it reaches both. Pick the pair
before you install: changing it later means renaming one. A wildcard certificate for the parent
(`*.example.com`) covers both names.

The agent charts are still a developer preview and are not published for download, so both paths
install from a checkout of this repository:

```console
git clone https://github.com/kasmtech/kasm-helm
cd kasm-helm
make deps-agent
```

### Path A — the whole stack on one cluster

Save this as `my-values.yaml` and replace every `example.com` name:

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  certificate:
    secretName: kasm-tls
  proxyService:
    type: ClusterIP           # never LoadBalancer next to an ingress controller
  ingress:
    enabled: true
    ingressClassName: nginx
  kasmZones:
    - name: default
      proxy_hostname: kasm.example.com
      proxy_connections: false               # browsers connect straight to the agent
      upstream_auth_address: kasm.example.com
  kasmConfig:
    generatePreseed: true                    # what carries kasmZones into the database
    authDomain: example.com                  # the shared parent domain

kasm-agent:
  agent:
    manager:
      hostname: kasm.example.com
      existingTokenSecret: kasm-secrets      # the Secret the control plane generates
      tokenSecretKey: manager-token
    publicHostname: sessions.example.com
    sessionProxy:
      certSecretName: kasm-tls
    ingress:
      enabled: true
      className: nginx
      annotations:                           # ingress-nginx cuts idle websockets at 60s
        nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
        nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
      tls:
        - secretName: kasm-tls
          hosts:
            - sessions.example.com
```

Everything else is defaulted. The control plane generates its own registration token into the
`kasm-secrets` Secret and the agent reads it from there; the agent joins the zone named `default`
and is sized for a small deployment. The two timeout annotations are the one tuning value here that
is not optional — ingress-nginx cuts an idle websocket at 60s, so without them every session dies
about a minute in. Other controllers have their own knob, in
[Idle timeouts](docs/howto/external-access-and-tls.md#idle-timeouts).

Install it:

```console
kubectl create namespace kasm
kubectl create secret tls kasm-tls -n kasm --cert=tls.crt --key=tls.key
helm install kasm charts/kasm-platform -n kasm -f my-values.yaml --timeout 20m
```

The long timeout is not padding: setting up the database and pulling the first images takes several
minutes on a cold cluster. Then [verify](#verify).

### Path B — add a Kubernetes agent to a Kasm you already run

First, on the Kasm you already have, make two changes so it accepts sessions served from a second
hostname:

* **Settings → Auth**: set *Kasm Auth Domain* to the parent domain shared by your existing Kasm
  hostname and the new session hostname (`example.com`). Without it, connecting to a session fails
  with a 401.
* **Infrastructure → Zones**, on the zone this cluster will join: turn *Proxy Connections* **off**,
  and set *Upstream Auth Address* to your Kasm hostname.

Save this as `agent-values.yaml` and replace every `example.com` name:

```yaml
agent:
  manager:
    hostname: kasm.example.com               # your existing Kasm
    existingTokenSecret: kasm-manager-token
  publicHostname: sessions.example.com
  sessionProxy:
    certSecretName: kasm-agent-tls
  ingress:
    enabled: true
    className: nginx
    annotations:                             # ingress-nginx cuts idle websockets at 60s
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    tls:
      - secretName: kasm-agent-tls
        hosts:
          - sessions.example.com
```

The agent joins the zone named `default` — the one a Kasm install starts with. Add `agent.zone` if
the zone you edited above is named something else. As on Path A, the two timeout annotations are
the one non-optional tuning value; other controllers have their own knob, in
[Idle timeouts](docs/howto/external-access-and-tls.md#idle-timeouts).

Install it:

```console
kubectl create namespace kasm-agent
kubectl create secret generic kasm-manager-token -n kasm-agent --from-literal=token='<your manager token>'
kubectl create secret tls kasm-agent-tls -n kasm-agent --cert=tls.crt --key=tls.key
helm install kasm-agent charts/kasm-agent -n kasm-agent -f agent-values.yaml --timeout 20m
```

If your Kasm control plane is itself a `kasm-helm` release in this same cluster, read the token out
of it instead of typing it:

```console
kubectl create secret generic kasm-manager-token -n kasm-agent \
  --from-literal=token="$(kubectl get secret kasm-secrets -n kasm -o jsonpath='{.data.manager-token}' | base64 -d)"
```

Then [verify](#verify).

### Verify

On Path B, read `kasm-agent` wherever these commands say `kasm`.

```console
kubectl get pods -n kasm                          # every pod Running
kubectl get agents.agent.kasm.com -n kasm         # PHASE is Ready
kubectl get svc k8s-agent-session-proxy -n kasm   # the Service browsers reach through the ingress
```

The agent listing should look like this. `Ready` means it registered itself with the control plane:

```text
NAME        PHASE   MANAGER            AGE
k8s-agent   Ready   kasm.example.com   2m
```

On Path A, read the admin password the chart generated for you:

```console
kubectl get secret kasm-secrets -n kasm -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Now open a **fresh private browser window** — a stale cookie from an earlier install causes
confusing 401s — and finish in the Kasm UI:

1. Sign in at `https://kasm.example.com`, on Path A as `admin@kasm.local` with that password.
2. **Infrastructure** → your new agent → **Enable**. New agents register disabled.
3. **Workspaces** → **Registry** → install a workspace. A new Kasm has an empty library, so this is
   the step that gives you something to launch. Then **Workspaces** → that workspace → assign it to
   the **All Users** group.
4. Launch a session from the Kasm UI; it should open. The browser's address bar shows
   `sessions.example.com`, because session traffic never goes through the control plane.

If a session fails to open, [External access and TLS](docs/howto/external-access-and-tls.md)
matches each symptom (401, 404, a session that dies after a minute) to its cause.

### Exposing sessions another way

Both paths above use an Ingress, which is what most clusters already have. The alternative worth
knowing is `agent.gatewayRoute`, which hands the session proxy's own certificate straight to the
browser through a Gateway API `TLSRoute` — pick it if you run the Gateway API and want end-to-end
TLS. `agent.route` is the native choice on OpenShift. All the options, with what each one costs
you, are in [External access and TLS](docs/howto/external-access-and-tls.md).

## Next steps

* **[What works on Kubernetes](docs/feature-matrix.md)** — every Kasm feature, whether it works
  here, and what it needs from the cluster.
* **[Planning a deployment](docs/planning.md)** — node sizing, storage, network, security posture,
  and day 2.
* **[External access and TLS](docs/howto/external-access-and-tls.md)** — every way to publish
  sessions, and the certificate and timeout rules behind them.
* **Chart references** — [`kasm-platform`](charts/kasm-platform/README.md) (the whole stack),
  [`kasm-agent`](charts/kasm-agent/README.md) (the Kubernetes agent),
  [`kasm-helm`](charts/kasm-helm/README.md) (the control plane). Every value, documented.

---

## Reference

### The charts in this repository

Ten charts: one control plane, seven that make up the Kubernetes agent, and two umbrellas that
compose them. [Architecture](docs/architecture.md) shows how they fit together and which one to
install; [Cluster how-tos](docs/howto/README.md) are the step-by-step cluster preparation guides
(RWX storage, NetworkPolicy, GPU nodes, private registries, privileged workloads).

You install an umbrella, not the pieces.

| Chart | Purpose |
| ----- | ------- |
| [`kasm-platform`](charts/kasm-platform/README.md) | **The whole stack in one release** — control plane plus Kubernetes agent, each half switchable off. Path A installs this. |
| [`kasm-agent`](charts/kasm-agent/README.md) | **The Kubernetes agent** — composes six agent subcharts plus three optional third-party dependencies (rclone CSI driver, GPU Operator, NFS provisioner). Path B installs this. |
| [`kasm-helm`](charts/kasm-helm/README.md) | **The control plane on its own** — web UI, manager/API, session proxy, Guacamole, RDP gateways, and a bundled PostgreSQL. Sessions do not run here. |

The parts those umbrellas are made of. You configure these through `kasm-agent` rather than
installing them yourself — `kasm-agent-crds` is the one exception:

| Chart | Purpose |
| ----- | ------- |
| [`kasm-agent-operator`](charts/kasm-agent-operator/README.md) | The CRDs, cluster RBAC, and controller-manager that reconcile `Agent`, `KasmWorkspace`, `KasmImagePuller`, `WarmPool`, and `WarmPoolInstance`. One per cluster. |
| [`kasm-agent-instance`](charts/kasm-agent-instance/README.md) | The `Agent` resource and the session proxy browsers connect to, plus the external-access options. |
| [`kasm-otel-collector`](charts/kasm-otel-collector/README.md) | An OpenTelemetry collector that fans agent traces, metrics and logs out to your own observability backends. |
| [`kasm-node-prep`](charts/kasm-node-prep/README.md) | Privileged DaemonSet that builds and loads host kernel modules (`v4l2loopback`, WireGuard) and applies optional node tuning. Off by default. |
| [`kasm-video-device-plugin`](charts/kasm-video-device-plugin/README.md) | Advertises `/dev/video*` as the schedulable resource `kasm.com/video`, for webcam sessions. Off by default. |
| [`kasm-egress-installer`](charts/kasm-egress-installer/README.md) | Privileged DaemonSet that chains a CNI shim into every node and brings up per-session OpenVPN, WireGuard or Ziti egress tunnels. Off by default. |
| [`kasm-agent-crds`](charts/kasm-agent-crds/README.md) | The same five CRDs as ordinary Helm templates, for fleets that want Helm to own the CRD lifecycle. Install as its own release, before the umbrellas. |

### Installing the control plane on its own

The control plane chart is generally available as of Kasm Workspaces 1.19.0, and it is published,
so it needs no checkout. It runs on Kubernetes 1.24 or newer — a lower floor than the agent's 1.26.
Sessions then run on agents you add separately: Kubernetes agents, Docker Agent servers, or
auto-scaled ones.

A minimal `my-values.yaml` sets the public DNS name and the TLS Secret to terminate with:

```yaml
publicAddr: kasm.example.com
certificate:
  secretName: my-tls-secret
```

Install from the OCI registry (recommended):

```bash
helm install kasm oci://registry-1.docker.io/kasmweb/kasm-helm \
  --version 1.1190.6 \
  --namespace kasm --create-namespace \
  -f my-values.yaml
```

Or from the classic Helm repository:

```bash
helm repo add kasmweb https://helm.kasm.com
helm repo update
helm install kasm kasmweb/kasm-helm \
  --version 1.1190.6 \
  --namespace kasm --create-namespace \
  -f my-values.yaml
```

Generated credentials and post-install notes are available at any time with
`helm get notes kasm -n kasm`. The full value reference is in
[charts/kasm-helm/README.md](charts/kasm-helm/README.md).

Two things about the control plane are easy to miss. **RDP target hosts are external** — RDP
sessions are routed by the in-cluster gateways to Windows or Linux hosts outside the cluster. And
**an ingress fronts the deployment**, so browser and HTTPS client traffic enters through your
ingress controller, typically backed by a cloud load balancer.

### Seeding the database at install time

The control-plane chart can seed Kasm's database when it initializes — users, groups, workspace
images, autoscale providers, SSO connectors — declared as Helm values instead of post-install API
calls. Path A above uses it for the zone and the auth domain, and it can seed the workspace library
too, so a fresh install comes up with something to launch. The full reference is
[charts/kasm-helm/docs/preseed.md](charts/kasm-helm/docs/preseed.md), including
[default user accounts and group permissions](charts/kasm-helm/docs/default-users.md)
(`defaultUsers: true`) and
[default API credentials](charts/kasm-helm/docs/default-api-users.md) (`defaultApiUsers: true`).

Seeding only happens at database initialization, so it applies to fresh installs. On an existing
database, make the same changes in the admin UI.

### Versioning

Chart versions track Kasm Workspaces versions. The middle component of the chart version
corresponds to the Kasm release — chart **1.1181.0** matches Kasm Workspaces **1.18.1**.

This branch (`1.1190.6` / app `1.19.0`) is the stable release for Kasm Workspaces **1.19.0**.

Always use the chart version that matches the Kasm Workspaces version you are deploying.

| Branch | Purpose |
| --- | --- |
| `release/<version>` | Stable chart for a specific Kasm Workspaces release |
| `develop` | Developer previews — no guaranteed migration path; not for production |

The agent-family and umbrella charts are versioned on their own line, independent of the control
plane, and are currently `0.1.0` (app `develop`) — a developer preview. That is why they install
from a checkout rather than a registry. Per-chart release history lives in each chart's
`CHANGELOG.md`, for example
[charts/kasm-helm/CHANGELOG.md](charts/kasm-helm/CHANGELOG.md); there is no repository-wide
changelog.

### Trying Kasm without installing it

Try Kasm Workspaces in your browser at [kasm.com](https://kasm.com/solutions/platform).
[Kasm Workspaces Community Edition](https://kasm.com/community-edition) is free for personal and
small-team use, and these charts work with both Community and commercial editions.

### More

* [Kasm Workspaces website](https://kasm.com/)
* [Kasm documentation](https://docs.kasm.com/) — installation, upgrade, configuration,
  multi-region, VM-to-Kubernetes migration, and troubleshooting
* [Helm chart repository](https://github.com/kasmtech/kasm-helm) — chart source and examples
* [Kasm on GitHub](https://github.com/kasmtech) — KasmVNC and the open-source workspace image library
* [Helm chart issues and discussion](https://github.com/kasmtech/kasm-helm/issues)

### License

These charts are published by Kasm Technologies. Kasm Workspaces itself is licensed separately —
see [kasm.com](https://kasm.com/) for license terms.
