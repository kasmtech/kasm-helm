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

Inline mermaid only: no SVG exports, no ASCII arrows, no `graph TD`. Every diagram starts with this
init block on its first line:

```text
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#eef3f8","primaryBorderColor":"#5b7a99","primaryTextColor":"#1d2b3a","secondaryColor":"#fbf3e6","secondaryBorderColor":"#b8863b","tertiaryColor":"#eaf5ec","tertiaryBorderColor":"#4f8a5b","lineColor":"#5b7a99","fontFamily":"Inter, Helvetica, Arial, sans-serif","fontSize":"14px"},"flowchart":{"curve":"basis","htmlLabels":true}}}%%
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

Classes, declared with exactly these definitions: control plane nodes take the primary colour by
default; agent nodes get `classDef agent fill:#eaf5ec,stroke:#4f8a5b`; external things (browsers,
load balancers, gateways) get `classDef ext fill:#fbf3e6,stroke:#b8863b`. Left to right for
traffic, top to bottom for trees.

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
