# Default API Users

This document describes every API credential that `kasmConfig.defaultApiUsers: true` seeds into the database. All entries are generated at DB initialization time via the preseed mechanism and are not re-applied on upgrade.

>>> [!warning] The current version of Kasm does not apply the permissions listed below at DB initialization time. This is an application bug, not a Helm chart defect, and is queued for a fix. The API configs are created, but with no permissions granted; assign them manually via the Kasm API/UI after install until the bug is resolved.
>>>

## Control flag

```yaml
kasmConfig:
  generatePreseed: true
  defaultApiUsers: true
```

`defaultApiUsers` seeds API credentials only. User accounts and groups are controlled separately by [`defaultUsers`](default-users.md).

Both flags are independent and can be combined:

```yaml
kasmConfig:
  generatePreseed: true
  defaultUsers: true      # users + groups
  defaultApiUsers: true   # API credentials
```

---

## API configs

### kasm_engineering_api (Kasm Engineering Automation)

Read-write API key used by Kasm automation tooling to manage autoscale and VM provider infrastructure.

| Field | Value |
|---|---|
| `api_key` | `KasmRWApiKey` |
| `read_only` | false |
| `enabled` | true |

**Permissions:**

| Permission | ID |
|---|---|
| `autoscale_create` | 2502 |
| `autoscale_delete` | 2503 |
| `autoscale_modify` | 2501 |
| `autoscale_schedule_create` | 2702 |
| `autoscale_schedule_delete` | 2703 |
| `autoscale_schedule_modify` | 2701 |
| `autoscale_schedule_view` | 2700 |
| `autoscale_view` | 2500 |
| `managers_view` | 1800 |
| `server_pools_view` | 2400 |
| `servers_view` | 2300 |
| `vm_provider_create` | 2602 |
| `vm_provider_delete` | 2603 |
| `vm_provider_modify` | 2601 |
| `vm_provider_view` | 2600 |
| `zones_view` | 1900 |

---

### kcs_api (Kasm Customer Support)

Read-only API key used by Kasm support staff for diagnostic access. No write permissions.

| Field | Value |
|---|---|
| `api_key` | `KcsReadApiKy` |
| `read_only` | true |
| `enabled` | true |

**Permissions:**

| Permission | ID |
|---|---|
| `user` | 100 |
| `users_view` | 300 |
| `groups_view` | 400 |
| `groups_view_ifmember` | 420 |
| `groups_view_system` | 440 |
| `agents_view` | 500 |
| `staging_view` | 600 |
| `casting_view` | 700 |
| `images_view` | 900 |
| `sessions_view` | 800 |
| `session_recordings_view` | 850 |
| `webfilters_view` | 1100 |
| `brandings_view` | 1200 |
| `settings_view` | 1300 |
| `auth_view` | 1400 |
| `licenses_view` | 1500 |
| `system_view` | 1600 |
| `reports_view` | 1700 |
| `managers_view` | 1800 |
| `zones_view` | 1900 |
| `companies_view` | 2000 |
| `connection_proxy_view` | 2100 |
| `physical_tokens_view` | 2200 |
| `servers_view` | 2300 |
| `server_pools_view` | 2400 |
| `autoscale_view` | 2500 |
| `vm_provider_view` | 2600 |
| `autoscale_schedule_view` | 2700 |
| `dns_providers_view` | 2800 |
| `registries_view` | 2900 |
| `storage_providers_view` | 3000 |
| `egress_providers_view` | 4000 |
| `egress_gateways_view` | 4100 |
| `ad_user_management_view` | 4300 |
| `banners_view` | 4400 |
| `server_templates_view` | 4500 |
| `labels_view` | 4600 |

---

## Credential storage

API key secrets (the hashed secret, not the `api_key` string) are stored in the `<release>-secrets` and `<release>-password-salts` Secrets as pre-install/pre-upgrade hooks. The chart re-reads these Secrets on `helm upgrade` via `lookup`, so secrets are stable across upgrades.

The `api_key` values (`KasmRWApiKey`, `KcsReadApiKy`) are static and not stored in Secrets. They are embedded directly in the preseed.

---

## Overriding defaults

Supply a matching entry under `kasmConfig.config.apiConfigs` using the same `key` or `name`. Your entry wins on key collision; the default is not emitted for that entry.

```yaml
kasmConfig:
  generatePreseed: true
  defaultApiUsers: true
  config:
    apiConfigs:
      - key: kasm_engineering_api
        name: Kasm Engineering Automation
        api_key: MyCustomApiKey
        read_only: false
        enabled: true
        permissions:
          - autoscale_view
          - autoscale_modify
```
