# Install on one cluster

> **Applies to:** both halves

## Why this is needed

`kasm-platform` installs both halves as one release, in one namespace, with nothing to copy
between them. The no-values install in [Get started](../../tutorials/get-started.md) is this
layout; this page adds a hostname and a certificate so it can be kept.

## Before you start

- A cluster that meets [Supported platforms](../../explanation/supported-platforms.md): Kubernetes
  1.26 or newer, amd64 nodes, a default StorageClass.
- A DNS name for the control plane, `kasm.example.com` below, pointing at whatever will front it.
- One exposure mechanism for the control plane, chosen from [Networking](../networking/README.md).
  The example uses an Ingress; a `LoadBalancer` Service (the default) needs no Ingress at all.
- A certificate, or cert-manager: [Certificates](../networking/certificates.md). Without either the
  chart generates a self-signed one.
- If any privileged chart will be on (`nodePrep`, `videoDevicePlugin`, `egressInstaller`), the
  namespace must be labelled `pod-security.kubernetes.io/enforce=privileged`, and that label covers
  the control plane too. [Deployment topologies](../../explanation/topologies.md) says when that is
  a reason to use two namespaces instead.

## Steps

1. **Write the values file.** Only the control plane needs anything; the agent derives its manager
   address, token and session hostname from the release it shares
   (`kasm-agent.agent.inClusterControlPlane: true` is the umbrella's default).

   ```yaml
   kasm-helm:
     publicAddr: kasm.example.com
     certificate:
       secretName: kasm-tls          # a kubernetes.io/tls Secret you created, or let cert-manager fill it
     proxyService:
       type: ClusterIP               # the Ingress owns the external address
     ingress:
       enabled: true
       ingressClassName: nginx
   ```

2. **Install.**

   ```console
   helm install kasm oci://registry-1.docker.io/kasmweb/kasm-platform \
     -n kasm --create-namespace -f values.yaml --timeout 20m
   ```

   The long timeout covers database initialization and the first image pulls. Applying these
   values to an existing release (the tutorial's) works as a `helm upgrade`; expect the database
   pod to restart once, because the PostgreSQL StatefulSet mounts the control-plane certificate
   Secret and `certificate.secretName` changed.

   > **Installing from a source checkout instead?** The published `oci://…/kasm-platform` archive
   > bundles its subcharts, so it needs nothing more. A git checkout does not — the umbrella's
   > `charts/` directory is staged at package time — so run `make deps-agent` before a
   > `helm install`/`upgrade` that points at a local `charts/kasm-platform`, and again after any
   > `git pull` that changes a subchart, since staged subcharts do not refresh on their own (a pin
   > that still matches on version but changed in content is only half-caught). See
   > [Publish the charts](../publish-charts.md) for the ordering and the stale-pin trap, and
   > [Architecture](../../explanation/architecture.md#the-chart-dependency-tree) for why.

3. **Enable the agent and authorize a workspace** in the admin UI, as in
   [Get started](../../tutorials/get-started.md), or seed `auto_agent` first with
   [Enable agents automatically](../enable-agents-automatically.md).

4. **Optional: direct-connect.** Sessions are relayed through the control plane. To have browsers
   stream from the agent's own hostname instead, follow
   [Switch sessions to direct-connect](../networking/direct-connect.md) after this page.

## Verify

```console
kubectl get pods -n kasm
kubectl get agents.agent.kasm.com -n kasm
curl -sk -o /dev/null -w '%{http_code}\n' https://kasm.example.com/
```

Expected: every pod `Running` and the `kasm-db-init` Job `Completed`; the agent `PHASE` is
`Ready`; the `curl` prints `200`. Then log in at `https://kasm.example.com` as `admin@kasm.local`
with the password from:

```console
kubectl get secret -n kasm kasm-secrets -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Launch a session: the address bar stays on `kasm.example.com`.

## Chart values

```yaml
kasm-helm:
  publicAddr: kasm.example.com
  certificate:
    secretName: kasm-tls
  proxyService:
    type: ClusterIP
  ingress:
    enabled: true
    ingressClassName: nginx

kasm-agent:
  agent:
    inClusterControlPlane: true     # the umbrella default; shown for clarity
```

Both halves can be switched off: `kasm-helm.enabled: false` gives
[Install an agent only](agent-only.md); `kasm-agent.enabled: false` gives a control plane on its
own.

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md) has the failures table, including the k3s
case where the default `LoadBalancer` Service collides with Traefik on port 443.

## Decisions

- [ ] `kasm-helm.publicAddr` set to the DNS name users will type; DNS in place.
- [ ] Certificate settled: a Secret you created, cert-manager, or the self-signed default accepted for evaluation.
- [ ] Exactly one exposure mechanism for the control plane; `proxyService.type=ClusterIP` behind an Ingress, Route or Gateway.
- [ ] Understood that the namespace's Pod Security label covers both halves.
- [ ] Someone owns the Enable and group-assignment clicks, or `auto_agent` is seeded.
- [ ] Relayed sessions accepted, or the direct-connect switch scheduled.
