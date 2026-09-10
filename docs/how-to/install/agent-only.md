# Add an agent cluster to an existing control plane

> **Applies to:** agent

## Why this is needed

A Kasm control plane already exists: in another Kubernetes cluster, on VMs, or hosted. This page
adds a Kubernetes cluster to it as an agent with the `kasm-agent` chart. It is how a multi-cluster
deployment grows: one control plane, one `kasm-agent` release in every further cluster, usually one
zone each. The control-plane half of this repository is not involved.
[One cluster or many](../../explanation/topologies.md#one-cluster-or-many) has the shape and the
three flows that cross a cluster boundary.

## Before you start

- The control plane's public hostname, and its manager token: the `manager` → `token` global
  setting under **Settings** in the Kasm admin UI.
- A zone for this cluster. One zone per cluster is the usual choice: create it on the control
  plane (**Infrastructure → Zones**, [Kasm docs: Deployment Zones](https://www.kasmweb.com/docs/latest/guide/zones/deployment_zones.html), or `kasm-helm.kasmZones` at install) and name it in
  `agent.zone`. `default` exists on every Kasm and is what the agent joins otherwise. Several
  clusters may share a zone; the manager then spreads sessions across them by capacity.
- Network paths, in both directions: this cluster must reach the control plane's hostname on 443,
  and the session proxy at `agent.publicHostname` must be reachable from browsers (direct-connect)
  or from the control-plane cluster (relayed). Agent clusters never need to reach each other.
- The manager must be able to reach the session proxy at `agent.publicHostname`, and so must
  browsers if the zone is direct-connect. Pick one exposure mechanism from
  [Networking](../networking/README.md). On a relayed zone (Kasm's default), nothing between the
  control plane's proxy and the session proxy may route on the `Host` header, so use a
  `LoadBalancer`/`NodePort` Service or TLS passthrough, not an Ingress or HTTPRoute;
  [Deployment topologies](../../explanation/topologies.md) explains why.
- A certificate for the session proxy if browsers will reach it directly:
  [Certificates](../networking/certificates.md).

## Steps

1. **Create the namespace and the token Secret.**

   ```console
   kubectl create namespace kasm-agent
   kubectl create secret generic kasm-manager-token -n kasm-agent \
     --from-literal=token='<the manager token>'
   ```

2. **Write the values file.** The three values the agent cannot be installed without are the
   manager hostname, the token and the public hostname.

   ```yaml
   agent:
     manager:
       hostname: kasm.example.com
       existingTokenSecret: kasm-manager-token
     publicHostname: eu.sessions.example.com
     zone: eu                          # the zone created for this cluster
     sessionProxy:
       service:
         type: LoadBalancer            # published directly; works on a relayed or a direct-connect zone
   ```

3. **Install.**

   ```console
   helm install kasm-agent oci://registry-1.docker.io/kasmweb/kasm-agent \
     -n kasm-agent -f values.yaml --timeout 10m
   ```

4. **Point DNS** for `eu.sessions.example.com` at the Service's external address.

5. **Enable the agent** under **Infrastructure → Agents** on the control plane, and authorize the
   workspace images for a group. On a control plane whose `auto_agent` setting is on, the agent
   enables itself: [Enable agents automatically](../enable-agents-automatically.md).

6. **Direct-connect only.** If the zone has *Proxy Connections* off, also set the Kasm
   Authorization Domain to the parent domain shared by both hostnames, and the zone's *Upstream Auth
   Address* to the control plane's hostname:
   [Switch sessions to direct-connect](../networking/direct-connect.md).

## Verify

```console
kubectl get agents.agent.kasm.com -n kasm-agent
kubectl get svc -n kasm-agent k8s-agent-session-proxy
curl -sk -o /dev/null -w '%{http_code}\n' https://eu.sessions.example.com/
```

Expected: `PHASE` is `Ready`; the Service has an `EXTERNAL-IP`; the `curl` prints `404`, which is
correct with no active session (it proves the session proxy answered). Then launch a session from
the control plane.

## Chart values

```yaml
agent:
  manager:
    hostname: kasm.example.com
    existingTokenSecret: kasm-manager-token
  publicHostname: eu.sessions.example.com
  zone: eu
  sessionProxy:
    service:
      type: LoadBalancer
```

Under `kasm-platform` with `kasm-helm.enabled: false`, nest the block under `kasm-agent:`.

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md). A `PHASE` short of `Ready` is the token, the
manager address, or an agent image tag the control plane's `manager/agent_version` setting does
not accept.

## Decisions

- [ ] Manager hostname and token obtained; token stored as a Secret, not inline in values.
- [ ] One zone per cluster decided; `agent.zone` matches a zone that exists on the control plane.
- [ ] Exposure mechanism chosen; on a relayed zone, one that does no `Host` routing.
- [ ] `agent.publicHostname` reachable from the manager, and from browsers on a direct-connect zone.
- [ ] Session-proxy certificate trusted by browsers if the zone is direct-connect.
- [ ] Enable click owned, or `auto_agent` on.
