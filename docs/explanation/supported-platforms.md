# Supported platforms

> **Applies to:** both halves

## Versions

| | Floor | Notes |
| --- | --- | --- |
| Kubernetes, control plane (`kasm-helm`) | **1.24** | Older may work; the charts track [supported Kubernetes releases](https://kubernetes.io/releases/) |
| Kubernetes, agent family | **1.26** | The shared floor for `kasm-agent` and all its subcharts |
| Helm | **3.18** | OCI support and the schema validation these charts rely on |
| PostgreSQL | **16** | Exactly 16 - see [Database](../how-to/database.md) |
| cert-manager | any current | Only when `certificate.certManager.enabled` or `agent.sessionProxy.certificate.enabled` |

Gateway API is versioned separately from Kubernetes, and the floor depends on which route kind you
need:

| Route kind | Standard channel since | Needs |
| ---------- | ---------------------- | ----- |
| `HTTPRoute` | Gateway API 1.0 | any conformant implementation |
| `TLSRoute` | Gateway API 1.5 | a listener with `tls.mode: Passthrough` |
| `TCPRoute` | Gateway API 1.6 | a `protocol: TCP` listener, **and** an implementation that actually serves TCPRoute |

Check what a cluster has:

```console
$ kubectl get crd gateways.gateway.networking.k8s.io \
    -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}'
v1.5.1
```

See [Gateway API](../how-to/networking/gateway-api-httproute.md).

## Node architecture

**Kasm workspace images are `linux/amd64` only.** `kasmweb/chrome:1.19.0-rolling-weekly` and its
siblings publish no arm64 build, so on an arm64 cluster the kubelet reports `NotFound` when it pulls
them - the tag exists, the platform does not, and the error does not say so.

That makes **k3d or kind on Apple Silicon unusable for workspace testing**: the control plane, the
agent and the operator all run fine (they are multi-arch), the agent registers, and then every
session fails to pull. A handful of images do carry arm64 builds - Alpine among them - so a session
can be launched with one of those, which is enough to exercise the session path but not the images
anyone actually deploys.

Check before assuming a cluster can run a given workspace:

```console
$ crane manifest kasmweb/chrome:1.19.0-rolling-weekly | jq -r '.manifests[].platform | .os + "/" + .architecture'
linux/amd64
```

For anything workspace-related, use an amd64 cluster.

## Distributions

| Platform | Status | What to know |
| -------- | ------ | ------------ |
| k3s | Verified end to end | Traefik is bundled; its Gateway API provider is **off** by default and needs a `HelmChartConfig` |
| kubeadm / vanilla | Verified end to end | Bring your own ingress controller or Gateway API implementation |
| EKS / AKS / GKE | Supported, see caveats | Node images, GPU drivers, kernel modules and client-IP handling all differ - [Managed providers](managed-providers.md) |
| OpenShift / ROSA / ARO | Supported, see caveats | Set `kasm-helm.isOpenshift=true`; Routes are the native path; SCCs govern the privileged components |

## What is not supported

Features that do not work on Kubernetes at all, and the ones that work with conditions, are listed
feature by feature in [What works on Kubernetes](../reference/feature-matrix.md). Read it before
committing to a feature, not after.
