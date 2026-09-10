# Why the charts ship no hook Jobs

> **Applies to:** both halves

Two things a fresh Kasm deployment needs cannot be expressed as a Kubernetes manifest: the Kasm
Authorization Domain on a database that already exists, and the two admin clicks that enable an
agent and authorize a workspace image for a group. A Helm hook Job could log in to the API and
make those calls after install. `kasm-platform` deliberately does not ship one.

The reasons, from the umbrella chart's own values file:

- **A hook is a program running with admin credentials inside your release**, on every install and
  upgrade, against a database it did not create. Its failure modes (a wrong password, a half-applied
  change, a retry against a control plane still starting) are harder to reason about than a documented
  manual step, and they are invisible in `helm template`.
- **On a fresh install the values suffice.** `kasm-helm.kasmConfig.authDomain` is applied at database
  initialization, and `auto_agent` can be seeded the same way
  ([Enable agents automatically](../how-to/enable-agents-automatically.md)). The hook would only ever
  matter on an existing database, which is precisely the case where an operator should decide.
- **Group authorization has no preseed path** (`group_images`), so a hook could not make the install
  complete either; it would move one click, not remove the step.

So the umbrella composes two complete charts and gets out of the way. What remains manual is
written down where you will meet it: in the release notes, in
[Get started](../tutorials/get-started.md), and in
[Switch sessions to direct-connect](../how-to/networking/direct-connect.md) for the existing-database
case, which is three API calls.
