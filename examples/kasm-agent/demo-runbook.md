# Demo runbook: one chart → functional Kasm deployment

Rehearsed end-to-end on a single-node k3s lab cluster (16GiB). Timings below are measured,
not estimated. Total demo time: **~6 minutes**, two commands and two admin clicks.

## Before the audience arrives

* Cluster prerequisites in place: ingress controller (or Gateway), cert-manager + issuer,
  default StorageClass. The namespace label commands below can also be pre-run.
* A values file ready — `platform-values.yaml` in this directory is the template. For the
  demo make sure it includes the **workspace image preseed** (the commented `config.images`
  block) so the library is not empty on first login.
* **Open a fresh incognito/private browser window.** Every reinstall invalidates old session
  cookies, and the stale domain-scoped copy causes confusing 401s on session connect.
* Build the chart dependencies **inside-out** (fresh clones have no vendored deps):
  `make deps-agent` — or manually `helm dependency build charts/kasm-agent` **then**
  `charts/kasm-platform`. Skipping the first silently renders a control-plane-only stack.
* Optional dry run: `helm template kasm charts/kasm-platform -f <values> | wc -l`
  (expect ~75 documents with the full feature set, not ~21).

## The demo

**1. One command, whole platform** *(3m30s on the rehearsal cluster — narrate architecture
while it rolls: control plane, operator + CRDs, telemetry collector, agent, session proxy)*

The chart also lives as an OCI artifact, which removes the checkout and dependency-build
steps entirely — the package embeds all eight dependencies:

```console
helm install kasm oci://<registry>/kasm-platform --version 0.1.0   -n kasm --create-namespace -f demo-values.yaml --timeout 15m --wait
```

Or from a repo checkout (after the inside-out `make deps-agent`):

```console
helm install kasm charts/kasm-platform -n kasm --create-namespace \
  -f demo-values.yaml --timeout 15m --wait
```

(Where Pod Security Admission enforcement is configured, also label the namespace
`pod-security.kubernetes.io/enforce=privileged` for the privileged node infrastructure.)

When helm returns, everything is up: `kubectl get pods -n kasm` shows both halves;
`kubectl get agents -n kasm` shows the agent `Ready` — it has already registered itself
with the manager it was installed alongside.

**2. Log in** at `https://kasm.<your-domain>` as `admin@kasm.local` (password pinned in the
values, or read from the `kasm-secrets` Secret). Works immediately — the session-cookie
domain was seeded at database initialization; no post-install configuration happened.

**3. Two admin clicks** *(the human approval beats — ~30s)*

* Infrastructure → the registered agent → **Enable** (new agents register disabled).
* Workspaces → the preseeded workspace (e.g. Doom) → assign group **All Users**
  (group→image authorization is a manual UI/API step — see the note below).

**4. Launch the workspace** *(11s to a running session on a warm node; first-ever launch on
a virgin node adds the image pull, which the agent's image pre-puller is already doing in
the background from the moment it registered)*

The browser connects **directly to the agent's session hostname** — point out the URL bar:
session traffic never relays through the control plane.

Good closing beats: `kubectl get kasmworkspaces -n kasm` (the session is a CRD),
`kubectl get pods -n kasm` (the workspace is just a pod), delete the session from the UI
and watch the pod go.

## Act two (optional): the recommended two-namespace layout

Same OCI artifact, deployed twice with opposite halves toggled off — control plane in
`kasm`, agent in `kasm-agent` with **NetworkPolicies enforced** and the privileged node
infrastructure confined to its own namespace. Rehearsed: **3m41s for both installs**,
agent registered Ready through the enforced policies, session end-to-end.

```console
REF=oci://<registry>/kasm-platform

helm install kasm $REF --version 0.1.0 -n kasm --create-namespace \
  -f cp-values.yaml --timeout 15m --wait                  # kasm-agent.enabled=false inside

kubectl create namespace kasm-agent
kubectl create secret generic kasm-manager-token -n kasm-agent \
  --from-literal=token="$(kubectl get secret kasm-secrets -n kasm \
    -o jsonpath='{.data.manager-token}' | base64 -d)"

helm install kasm-agent $REF --version 0.1.0 -n kasm-agent \
  -f agent-values.yaml --timeout 10m --wait               # kasm-helm.enabled=false inside
```

Then the same login → enable → authorize → launch flow. Good talking points:
`kubectl get netpol -n kasm-agent` (seven enforced policies), the privileged PSS scope
touching only `kasm-agent`, and the token Secret copy being the entire cross-namespace
coupling. Gateway/Ingress must admit routes from BOTH namespaces. If using the agent
chart's baseline NetworkPolicies with an in-cluster manager reached through hostPort
ingress, remember `networkPolicies.manager.ports` needs the ingress controller's backend
port (Traefik: 8443) — the values files here set it.

## Resetting between runs

Delete the Kasm custom resources FIRST — their finalizers need the operator alive. A bare
`helm uninstall` strands the Agent CR, and the only recovery is reinstalling the operator
to reap it. Deleting the namespace is what makes the next run fresh: it removes the
database PVC, so preseeds apply again. CRDs survive by design; reinstalls skip them.

```console
# single-namespace                                   # two-namespace: same, then also
kubectl delete kasmworkspaces,agents,kasmimagepullers \
  --all -n <ns> --ignore-not-found --wait            #   (CRs live in the agent namespace)
helm uninstall <release> -n <ns>                     # helm uninstall kasm -n kasm
kubectl delete namespace <ns> --wait                 # kubectl delete ns kasm kasm-agent
```

## If something goes sideways

| Symptom | Cause | Fix |
|---|---|---|
| 401 connecting to the session | Stale browser cookies from a previous install | Incognito window / clear cookies for the parent domain |
| "No resources are available" | Agent not enabled yet, or enabled <30s ago | Enable it; wait one heartbeat cycle (~15s) |
| "Image Not Authorized" | Workspace not assigned to the user's group | The All Users click in step 3 |
| Login 500 on a fresh install | `kasm_auth_domain` was preseeded via `config.settings` | Never do that — use `kasmConfig.authDomain` (the values file here already does) |

## Remaining manual steps

Two manual steps remain in this flow; both are candidates for future automation:

* **Group→image authorization** (the second admin click). Assigning a workspace image to a group
  is still a manual UI/API step: unlike zones, `group_images` has no preseed path, so the
  library-to-group mapping cannot yet be declared in values.
* **Enabling a registering agent** (the first admin click). New agents register disabled and are
  enabled by hand; auto-enable would be operator/manager behavior.
