# Enable agents automatically

> **Applies to:** control plane

## Why this is needed

A new agent registers **disabled** and stays that way until someone clicks **Enable** under
Infrastructure → Agents. The manager setting `auto_agent` ("Automatically Enable Agents", category
`scale`) enables an agent as it registers. It acts only on a registration event: a pod restart
resumes heartbeats and changes nothing, and an agent that re-registers after a gap is enabled
again by the same rule.

## Before you start

- Know which case you are in. On a **fresh** install the setting can be seeded at database
  initialization. On an **existing** database the seed no longer runs and the setting is changed
  in the admin UI or through the API.
- Workspace authorization is a separate step with no preseed path (`group_images`): each image
  still has to be assigned to a group under Workspaces → the image.

## Steps

### Fresh install: seed it

1. Turn on the value that seeds the setting, and the preseed that carries it, and install:

   ```yaml
   kasm-helm:
     kasmConfig:
       generatePreseed: true
       autoEnableAgents: true
   ```

   A release installed through Rancher's catalog has both on already (their unset default is "on
   under Rancher, off elsewhere"), so there is nothing to add there. The long form still works and
   wins over `autoEnableAgents` when both name `auto_agent`:

   ```yaml
   kasm-helm:
     kasmConfig:
       generatePreseed: true
       config:
         settings:
           - category: scale
             name: auto_agent
             title: "Automatically Enable Agents"
             value_type: bool
             value: "True"
             sanitize: false
   ```

2. Install as usual. Agents that register after the database initialized come up enabled.

### Existing database: change it

1. In the admin UI: **Settings → Global Settings → Scale → Automatically Enable Agents → on**
   ([Kasm docs: Settings](https://www.kasmweb.com/docs/latest/guide/settings.html)).

2. Or through the API, with the admin credentials:

   ```console
   POST /api/authenticate          {"username":"admin@kasm.local","password":"<admin password>"}   -> token
   POST /api/admin/get_settings    {"username":"admin@kasm.local","token":"<token>"}              -> the entry with name "auto_agent"; note its setting_id
   POST /api/admin/update_setting  {"username":"admin@kasm.local","token":"<token>","setting_id":"<id>","value":"True"}
   ```

   `setting_id` and `value` are top-level keys; a `target_setting` wrapper does not work.

3. Agents already registered stay as they are. Enable them once by hand. Deleting and recreating
   the `Agent` resource is not enough on its own: the manager keeps one server record per agent
   hostname and re-uses it, enabled state included, when the same hostname registers again. To
   produce a **new** registration, delete the record first under Infrastructure → Agents (API:
   `delete_server` with `server_type: "host"` in `target_server`), then recreate the `Agent`.

## Verify

Register a new agent (or delete its server record under Infrastructure → Agents, then
`kubectl delete agents.agent.kasm.com k8s-agent -n <ns>` and let the chart's resource be
recreated by `helm upgrade`), then:

```console
kubectl get agents.agent.kasm.com -n <ns>
```

Expected: `PHASE Ready`, and under Infrastructure → Agents the new agent shows **Enabled** without a
click. A session launched after one heartbeat interval (about 15 seconds) starts instead of
failing with "No resources are available".

## Chart values

```yaml
kasm-helm:
  kasmConfig:
    generatePreseed: true
    config:
      settings:
        - category: scale
          name: auto_agent
          title: "Automatically Enable Agents"
          value_type: bool
          value: "True"
          sanitize: false
```

Installing `kasm-helm` directly, drop the `kasm-helm:` key. The rest of the `settings` shape is in
[Preseeding](../reference/preseed.md#settings).

## Troubleshooting

"No resources are available" on launch with `auto_agent` on: the agent registered before the
setting changed, or fewer than 15 seconds have passed since it enabled. "Image Not Authorized": the
group assignment, which this setting does not cover. Otherwise
[Troubleshooting](../reference/troubleshooting.md).

## Decisions

- [ ] Fresh install: `kasmConfig.autoEnableAgents: true` with `generatePreseed: true` (both on by default under Rancher), or the `auto_agent` entry in `kasmConfig.config.settings`.
- [ ] Existing database: the setting flipped in the UI or with `update_setting`.
- [ ] Agents that registered before the change enabled once by hand, or their server records deleted before re-registering.
- [ ] Group assignment for workspace images still owned by someone.
