# Label the agent's workloads

> **Applies to:** the agent half (`kasm-agent`)

## Why this is needed

Teams that select Kubernetes objects by label — for cost allocation, NetworkPolicies, monitoring
dashboards, or `kubectl` filters — need their own labels on the resources this chart and its operator
create. The agent chart exposes three separate label knobs, because the objects fall into three groups
that are created by different things and are usually tracked separately.

## The three knobs

| Value | Labels | Created by | Typical use |
|---|---|---|---|
| `agent.commonLabels` | The objects **this chart renders**: the `Agent` custom resource, the operator RBAC, the session-proxy TLS Secret | Helm | Tag the release's own declarative objects |
| `agent.agentLabels` | The **agent's own workloads**: the agent Deployment, the session proxy, and their Services and RBAC | the operator, from the `Agent` CR | Cost/monitoring/NetworkPolicy selection of the long-running agent pods |
| `agent.workspaceLabels` | Every **workspace (session) pod** the agent launches, and its resources | the operator, per session | Track or govern the ephemeral session pods, separately from the agent |

Each set is added to the objects' `metadata.labels` (and the workload pod templates). None of them touch
the pod **selectors**, which stay immutable across upgrades, so a label may be changed or removed without
orphaning a Deployment.

`agentLabels` and `workspaceLabels` are deliberately distinct so the agent's own pods and the workspace
pods it spawns can be told apart by a selector, even though both are operator-managed.

## Not the same as server labels

Don't confuse these with **Kasm server labels** — a separate feature for per-workspace *targeting*,
matched against a workspace's include/exclude labels. Those are set on the server in the Kasm admin UI
(or the `update_server` admin API), never become Kubernetes labels, and are not a chart value. See
[Scope workspaces to nodes](nodes/scope-workspaces-to-nodes.md).

## Set them

```yaml
kasm-agent:
  agent:
    commonLabels:
      app.kubernetes.io/part-of: kasm      # on the Agent CR, its RBAC, the proxy TLS Secret
    agentLabels:
      team: platform                       # on the agent Deployment + session proxy
      cost-center: "4812"
    workspaceLabels:
      team: platform                       # on every session pod this agent launches
      workload: kasm-session
```

A session's own labels are layered on top of `workspaceLabels`, winning on any conflicting key.

## Upgrading an existing cluster

`agentLabels` and `workspaceLabels` are fields on the `Agent` CRD. Helm installs a chart's CRDs on first
install but never updates them on `helm upgrade`, so on a cluster whose `Agent` CRD predates these fields
a server-side apply fails with `field not declared in schema`. Update the CRDs first —
`kubectl apply --server-side -f charts/kasm-agent-operator/crds/`, or run the `kasm-agent-crds` release,
which ships them as ordinary templates Helm *will* upgrade. See
[Install the CRDs as their own release](install/crds.md).
