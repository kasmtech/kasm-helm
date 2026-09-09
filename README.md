# Kasm Workspaces on Kubernetes

![Version: 1.1190.6](https://img.shields.io/badge/Version-1.1190.6-informational?style=flat-square) ![AppVersion: 1.19.0](https://img.shields.io/badge/AppVersion-1.19.0-informational?style=flat-square) ![Type: Application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Kasm Workspaces streams desktops, browsers and applications into an ordinary web browser. A Kasm
deployment has two parts: a **control plane**, which people sign in to, and one or more **agents**, which
manage and provision the workspaces. This repository holds the Helm charts for both.

Just evaluating? [The smallest install](#the-smallest-install) is one command with no values at
all. Otherwise there are three ways in:

* **[Path A](#path-a-the-whole-stack-on-one-cluster)** — you have nothing yet. Install both parts
  on one Kubernetes cluster.
* **[Path B](#path-b-add-a-kubernetes-agent-to-a-kasm-you-already-run)** — you already run Kasm
  somewhere. Add a Kubernetes cluster to it as a new agent.
* **[Path C](#path-c-the-control-plane-on-its-own)** — You just want to install the Kasm control plane and will add agents later

## Quickstart

### Before you start

| You need | Check it with |
| --- | --- |
| A Kubernetes cluster, 1.26 or newer | `kubectl version` |
| Helm 3.18 or newer | `helm version` |
| A default StorageClass — some distributions ship none, RKE2 among them | `kubectl get storageclass` (look for `(default)`) |
| An ingress controller | `kubectl get ingressclass` |
| Two DNS names pointing at your cluster: one for the login page, one for sessions | `dig +short kasm.example.com sessions.example.com` |
| A TLS certificate covering both names — [make one below](#get-a-certificate) if you have none | `openssl x509 -in tls.crt -noout -ext subjectAltName` |
| **Path B only:** your Kasm deployment's manager token | It is the `manager` → `token` global setting, under **Settings** in the Kasm admin UI |

**By default, browsers stream sessions straight from the agent**, so the agent needs a hostname of
its own and Kasm's login cookie has to reach both halves. Scope the cookie to a domain that is a
parent of both names — `kasm.example.com` and `sessions.example.com` under `example.com`, or
`sessions.kasm.example.com` under the control plane's own name. That parent has to be a registrable
domain: browsers refuse to scope a cookie to a public suffix like `.com` or `github.io`. Pick the
pair before you install; changing it later means renaming a host, reissuing certificates and
resetting the auth domain by hand.

One certificate covering both hostnames is enough for the quickstart, because an Ingress terminates
TLS for both. Be careful with wildcards though: a TLS wildcard matches exactly one label, so
`*.example.com` covers both hostnames but **not** `*.sessions.example.com` — which the session proxy
does need on the passthrough and direct-Service paths, where browsers reach it rather than the
Ingress. See [Certificates](docs/planning/networking/certificates.md).

None of this applies if you run the
[proxied topology](docs/planning/networking/README.md#direct-connect-or-proxied), where browsers
only ever talk to the control plane.

Every chart in this repository is published as an OCI artifact under
`oci://registry-1.docker.io/kasmweb/`, dependencies embedded, so neither path below needs a
checkout. Pin the version you install:

```console
helm show chart oci://registry-1.docker.io/kasmweb/kasm-platform --version 1.1190.6
```

Working on the charts themselves? [Building from a checkout](#building-from-a-checkout) at the end
covers that instead.

### The smallest install

To try Kasm on a cluster you already have, with nothing configured:

```console
$ helm install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
    -n kasm --create-namespace --timeout 20m
```

That works because the chart fills in what it can: the agent takes its manager address, registration
token and session-proxy address from the control plane installed alongside it, and both halves
generate a self-signed certificate rather than wait on Secrets that do not exist. Reach it on the
external address of the `kasm-proxy-ext-default` Service:

```console
$ kubectl -n kasm get svc kasm-proxy-ext-default
NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)         AGE
kasm-proxy-ext-default   LoadBalancer   10.43.10.201   10.0.0.42     443:31856/TCP   4m

$ kubectl -n kasm get secret kasm-secrets -o jsonpath='{.data.admin-password}' | base64 -d; echo
Hs7qP2mWkR4vX9tL
```

Then enable the agent: it registers itself and heartbeats, but arrives **disabled**, so no session
will start until you switch it on under *Infrastructure → Agents* in the admin UI. There is no chart
value for that — it is manager-side state.

**This is for evaluation.** The certificate is self-signed, so your browser will warn; sessions
relay through the control plane, which caps them at a 30-minute idle timeout that cannot be raised
from values; and there is no DNS name, so nothing here survives the address changing. Every one of
those is fixed by the three paths below, which is why they exist.

### On k3s, add an Ingress

k3s ships Traefik, which already holds `:443` on every node through ServiceLB. The default
`proxyService.type=LoadBalancer` asks for the same port, so its ServiceLB pods never schedule
(`didn't have free ports for the requested pod ports`) and the Service sits at `EXTERNAL-IP:
<pending>` forever — the release comes up healthy and is simply unreachable. Publish it through
Traefik instead:

```console
$ helm install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
    -n kasm --create-namespace --timeout 20m \
    --set kasm-helm.publicAddr=kasm.example.com \
    --set kasm-helm.proxyService.type=ClusterIP \
    --set kasm-helm.ingress.enabled=true \
    --set kasm-helm.ingress.ingressClassName=traefik
```

`proxyService.type=NodePort` is the other way out, and needs neither an ingress controller nor a
load-balancer provider:

```console
$ helm upgrade --install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
    -n kasm --create-namespace --set kasm-helm.proxyService.type=NodePort

$ kubectl -n kasm get svc kasm-proxy-ext-default
NAME                     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)         AGE
kasm-proxy-ext-default   NodePort   10.96.241.161   <none>        443:32010/TCP   1m
```

Then browse `https://<node-ip>:32010/`. Pin the port with `proxyService.nodePort` if you want it
stable, and set `kasmZones[].proxy_port` to match — Kasm builds session URLs from the zone's port,
not from the Service, so a non-standard port needs telling. Or
`kubectl -n kasm port-forward svc/kasm-proxy-default 8443:8443` for a look without any of it.

#### Reaching it without editing /etc/hosts

An Ingress routes on the `Host` header, so the hostname has to resolve somewhere. On a local
cluster, wildcard DNS services like `nip.io` and `sslip.io` resolve `<anything>.<ip>.nip.io` to that
IP, which saves the hosts-file edit entirely — use the node's address:

```console
$ kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}{"\n"}'
192.168.107.2

$ helm upgrade --install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
    -n kasm --create-namespace --timeout 20m \
    --set kasm-helm.publicAddr=kasm.192.168.107.2.nip.io \
    --set kasm-helm.proxyService.type=ClusterIP \
    --set kasm-helm.ingress.enabled=true \
    --set kasm-helm.ingress.ingressClassName=traefik

$ curl -sk -o /dev/null -w '%{http_code}\n' https://kasm.192.168.107.2.nip.io/
200
```

The generated certificate follows `publicAddr`, so it covers that name and browsers get the chart's
certificate rather than the ingress controller's default. Whether the node IP is reachable from your
machine depends on your container runtime — it is with OrbStack, and with Docker Desktop you want
`k3d cluster create -p "443:443@loadbalancer"` and `127.0.0.1.nip.io` names instead.

### Get a certificate

Both paths need one Secret holding a certificate valid for **both** hostnames. Skip this if you
already have one.

#### With cert-manager (recommended)

Needs cert-manager installed and a working `ClusterIssuer`. One Certificate covers both names:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kasm-tls
  namespace: kasm
spec:
  secretName: kasm-tls
  dnsNames:
    - kasm.example.com
    - sessions.example.com
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-prod
```

```console
$ kubectl create namespace kasm
$ kubectl apply -f certificate.yaml
$ kubectl -n kasm get certificate kasm-tls
NAME       READY   SECRET     AGE
kasm-tls   True    kasm-tls   47s
```

Wait for `READY=True` before installing — the Secret does not exist until then. Stuck at `False` is
almost always the ACME challenge: `kubectl -n kasm describe certificate kasm-tls` names the reason.

#### Self-signed, for a lab

No public DNS or issuer needed, and fine for trying Kasm out:

```console
$ openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout tls.key -out tls.crt \
    -subj "/CN=kasm.example.com" \
    -addext "subjectAltName=DNS:kasm.example.com,DNS:sessions.example.com"

$ openssl x509 -in tls.crt -noout -subject -ext subjectAltName
subject=CN = kasm.example.com
X509v3 Subject Alternative Name:
    DNS:kasm.example.com, DNS:sessions.example.com

$ kubectl create namespace kasm
$ kubectl create secret tls kasm-tls -n kasm --cert=tls.crt --key=tls.key
secret/kasm-tls created
```

Both hostnames must appear in that SAN list. A certificate for only the login hostname lets you sign
in and then fails every session.

> **Your browser will warn on this certificate.** Accept the warning on the hostname you browse to.
> If you would rather not see it at all, issue a locally-trusted certificate with
> [mkcert](https://github.com/FiloSottile/mkcert) and pass it as `certificate.secretName`, or use
> cert-manager with an issuer your machine already trusts.

### Path A: the whole stack on one cluster

Save this as `my-values.yaml` and replace every `example.com` name:

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  certificate:
    secretName: kasm-tls
  proxyService:
    type: ClusterIP           # the Ingress owns the external address
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
[Idle timeouts](docs/planning/networking/loadbalancer-nodeport.md#idle-timeouts).

Install it:

```console
helm install kasm oci://registry-1.docker.io/kasmweb/kasm-platform -n kasm -f my-values.yaml --timeout 20m
```

The `kasm` namespace and the `kasm-tls` Secret come from [Get a certificate](#get-a-certificate)
above.

The long timeout is not padding: setting up the database and pulling the first images takes several
minutes on a cold cluster. Then [verify](#verify).

### Path B: add a Kubernetes agent to a Kasm you already run

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
[Idle timeouts](docs/planning/networking/loadbalancer-nodeport.md#idle-timeouts).

Install it:

```console
kubectl create namespace kasm-agent
kubectl create secret generic kasm-manager-token -n kasm-agent --from-literal=token='<your manager token>'
kubectl create secret tls kasm-agent-tls -n kasm-agent --cert=tls.crt --key=tls.key
helm install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent -n kasm-agent -f agent-values.yaml --timeout 20m
```

No certificate yet? [Get a certificate](#get-a-certificate) above applies here too — this path needs
only the **session** hostname (`sessions.example.com`) in the SAN list, and the Secret goes in the
`kasm-agent` namespace rather than `kasm`. The self-signed warning matters more on this path, since
the session hostname is the one your browser streams from.

If your Kasm control plane is itself a `kasm-helm` release in this same cluster, read the token out
of it instead of typing it:

```console
kubectl create secret generic kasm-manager-token -n kasm-agent \
  --from-literal=token="$(kubectl get secret kasm-secrets -n kasm -o jsonpath='{.data.manager-token}' | base64 -d)"
```

Then [verify](#verify).

### Path C: the control plane on its own

The control plane chart is generally available as of Kasm Workspaces 1.19.0. It runs on
Kubernetes 1.24 or newer — a lower floor than the agent family's 1.26.
Sessions then run on agents you add separately: Kubernetes agents, Docker Agent servers, or
auto-scaled ones.

A minimal `my-values.yaml` sets the public DNS name and the TLS Secret to terminate with:

```yaml
publicAddr: kasm.example.com
certificate:
  secretName: my-tls-secret
```

Only one hostname is involved here, so [Get a certificate](#get-a-certificate) above is simpler on
this path: drop `sessions.example.com` from the SAN list or the Certificate's `dnsNames`. Or let the
chart ask cert-manager for it directly, with no Secret to create by hand:

```yaml
publicAddr: kasm.example.com
certificate:
  secretName: kasm-tls
  certManager:
    enabled: true
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer
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

If a session fails to open, [External access and TLS](docs/planning/networking/README.md)
matches each symptom (401, 404, a session that dies after a minute) to its cause.

### Exposing sessions another way

Both paths above use an Ingress, which is what most clusters already have. The alternative worth
knowing is `agent.gatewayRoute`, which hands the session proxy's own certificate straight to the
browser through a Gateway API `TLSRoute` — pick it if you run the Gateway API and want end-to-end
TLS. `agent.route` is the native choice on OpenShift. All the options, with what each one costs
you, are in [External access and TLS](docs/planning/networking/README.md).

## Next steps

**[The documentation](docs/README.md)** is the map — what to read, in what order. The pages you are
most likely to want next:

* **[What works on Kubernetes](docs/reference/feature-matrix.md)** — every Kasm feature, whether it
  works here, and what it needs from the cluster. Read it before promising anyone a feature.
* **[Planning](docs/planning/README.md)** — the decision sequence: topology, capacity, networking,
  storage, database, security, install.
* **[Networking](docs/planning/networking/README.md)** — publishing both halves. Start with
  [Certificates](docs/planning/networking/certificates.md), then one mechanism per half.
* **[Troubleshooting](docs/operate/troubleshooting.md)** — when it is installed and something is
  wrong.
* **Chart references** — [`kasm-platform`](charts/kasm-platform/README.md) (the whole stack),
  [`kasm-agent`](charts/kasm-agent/README.md) (the Kubernetes agent),
  [`kasm-helm`](charts/kasm-helm/README.md) (the control plane). Every value, documented.

---

## The charts in this repository

Ten charts: one control plane, seven that make up the Kubernetes agent, and two umbrellas that
compose them. [Architecture](docs/overview/architecture.md) shows how they fit together;
[The charts](docs/overview/charts.md) says what each installs and which one to start from;
[Planning](docs/planning/README.md) is the decision sequence that ends in a values file.

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
| [`kasm-agent-operator`](charts/kasm-agent-operator/README.md) | The CRDs, cluster RBAC, and controller-manager that reconcile `Agent`, `KasmWorkspace`, and `KasmImagePuller`. One per cluster. |
| [`kasm-agent-instance`](charts/kasm-agent-instance/README.md) | The `Agent` resource and the session proxy browsers connect to, plus the external-access options. |
| [`kasm-otel-collector`](charts/kasm-otel-collector/README.md) | An OpenTelemetry collector that fans agent traces, metrics and logs out to your own observability backends. |
| [`kasm-node-prep`](charts/kasm-node-prep/README.md) | Privileged DaemonSet that builds and loads host kernel modules (`v4l2loopback`, WireGuard) and applies optional node tuning. Off by default. |
| [`kasm-video-device-plugin`](charts/kasm-video-device-plugin/README.md) | Advertises `/dev/video*` as the schedulable resource `kasm.com/video`, for webcam sessions. Off by default. |
| [`kasm-egress-installer`](charts/kasm-egress-installer/README.md) | Privileged DaemonSet that chains a CNI shim into every node and brings up per-session OpenVPN, WireGuard or Ziti egress tunnels. Off by default. |
| [`kasm-agent-crds`](charts/kasm-agent-crds/README.md) | The same five CRDs as ordinary Helm templates, for fleets that want Helm to own the CRD lifecycle. Install as its own release, before the umbrellas. |

## Installing

### Where the charts are published

Every chart is pushed to Docker Hub as an OCI artifact, dependencies embedded:

```console
helm install <release> oci://registry-1.docker.io/kasmweb/<chart> --version <version>
```

`kasm-platform`, `kasm-agent`, `kasm-agent-instance`, `kasm-agent-operator`, `kasm-agent-crds`,
`kasm-otel-collector`, `kasm-node-prep`, `kasm-video-device-plugin`, `kasm-egress-installer` and
`kasm-helm` are all there. `kasm-helm` is additionally published to the classic Helm repository at
`https://helm.kasm.com`:

```console
helm repo add kasm https://helm.kasm.com
helm repo update
helm install kasm kasm/kasm-helm --version 1.1190.6
```

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
plane, and are currently `0.1.0` (app `develop`) — a developer preview, published under the same
registry but with no guaranteed migration path between previews. Per-chart release history lives in
each chart's `CHANGELOG.md`, for example
[charts/kasm-helm/CHANGELOG.md](charts/kasm-helm/CHANGELOG.md); there is no repository-wide
changelog.

### Building from a checkout

Only needed to work on the charts themselves. The six Kasm subcharts are `file://` dependencies, so
they have to be staged inside-out before either umbrella will build:

```console
git clone https://github.com/kasmtech/kasm-helm
cd kasm-helm
make deps-agent          # helm dependency build for kasm-agent, then kasm-platform

helm install kasm charts/kasm-platform -n kasm --create-namespace -f my-values.yaml
```

`make test` runs the full static suite — lint, kubeconform, kyverno, unit tests, CRD sync and
version parity — against the working tree.

## Seeding the database at install time

The control-plane chart can seed Kasm's database when it initializes — users, groups, workspace
images, autoscale providers, SSO connectors — declared as Helm values instead of post-install API
calls. Path A above uses it for the zone and the auth domain, and it can seed the workspace library
too, so a fresh install comes up with something to launch. The full reference is
[charts/kasm-helm/docs/preseed.md](docs/reference/preseed.md), including
[default user accounts and group permissions](docs/reference/default-users.md)
(`defaultUsers: true`) and
[default API credentials](docs/reference/default-api-users.md) (`defaultApiUsers: true`).

Seeding only happens at database initialization, so it applies to fresh installs. On an existing
database, make the same changes in the admin UI.

## Trying Kasm without installing it

Try Kasm Workspaces in your browser at [kasm.com](https://kasm.com/solutions/platform).
[Kasm Workspaces Community Edition](https://kasm.com/community-edition) is free for personal and
small-team use, and these charts work with both Community and commercial editions.

## More

* [Kasm Workspaces website](https://kasm.com/)
* [Kasm documentation](https://docs.kasm.com/) — installation, upgrade, configuration,
  multi-region, VM-to-Kubernetes migration, and troubleshooting
* [Helm chart repository](https://github.com/kasmtech/kasm-helm) — chart source and examples
* [Kasm on GitHub](https://github.com/kasmtech) — KasmVNC and the open-source workspace image library
* [Helm chart issues and discussion](https://github.com/kasmtech/kasm-helm/issues)

## License

These charts are published by Kasm Technologies. Kasm Workspaces itself is licensed separately —
see [kasm.com](https://kasm.com/) for license terms.
