# Kasm on Kubernetes: documentation

> **Applies to:** both halves

Kasm on Kubernetes is two halves: the control plane (the `kasm-helm` chart: web UI, API, manager,
database) and one or more agents (the `kasm-agent` family: where sessions run). Every page opens
with an **Applies to** line that says which half it is about.

**Values convention.** Values are written as they appear in a `kasm-platform` values file:
`kasm-helm.publicAddr` for the control plane, `kasm-agent.agent.publicHostname` for the agent.
Installing `kasm-helm` or `kasm-agent` on its own, drop the leading `kasm-helm.` or `kasm-agent.`.

**Reading path.** Start with the [root README](../README.md) (one command), then the tutorial,
then the one how-to you need. Explanation and reference are one link away from every page.

## Tutorial

| Page | What you end up with |
| ---- | -------------------- |
| [Get started](tutorials/get-started.md) | The no-values install, end to end, to a running session |

## How-to guides

One task per page. Each ends in a Decisions block that is the checklist.

| Page | Task |
| ---- | ---- |
| [Install on one cluster](how-to/install/one-cluster.md) | `kasm-platform`, one release: the relayed default, with a hostname and certificate |
| [Install in two namespaces](how-to/install/two-namespaces.md) | `kasm-helm` and `kasm-agent` as separate releases: token copy, PSS scope, NetworkPolicies |
| [Add an agent cluster](how-to/install/agent-only.md) | `kasm-agent` in another cluster, against a control plane that already exists: the multi-cluster building block |
| [Install the CRDs as their own release](how-to/install/crds.md) | `kasm-agent-crds`, and the upgrade order it imposes |
| [Networking](how-to/networking/README.md) | Pick one exposure mechanism per half: [certificates](how-to/networking/certificates.md), [Ingress](how-to/networking/ingress.md), [HTTPRoute](how-to/networking/gateway-api-httproute.md), [TLS passthrough](how-to/networking/gateway-api-passthrough.md), [TCPRoute](how-to/networking/gateway-api-tcproute.md), [LoadBalancer and NodePort](how-to/networking/loadbalancer-nodeport.md), [OpenShift Route](how-to/networking/openshift-route.md), [NetworkPolicies](how-to/networking/network-policies.md), [egress](how-to/networking/egress.md) |
| [Switch sessions to direct-connect](how-to/networking/direct-connect.md) | Hostname pair, authorization domain, zone routing |
| [Publish the RDP gateway](how-to/networking/rdp-gateway.md) | `directRdpService` or a `TCPRoute` |
| [Nodes](how-to/nodes/README.md) | [Scope workspaces to nodes](how-to/nodes/scope-workspaces-to-nodes.md), [GPU](how-to/nodes/gpu.md), [webcam and kernel modules](how-to/nodes/webcam-kernel-modules.md), [Secure Boot](how-to/nodes/secure-boot.md), [tuning and swap](how-to/nodes/tuning-and-swap.md), [privileged workloads](how-to/nodes/privileged-workloads.md) |
| [Storage](how-to/storage/README.md) | [RWX profiles](how-to/storage/rwx-profiles.md), [cloud storage mappings](how-to/storage/cloud-mappings.md) |
| [Registries and airgap](how-to/registries-and-airgap.md) | Private registries, pull secrets, pre-pulling, the four things to mirror |
| [Database](how-to/database.md) | Bundled PostgreSQL or your own, sizing, seeding |
| [Deploy multiple zones](how-to/multi-zone.md) | Declare zones on the control plane and add one agent release per zone |
| [Enable agents automatically](how-to/enable-agents-automatically.md) | `auto_agent` by preseed or on an existing database |
| [Label the agent's workloads](how-to/label-workloads.md) | `commonLabels`, `agentLabels`, `workspaceLabels`: what each one labels |
| [Day 2](how-to/day-2.md) | Upgrade, uninstall in two steps, backup, restore |
| [Publish the charts](how-to/publish-charts.md) | Package and push the OCI artifacts |

## Explanation

| Page | Question it answers |
| ---- | ------------------- |
| [Architecture](explanation/architecture.md) | What the two halves are, and how the ten charts compose |
| [Deployment topologies](explanation/topologies.md) | Relayed or direct-connect; one release or two namespaces; one cluster or many, and what each fixes |
| [Capacity](explanation/capacity.md) | What a session costs, and which ceiling binds first |
| [Zones](explanation/multi-zone.md) | What a zone is, and what more than one forces |
| [Security posture](explanation/security-posture.md) | PSS, RBAC, the privileged charts, isolation |
| [Managed providers](explanation/managed-providers.md) | What EKS, AKS, GKE and OpenShift decide for you |
| [Supported platforms](explanation/supported-platforms.md) | Version floors, node architecture, distributions |
| [Sessions: Docker agent vs Kubernetes](explanation/sessions-docker-vs-kubernetes.md) | What the operator adds to a session's environment |
| [Why the CRDs are split](explanation/why-the-crds-are-split.md) | Two ways to install a CRD, and why the repo ships both |
| [Why no hook Jobs](explanation/why-no-hook-jobs.md) | Why the charts leave some steps to you |

## Reference

| Page | Contains |
| ---- | -------- |
| [What works on Kubernetes](reference/feature-matrix.md) | Every Kasm feature, its status, and the how-to that installs what it needs |
| [Ports and hostnames](reference/ports-and-hostnames.md) | Every port, Service name and hostname |
| [Troubleshooting](reference/troubleshooting.md) | Symptom, cause, command: the one failures table |
| [The charts](reference/charts.md) | Ten charts, one line each, linking every value reference |
| [Preseeding](reference/preseed.md) | Seeding the database at initialization |
| [Default users](reference/default-users.md) · [Default API users](reference/default-api-users.md) | What `defaultUsers` and `defaultApiUsers` create |
| [Where Kasm's documentation takes over](reference/kasm-docs.md) | The boundary between these pages and Kasm's own: admin-UI configuration is documented there, not here |

Adding or changing a page: [CONTRIBUTING.md](../CONTRIBUTING.md).
