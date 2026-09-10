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

1. Add the setting to the preseed and install. `generatePreseed` must be on for `config.settings`
   to be applied.

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

3. Agents already registered stay as they are. Enable them once by hand, or delete and recreate the
   `Agent` resource so it registers again.

## Verify

Register a new agent (or `kubectl delete agents.agent.kasm.com k8s-agent -n <ns>` and let the
chart's resource be recreated by `helm upgrade`), then:

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

- [ ] Fresh install: `auto_agent` seeded through `kasmConfig.config.settings` with `generatePreseed: true`.
- [ ] Existing database: the setting flipped in the UI or with `update_setting`.
- [ ] Agents that registered before the change enabled once by hand.
- [ ] Group assignment for workspace images still owned by someone.
