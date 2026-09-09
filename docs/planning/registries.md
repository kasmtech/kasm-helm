# Private registries and image pulling

> **Applies to:** [Private image registries](../reference/feature-matrix.md#security-and-isolation) and [image pre-pulling](../reference/feature-matrix.md#observability-and-operations) · **Charts/values:** `agent.workspaceImagePullSecrets`, `agent.imagePullSecrets`, `operator.imagePullSecrets`, `otelCollector.imagePullSecrets`, `videoDevicePlugin.imagePullSecrets`, `egressInstaller.imagePullSecrets`, `csiRclone.imagePullSecrets`, `kasm-helm.imagePullSecrets.enabled`, `agent.imagePuller.enabled`, `agent.imagePuller.images`, `agent.imagePuller.imagePullPolicy`, `agent.imageAvailabilityPolicy`, `agent.image.registry`, `agent.sessionProxy.image.registry`, `agent.sessionProxy.sidecarImage.registry`, `operator.image.registry`, `otelCollector.image.registry`, `videoDevicePlugin.image.registry`, `nodePrep.image.registry`

## Why this is needed

Three different image flows exist and they use **different** settings:

| Flow | Who pulls | Value |
| ---- | --------- | ----- |
| Kasm component images (agent API, session proxy, operator, collector, plugins) | kubelet, per chart | each chart's own `imagePullSecrets` |
| **Workspace** images launched as sessions | kubelet, injected by the agent | `agent.workspaceImagePullSecrets` |
| Pre-staged images on every node | the image-puller DaemonSet via `crictl` | `agent.imagePuller.images[].imagePullSecrets` |

Getting the first one right does nothing for the second. This is the most common cause of
`ImagePullBackOff` on session pods in an otherwise healthy install.

## Before you start

* Credentials for the registry, and the ability to create Secrets in the release namespace(s).
* Secrets do **not** cross namespaces. A two-namespace layout needs the Secret in **both**.
* `kasm-node-prep` has **no** `imagePullSecrets` value. Its builder image (`nodePrep.image.registry`
  / `.repository` / `.tag`) must come from a registry the node's runtime can pull anonymously, or be
  mirrored at the runtime level (containerd `hosts.toml`, CRI-O `registries.conf`).

Cloud variants:

| Platform | Notes |
| -------- | ----- |
| EKS / ECR | ECR tokens expire every 12 hours. Refresh them with the ECR credential helper or external-secrets, or attach the pull permission to the node role and skip the Secret. |
| GKE / Artifact Registry | Prefer Workload Identity or the node service account over a static Secret. |
| AKS / ACR | Attach the ACR to the cluster (`az aks update --attach-acr`) instead of a Secret where possible. |
| OpenShift | A `dockercfg`/`dockerconfigjson` Secret linked to the ServiceAccount works the same way. |
| Airgap | See step 5. |

## Steps

1. **Create the pull Secret** in each release namespace:

   ```console
   kubectl create secret docker-registry internal-registry \
     --namespace kasm-agent \
     --docker-server=registry.example.internal \
     --docker-username='<user>' \
     --docker-password='<password>'
   ```

   Repeat for the control-plane namespace if the two are split.

2. **Reference it for the Kasm component images** — each chart has its own list:

   ```yaml
   agent:
     imagePullSecrets:
       - name: internal-registry
   operator:
     imagePullSecrets:
       - name: internal-registry
   otelCollector:
     imagePullSecrets:
       - name: internal-registry
   videoDevicePlugin:
     imagePullSecrets:
       - name: internal-registry
   egressInstaller:
     imagePullSecrets:
       - name: internal-registry
   ```

   Control plane (`kasm-helm`) uses a different shape — it can create the Secret for you:

   ```yaml
   kasm-helm:
     imagePullSecrets:
       enabled: true
       registry: registry.example.internal
       username: "<user>"
       password: "<password>"
   ```

   Set only `imagePullSecrets.enabled` and `imagePullSecrets.name` to reuse a Secret you created
   yourself.

3. **Reference it for workspace images** — this is the separate one:

   ```yaml
   agent:
     workspaceImagePullSecrets:
       - name: internal-registry
   ```

   The agent injects these into every session pod it launches.

4. **Pre-pull images** so the first session on a node does not wait for a cold pull:

   ```yaml
   agent:
     imagePuller:
       enabled: true
       imagePullPolicy: IfNotPresent
       images:
         - image: registry.example.internal/kasmweb/chrome:1.18.0
           registry: https://registry.example.internal
           imagePullSecrets:
             - name: internal-registry
     imageAvailabilityPolicy: all
   ```

   Two pullers coexist: the operator **already** creates one named `kasm-image-puller` from the
   manager's own workspace list, without being asked. `agent.imagePuller.*` renders an *additional*
   explicit one for images you want staged regardless. Note `images[].image` is a full reference used
   verbatim — it must already name the mirror.

5. **Airgap: mirror everything, then re-point the registries.**

   ```console
   make images-agent          # prints the list and writes dist/kasm-agent-images.txt
   make package-agent         # dist/kasm-agent-0.1.0.tgz, dependencies embedded
   ```

   Mirror each reference (`skopeo copy`, `crane copy`, or your registry's replication), then override
   per chart:

   ```yaml
   operator:
     image:
       registry: registry.example.internal
   otelCollector:
     image:
       registry: registry.example.internal
   agent:
     image:
       registry: registry.example.internal
     sessionProxy:
       image:
         registry: registry.example.internal
       sidecarImage:
         registry: registry.example.internal
   videoDevicePlugin:
     image:
       registry: registry.example.internal
   nodePrep:
     image:
       registry: registry.example.internal
   ```

   Two sets are **not** covered by that block: **workspace images** (re-point them in the Kasm
   manager's workspace registry) and `agent.imagePuller.images` (full references, above). The
   third-party subcharts have their own paths — `csiRclone.imagePullSecrets`,
   `nfs-server-provisioner.image.repository`, and NVIDIA's separate air-gap procedure for
   `gpuOperator`. Full detail:
   [Airgapped installation](../../charts/kasm-agent/README.md#airgapped-installation).

## Verify

```console
kubectl -n kasm-agent get events --field-selector reason=Failed
kubectl -n kasm-agent get pods
kubectl -n kasm-agent get kasmimagepullers.agent.kasm.com
```

Expected indicators:

* `get events --field-selector reason=Failed` returns **`No resources found`** (no
  `ErrImagePull` / `ImagePullBackOff`).
* Every pod in the namespace is `Running` (or `Completed`), none in `ImagePullBackOff`.
* The image-puller DaemonSet has a pod on every session node.
* The Secret is the right type:

  ```console
  kubectl -n kasm-agent get secret internal-registry \
    -o jsonpath='{.type}{"\n"}'      # -> kubernetes.io/dockerconfigjson
  ```

* Launch a session from a private workspace image; the pod reaches `Running` without a pull error.

## Chart values

Under the `kasm-platform` umbrella:

```yaml
kasm-agent:
  agent:
    imagePullSecrets:
      - name: internal-registry
    workspaceImagePullSecrets:
      - name: internal-registry
    imagePuller:
      enabled: true
      images:
        - image: registry.example.internal/kasmweb/chrome:1.18.0
          registry: https://registry.example.internal
          imagePullSecrets:
            - name: internal-registry
  operator:
    imagePullSecrets:
      - name: internal-registry

kasm-helm:
  imagePullSecrets:
    enabled: true
    name: internal-registry
```

Installing the charts directly? Drop the `kasm-agent:` key (start at `agent:` / `operator:`) and the
`kasm-helm:` key respectively.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Agent and operator pods run fine, but **session** pods `ImagePullBackOff` | Only `imagePullSecrets` was set; workspace images use a different value | Set `agent.workspaceImagePullSecrets` |
| Pull works in one namespace, fails in the other | Secrets do not cross namespaces | Create the Secret in both release namespaces |
| ECR pulls fail every morning | ECR tokens expire after 12h | Refresh with the ECR credential helper / external-secrets, or use the node role |
| `nodePrep` builder image will not pull from a private registry | `kasm-node-prep` has no `imagePullSecrets` value | Mirror it somewhere anonymously pullable, or configure the credential at the container runtime (containerd `hosts.toml`, CRI-O `registries.conf`) |
| Pre-pull DaemonSet fails on one image only | `imagePuller.images[].image` still names the upstream registry | Rewrite the full reference to the mirror, and add that entry's `imagePullSecrets` |
| A workspace is reported unavailable although some nodes have the image | `agent.imageAvailabilityPolicy: all` requires it on every node | Switch to `any`, or fix the failing node's pull |
| `gpuOperator` operands fail to pull in an airgap | The operand set is not in `dist/kasm-agent-images.txt` | Follow NVIDIA's air-gapped procedure, values passed through as `gpuOperator.*` |

## Checklist

- [ ] `kubernetes.io/dockerconfigjson` Secret created in every release namespace
- [ ] Per-chart `imagePullSecrets` set for the Kasm component images
- [ ] `agent.workspaceImagePullSecrets` set for session images
- [ ] `kasm-helm.imagePullSecrets` configured on the control-plane side
- [ ] `nodePrep.image.*` reachable without a pull secret (or handled at the runtime)
- [ ] Pre-pull list uses full mirror references with per-image `imagePullSecrets`
- [ ] Airgap: `make images-agent` mirrored, `image.registry` overridden per chart, workspace images re-pointed in the manager
- [ ] `kubectl get events --field-selector reason=Failed` is empty and all pods are Running
- [ ] A private-registry workspace launches successfully
