# Where Kasm's documentation takes over

> **Applies to:** both halves

Everything an administrator configures in the Kasm admin UI or API works the same on Kubernetes as
on any other Kasm deployment, and is documented by Kasm. These pages do not repeat it. They cover
what is Kubernetes-specific and stop at the point where Kasm's documentation takes over. This table
is that boundary.

| Topic | Kubernetes-specific part, here | The rest, in Kasm's documentation |
| ----- | ------------------------------ | --------------------------------- |
| Enabling a registered agent | [Enable agents automatically](../how-to/enable-agents-automatically.md) | [Agent settings](https://www.kasmweb.com/docs/latest/guide/agent_settings.html) |
| Zones and where an agent joins | [Deploy multiple zones](../how-to/multi-zone.md), [Add an agent cluster](../how-to/install/agent-only.md) | [Deployment Zones](https://www.kasmweb.com/docs/latest/guide/zones/deployment_zones.html) |
| Authorization Domain and other global settings | [Switch sessions to direct-connect](../how-to/networking/direct-connect.md) | [Settings](https://www.kasmweb.com/docs/latest/guide/settings.html) |
| Workspace images and who may launch them | nothing; [Registries and airgap](../how-to/registries-and-airgap.md) for where images are pulled from | [Workspaces](https://www.kasmweb.com/docs/latest/guide/workspaces.html), [Custom images](https://www.kasmweb.com/docs/latest/guide/custom_images.html), [Groups](https://www.kasmweb.com/docs/latest/guide/groups.html) |
| Egress providers, gateways and credentials | [Egress installer](../how-to/networking/egress.md), the node-side daemon | [Egress](https://www.kasmweb.com/docs/latest/guide/egress.html) |
| Users, groups, authentication | nothing | [Users](https://www.kasmweb.com/docs/latest/guide/users.html), [Groups](https://www.kasmweb.com/docs/latest/guide/groups.html) |
| Multi-server topology on VMs | [Deployment topologies](../explanation/topologies.md), the Kubernetes equivalent | [Multi Server Installation](https://www.kasmweb.com/docs/latest/install/multi_server_install.html) |

Links point at the `latest` documentation. Check the version selector there against the Kasm
version the control plane runs (`kasm-helm`'s `appVersion`).
