# Default Users and Groups

This document describes every user account, group, and group permission that `kasmConfig.defaultUsers: true` seeds into the database. All entries are generated at DB initialization time via the preseed mechanism and are not re-applied on upgrade.

## Control flags

```yaml
kasmConfig:
  generatePreseed: true
  defaultUsers: true
  adminUsername: "admin@kasm.local"  # optional; defaults to admin@kasm.local
```

`defaultUsers` seeds users and groups only. API credentials are controlled separately by [`defaultApiUsers`](default-api-users.md).

`adminUsername` sets the login username for the seeded admin account (the `admins`-group member). It defaults to `admin@kasm.local`, the only true built-in administrator account. Setting it to any other value (for example, `system@kasm.local` for Kasm internal deployments) still seeds an admin-group member under that username, but it is no longer treated as the built-in account: its password and salt are generated the same way as any other non-built-in user (see below), under a secret key derived from the local part of the username (the part before `@`) — e.g. `system@kasm.local` → `system-password`/`system-salt`. In that case the chart also does not create the `admin-password` key in the `<release>-secrets` Secret at all, and does not populate `DEFAULT_ADMIN_PASSWORD` for the db-init Job. All other user accounts, group memberships, and permissions are unaffected by this value.

---

## Users

| Username | Realm | Built-in | crypt index | Groups |
|---|---|---|---|---|
| `admin@kasm.local` | local | yes (index 2) | `${crypt:password:2}` | all_users, admins |
| `user@kasm.local` | local | yes (index 1) | `${crypt:password:1}` | all_users |
| `siteadmin@kasm.local` | local | no | generated | site_admins, all_site_users, all_users |
| `workspaceadmin@kasm.local` | local | no | generated | workspace_admins, all_site_users, all_users |

**Built-in users** are exactly `admin@kasm.local` and `user@kasm.local` — these two usernames use Kasm startup token credentials regardless of any other configuration. The admin account password is the `admin-password` key in the `<release>-secrets` Secret. The user account password is the `user-password` key in the same Secret. Both keys only exist while their respective built-in account is actually seeded.

**Non-built-in users** (`siteadmin@kasm.local` → `site-admin-password`/`site-admin-salt`, `workspaceadmin@kasm.local` → `workspace-admin-password`/`workspace-admin-salt`, and the `admins`-group member seeded when `adminUsername` is set to anything other than `admin@kasm.local` → `<local-part>-password`/`<local-part>-salt`) receive generated credentials stored in the `<release>-secrets` and `<release>-password-salts` Secrets under these short, readable keys — the same naming convention used for every non-built-in default user.

---

## Groups

### all_users

| Field | Value |
|---|---|
| `group_id` | `68d557ac-4cac-42cc-a9f3-1c7c853de0f3` (stable UUID) |
| `is_system` | true |
| `priority` | 1000 |

**Permissions:** `user`

**Settings:**

| Setting | Value |
|---|---|
| `allow_kasm_pause` | False |
| `allow_kasm_stop` | False |
| `keepalive_expiration_action` | delete |
| `usage_limit` | {} |

---

### admins (Administrators)

| Field | Value |
|---|---|
| `group_id` | `${uuid:group_id:2}` |
| `is_system` | true |
| `priority` | 1 |

**Permissions:** `global_admin`

**Settings:**

| Setting | Value |
|---|---|
| `allow_kasm_pause` | True |
| `allow_kasm_stop` | True |
| `allow_totp_2fa` | True |
| `disabled_image_message` | "This image is currently disabled." |
| `require_2fa` | True |
| `show_disabled_images` | True |

---

### all_site_users (All Site Users)

| Field | Value |
|---|---|
| `group_id` | `${uuid:group_id:N}` (generated) |
| `is_system` | false |
| `priority` | 1000 |

**Permissions:** `user`

**Settings (partial — full list is authoritative in `_kasm_config_helper.tpl`):**

| Setting | Value |
|---|---|
| `allow_2fa_self_enrollment` | True |
| `allow_kasm_audio` | True |
| `allow_kasm_clipboard_down` | True |
| `allow_kasm_clipboard_seamless` | True |
| `allow_kasm_clipboard_up` | True |
| `allow_kasm_delete` | True |
| `allow_kasm_downloads` | True |
| `allow_kasm_gamepad` | True |
| `allow_kasm_microphone` | True |
| `allow_kasm_printing` | True |
| `allow_kasm_sharing` | True |
| `allow_kasm_uploads` | True |
| `allow_kasm_webcam` | True |
| `allow_persistent_profile` | True |
| `allow_totp_2fa` | True |
| `allow_user_storage_mapping` | True |
| `allow_webauthn_2fa` | True |
| `auto_add_local_users` | True |
| `idle_disconnect` | 20 |
| `keepalive_expiration` | 3600 |
| `keepalive_expiration_action` | delete |
| `max_kasms_per_user` | 5 |
| `max_user_storage_mappings` | 2 |

---

### site_admins (Site Administrators)

| Field | Value |
|---|---|
| `group_id` | `${uuid:group_id:N}` (generated) |
| `is_system` | false |
| `priority` | 3 |

**Permissions:**

`user`, `users_view`, `users_modify`, `users_create`, `users_delete`, `users_auth_session`, `groups_view`, `groups_modify`, `groups_create`, `groups_delete`, `groups_view_ifmember`, `groups_modify_ifmember`, `agents_view`, `staging_view`, `casting_view`, `casting_modify`, `casting_create`, `casting_delete`, `sessions_view`, `sessions_modify`, `sessions_delete`, `session_recordings_view`, `images_view`, `images_modify`, `images_create`, `images_delete`, `images_modify_resources`, `devapi_view`, `webfilters_view`, `webfilters_modify`, `webfilters_create`, `webfilters_delete`, `brandings_view`, `brandings_modify`, `brandings_create`, `brandings_delete`, `settings_view`, `settings_modify_auth`, `settings_modify_storage`, `auth_view`, `auth_modify`, `auth_create`, `auth_delete`, `licenses_view`, `system_view`, `system_export_schema`, `reports_view`, `zones_view`, `connection_proxy_view`, `physical_tokens_view`, `physical_tokens_modify`, `physical_tokens_create`, `physical_tokens_delete`, `servers_view`, `autoscale_schedule_view`, `registries_view`, `registries_modify`, `registries_create`, `registries_delete`, `storage_providers_view`, `storage_providers_modify`, `storage_providers_create`, `storage_providers_delete`, `egress_gateways_view`, `egress_gateways_modify`, `egress_gateways_create`, `egress_gateways_delete`, `egress_credentials_view`, `egress_credentials_modify`, `egress_credentials_create`, `egress_credentials_delete`, `egress_providers_view`, `egress_providers_modify`, `egress_providers_create`, `egress_providers_delete`, `ad_user_management_view`, `ad_user_management_modify`, `ad_user_management_create`, `ad_user_management_delete`, `banners_view`, `banners_modify`, `banners_create`, `banners_delete`, `labels_view`

---

### workspace_admins (Workspace Administrators)

| Field | Value |
|---|---|
| `group_id` | `${uuid:group_id:N}` (generated) |
| `is_system` | false |
| `priority` | 4 |

**Permissions:**

`user`, `users_view`, `groups_view`, `agents_view`, `staging_view`, `casting_view`, `casting_modify`, `casting_create`, `casting_delete`, `sessions_view`, `sessions_modify`, `sessions_delete`, `images_view`, `images_modify`, `images_create`, `images_delete`, `images_modify_resources`, `webfilters_view`, `system_view`, `reports_view`, `zones_view`, `servers_view`, `server_pools_view`, `registries_view`, `registries_modify`, `registries_create`, `registries_delete`, `storage_providers_view`

---

## Overriding defaults

Supply a matching entry under `kasmConfig.config.users` or `kasmConfig.config.groups` using the same `username`/`name` or `key`. Your entry wins on key collision; the default is not emitted for that entry.

```yaml
kasmConfig:
  generatePreseed: true
  defaultUsers: true
  config:
    users:
      - username: "admin@kasm.local"
        pw_hash: "your-custom-hash"
    groups:
      - key: admins
        priority: 10
```
