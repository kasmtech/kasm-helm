# Kasm DB Preseed

The preseed feature generates a `custom_properties.yaml` that the chart's db-init Job merges (with `yq`) into the image's baked-in `default_properties.yaml` before Kasm's `startup.sh` consumes it. This lets you declare Kasm configuration—users, groups, images, autoscale providers, SSO connectors, and more—as Helm values rather than post-install API calls.

> [!WARNING]
> The current version of Kasm does not apply API config permissions (`apiConfigs[].permissions`) seeded via DB Preseed. This is an application bug, not a Helm chart defect, and is queued for a fix. Seeded API configs are created, but any `permissions` list on them is not applied at DB initialization time; grant permissions manually via the Kasm API/UI after install until the bug is resolved.

## Enabling Preseed

Three top-level flags control the feature. All default to `false` (opt-in).

```yaml
kasmConfig:
  generatePreseed: true  # generate the Secret and mount it into the db-init Job
  defaultUsers: true  # seed default user accounts and groups
  defaultApiUsers: true  # seed default API credentials
```

`generatePreseed: false` produces zero documents and skips all preseed-related work. Set it `true` only on fresh installs (`dbManagement.initialize: true`); rerunning preseed on an existing database is not supported by Kasm.

## Supplying a Custom `default_properties.yaml` via Secret

`kasmConfig.config` expresses preseed data as Helm values, which the chart renders into `custom_properties.yaml` and merges with Kasm's baked-in `default_properties.yaml`. For infrastructure-as-code workflows that manage the entire seed file directly as a Kubernetes Secret—rather than expressing every section as Helm values—reference that Secret with `kasmConfig.existingDefaultPropertiesSecret`:

```yaml
kasmConfig:
  existingDefaultPropertiesSecret:
    name: my-custom-seed  # Secret name; must already exist in the release namespace
    key: default_properties.yaml # data key within the Secret containing the seed file
```

Create the Secret before installing or upgrading the release:

```bash
kubectl create secret generic my-custom-seed \
  --namespace <release-namespace> \
  --from-file=default_properties.yaml=./default_properties.yaml
```

When `existingDefaultPropertiesSecret.name` is set, the db-init Job mounts the Secret and copies its contents over the image's baked-in `default_properties.yaml` before DB initialization runs. This works independently of `generatePreseed`:

- `existingDefaultPropertiesSecret` only (`generatePreseed: false`): the customer-provided file is used as-is, with no chart-side merge.
- `existingDefaultPropertiesSecret` and `generatePreseed: true` together: the customer-provided file becomes the base seed file, and the chart's `kasmConfig.config`-generated `custom_properties.yaml` is merged on top of it (same merge semantics described above).

The Secret is read once, at db-init Job runtime, on every install where `dbManagement.initialize: true`; like the rest of preseed, it has no effect on an already-initialized database.

## Default Users and API Users

```yaml
kasmConfig:
  generatePreseed: true
  defaultUsers: true
  defaultApiUsers: true
```

### Default Users

`defaultUsers: true` seeds:
- Users:
  - `admin@kasm.local`
  - `user@kasm.local`
  - `siteadmin@kasm.local`
  - `workspaceadmin@kasm.local`
- Groups:
  - `all_users`
  - `admins`
  - `all_site_users`
  - `site_admins`
  - `workspace_admins`

The default Administrator user is `admin@kasm.local`, the only true built-in admin account. Use `adminUsername` to change the login username seeded on the admin-group member (for example, `system@kasm.local`); doing so seeds that account with generated (non-built-in) credentials instead of the built-in `admin@kasm.local` token-based credentials — see [Default Users and Groups](default-users.md#users).

> [!NOTE]
> See [Default Users and Groups](default-users.md) for the full account list, group membership, and per-group permission set.

### Default API Users

`defaultApiUsers: true` seeds:
- API configs: `kasm_engineering_api` (read-write automation key), `kcs_api` (read-only support key)

`defaultUsers` and `defaultApiUsers` are independent. Set both to reproduce the full default seed:

> [!NOTE]
> See [Default API Users](default-api-users.md) for the full API credential list and permission set.

User-supplied entries under `kasmConfig.config` override defaults when `username`, `key`, or `name` matches.

## kasmConfig Values Structure

All preseed data sections live under `kasmConfig.config`. The top-level `kasmConfig` key holds only the two control flags.

```yaml
kasmConfig:
  generatePreseed: true
  defaultUsers: false
  defaultApiUsers: false
  adminUsername: "admin@kasm.local"  # optional; set to override the seeded admin account username
  config:
    groups: []
    users: []
    apiConfigs: []
    settings: []
    groupSettings: []
    images: []
    zones: []  # derived from kasmZones; do not set manually
    registries: []
    server_pools: []
    autoscale: []
    oidcConfigs: []
    samlConfigs: []
    ldapConfigs: []
    branding: []
    aws_configs: []
    azure_configs: []
    digital_ocean_vm_configs: []
    gcp_vm_configs: []
    harvester_vm_configs: []
    kubevirt_vm_configs: []
    nutanix_vm_configs: []
    oci_vm_configs: []
    openstack_vm_configs: []
    proxmox_vm_configs: []
    vsphere_vm_configs: []
    filter_policies: []
    banners: []
    cast_configs: []
    sso_to_group_mapping: []
    sso_attribute_userfield_mapping: []
    schedules: []
    staging_configs: []
    storage_providers: []
    storage_mappings: []
    file_mappings: []
    domains: []
    labels: []
    aws_dns_configs: []
    azure_dns_configs: []
    digital_ocean_dns_configs: []
    gcp_dns_configs: []
    oci_dns_configs: []
```

Sections that are absent or empty render as `[]` in the preseed. Omitting a section is equivalent to setting it to an empty list.

## ID and token resolution

The chart emits placeholder tokens at render time. They are expanded by Kasm's seed loader (`initialize_postgres_db.py`, invoked as `server.pyc --initialize-database`) during DB initialization, not by Helm and not by `startup.sh`. Each distinct token string is replaced consistently throughout the file, which is what makes cross-references by token work.

| Token syntax | Replaced with | Example |
|---|---|---|
| `${uuid:TYPE:N}` | a fresh UUID4, one per distinct token | `${uuid:group_id:1}` |
| `${crypt:password:N}` | 256 random bytes, hex-encoded | `users[].crypt_password` |
| `${crypt:salt:N}` | 256 random bytes, hex-encoded | `users[].crypt_salt` |
| `${datetime:utcnow}` | the current UTC timestamp | `users[].created` |

For user-supplied entities (non-built-in users, API configs), the chart generates a random password at render time, stores it in the `<release>-secrets` Secret, and stores the corresponding salt in `<release>-password-salts`. On subsequent `helm upgrade` calls, the chart re-reads those Secrets via `lookup` so passwords are stable across upgrades.

Built-in users (exactly `admin@kasm.local` and `user@kasm.local`) get their login credential a different way. The chart renders a placeholder `pw_hash`/`salt` for them, and `startup.sh` overwrites both in the merged seed file from the `DEFAULT_ADMIN_PASSWORD` / `DEFAULT_USER_PASSWORD` environment variables, which the db-init Job sources from the `admin-password` and `user-password` keys of the passwords Secret. The `${crypt:password:N}` / `${crypt:salt:N}` tokens are unrelated to login: they populate the separate encrypted `crypt_password`/`crypt_salt` columns, are rendered for every user (not just built-ins), and always resolve to random bytes. If `kasmConfig.defaultUsers` and `kasmConfig.adminUsername` (set to anything other than `admin@kasm.local`) replace it with a renamed admin account, that account is no longer a built-in user: it gets a generated password/salt/hash like any other non-built-in user, stored under a `<local-part>-password`/`<local-part>-salt` key pair (e.g. `system@kasm.local` → `system-password`), and the chart does not create an `admin-password` key at all in that case.

### Name-based cross-references

Several sections accept a `*_name` field as an alternative to a `*_id` field. The chart resolves the name to the generated UUID at render time.

```yaml
kasmConfig:
  config:
    server_pools:
      - name: primary-pool
        server_pool_id: "pool-uuid-001"  # explicit ID takes precedence
    images:
      - name: kasmweb/ubuntu-focal-desktop
        pool_name: primary-pool  # resolved to pool-uuid-001
    autoscale:
      - autoscale_config_name: my-agent
        pool_name: primary-pool  # resolved
        zone_name: default  # resolved from kasmZones
        aws_config_name: my-aws  # resolved from aws_configs
```

`server_pools[].type` (or `server_pool_type`) accepts only the values Kasm understands: `Docker Agent` and `Server Pool`. Matching is case-insensitive and trims whitespace; `docker`, `agent`, and `docker agent` all resolve to `Docker Agent`, and `server`/`server pool` resolve to `Server Pool`. If omitted, it defaults to `Docker Agent`. Any other value fails the render.

Supported name lookups:
- `images[].pool_name` → `server_pools[].name`
- `images[].zone_name` → `kasmZones[].name`
- `autoscale[].pool_name` → `server_pools[].name`
- `autoscale[].zone_name` → `kasmZones[].name`
- `autoscale[].*_config_name` → matching `*_configs[].config_name`
- `cast_configs[].group_name` → `groups[].name`
- `group_settings[].group_name` → `groups[].name`

If a referenced name is not found, `helm template` fails with an error.

## Section reference

This section reference lists every top-level key each part of `kasmConfig.config` accepts, matching `charts/kasm-helm/templates/db-preseed-secret.yaml` field for field. Fields not marked `required` are optional and take the default shown when unset (`null` for scalars, `{}`/`[]` — rendered as JSON — for objects/arrays).

### What `required` means

Two independent mechanisms can reject a value, and they fail at different times with different error messages. The markings below distinguish them:

| Marking | Enforced by | Fails when | Symptom |
|---|---|---|---|
| `required` | a `required` guard in `db-preseed-secret.yaml` | `helm template` / `helm install` | render aborts with the guard's message |
| `required (DB)` | a `NOT NULL` column with no column default in Kasm's schema | db-init Job, after render succeeds | Job fails with a Postgres `NotNullViolation` |
| `required` | both | render | render aborts |

The DB-level set is derived from Kasm's SQLAlchemy model (`api_server/api_server/data/model.py`), where a column counts as required exactly when `nullable=False` and it carries neither `default=` nor `server_default=`. That is the same rule Kasm's own `export_schema()` uses to produce `tests/schemas/1_19_0-schema.yaml`, so the schema fixture in this repo agrees with the model for every table the preseed writes to.

Three consequences that are easy to get wrong:

- **A `NOT NULL` column that has a default is not required.** The seed loader constructs each row as `Model(**record)`, and SQLAlchemy substitutes the column default when a field is absent *or* explicitly `null`. The chart emits `null` for many such fields (`images[].gpu_count`, `cast_configs[].session_remaining`, `gcp_vm_configs[].gcp_credentials`, and others) and the insert still succeeds.
- **Several `required (DB)` columns are supplied by the chart, not by you.** `users[].created`, `users[].crypt_password`, `users[].crypt_salt`, `api_configs[].api_key_secret_hash`, `api_configs[].salt`, `api_configs[].created`, `banners[].config`, `domains[].created`, `domains[].updated`, and all eleven of `branding`'s `NOT NULL` text/URL columns are `NOT NULL` with no default, but the chart always renders a value. They are not listed as required below because you never have to set them.
- **A `required` marking does not imply the column is `NOT NULL`.** `groups[].name`, `users[].username`, all four `settings[]` fields, both `group_settings[]` fields, `filter_policies[].filter_policy_name`, and three `vsphere_vm_configs[]` fields are nullable in the database; the chart enforces them anyway because a row without them is useless.

Neither mechanism tells you whether a config with only the required fields set will actually *work*. See the note under [VM provider configs](#vm-provider-configs).

### groups

```yaml
kasmConfig:
  config:
    groups:
      - name: "My Group"  # required; a `group_name` alias is also accepted. `groups.name` is nullable in the DB
        description: ""  # optional
        group_id: null  # optional; auto-generated (${uuid:group_id:N}) if omitted
        group_metadata: null  # optional; arbitrary JSON object
        is_system: false  # optional; default false
        key: null  # optional; alternate lookup name used by `group_name` references elsewhere (defaults to `name` if unset)
        priority: 1000  # optional; default 1000
        program_data: null  # optional; arbitrary JSON object
        permissions:  # optional; list of permission names, seeded into group_permissions
          - users_view
          - images_view
        settings:  # optional; map of setting-name -> {value, value_type, description}, seeded into group_settings
          allow_kasm_audio:
            value: "True"
            value_type: bool
            description: ""
```

### users

```yaml
kasmConfig:
  config:
    users:
      - username: "ops@example.com"  # required; `users.username` is nullable in the DB
        realm: local  # optional; default "local"
        groups:  # optional; list of group names, seeded into user_groups
          - My Group
        password: null  # optional; inline plaintext password for non-built-in users (otherwise a password is generated and stored in the passwords Secret)
        anonymous: false  # optional; default false
        city: null  # optional
        company_id: null  # optional
        country: null  # optional
        custom_attribute_1: null  # optional
        custom_attribute_2: null  # optional
        custom_attribute_3: null  # optional
        disabled: false  # optional; default false
        email: null  # optional; defaults to `username` if unset
        email_confirm_token: null  # optional
        email_pw_reset_request_date: null  # optional
        failed_pw_attempts: null  # optional
        first_name: null  # optional
        last_name: null  # optional
        locked: false  # optional; default false
        notes: null  # optional
        oidc_id: null  # optional
        organization: null  # optional
        phone: null  # optional
        plan_end_date: null  # optional
        plan_id: null  # optional
        plan_start_date: null  # optional
        program_id: null  # optional
        saml_id: null  # optional
        secret: null  # optional
        set_two_factor: false  # optional; default false
        sso_ep: null  # optional
        state: null  # optional
        stripe_id: null  # optional
        subscription_id: null  # optional
        user_id: null  # optional; auto-generated if omitted
        pw_hash: null  # optional; overrides the generated password hash (advanced; normally leave unset)
        salt: null  # optional; overrides the generated salt (advanced; normally leave unset)
        crypt_password: null  # optional; built-in users only, overrides the ${crypt:password:N} token
        crypt_salt: null  # optional; built-in users only, overrides the ${crypt:salt:N} token
        created: null  # optional; defaults to ${datetime:utcnow}
        password_set_date: null  # optional; defaults to ${datetime:utcnow}
```

Non-built-in users get a generated password stored in the passwords Secret (`<local-part>-password`/`<local-part>-salt` keys), and the chart renders the resulting `pw_hash`/`salt` directly. Built-in users (exactly `admin@kasm.local` and `user@kasm.local`) get a placeholder `pw_hash`/`salt` that `startup.sh` overwrites from the `admin-password`/`user-password` Secret keys at db-init time; see [ID and token resolution](#id-and-token-resolution).

`created`, `crypt_password`, and `crypt_salt` are `NOT NULL` with no default in the DB, so every user row must carry them. The chart always renders all three, which is why they are not marked required above.

### apiConfigs

```yaml
kasmConfig:
  config:
    apiConfigs:
      - name: "automation-api"  # required
        api_key: "MyStaticApiKey" # required
        key: null  # optional; alternate identity key used for Secret naming and override matching (defaults to `name`)
        api_id: null  # optional; auto-generated if omitted
        enabled: true  # optional; default true
        read_only: true  # optional; default true (note: defaults to true, not false)
        expires: null  # optional
        api_key_secret_hash: null  # optional; overrides the generated secret hash (advanced; normally leave unset)
        salt: null  # optional; overrides the generated salt (advanced; normally leave unset)
        created: null  # optional; defaults to ${datetime:utcnow}
        permissions:  # optional; list of permission names, seeded into group_permissions
          - autoscale_view
          - autoscale_modify
```

> [!WARNING]
> API `permissions` are not currently applied by Kasm at DB initialization time (application bug, fix pending). The API config is created, but with no permissions granted; assign them manually after install.

### settings

System settings (site-wide configuration).

```yaml
kasmConfig:
  config:
    settings:
      - category: auth  # required; nullable in the DB
        name: auth_totp_enabled  # required; nullable in the DB
        title: "TOTP Auth"  # required; nullable in the DB
        value_type: bool  # required; nullable in the DB
        value: "True"  # optional; default ""; strings/maps/lists are all accepted and serialized appropriately
        description: ""  # optional
        sanitize: false  # optional; default false
        services_restart: null  # optional
        setting_id: null  # optional; auto-generated if omitted
```

### group_settings

Per-group settings can be declared inline under `groups[].settings` (above) or as a standalone top-level list that cross-references a group by name:

```yaml
kasmConfig:
  config:
    group_settings:
      - group_name: "My Group"  # or group_id
        name: allow_kasm_audio  # required; nullable in the DB
        value_type: bool  # required; nullable in the DB
        value: "True"  # optional; default ""
        description: ""  # optional
        group_setting_id: null  # optional; auto-generated if omitted
```

### images

Kasm workspace images (Docker images or remote apps).

```yaml
kasmConfig:
  config:
    images:
      - name: kasmweb/ubuntu-focal-desktop  # optional, but effectively required to identify the image (no `required` guard is enforced by the chart)
        friendly_name: "Ubuntu Desktop"  # optional; defaults to `name`
        pool_name: primary-pool  # optional; name-based lookup, resolved to server_pool_id
        zone_name: default  # optional; name-based lookup, resolved to zone_id
        image_type: Container  # optional; default "Container"
        image_id: null  # optional; auto-generated if omitted
        image_src: null  # optional
        allow_network_selection: false  # optional; default false
        available: true  # optional; default true
        categories: []  # optional; list of category strings
        cores: null  # optional
        cpu_allocation_method: null  # optional
        description: null  # optional
        docker_registry: null  # optional
        docker_token: null  # optional
        docker_user: null  # optional
        enabled: true  # optional; default true
        enforce_workspace_persistence: false  # optional; default false
        exec_config: {}  # optional; arbitrary JSON
        filter_policy_force_disabled: false  # optional; default false
        filter_policy_id: null  # optional
        gpu_count: null  # optional
        hash: null  # optional
        hidden: false  # optional; default false
        is_remote_app: false  # optional; default false
        launch_config: {}  # optional; arbitrary JSON
        link_url: null  # optional
        memory_bytes: null  # optional; raw bytes
        notes: null  # optional
        override_egress_gateways: false  # optional; default false
        persistent_profile_path: null  # optional
        rdp_client_type: null  # optional
        remote_app_args: null  # optional
        remote_app_icon: null  # optional
        remote_app_name: null  # optional
        remote_app_program: null  # optional
        require_gpu: false  # optional; default false
        restrict_network_names: []  # optional; list of network name strings
        restrict_to_network: false  # optional; default false
        restrict_to_server: false  # optional; default false
        restrict_to_zone: false  # optional; default false
        run_config: {}  # optional; arbitrary JSON
        server_id: null  # optional
        server_pool_id: null  # optional; explicit ID, takes precedence over pool_name
        session_banner_force_disabled: false  # optional; default false
        session_banner_id: null  # optional
        session_time_limit: null  # optional
        uncompressed_size_bytes: null  # optional; raw bytes
        volume_mappings: {}  # optional; arbitrary JSON
        x_res: null  # optional
        y_res: null  # optional
        zone_id: null  # optional; explicit ID, takes precedence over zone_name
```

### autoscale

```yaml
kasmConfig:
  config:
    autoscale:
      - autoscale_config_name: "aws-us-east-1"  # required (an `autoscale_config_name`/`name` alias is accepted)
        pool_name: primary-pool  # required; name-based lookup, resolved to server_pool_id. Set `server_pool_id` instead to supply an explicit ID
        zone_name: default  # required (DB); name-based lookup, resolved to zone_id. Set `zone_id` instead to supply an explicit ID
        type: "Docker Agent"  # optional; default "Docker Agent", other option "Server"
        aws_config_name: my-aws  # required; name-based lookup for the matching VM provider — see below
        agent_memory_override_bytes: 4294967296  # optional; default 0, raw bytes
        standby_memory_bytes: 2147483648  # optional; default 0, raw bytes
        max_simultaneous_sessions_per_server: 4  # optional; default 1
        downscale_backoff: 1800  # optional; default 1800
        autoscale_config_id: null  # optional; auto-generated if omitted
        ad_computer_container_dn: null  # optional
        ad_create_machine_record: false  # optional; default false
        ad_recursive_machine_record_cleanup: false  # optional; default false
        agent_cores_override: 0  # optional; default 0
        agent_gpus_override: 0  # optional; default 0
        agent_installed: false  # optional; default false
        aggressive_scaling: true  # optional; default true
        base_domain_name: null  # optional
        connection_credential_type: null  # optional
        connection_info: {}  # optional; default {}; a YAML map, rendered as a JSON object
        connection_passphrase: null  # optional
        connection_password: null  # optional
        connection_port: null  # optional
        connection_private_key: null  # optional
        connection_sso_username_domain: null  # optional
        connection_type: "KasmVNC"  # optional; default "KasmVNC"
        connection_username: null  # optional
        enabled: true  # optional; default true
        hooks: {}  # optional; default {}; a YAML map, rendered as a JSON object
        ldap_id: null  # optional
        max_simultaneous_users: 1  # optional; default 1
        minimum_pool_standby_sessions: 0  # optional; default 0
        register_dns: false  # optional; default false
        require_checkin: false  # optional; default false
        reusable: false  # optional; default false
        rotate_servers_in_days: null  # optional
        rotate_servers_pre_warm_minutes: null  # optional
        standby_cores: 0  # optional; default 0
        standby_gpus: 0  # optional; default 0
        use_user_private_key: true  # optional; default true
```

Three notes on the above:

- `pool_name` is not optional. The chart resolves `server_pool_id` unconditionally, so an entry with neither `pool_name` nor `server_pool_id` fails to render with `pool_name is required to resolve server pool`. Every autoscale entry therefore needs a corresponding `server_pools` entry.
- `zone_name` is not optional either, for a different reason: the chart renders `zone_id: null` when neither `zone_name` nor `zone_id` is set, and `autoscale_configs.zone_id` is `NOT NULL` with no default. That renders cleanly and then fails in the db-init Job.
- The autoscale type is read from the `type` key, not `autoscale_type`. Setting `autoscale_type` has no effect; the rendered `autoscale_type` field falls back to `"Docker Agent"`.

`autoscale_type`, `last_provision`, and `request_downscale_at` are `NOT NULL` with no default in the DB, but the chart always renders them: `autoscale_type` from `type` as described above, and `last_provision`/`request_downscale_at` always as `"1970-01-01 00:00:00"` to prevent non-deterministic template output. Kasm sets the latter two at runtime and any input value for them is ignored.

Every VM provider has a matching `<provider>_config_id`/`<provider>_vm_config_id` field and a `<provider>_dns_config_id` field on each autoscale entry (22 fields total, covering all 11 providers documented in [VM provider configs](#vm-provider-configs)). Set the `*_config_name` alias shown in [Name-based cross-references](#name-based-cross-references) (e.g. `aws_config_name`, `gcp_vm_config_name`, `vsphere_vm_config_name`) to resolve by name, or set the `*_config_id`/`*_vm_config_id` field directly with an explicit ID. `*_dns_config_id` fields are **not** resolved by name — they only accept an explicit ID (`null` by default) and must reference a DNS config's ID directly if used.

### zones

Zones are derived from `kasmZones` at the chart level and are not set under `kasmConfig.config`. Each `kasmZones` entry produces one zone in the preseed. See [Zones](#zones-1) below for the full field list.

### SSO connectors

#### OIDC

```yaml
kasmConfig:
  config:
    oidcConfigs:
      - display_name: "Okta"  # required
        client_id: "abc123"  # required
        client_secret: "secret"  # required (or via existingSecret)
        auth_url: "https://..."  # required
        token_url: "https://..."  # required
        user_info_url: "https://..."  # required
        redirect_url: "https://..."  # required
        username_attribute: email  # required
        logout_with_oidc_provider: true  # required
        enable_frontchannel_logout: false # required
        scope:  # optional; list of scope strings
          - openid
          - email
          - profile
        oidc_id: null  # optional; auto-generated if omitted
        auto_login: false  # optional; default false
        debug: false  # optional; default false
        enabled: true  # optional; default true
        groups_attribute: null  # optional
        hostname: null  # optional
        is_default: false  # optional; default false
        issuer: null  # optional
        logo_url: null  # optional
```

#### SAML

```yaml
kasmConfig:
  config:
    samlConfigs:
      - display_name: "AzureAD"  # required
        idp_sso_url: "https://..."  # required
        idp_entity_id: "https://..."  # required
        idp_x509_cert: "MIIC..."  # required
        sp_entity_id: "https://kasm.example.com"  # required
        sp_acs_url: "https://kasm.example.com/api/public/acs"  # required
        enabled: true  # optional; default true
        saml_id: null  # optional; auto-generated if omitted
        adfs: false  # optional; default false
        authn_request_signed: false  # optional; default false
        auto_login: false  # optional; default false
        debug: false  # optional; default false
        digest_algorithm: null  # optional
        group_attribute: null  # optional
        hostname: null  # optional
        idp_slo_url: null  # optional
        is_default: false  # optional; default false
        logo_url: null  # optional
        logout_request_signed: false  # optional; default false
        logout_response_signed: false  # optional; default false
        name_id_encrypted: false  # optional; default false
        requested_authn_context: false  # optional; default false
        sign_metadata: false  # optional; default false
        signature_algorithm: null  # optional
        sp_name_id: null  # optional
        sp_private_key: null  # optional
        sp_slo_url: null  # optional
        sp_x509_cert: null  # optional
        strict: false  # optional; default false
        want_assertions_encrypted: false  # optional; default false
        want_assertions_signed: false  # optional; default false
        want_attribute_statement: false  # optional; default false
        want_messages_signed: false  # optional; default false
        want_name_id: false  # optional; default false
        want_name_id_encrypted: false  # optional; default false
```

#### LDAP

```yaml
kasmConfig:
  config:
    ldapConfigs:
      - name: "Corp LDAP"  # required
        url: "ldap://ldap.corp.com"  # required
        search_base: "dc=corp,dc=com" # required
        search_filter: "(objectClass=person)" # required
        group_membership_filter: "(memberOf=cn=kasm,...)" # required
        service_account_dn: "cn=svc,dc=corp,dc=com"  # optional
        service_account_password: "secret"  # optional; or via existingSecret
        ldap_id: null  # optional; auto-generated if omitted
        auto_create_app_user: false  # optional; default false
        connection_timeout: 10  # optional; default 10
        email_attribute: "mail"  # optional; default "mail"
        enabled: true  # optional; default true
        search_subtree: true  # optional; default true
        username_domain_match: null  # optional
```

### server_pools

```yaml
kasmConfig:
  config:
    server_pools:
      - name: primary-pool  # required (a `server_pool_name` alias is also accepted)
        server_pool_id: null  # optional; auto-generated (${uuid:server_pool_id:N}) if omitted; an explicit value takes precedence
        server_pool_type: Docker Agent  # optional; default "Docker Agent"; "Docker Agent" or "Server Pool", case-insensitive, `docker`/`server` shorthands accepted (a `type` alias is also accepted)
        server_assignment_enabled: false  # optional; default false
```

### branding

```yaml
kasmConfig:
  config:
    branding:
      - name: "Acme Corp"  # required
        branding_config_id: null  # optional; auto-generated if omitted
        title: "Acme Workspaces"  # optional; an `html_title` alias is also accepted; both default to "Kasm Workspaces"
        is_default: true  # optional; default true
        dashboard_logo_url: "img/headerlogo.svg"  # optional; default "img/headerlogo.svg"
        favicon_logo_url: "img/favicon.png"  # optional; default "img/favicon.png"
        header_logo_url: "img/headerlogo.svg"  # optional; default "img/headerlogo.svg"
        login_logo_url: "img/logo.svg"  # optional; default "img/logo.svg"
        login_splash_url: "img/login_splash.jpg"  # optional; default "img/login_splash.jpg"
        launcher_background_url: "img/backgrounds/background1.jpg"  # optional; default "img/backgrounds/background1.jpg"
        login_caption: "The Container Streaming Platform®"  # optional; default "The Container Streaming Platform®"
        username_input_label: "Username"  # optional; default "Username"
        joining_session_text: "Creating a secure connection..."  # optional
        loading_session_text: "Creating a secure connection..."  # optional
        destroying_session_text: "Destroying session..."  # optional
```

`hostname` is always set to `Values.publicAddr` and is not settable per-entry; `Values.publicAddr` is required whenever `kasmConfig.config.branding` is non-empty.

### registries

```yaml
kasmConfig:
  config:
    registries:
      - registry_url: null  # optional
        registry_id: null  # optional; auto-generated if omitted
        channel: null  # optional
        config: {}  # optional; arbitrary JSON
        do_auto_update: false  # optional; default false
        kasm_version: null  # optional
        schema_version: null  # optional
```

### filter_policies

Web filtering policies.

```yaml
kasmConfig:
  config:
    filter_policies:
      - filter_policy_name: "Restricted"  # required; nullable in the DB
        filter_policy_id: null  # optional; auto-generated if omitted
        filter_policy_descriptions: ""  # optional; default ""
        deny_by_default: false  # optional; default false
        enable_categorization: false  # optional; default false
        enable_safe_search: false  # optional; default false
        disable_logging: false  # optional; default false
        categories: {}  # optional; arbitrary JSON
        domain_blacklist: {}  # optional; arbitrary JSON
        domain_whitelist: {}  # optional; arbitrary JSON
        safe_search_patterns: {}  # optional; arbitrary JSON
        ssl_bypass_domains: {}  # optional; arbitrary JSON
        ssl_bypass_ips: {}  # optional; arbitrary JSON
```

### banners

```yaml
kasmConfig:
  config:
    banners:
      - name: "Maintenance Notice"  # required
        banner_id: null  # optional; auto-generated if omitted
        config: {}  # optional; arbitrary JSON (banner text, styling, scheduling)
```

### cast_configs

Kasm Casting configurations for anonymous/embedded session launches.

```yaml
kasmConfig:
  config:
    cast_configs:
      - casting_config_name: "public-demo"  # required
        key: "demo-cast-key"  # required
        image_id: "image-uuid"  # required
        group_name: "My Group"  # optional; name-based lookup, resolved to group_id (a `group_id` field is also accepted directly)
        cast_config_id: null  # optional; auto-generated if omitted
        allow_anonymous: false  # optional; default false
        allow_kasm_audio: true  # optional; default true
        allow_kasm_clipboard_down: true  # optional; default true
        allow_kasm_clipboard_up: true  # optional; default true
        allow_kasm_downloads: true  # optional; default true
        allow_kasm_gamepad: false  # optional; default false
        allow_kasm_microphone: false  # optional; default false
        allow_kasm_printing: false  # optional; default false
        allow_kasm_rdp_client_file_transfer_clipboard: false  # optional; default false
        allow_kasm_rdp_map_local_drives: false  # optional; default false
        allow_kasm_rdp_webauthn_passthrough: false  # optional; default false
        allow_kasm_sharing: false  # optional; default false
        allow_kasm_smart_card_passthrough: false  # optional; default false
        allow_kasm_uploads: true  # optional; default true
        allow_kasm_webcam: false  # optional; default false
        allow_resume: false  # optional; default false
        allowed_referrers: []  # optional; list of referrer URL strings
        disable_control_panel: false  # optional; default false
        disable_fixed_res: false  # optional; default false
        disable_tips: false  # optional; default false
        dynamic_docker_network: false  # optional; default false
        dynamic_kasm_url: false  # optional; default false
        enable_sharing: false  # optional; default false
        enforce_client_settings: false  # optional; default false
        error_url: null  # optional
        ip_request_limit: null  # optional
        ip_request_seconds: null  # optional
        kasm_audio_default_on: true  # optional; default true
        kasm_ime_mode_default_on: false  # optional; default false
        kasm_url: null  # optional
        launcher_background_url: null  # optional
        limit_ips: false  # optional; default false
        limit_sessions: false  # optional; default false
        remote_app_configs: {}  # optional; arbitrary JSON
        require_recaptcha: false  # optional; default false
        session_remaining: null  # optional
        valid_until: null  # optional
```

### sso_to_group_mapping

Maps SSO group claims to Kasm groups.

```yaml
kasmConfig:
  config:
    sso_to_group_mapping:
      - group_id: "group-uuid"  # required
        sso_group_id: null  # optional; auto-generated if omitted
        ldap_id: null  # optional; set to associate this mapping with a specific LDAP connector
        oidc_id: null  # optional; set to associate this mapping with a specific OIDC connector
        saml_id: null  # optional; set to associate this mapping with a specific SAML connector
        sso_group_attributes: null  # optional
        apply_to_all_users: false  # optional; default false
```

### sso_attribute_userfield_mapping

Maps SSO attribute claims to Kasm user fields.

```yaml
kasmConfig:
  config:
    sso_attribute_userfield_mapping:
      - attribute_name: "department"  # optional
        user_field: "organization"  # optional
        sso_attribute_id: null  # optional; auto-generated if omitted
        ldap_id: null  # optional
        oidc_id: null  # optional
        saml_id: null  # optional
```

### schedules

Autoscale on/off schedules.

```yaml
kasmConfig:
  config:
    schedules:
      - autoscale_config_id: "autoscale-uuid"  # required
        active_start_time: "08:00:00"  # required
        active_end_time: "18:00:00"  # required
        timezone: "America/New_York"  # required
        schedule_id: null  # optional; auto-generated if omitted
        days_of_the_week: []  # optional; list of weekday strings/integers
```

### staging_configs

Pre-warmed ("staged") session pools.

```yaml
kasmConfig:
  config:
    staging_configs:
      - image_id: "image-uuid"  # required
        zone_id: "zone-uuid"  # required
        num_sessions: 2  # required
        expiration: 3600  # required
        staging_config_id: null  # optional; auto-generated if omitted
        autoscale_config_id: null  # optional
        server_pool_id: null  # optional
        allow_kasm_audio: true  # optional; default true
        allow_kasm_clipboard_down: true  # optional; default true
        allow_kasm_clipboard_up: true  # optional; default true
        allow_kasm_downloads: true  # optional; default true
        allow_kasm_gamepad: false  # optional; default false
        allow_kasm_microphone: false  # optional; default false
        allow_kasm_printing: false  # optional; default false
        allow_kasm_rdp_client_file_transfer_clipboard: false  # optional; default false
        allow_kasm_uploads: true  # optional; default true
        allow_kasm_webcam: false  # optional; default false
```

### storage_providers

```yaml
kasmConfig:
  config:
    storage_providers:
      - name: "Corporate S3"  # required
        default_target: "/data"  # required
        storage_provider_id: null  # optional; auto-generated if omitted
        storage_provider_type: null  # optional
        enabled: true  # optional; default true
        auth_url: null  # optional
        auth_url_options: {}  # optional; arbitrary JSON
        client_id: null  # optional
        client_secret: null  # optional
        mount_config: {}  # optional; arbitrary JSON
        redirect_url: null  # optional
        root_drive_url: null  # optional
        scope: []  # optional; list of scope strings
        token_url: null  # optional
        volume_config: {}  # optional; arbitrary JSON
        webdav_url: null  # optional
```

### storage_mappings

```yaml
kasmConfig:
  config:
    storage_mappings:
      - name: "home-drive"  # required
        storage_provider_id: "provider-uuid"  # required
        storage_mapping_id: null  # optional; auto-generated if omitted
        enabled: true  # optional; default true
        target: null  # optional
        read_only: false  # optional; default false
        group_id: null  # optional
        image_id: null  # optional
        user_id: null  # optional
        config: null  # optional
```

### file_mappings

```yaml
kasmConfig:
  config:
    file_mappings:
      - name: "motd"  # required
        destination: "/etc/motd"  # required
        file_type: "text"  # required
        content: "Welcome to Kasm"  # required
        file_map_id: null  # optional; auto-generated if omitted
        enabled: true  # optional; default true
        is_executable: false  # optional; default false
        is_readable: true  # optional; default true
        is_writable: true  # optional; default true
        description: null  # optional
        group_id: null  # optional
        image_id: null  # optional
        user_id: null  # optional
```

> [!WARNING]
> `file_mappings` cannot currently be seeded. `file_mappings.created` is `NOT NULL` with no column default, and the chart does not render a `created` field for this section (unlike `users`, `api_configs`, and `domains`, which all default it to `${datetime:utcnow}`). Any non-empty `file_mappings` list renders successfully and then fails the db-init Job with a not-null violation on `created`. Create file mappings through the Kasm API/UI after install until the chart emits the field.

### domains

```yaml
kasmConfig:
  config:
    domains:
      - domain_name: "example.com"  # required
        domain_id: null  # optional; auto-generated if omitted
        is_system: false  # optional; default false
        categories: []  # optional; list of category strings
        requested: null  # optional
        created: null  # optional; defaults to ${datetime:utcnow}
        updated: null  # optional; defaults to ${datetime:utcnow}
```

### labels

```yaml
kasmConfig:
  config:
    labels:
      - name: "production"  # required
        label_id: null  # optional; auto-generated if omitted
```

### DNS provider configs

DNS provider configs follow the same optional-except-`config_name` pattern as VM provider configs, with a much smaller field set (no `max_instances`, no compute sizing fields — these providers are used solely to manage DNS records for autoscaled agents).

```yaml
kasmConfig:
  config:
    aws_dns_configs:
      - config_name: "aws-dns"  # required
        config_id: null  # optional; auto-generated if omitted
        aws_access_key_id: null  # optional
        aws_secret_access_key: null  # optional
    azure_dns_configs:
      - config_name: "azure-dns"  # required
        azure_client_id: "uuid"  # required
        azure_client_secret: "secret"  # required
        azure_tenant_id: "uuid"  # required
        azure_subscription_id: "uuid"  # required
        azure_resource_group: "kasm-rg"  # required
        azure_region: eastus  # required
        azure_dns_config_id: null  # optional; auto-generated if omitted
        azure_authority: null  # optional
    digital_ocean_dns_configs:
      - config_name: "do-dns"  # required
        config_id: null  # optional; auto-generated if omitted
        digital_ocean_token: null  # optional
    gcp_dns_configs:
      - config_name: "gcp-dns"  # required
        config_id: null  # optional; auto-generated if omitted
        gcp_credentials: null  # optional
        gcp_project: null  # optional
    oci_dns_configs:
      - config_name: "oci-dns"  # required
        config_id: null  # optional; auto-generated if omitted
        oci_compartment_ocid: null  # optional
        oci_fingerprint: null  # optional
        oci_private_key: null  # optional
        oci_region: null  # optional
        oci_tenancy_ocid: null  # optional
        oci_user_ocid: null  # optional
```

None of the `*_dns_configs` credential fields currently support `existingSecret`/`existingSecretKey` — only the VM provider (`*_vm_configs`/`aws_configs`/`azure_configs`) sections do. Set DNS provider credentials inline if you need them.

### VM provider configs

All VM provider sections follow the same structure: a `config_name` (or, for OCI only, `name`) key, provider-specific fields, and — for credential-bearing fields — an optional `existingSecret`/`existingSecretKey` pair in place of an inline value. Every top-level key accepted by each provider is listed below; fields marked `required` cause `helm template` to fail with an explicit error if omitted (or, for credential fields, if neither the inline value nor `existingSecret`+`existingSecretKey` is set). All other fields are optional **from the chart's point of view** and default as shown — `null` for unset scalars, `{}`/`[]` (rendered as JSON) for unset objects/arrays, and explicit booleans where the chart substitutes a default.

> [!IMPORTANT]
> `required`/`optional` below is cross-checked against both sources described under [What `required` means](#what-required-means). For every provider except vSphere, the chart guards and the DB constraints agree exactly on which fields are required. vSphere is the one exception: the DB marks `vsphere_os_password`, `vsphere_os_username`, and `vsphere_template_name` nullable, but the chart enforces all three anyway (flagged inline below).
>
> Neither source, however, tells you whether a config with only the required fields set will actually provision a working VM. GCP, DigitalOcean, and OCI in particular mark almost nothing beyond `config_name` as required at either the Helm or DB level, even though a real deployment obviously needs things like a project/zone/machine type/image or equivalent. Whether Kasm's provisioning code enforces or defaults those fields at runtime is not something this document (or this repository) can verify — it lives in Kasm's backend, not the Helm chart. Treat "optional" strictly as "won't fail at render/insert time," and consult Kasm's own documentation or support for what a given provider actually needs to launch successfully.

All byte-sized fields (`*_bytes`, `*_boot_volume_bytes`, `*_disk_size_bytes`, `*_volume_size_bytes`) accept raw byte values; no unit conversion is performed.

> [!NOTE]
> This section documents exactly what `charts/kasm-helm/templates/db-preseed-secret.yaml` renders and accepts, field for field, so it is authoritative for which Helm values to set. It is not authoritative for whether those values load: where a chart field name has no matching DB column, the import fails rather than the field being ignored. `vsphere_vm_configs` is the known case; see the warning under [vSphere](#vsphere).

#### AWS

```yaml
kasmConfig:
  config:
    aws_configs:
      - config_name: "us-east-1-kasm"  # required
        aws_ec2_instance_type: t3.medium  # required
        aws_ec2_private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\n..."  # required (or via existingSecret)
        aws_ec2_public_key: "ssh-rsa AAAA..." # required (or via existingSecret)
        aws_config_id: null  # optional; auto-generated (${uuid:aws_config_id:N}) if omitted
        aws_access_key_id: "AKIA..."  # optional; or via existingSecret
        aws_secret_access_key: null  # optional; or via existingSecret
        aws_ec2_ami_id: null  # optional
        aws_ec2_config_override: {}  # optional; arbitrary JSON passed through to the AWS SDK call
        aws_ec2_custom_tags: {}  # optional; key/value tags applied to launched instances
        aws_ec2_ebs_volume_size_bytes: null  # optional; raw bytes
        aws_ec2_ebs_volume_type: null  # optional; e.g. gp3
        aws_ec2_iam: null  # optional; IAM instance profile name
        aws_ec2_security_group_ids:  # optional; list of security group IDs
          - sg-0abc123
        aws_ec2_subnet_id: subnet-0abc123  # optional
        aws_region: us-east-1  # optional
        max_instances: 10  # optional; unbounded (null) if omitted
        retrieve_password: false  # optional; default false
        startup_script: null  # optional
```

#### Azure

```yaml
kasmConfig:
  config:
    azure_configs:
      - config_name: "azure-eastus"  # required
        azure_client_id: "uuid"  # required
        azure_client_secret: "secret"  # required (or via existingSecret)
        azure_tenant_id: "uuid"  # required
        azure_subscription_id: "uuid"  # required
        azure_resource_group: "kasm-rg"  # required
        azure_region: eastus  # required
        azure_vm_size: Standard_D4s_v3  # required
        azure_network_sg: "kasm-nsg"  # required
        azure_subnet: "kasm-subnet"  # required
        azure_os_username: kasmuser  # required
        azure_os_password: "secret"  # required (or via existingSecret)
        azure_os_disk_type: Premium_LRS  # required
        azure_os_disk_size_bytes: 53687091200 # required; raw bytes
        max_instances: 10  # required (no default; unlike most other providers)
        azure_config_id: null  # optional; auto-generated if omitted
        azure_authority: null  # optional; custom AAD authority URL
        azure_config_override: {}  # optional; arbitrary JSON passed through to the Azure SDK call
        azure_image_reference: {}  # optional; custom image reference object
        azure_is_windows: false  # optional; default false
        azure_public_ip: false  # optional; default false
        azure_ssh_public_key: null  # optional
        azure_tags: {}  # optional; key/value tags applied to launched VMs
        startup_script: null  # optional
```

#### GCP

```yaml
kasmConfig:
  config:
    gcp_vm_configs:
      - config_name: "gcp-us-central1"  # required
        gcp_config_id: null  # optional; auto-generated if omitted
        gcp_project: my-project  # optional
        gcp_region: us-central1  # optional
        gcp_zone: us-central1-a  # optional
        gcp_machine_type: n2-standard-4  # optional
        gcp_image: projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20240110  # optional
        gcp_credentials: '{"type": "service_account", ...}'  # optional; or via existingSecret
        gcp_boot_volume_bytes: 53687091200  # optional; raw bytes
        gcp_disk_type: pd-ssd  # optional
        gcp_network: null  # optional
        gcp_subnetwork: null  # optional
        gcp_public_ip: false  # optional; default false
        gcp_cmek: null  # optional; customer-managed encryption key
        gcp_config_override: {}  # optional; arbitrary JSON passed through to the GCP SDK call
        gcp_custom_labels: {}  # optional; key/value labels applied to launched instances
        gcp_guest_accelerators: []  # optional; list of GPU accelerator objects
        gcp_metadata: {}  # optional; instance metadata key/value pairs
        gcp_network_tags: []  # optional; list of network tag strings
        gcp_service_account: {}  # optional; service account object attached to the instance
        max_instances: 10  # optional; unbounded (null) if omitted
        startup_script: null  # optional
        startup_script_type: null  # optional
        vm_installed_os_type: null  # optional
```

#### DigitalOcean

```yaml
kasmConfig:
  config:
    digital_ocean_vm_configs:
      - config_name: "do-nyc3"  # required
        config_id: null  # optional; auto-generated if omitted
        digital_ocean_droplet_image: ubuntu-20-04-x64  # optional
        digital_ocean_droplet_size: s-4vcpu-8gb # optional
        digital_ocean_firewall_name: null  # optional
        digital_ocean_sshkey_name: null  # optional
        digital_ocean_tags: null  # optional
        digital_ocean_token: "dop_v1_..."  # optional; or via existingSecret
        max_instances: 10  # optional; unbounded (null) if omitted
        region: nyc3  # optional
        startup_script: null  # optional
```

#### Harvester

```yaml
kasmConfig:
  config:
    harvester_vm_configs:
      - config_name: "harvester-cluster1"  # required
        cores: 4  # required
        disk_image: ubuntu-focal.img  # required
        disk_size_bytes: 53687091200  # required; raw bytes
        kube_host: "https://harvester.example.com:6443"  # required
        max_instances: 10  # required
        memory_bytes: 8589934592  # required; raw bytes
        vm_namespace: kasm  # required
        config_id: null  # optional; auto-generated if omitted
        config_override: null  # optional
        enable_efi_boot: false  # optional; default false
        enable_secure_boot: false  # optional; default false
        enable_tpm: false  # optional; default false
        interface_type: null  # optional
        kube_api_token: "kube-api-token"  # optional; or via existingSecret
        kube_ssl_cert: null  # optional; or via existingSecret
        network_name: null  # optional
        network_type: null  # optional
        startup_script: null  # optional
        vm_public_ssh_key: null  # optional
```

#### KubeVirt

```yaml
kasmConfig:
  config:
    kubevirt_vm_configs:
      - config_name: "kubevirt-cluster1"  # required
        cores: 4  # required
        disk_size_bytes: 53687091200  # required; raw bytes
        disk_source: "my-golden-image-pvc"  # required
        kube_host: "https://kubernetes.example.com:6443"  # required
        max_instances: 10  # required
        memory_bytes: 8589934592  # required; raw bytes
        vm_namespace: kasm  # required
        config_id: null  # optional; auto-generated if omitted
        config_override: null  # optional
        enable_efi_boot: false  # optional; default false
        enable_secure_boot: false  # optional; default false
        enable_tpm: false  # optional; default false
        interface_type: null  # optional
        kube_api_token: "kube-api-token"  # optional; or via existingSecret
        kube_ssl_cert: null  # optional; or via existingSecret
        network_name: null  # optional
        network_type: null  # optional
        startup_script: null  # optional
        vm_public_ssh_key: null  # optional
```

#### Nutanix

```yaml
kasmConfig:
  config:
    nutanix_vm_configs:
      - config_name: "nutanix-cluster1"  # required
        api_version: "3.1"  # required
        cores: 4  # required
        host: "nutanix-pc.example.com"  # required
        max_instances: 10  # required
        memory_bytes: 8589934592  # required; raw bytes
        password: "secret"  # required (or via existingSecret)
        port: 9440  # required
        username: admin  # required
        vm_candidate: "kasm-golden-image"  # required
        config_id: null  # optional; auto-generated if omitted
        startup_script: null  # optional
        verify_ssl: true  # optional; default true
```

#### OCI

```yaml
kasmConfig:
  config:
    oci_vm_configs:
      - config_name: "oci-us-ashburn"  # required (a `name` field is also accepted as an alias)
        config_id: null  # optional; auto-generated if omitted
        max_instances: 10  # optional; unbounded (null) if omitted
        oci_availability_domains: []  # optional
        oci_baseline_ocpu_utilization: null  # optional
        oci_boot_volume_bytes: 53687091200  # optional; raw bytes
        oci_compartment_ocid: null  # optional
        oci_config_override: {}  # optional; arbitrary JSON passed through to the OCI SDK call
        oci_custom_tags: {}  # optional; key/value tags applied to launched instances
        oci_fingerprint: null  # optional
        oci_flex_cpus: null  # optional; flex-shape CPU count
        oci_flex_memory_bytes: null  # optional; flex-shape memory, raw bytes
        oci_image_ocid: null  # optional
        oci_nsg_ocids: []  # optional; list of network security group OCIDs
        oci_private_key: "-----BEGIN PRIVATE KEY-----\n..."  # optional; or via existingSecret
        oci_region: null  # optional
        oci_shape: null  # optional
        oci_ssh_public_key: null  # optional
        oci_storage_vpus_per_gb: null  # optional
        oci_subnet_ocid: null  # optional
        oci_tenancy_ocid: null  # optional
        oci_user_ocid: null  # optional
        startup_script: null  # optional
```

#### OpenStack

```yaml
kasmConfig:
  config:
    openstack_vm_configs:
      - config_name: "openstack-region1"  # required
        max_instances: 10  # required
        openstack_auth_method: password  # required
        openstack_availability_zone: nova  # required
        openstack_cinder_endpoint: "https://cinder.example.com:8776/v3"  # required
        openstack_cinder_version: v3  # required
        openstack_flavor: m1.large  # required
        openstack_glance_endpoint: "https://glance.example.com:9292"  # required
        openstack_glance_version: v2  # required
        openstack_image_id: "image-uuid"  # required
        openstack_keystone_endpoint: "https://keystone.example.com:5000/v3"  # required
        openstack_network_id: "network-uuid"  # required
        openstack_nova_endpoint: "https://nova.example.com:8774/v2.1"  # required
        openstack_nova_version: v2.1  # required
        openstack_project_name: kasm-project  # required
        config_id: null  # optional; auto-generated if omitted
        openstack_application_credential_id: null  # optional
        openstack_application_credential_secret: null # optional; or via existingSecret
        openstack_config_override: {}  # optional; arbitrary JSON passed through to the OpenStack SDK call
        openstack_create_volume: false  # optional; default false
        openstack_key_name: null  # optional
        openstack_metadata: {}  # optional; instance metadata key/value pairs
        openstack_password: "secret"  # optional; or via existingSecret
        openstack_project_domain_name: null  # optional
        openstack_security_groups: []  # optional; list of security group name strings
        openstack_user_domain_name: null  # optional
        openstack_username: null  # optional
        openstack_volume_size_bytes: null  # optional; raw bytes
        openstack_volume_type: null  # optional
        startup_script: null  # optional
```

#### Proxmox

```yaml
kasmConfig:
  config:
    proxmox_vm_configs:
      - config_name: "proxmox-cluster1"  # required
        cluster_node_name: pve1  # required
        cores: 4  # required
        host: "https://proxmox.example.com:8006"  # required
        installed_os_type: linux  # required
        max_instances: 10  # required
        memory_bytes: 8589934592  # required; raw bytes
        template_name: "kasm-golden-template"  # required
        token_name: "kasm@pve!kasm-token"  # required
        token_value: "secret"  # required (or via existingSecret)
        username: "kasm@pve"  # required
        vmid_range_lower: 9000  # required
        vmid_range_upper: 9999  # required
        config_id: null  # optional; auto-generated if omitted
        full_clone: true  # optional; default true
        resource_pool_name: null  # optional
        startup_script: null  # optional
        startup_script_path: null  # optional
        storage_pool_name: null  # optional
        target_node_name: null  # optional
        verify_ssl: true  # optional; default true
```

#### vSphere

```yaml
kasmConfig:
  config:
    vsphere_vm_configs:
      - config_name: "vsphere-dc1"  # required
        max_instances: 10  # required
        vsphere_datacenter_name: "DC1"  # required
        vsphere_installed_OS_type: linux  # required (note the capitalized OS)
        vsphere_os_password: "secret"  # required, or via existingSecret; nullable in the DB
        vsphere_os_username: kasmuser  # required; nullable in the DB
        vsphere_template_name: "kasm-golden-template"  # required; nullable in the DB
        vsphere_vcenter_address: "vcenter.example.com"  # required
        vsphere_vcenter_password: "secret"  # required (or via existingSecret)
        vsphere_vcenter_port: 443  # required
        vsphere_vcenter_username: "administrator@vsphere.local"  # required
        config_id: null  # optional; auto-generated if omitted
        startup_script: null  # optional
        vsphere_cluster_name: null  # optional
        vsphere_cpus: null  # optional
        vsphere_datastore: null  # optional; see warning below: not a real column
        vsphere_datastore_cluster_name: null  # optional; see warning below: not a real column
        vsphere_memoryMB: null  # optional; see warning below: not a real column
        vsphere_resource_pool: null  # optional
        vsphere_vm_folder: null  # optional
```

> [!WARNING]
> `vsphere_datastore`, `vsphere_datastore_cluster_name`, and `vsphere_memoryMB` are rendered by the chart but do not exist as columns on `vsphere_vm_configs`. The real columns are `vsphere_datastore_name`, `vsphere_use_datastore_cluster`, and `vsphere_memory_bytes` (bytes, not megabytes). The seed loader builds each row as `Model(**record)`, so any unknown key raises a `TypeError` and aborts the whole import. This makes any non-empty `vsphere_vm_configs` list fail the db-init Job regardless of what you set. Configure vSphere through the Kasm API/UI after install until the chart's field names are corrected.

## Credential handling

### Inline values

Credentials can be set directly in values:

```yaml
kasmConfig:
  config:
    oidcConfigs:
      - client_id: "abc123"
        client_secret: "my-secret"
```

Inline credentials end up in the Helm release history. Use external references for production workloads.

### External Secret references

Set `existingSecret` (Secret name) and `existingSecretKey` (data key) on any config item that carries a credential field. The chart reads the Secret at render time via `lookup` and embeds the decoded value in the preseed Secret.

```yaml
kasmConfig:
  config:
    oidcConfigs:
      - client_id: "abc123"
        existingSecret: my-oidc-secret
        existingSecretKey: client_secret
    aws_configs:
      - config_name: aws-prod
        aws_ec2_instance_type: t3.medium
        aws_ec2_private_key: "ssh-rsa ..."
        aws_ec2_public_key: "ssh-rsa ..."
        existingSecret: aws-kasm-creds
        existingSecretKey: secret_access_key
```

The `existingSecret`/`existingSecretKey` pair is per config item, not per field. One item can reference only one external Secret. For items that have multiple credential fields (e.g., AWS access key ID and secret access key), either supply them inline or provide both as separate fields from the same Secret data key (if the Secret stores a compound value) or use separate config items.

When `existingSecret`/`existingSecretKey` is not set, the inline field value is used. If neither is set and the field is required, `helm template` fails.

### Credential rotation

The passwords Secret (`<release>-secrets`) and salts Secret (`<release>-password-salts`) are created as pre-install/pre-upgrade hooks with no `hook-delete-policy`. Helm preserves them across upgrades, and the chart reads them back via `lookup` so re-rendering does not rotate credentials.

To rotate a credential:

1. Delete the relevant key from the passwords or salts Secret (or delete the Secret entirely to regenerate all passwords).
2. Run `helm upgrade`. The chart generates a new value for any missing key.
3. For external Secret references (`existingSecret`/`existingSecretKey`), update the referenced Secret before running `helm upgrade`. The chart reads the new value at render time.

Built-in user passwords are stored in the passwords Secret under the `admin-password` and `user-password` keys. The db-init Job passes them to `startup.sh` as `DEFAULT_ADMIN_PASSWORD` / `DEFAULT_USER_PASSWORD`, which hashes each with a fresh salt and writes both into the merged seed file. Rotating them requires deleting those keys from the Secret and running `helm upgrade` followed by a DB re-initialization (which is only safe on a fresh install).

Autoscale and VM provider credentials embedded in the preseed are only applied during DB initialization. Changing them after initialization requires updating them via the Kasm API, not through Helm.

## Zones

Zones in the preseed come from `kasmZones`, not from `kasmConfig.config`. Each `kasmZones` entry produces one zone with the following fields:

```yaml
kasmZones:
  - name: us-east  # required; becomes zone_name
    proxy_hostname: kasm.example.com  # optional; default "$request_host$"
    primary: true  # required exactly once across all zones; not a preseed field itself — selects the primary zone at the chart level
    zone_id: null  # optional; auto-generated (${uuid:zone_id:N}) if omitted
    upstream_auth_address: kasm-internal.example.com  # optional; default "$request_host$"
    load_strategy: fewest_sessions  # optional; default "most_sessions"
    allow_origin_domain: null  # optional; default "$request_host$"
    enable_rdp_direct_login: false  # optional; default false
    enable_rdp_https_gw: true  # optional; default true
    enable_rdp_https_gw_dlp: false  # optional; default false
    prioritize_static_agents: true  # optional; default true
    proxy_connections: true  # optional; default true
    proxy_rdp_client_connections: true  # optional; default true
    proxy_path: "desktop"  # optional; default "desktop"
    proxy_port: 443  # optional; default 443
    proxy_rdp_hostname: null  # optional; default "$request_host$"
    proxy_rdp_port: 443  # optional; default 443
    search_alternate_zones: true  # optional; default true
    verify_rdp_client_ip: false  # optional; default false
```

`primary_manager_id` is always rendered as `null`; Kasm assigns it at runtime and it is not settable via preseed.

`proxy_hostname` is also used to build the `ingress`, `route`, and `certificate.certManager` hostnames/SANs for each zone, so it only needs to be set once. `proxyAddress` is a deprecated alias for `proxy_hostname` kept for backwards compatibility; if both are set on a zone, `proxy_hostname` wins.

## Multi-zone installs

Each entry in `kasmZones` produces one zone in the preseed. Autoscale configs, images, and other zone-referencing sections use `zone_name` to cross-reference.

```yaml
kasmZones:
  - name: us-east
    proxy_hostname: kasm-east.example.com
    primary: true
  - name: eu-west
    proxy_hostname: kasm-eu.example.com

kasmConfig:
  generatePreseed: true
  config:
    autoscale:
      - autoscale_config_name: east-agents
        zone_name: us-east
        aws_config_name: aws-us-east
      - autoscale_config_name: eu-agents
        zone_name: eu-west
        aws_config_name: aws-eu-west
```

## Generated Secrets

When `generatePreseed: true`, the chart emits up to three Secrets:

| Secret | Contains |
|---|---|
| `<release>-secrets` | manager-token, service-token, db-password, user-password, per-user passwords, per-api-config passwords, and admin-password (only while `admin@kasm.local` is actually seeded — see [Default Users and Groups](default-users.md#users)) |
| `<release>-password-salts` | per-user salts, per-api-config salts (emitted only when non-built-in users or apiConfigs are present) |
| `<release>-db-preseed` | `custom_properties.yaml` mounted into the db-init Job |

All three are annotated `helm.sh/hook: pre-install,pre-upgrade` so they exist before any other resource applies.
