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
- A zone for this cluster, **with a manager of its own**. An agent joins the zone of the manager
  it registers with, so the zone's hostname is what goes in `agent.manager.hostname`, and
  `agent.zone` only labels what the agent reports (it must match; it moves nothing). On a
  Kubernetes control plane a zone is a `kasm-helm.kasmZones` entry, which renders its manager and
  proxy on `proxy_hostname` ([Deploy multiple zones](../multi-zone.md)); a zone created only under
  **Infrastructure → Zones** ([Kasm docs: Deployment Zones](https://www.kasmweb.com/docs/latest/guide/zones/deployment_zones.html))
  has no manager there and cannot take this agent. On a VM control plane the zone's manager
  hostname is whatever Kasm's multi-server layout gave it. `default` exists on every Kasm and is
  what an agent pointed at the primary hostname joins. Several clusters may share a zone; the
  manager then spreads sessions across them by capacity.
- Network paths, in both directions: this cluster must reach the control plane's hostname on 443,
  and the session proxy at `agent.publicHostname` must be reachable from browsers (direct-connect)
  or from the control-plane cluster (relayed). Agent clusters never need to reach each other.
- The manager must be able to reach the session proxy at `agent.publicHostname:agent.publicPort`,
  and so must browsers if the zone is direct-connect. Pick one exposure mechanism from
  [Networking](../networking/README.md). On a relayed zone (Kasm's default), nothing between the
  control plane's proxy and the session proxy may route on the `Host` header, so use a
  `LoadBalancer`/`NodePort` Service, not an Ingress or HTTPRoute (TLS passthrough does not work
  there); [Deployment topologies](../../explanation/topologies.md) explains why. A published
  Service exposes the session proxy's own ports, 4444 and 4445, unless
  `agent.sessionProxy.service.httpsPort` and `httpPort` map them elsewhere; the values below map
  443 onto 4444.
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
       hostname: eu.kasm.example.com   # the zone's hostname (kasmZones[].proxy_hostname), not publicAddr
       existingTokenSecret: kasm-manager-token
     publicHostname: eu.sessions.example.com
     zone: eu                          # must match the zone behind manager.hostname
     sessionProxy:
       service:
         type: LoadBalancer            # published directly; works on a relayed or a direct-connect zone
         httpsPort: 443                # the Service's 443 onto the proxy's 4444 listener
   ```

   With `publicHostname` set, `publicPort` defaults to 443, and `httpsPort: 443` is what makes the
   Service answer there: the container keeps listening on 4444, the Service publishes it as 443,
   and the manager's hello call to `<publicHostname>:443` succeeds. Leave `httpsPort` empty and
   the Service publishes the proxy's own 4444 instead, so that call fails and every launch returns
   "No resources are available". A NodePort is reached on its node port, which `publicPort` then
   has to name ([LoadBalancer and NodePort](../networking/loadbalancer-nodeport.md)).

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
   [Switch sessions to direct-connect](../networking/direct-connect.md). Browsers are sent to
   `eu.sessions.example.com` on the zone's *Proxy Port*, not on `publicPort`; with `httpsPort: 443`
   above, the zone's default of 443 already matches. Only a NodePort has to be named there
   (`kasmZones[].proxy_port`, or Infrastructure → Zones).

7. **Uninstall in two steps, when the time comes.** Delete the `KasmWorkspace` and `Agent`
   resources and let the operator clean up, then `helm uninstall`; a one-step `helm uninstall`
   leaves the `Agent` stuck on its finalizer with the agent pods running
   ([Day 2](../day-2.md#uninstall)). The `kasm-agent-state` ConfigMap survives the uninstall and
   carries the agent's `server_id`; a reinstall reuses it. Delete it before registering the
   cluster with a **different** control plane:

   ```console
   kubectl -n kasm-agent delete configmap kasm-agent-state
   ```

## Verify

```console
kubectl get agents.agent.kasm.com -n kasm-agent
kubectl get svc -n kasm-agent k8s-agent-session-proxy
curl -sk -o /dev/null -w '%{http_code}\n' https://eu.sessions.example.com/
```

Expected: `PHASE` is `Ready`, which means the agent registered with the zone's manager and its
heartbeats are arriving; the Service has an `EXTERNAL-IP` and `443:<nodeport>/TCP,4445:<nodeport>/TCP`;
the `curl` prints `404`, which is correct with no active session (it proves the session proxy
answered). The `Agent` status carries no zone and no enabled state, so also check
**Infrastructure → Agents** on the control plane: the agent is listed as `eu.sessions.example.com`
in zone `eu` (or `get_servers` on the API shows it with `zone_name: eu`) and is enabled. An agent
listed in the primary zone registered through the primary hostname. Then launch a session from
the control plane; the API log shows
`Requesting Hello ... https://eu.sessions.example.com:443/agent/api/v1/create_container/` and the
`KasmWorkspace` appears in this cluster.

## Chart values

```yaml
agent:
  manager:
    hostname: eu.kasm.example.com
    existingTokenSecret: kasm-manager-token
  publicHostname: eu.sessions.example.com
  zone: eu
  sessionProxy:
    service:
      type: LoadBalancer
      httpsPort: 443
```

Under `kasm-platform` with `kasm-helm.enabled: false`, nest the block under `kasm-agent:`.

## Troubleshooting

[Troubleshooting](../../reference/troubleshooting.md). A `PHASE` short of `Ready` is the token, the
manager address (`Progressing` with `waiting for workloads (agent=false, ...)` and
`heartbeat failed` in the agent log), or an agent image tag the control plane's
`manager/agent_version` setting does not accept. A record in the wrong zone is `manager.hostname`
pointing at another zone's manager. "No resources are available" on launch with a `Ready` agent is
the agent not enabled, or `publicPort` not matching the port the Service exposes (443 with
`httpsPort: 443`; the node port on a NodePort).

## Decisions

- [ ] Manager token obtained and stored as a Secret, not inline in values.
- [ ] One zone per cluster decided; the zone has a manager (`kasmZones` entry) and `agent.manager.hostname` is that zone's hostname; `agent.zone` matches.
- [ ] Exposure mechanism chosen; on a relayed zone, a published Service.
- [ ] `sessionProxy.service.httpsPort: 443`, so `agent.publicPort` and the zone's Proxy Port stay at 443; on a NodePort both name the node port.
- [ ] `agent.publicHostname` reachable from the manager, and from browsers on a direct-connect zone.
- [ ] `PHASE Ready`; the control plane lists the agent in the intended zone.
- [ ] Two-step uninstall known; `kasm-agent-state` deleted before re-registering elsewhere.
- [ ] Session-proxy certificate trusted by browsers if the zone is direct-connect.
- [ ] Enable click owned, or `auto_agent` on.
