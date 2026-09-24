# Install from the Rancher catalog

> **Applies to:** both halves · **Charts/values:** `global.cattle.systemDefaultRegistry`, and the
> form fields in each published chart's `questions.yaml`

## Why this is needed

Rancher's Apps catalog installs any Helm chart, but it reads three files a plain `helm install`
ignores: the `catalog.cattle.io/*` annotations in `Chart.yaml`, `app-readme.md` and
`questions.yaml`. The published charts carry all three, so in Rancher they appear with a display
name, a short description on the tile, an install form for the values an install cannot guess, and
the CRD chart installed first without a separate step. This page is the Rancher-side procedure; the
values themselves are the same as on every other page, so the how-to for your layout
([one cluster](one-cluster.md), [two namespaces](two-namespaces.md),
[agent only](agent-only.md)) still applies.

## Before you start

- Rancher 2.9 or newer, and a downstream cluster that meets
  [Supported platforms](../../explanation/supported-platforms.md). The charts declare `kubeVersion`
  and `catalog.cattle.io/kube-version`, so Rancher hides them from a cluster below the floor
  rather than failing the install.
- Cluster-owner rights on that cluster. `kasm-agent` and `kasm-platform` install
  CustomResourceDefinitions and ClusterRoles; a project-scoped user cannot.
- A released chart version. Rancher hides prerelease versions (`1.1200.0-develop` and the like)
  unless the user's preferences turn on **Include Prerelease Versions**, so a catalog entry built
  from the development line shows nothing until that preference is set.
- If any privileged chart will be on (`nodePrep`, `videoDevicePlugin`, `egressInstaller`, or the
  standalone `kasm-egress-installer`): the target namespace must be exempt from Pod Security
  Admission. On RKE2 the CIS profile enforces `restricted` cluster-wide, and the exemption is a
  cluster-level setting, not a namespace label:
  [Privileged workloads and cluster policy](../nodes/privileged-workloads.md).

## Steps

1. **Add the repository.** In Rancher, open the cluster, then **Apps → Repositories → Create**.
   Two forms work:

   | Repository | URL | Notes |
   | --- | --- | --- |
   | HTTP index | `https://helm.kasm.com` | One entry lists every chart published to the index. Rancher resolves `catalog.cattle.io/auto-install` within the repository the app chart came from, so this is the entry that makes the CRD chart install on its own. |
   | OCI, one chart per entry | `oci://registry-1.docker.io/kasmweb/kasm-platform` | Docker Hub does not serve the registry catalog endpoint, so an OCI repository entry has to name one chart. Add one entry per chart you intend to install, and see step 3 for the CRD chart. |

   Which charts the HTTP index carries is decided at publish time
   ([Publish the charts](../publish-charts.md)); the OCI URLs are where every published chart is.

2. **Install.** **Apps → Charts**, pick **Kasm Workspaces** (`kasm-platform`), **Kasm Workspaces
   Kubernetes Agent** (`kasm-agent`) or **Kasm Egress Installer**, choose the version, and set the
   namespace. The release name Rancher proposes is the one every page in these docs assumes
   (`kasm` for the platform and control plane, `kasm-agent` for the agent). The form has one group
   per topic:

   | Group | What it sets |
   | --- | --- |
   | Control plane | `kasm-helm.enabled`, the public hostname, deployment size, Ingress. Without an Ingress the proxy is published by a NodePort Service: RKE2 ships no LoadBalancer implementation, so the chart picks NodePort whenever Rancher installed it (`kasm-helm.proxyService.type` overrides) |
   | Certificate | cert-manager issuer, or an existing TLS Secret; otherwise self-signed |
   | Credentials | admin password and manager token; empty generates them |
   | Database | external PostgreSQL, or the bundled one's StorageClass |
   | Agent | `kasm-agent.enabled`, in-release registration or an explicit manager, the session hostname, the session proxy's exposure |
   | Cluster features | NetworkPolicies, kernel modules, video device plugin, VPN egress, GPU Operator, NFS provisioner, rclone CSI |

   Everything the form does not show keeps the chart default. **Edit YAML** on the same screen
   exposes the whole values file, with the form's answers already merged in; the chart README is
   the reference for it.

3. **The CRD chart.** `kasm-platform` and `kasm-agent` carry
   `catalog.cattle.io/auto-install: kasm-agent-crds=match`, so from a repository that lists both
   charts Rancher installs `kasm-agent-crds` at the same version, into the same namespace, before
   the app release, and upgrades it with the app; nothing to do, the extra release in the namespace
   is expected. From a one-chart OCI entry that lookup has nothing to find: add
   `oci://registry-1.docker.io/kasmweb/kasm-agent-crds` as its own entry and install it first
   ([Install the CRDs as their own release](crds.md)), then the app chart. Either way the operator
   chart's own `crds/` directory is still in the archive and still harmless: Helm skips a CRD that
   already exists.

4. **Air-gapped cluster: nothing extra for the images.** When the cluster (or Rancher itself) has a
   system default registry configured, Rancher passes it to every chart as
   `global.cattle.systemDefaultRegistry`, and every Kasm image in `kasm-helm` and in the six Kasm
   subcharts of `kasm-agent` is rendered from it, per-image `registry` values ignored. Mirror the
   images from the lists in [Registries and airgap](../registries-and-airgap.md) to that registry.
   The three third-party dependencies of `kasm-agent` (`csiRclone`, `gpuOperator`,
   `nfs-server-provisioner`) do not read the global; set their image values in **Edit YAML**.
   Workspace images are still pulled from wherever the manager's image list points, exactly as on
   any other cluster.

5. **Sign in and authorize a workspace.** The UI is at `https://<any node address>:30443`: with
   no Ingress and no `proxyService.type`, the chart publishes the proxy on a NodePort pinned to
   30443 and seeds the default zone to advertise that port in session URLs. Sign in as
   `admin@kasm.local` with the password from Secret `<release>-secrets`. The agent enables itself
   as it registers, because the same seed turns on "Automatically Enable Agents"
   (`kasm-helm.kasmConfig.autoEnableAgents`); assigning a workspace image to a group is the one
   remaining click: [Get started](../../tutorials/get-started.md) from step 8. Both seeds happen
   at database initialization only, so they are settings to change in the admin UI on a database
   that already exists.

## Verify

The app shows **Deployed** under **Apps → Installed Apps**, twice for an umbrella install:

```console
helm list -n kasm
```

```
NAME             NAMESPACE  REVISION  STATUS    CHART                          APP VERSION
kasm             kasm       1         deployed  kasm-platform-<version>        <version>
kasm-agent-crds  kasm       1         deployed  kasm-agent-crds-<version>      <version>
```

Without a public hostname or an Ingress, the UI is at any node's address on the pinned node port:

```console
kubectl -n kasm get svc kasm-proxy-ext-default -o jsonpath='{.spec.type} {.spec.ports[0].nodePort}{"\n"}'
```

```
NodePort 30443
```

The agent shows as enabled without a visit to Infrastructure → Agents, and the seeded zone carries the
port:

```console
kubectl -n kasm get agents.agent.kasm.com
kubectl -n kasm get secret kasm-db-preseed -o jsonpath='{.data.custom_properties\.yaml}' | base64 -d | grep -E 'auto_agent|proxy_port'
```

```
NAME        PHASE   REGISTERED   ...
k8s-agent   Ready   True         ...
  name: "auto_agent"
  proxy_port: 30443
```

On an air-gapped cluster, every image carries the system default registry:

```console
kubectl get pods -n kasm -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | sort -u
```

```
registry.internal.example.com/kasmweb/api:<tag>
registry.internal.example.com/kasmweb/agent-operator:<tag>
...
```

## Chart values

None beyond what the form sets. The values Rancher adds on its own, and the one default that reacts
to them:

```yaml
global:
  cattle:
    clusterId: c-m-xxxxxxxx                                 # set by Rancher; makes proxyService.type resolve to NodePort
    systemDefaultRegistry: registry.internal.example.com   # set by Rancher; leave empty elsewhere
kasm-helm:
  proxyService:
    type: ""                                               # empty: LoadBalancer, or NodePort under Rancher. Set LoadBalancer only with MetalLB or a cloud LB present
    nodePort: ""                                           # empty: 30443 when the chart chose NodePort under Rancher, else Kubernetes-assigned
  kasmConfig:
    generatePreseed: null                                  # null: on under Rancher (the zone port and auto_agent need seeding), off elsewhere
    autoEnableAgents: null                                 # null: on under Rancher, off elsewhere; agents come up enabled as they register
```

Every one of the four is a plain value to set explicitly when the default is not wanted; they apply
at database initialization, so on a database that already exists the zone port and auto_agent are
changed in the admin UI instead.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| The chart is not listed under **Charts** | The only published versions are prereleases, and the user preference **Include Prerelease Versions** is off | Turn the preference on, or install a released version |
| The chart is listed but greyed out for this cluster | The cluster is below `catalog.cattle.io/kube-version`, or Rancher is below `catalog.cattle.io/rancher-version` | Upgrade the cluster; the floors are in [Supported platforms](../../explanation/supported-platforms.md) |
| The install form reports that `kasm-agent-crds` cannot be found | `catalog.cattle.io/auto-install` is resolved within the app chart's repository, and a one-chart OCI entry has no other chart in it | Install `kasm-agent-crds` first from its own OCI entry, or use an HTTP index that lists both |
| A privileged DaemonSet has `desired` pods and none `ready`, events say `violates PodSecurity` | RKE2 CIS profile, or another cluster-wide `restricted` enforcement | Exempt the namespace in the cluster's Pod Security Admission configuration: [Privileged workloads](../nodes/privileged-workloads.md) |
| The control-plane proxy Service stays `<pending>` | `kasm-helm.proxyService.type` was set to `LoadBalancer` on a cluster with no LoadBalancer implementation (RKE2 ships none) | Leave the type empty so it resolves to NodePort, or install MetalLB and keep LoadBalancer |
| GPU Operator or NFS provisioner pods pull from `docker.io` on an air-gapped cluster | Third-party dependencies do not read `global.cattle.systemDefaultRegistry` | Set their image values in **Edit YAML** |

## Decisions

- [ ] Rancher is 2.9 or newer and the installing user is a cluster owner.
- [ ] The version being installed is a release, or **Include Prerelease Versions** is on.
- [ ] `kasm-agent-crds` is reachable: the HTTP index lists it, or it was installed first from its own OCI entry.
- [ ] Every privileged feature left on has its namespace exempted from Pod Security Admission.
- [ ] On an air-gapped cluster, the third-party dependencies' image values point at the mirror by hand.
