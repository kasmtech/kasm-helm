# Contributing to the documentation

The documentation under `docs/` follows [Diátaxis](https://diataxis.fr/): four kinds of page,
never mixed inside one file. This page says how to write one that fits.

## Reference Kasm's documentation, do not repeat it

Anything an administrator does in the Kasm admin UI or API (zones, settings, egress providers,
workspace images, groups) works the same on Kubernetes and is documented by Kasm. A page here says
what is Kubernetes-specific, names the menu path once when a step needs it, and links the Kasm page
for the rest. Never transcribe Kasm's configuration into these pages. The links live in
[Where Kasm's documentation takes over](docs/reference/kasm-docs.md); add a row there when a new page
needs one.

## The four kinds

| Kind | Directory | Answers | Rules |
| ---- | --------- | ------- | ----- |
| Tutorial | `docs/tutorials/` | "Show me" | Exactly one: `get-started.md`. A guided path that is guaranteed to work, with expected output at every step. |
| How-to | `docs/how-to/` | "How do I" | One task per page, for someone who already knows what they want. Follows the skeleton below. |
| Explanation | `docs/explanation/` | "Why" | Trade-offs and reasons. No procedures; only illustrative commands. |
| Reference | `docs/reference/` | "What exactly" | Tables, values, exact names. Chart READMEs are reference too. |

If a page needs to explain and instruct, split it: the reasoning goes to `explanation/`, the
procedure to `how-to/`, and each links the other with its title as the link text.

## The how-to skeleton

Headings verbatim, in this order:

```markdown
# Title (an imperative: "Publish the RDP gateway")

> **Applies to:** control plane · agent · both

## Why this is needed        (2 to 5 lines; optional)
## Before you start
## Steps
## Verify                    (commands WITH expected output)
## Chart values              (the values block, once)
## Troubleshooting           (only failures specific to this page; else one link to reference/troubleshooting.md)
## Decisions                 (3 to 8 checkbox lines)
```

No `## Checklist` sections: the Decisions block is the checklist. State a rule once, on the page
that owns it, and link to it from everywhere else. The owners today:

| Rule | Owner |
| ---- | ----- |
| Leave `networkPolicies` off in a namespace shared with the control plane | [Deployment topologies](docs/explanation/topologies.md) |
| Idle timeout of 3600s or more on whatever fronts the session proxy | [LoadBalancer and NodePort, Idle timeouts](docs/how-to/networking/loadbalancer-nodeport.md#idle-timeouts) |
| A TLS wildcard matches one label | [Certificates](docs/how-to/networking/certificates.md) |
| How direct-connect works, and how to switch to it | [Deployment topologies](docs/explanation/topologies.md) and [Switch sessions to direct-connect](docs/how-to/networking/direct-connect.md) |
| Symptom, cause, command | [Troubleshooting](docs/reference/troubleshooting.md) |

## Page conventions

- The first line is the H1. The second non-blank line is the banner:
  `> **Applies to:** control plane · agent · both`. Never above the H1.
- Admonitions are `> **Note.** …` and `> **Warning.** …`. Never the `>>> [!warning]` site syntax.
- Values are written as they appear in a `kasm-platform` values file
  (`kasm-helm.publicAddr`, `kasm-agent.agent.publicHostname`). The index states the convention once;
  pages do not restate it.
- Short sentences. Lead with the answer. Tables for parallel facts. No em dashes. No "simply", no
  "just". Do not narrate history except in changelogs.
- Every verification command sits in a fenced block with its expected output.
- Link with the target page's title as the link text, never a section number.
- No trailing `---` rule at the end of a page.

## Diagrams

Inline mermaid only: no SVG exports, no ASCII arrows, no `graph TD`. The palette follows the Kasm
documentation's own architecture drawings: light-grey cards, dashed tiers, and edge colours that say
what travels on the edge. Every flowchart starts with this init block on its first line:

```text
%%{init: {"theme":"base","themeVariables":{"background":"#ffffff","primaryColor":"#f2f4f7","primaryBorderColor":"#f2f4f7","primaryTextColor":"#0f2a44","lineColor":"#0f2a44","clusterBkg":"#ffffff","clusterBorder":"#4a4a4a","edgeLabelBackground":"#ffffff","fontFamily":"Montserrat, Helvetica, Arial, sans-serif","fontSize":"13px"},"flowchart":{"curve":"linear","htmlLabels":true,"nodeSpacing":36,"rankSpacing":64}}}%%
```

A sequence diagram starts with the plain init instead: no fills, navy lines and text.

```text
%%{init: {"theme":"base","themeVariables":{"background":"#ffffff","primaryColor":"#ffffff","primaryBorderColor":"#0f2a44","primaryTextColor":"#0f2a44","lineColor":"#0f2a44","actorBkg":"#ffffff","actorBorder":"#0f2a44","actorTextColor":"#0f2a44","signalColor":"#0f2a44","signalTextColor":"#0f2a44","activationBkgColor":"#ffffff","activationBorderColor":"#0f2a44","fontFamily":"Montserrat, Helvetica, Arial, sans-serif","fontSize":"13px"}}}%%
```

Three levels, matched to the quadrant:

| Level | Where | Shape |
| ----- | ----- | ----- |
| 0 | root README, tutorial | `flowchart LR`, three nodes: Browser, Control plane, Agent (sessions) |
| 1 | explanation | `flowchart TB` for the chart tree; `flowchart LR` for relayed vs direct, two diagrams with the same nodes |
| 2 | how-to | one `flowchart LR` per exposure mechanism: Browser, then the front end, then the Service, then the pod, with the port on each edge label |

Node ids and labels are the same on every page:

```text
browser["Browser"]   cp["Control plane proxy"]   sp["Session proxy"]   ws["Workspace pod"]
lb["LoadBalancer"]   ing["Ingress controller"]    gw["Gateway"]         route["OpenShift router"]
```

Every node is a card. Declare the class once per diagram and put `:::card` on every node
declaration; a node that only appears in an edge gets its own declaration line so the class applies.
No `classDef agent`, no `classDef ext`, no `class ...` lines.

```text
classDef card fill:#f2f4f7,stroke:#f2f4f7,color:#0f2a44,font-weight:600
browser["Browser"]:::card
```

Every subgraph gets a `style` line: dashed dark grey for a tier, a cluster, a zone or a namespace;
light blue for the box where sessions run.

```text
style <id> fill:#ffffff,stroke:#4a4a4a,stroke-dasharray:6 4
style <id> fill:#ffffff,stroke:#5aa9e6,stroke-width:2px
```

Every edge gets a `linkStyle` by what travels on it. Indices follow declaration order in the source,
and edges written inside a subgraph count where they appear; indices that share a style go on one
line (`linkStyle 0,1,4 stroke:#e0413f,stroke-width:2px`). Every line is `stroke:<hex>,stroke-width:2px`
plus the dash array where the table names one.

| Colour | Hex | What travels |
| ------ | --- | ------------ |
| red | `#e0413f` | HTTPS between tiers (443, 8443, 4444) |
| light blue | `#5ec2ef` | the browser to the web app or control plane: login, UI |
| yellow | `#f0b429` | the second path or population: the direct session connection, the other zone |
| dark blue | `#1a3ec8` | RDP |
| purple | `#b39ddb` | KasmVNC, session proxy to workspace (6901) |
| orange | `#e9a53b` | database |
| green | `#4cc44c` | proxy to endpoints (RDP, VNC, SSH), egress to the internet |
| dark grey, dashed | `#4a4a4a` + `stroke-dasharray:6 4` | control traffic: register, heartbeat, a user choosing, dependency lines |
| the path's colour, dotted | `stroke-dasharray:2 4` | launch, "creates" |

Edge labels keep their text; where a label names a protocol and a port, write it as
`PROTOCOL (port) · detail`, for example `HTTPS (443) · kasm.example.com`. Left to right for traffic,
top to bottom for trees.

## Checking links

```console
make linkcheck
```

runs `scripts/linkcheck.py`, which follows every relative link and anchor in every markdown file in
the repository, chart READMEs included. Expected output ends with:

```text
0 broken link(s), 0 fragile anchor(s) across N markdown files
```

A "fragile anchor" is a heading whose slug contains `--` (a punctuation character deleted between
two spaces); reword the heading rather than link to it.

## Chart READMEs

`charts/*/README.md` is generated by helm-docs from `README.md.gotmpl` and `values.yaml`. Edit those,
then `make readme-all`; `make readme-check-all` fails when a README is stale. How to package and push
the charts is in [Publish the charts](docs/how-to/publish-charts.md).

The published charts also carry the three files Rancher's Apps catalog reads (`catalog.cattle.io/*`
annotations in `Chart.yaml`, `app-readme.md`, `questions.yaml`). `make rancher-check` verifies them;
it fails on a question whose `variable` names no value in the chart or the dependency its prefix
names. Keep `charts/kasm-platform/questions.yaml` in step with the `kasm-helm` and `kasm-agent`
forms it mirrors under those prefixes.
