# Kasm DB Preseed

The preseed feature generates a `custom_properties.yaml` that Kasm's `startup.sh` merges into the default seed data at DB initialization time. This lets you declare Kasm configuration—users, groups, images, autoscale providers, SSO connectors, and more—as Helm values rather than post-install API calls.

>>> [!warning] The current version of Kasm does not apply API config permissions (`apiConfigs[].permissions`) seeded via DB Preseed. This is an application bug, not a Helm chart defect, and is queued for a fix. Seeded API configs are created, but any `permissions` list on them is not applied at DB initialization time; grant permissions manually via the Kasm API/UI after install until the bug is resolved.
>>>

## Enabling Preseed

Three top-level flags control the feature. All default to `false` (opt-in).

```yaml
kasmConfig:
  generatePreseed: true    # generate the Secret and mount it into the db-init Job
  defaultUsers: true       # seed default user accounts and groups
  defaultApiUsers: true    # seed default API credentials
```

`generatePreseed: false` produces zero documents and skips all preseed-related work. Set it `true` only on fresh installs (`dbManagement.initialize: true`); rerunning preseed on an existing database is not supported by Kasm.

## Supplying a Custom `default_properties.yaml` via Secret

`kasmConfig.config` expresses preseed data as Helm values, which the chart renders into `custom_properties.yaml` and merges with Kasm's baked-in `default_properties.yaml`. For infrastructure-as-code workflows that manage the entire seed file directly as a Kubernetes Secret—rather than expressing every section as Helm values—reference that Secret with `kasmConfig.existingDefaultPropertiesSecret`:

```yaml
kasmConfig:
  existingDefaultPropertiesSecret:
    name: my-custom-seed         # Secret name; must already exist in the release namespace
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

>>> [!note] See [Default Users and Groups](default-users.md) for the full account list, group membership, and per-group permission set.
>>>

### Default API Users

`defaultApiUsers: true` seeds:
- API configs: `kasm_engineering_api` (read-write automation key), `kcs_api` (read-only support key)

`defaultUsers` and `defaultApiUsers` are independent. Set both to reproduce the full default seed:

>>> [!note] See [Default API Users](default-api-users.md) for the full API credential list and permission set.
>>>

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
    zones: []             # derived from kasmZones; do not set manually
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

The chart generates stable IDs and credentials at render time using Kasm startup tokens. These tokens are expanded by `startup.sh` during DB initialization, not by Helm.

| Token syntax | Resolved by | Example |
|---|---|---|
| `${uuid:TYPE:N}` | startup.sh | `${uuid:group_id:1}` |
| `${crypt:password:N}` | startup.sh | built-in user password hash |
| `${crypt:salt:N}` | startup.sh | built-in user salt |
| `${datetime:utcnow}` | startup.sh | current UTC timestamp |

For user-supplied entities (non-built-in users, API configs), the chart generates a random password at render time, stores it in the `<release>-secrets` Secret, and stores the corresponding salt in `<release>-password-salts`. On subsequent `helm upgrade` calls, the chart re-reads those Secrets via `lookup` so passwords are stable across upgrades.

Built-in users — exactly `admin@kasm.local` and `user@kasm.local` — always use `${crypt:password:N}` tokens. The actual credential at N=2 is the `admin-password` value from the passwords Secret. If `kasmConfig.defaultUsers` and `kasmConfig.adminUsername` (set to anything other than `admin@kasm.local`) replace it with a renamed admin account, that account is no longer a built-in user: it gets a generated password/salt/hash like any other non-built-in user, stored under a `<local-part>-password`/`<local-part>-salt` key pair (e.g. `system@kasm.local` → `system-password`), and the chart does not create an `admin-password` key at all in that case.

### Name-based cross-references

Several sections accept a `*_name` field as an alternative to a `*_id` field. The chart resolves the name to the generated UUID at render time.

```yaml
kasmConfig:
  config:
    server_pools:
      - name: primary-pool
        server_pool_id: "pool-uuid-001"   # explicit ID takes precedence
    images:
      - name: kasmweb/ubuntu-focal-desktop
        pool_name: primary-pool           # resolved to pool-uuid-001
    autoscale:
      - autoscale_config_name: my-agent
        pool_name: primary-pool           # resolved
        zone_name: default               # resolved from kasmZones
        aws_config_name: my-aws          # resolved from aws_configs
```

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

### groups

```yaml
kasmConfig:
  config:
    groups:
      - name: "My Group"          # required
        description: ""
        priority: 500             # default 1000
        is_system: false
        permissions:
          - users_view
          - images_view
        settings:
          allow_kasm_audio:
            value: "True"
            value_type: bool
```

`group_id` is auto-generated as `${uuid:group_id:N}` if omitted. The `key` field is an alternate lookup name used by `group_name` references elsewhere.

### users

```yaml
kasmConfig:
  config:
    users:
      - username: "ops@example.com"  # required
        realm: local
        groups:
          - My Group
```

Non-built-in users get a generated password stored in the passwords Secret. Built-in users (`admin@kasm.local`, `user@kasm.local`) use `${crypt:password:N}` tokens derived from the admin-password/user-password Secret keys.

### apiConfigs

```yaml
kasmConfig:
  config:
    apiConfigs:
      - name: "automation-api"    # required
        api_key: "MyStaticApiKey" # required
        enabled: true
        read_only: false
        permissions:
          - autoscale_view
          - autoscale_modify
```

>>> [!warning] `permissions` is not currently applied by Kasm at DB initialization time (application bug, fix pending). The API config is created, but with no permissions granted; assign them manually after install.
>>>

### settings

System settings (site-wide configuration).

```yaml
kasmConfig:
  config:
    settings:
      - category: auth            # required
        name: auth_totp_enabled   # required
        title: "TOTP Auth"        # required
        value_type: bool          # required
        value: "True"
        sanitize: false
```

### images

Kasm workspace images (Docker images or remote apps).

```yaml
kasmConfig:
  config:
    images:
      - name: kasmweb/ubuntu-focal-desktop  # required
        friendly_name: "Ubuntu Desktop"
        pool_name: primary-pool             # name-based lookup
        image_type: Container
        memory_bytes: null
        uncompressed_size_bytes: null
        cores: null
```

### autoscale

```yaml
kasmConfig:
  config:
    autoscale:
      - autoscale_config_name: "aws-us-east-1"  # required
        autoscale_type: "AWS"
        zone_name: default
        pool_name: primary-pool
        aws_config_name: my-aws
        agent_memory_override_bytes: 4294967296
        standby_memory_bytes: 2147483648
        max_simultaneous_sessions_per_server: 4
        downscale_backoff: 1800
```

`last_provision` is always rendered as `"1970-01-01 00:00:00"` to prevent non-deterministic template output. Kasm sets the actual value at runtime.

### zones

Zones are derived from `kasmZones` at the chart level and are not set under `kasmConfig.config`. Each `kasmZones` entry produces one zone in the preseed.

```yaml
kasmZones:
  - name: default
    proxyAddress: kasm.example.com
    primary: true
```

### SSO connectors

#### OIDC

```yaml
kasmConfig:
  config:
    oidcConfigs:
      - display_name: "Okta"           # required
        client_id: "abc123"            # required
        client_secret: "secret"        # required (or via existingSecret)
        auth_url: "https://..."        # required
        token_url: "https://..."       # required
        user_info_url: "https://..."   # required
        redirect_url: "https://..."    # required
        username_attribute: email      # required
        logout_with_oidc_provider: true  # required
        enable_frontchannel_logout: false # required
        scope:
          - openid
          - email
          - profile
```

#### SAML

```yaml
kasmConfig:
  config:
    samlConfigs:
      - display_name: "AzureAD"        # optional
        idp_sso_url: "https://..."
        idp_entity_id: "https://..."
        idp_x509_cert: "MIIC..."
        sp_entity_id: "https://kasm.example.com"
        sp_acs_url: "https://kasm.example.com/api/public/acs"
        enabled: true
```

#### LDAP

```yaml
kasmConfig:
  config:
    ldapConfigs:
      - name: "Corp LDAP"             # required
        url: "ldap://ldap.corp.com"   # required
        search_base: "dc=corp,dc=com" # required
        search_filter: "(objectClass=person)" # required
        group_membership_filter: "(memberOf=cn=kasm,...)" # required
        service_account_dn: "cn=svc,dc=corp,dc=com"
        service_account_password: "secret"  # or via existingSecret
```

### VM provider configs

All VM provider sections follow the same structure. Required fields vary by provider.

#### AWS

```yaml
kasmConfig:
  config:
    aws_configs:
      - config_name: "us-east-1-kasm"    # required
        aws_ec2_instance_type: t3.medium  # required
        aws_ec2_private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\n..." # required
        aws_ec2_public_key: "ssh-rsa AAAA..."   # required
        aws_region: us-east-1
        aws_access_key_id: "AKIA..."         # or via existingSecret
        aws_secret_access_key: "secret"      # or via existingSecret
        aws_ec2_security_group_ids:
          - sg-0abc123
        aws_ec2_subnet_id: subnet-0abc123
        max_instances: 10
```

#### Azure

```yaml
kasmConfig:
  config:
    azure_configs:
      - config_name: "azure-eastus"        # required
        azure_client_id: "uuid"            # required
        azure_client_secret: "secret"      # required (or via existingSecret)
        azure_tenant_id: "uuid"            # required
        azure_subscription_id: "uuid"      # required
        azure_resource_group: "kasm-rg"    # required
        azure_region: eastus               # required
        azure_vm_size: Standard_D4s_v3     # required
        azure_network_sg: "kasm-nsg"       # required
        azure_subnet: "kasm-subnet"        # required
        azure_os_username: kasmuser        # required
        azure_os_password: "secret"        # required (or via existingSecret)
        azure_os_disk_type: Premium_LRS    # required
        azure_os_disk_size_bytes: 53687091200  # required
        max_instances: 10                  # required
```

#### GCP

```yaml
kasmConfig:
  config:
    gcp_vm_configs:
      - config_name: "gcp-us-central1"     # required
        gcp_project: my-project
        gcp_region: us-central1
        gcp_zone: us-central1-a
        gcp_machine_type: n2-standard-4
        gcp_image: projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20240110
        gcp_credentials: '{"type": "service_account", ...}'  # or via existingSecret
        gcp_boot_volume_bytes: 53687091200
        max_instances: 10
```

#### Other providers

The remaining providers (DigitalOcean, Harvester, KubeVirt, Nutanix, OCI, OpenStack, Proxmox, vSphere) follow the same pattern: a `config_name` field, provider-specific required fields, and an optional `existingSecret`/`existingSecretKey` for credentials. All byte-sized fields (`memory_bytes`, `disk_size_bytes`, `oci_boot_volume_bytes`, `oci_flex_memory_bytes`, `openstack_volume_size_bytes`) accept raw byte values; no unit conversion is performed. See `tests/schemas/1_19_0-schema.yaml` for the authoritative field list per provider.

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

Built-in user passwords (admin-password, user-password) are stored in the passwords Secret under the `admin-password` and `user-password` keys respectively. These map to `${crypt:password:2}` and `${crypt:password:1}` in the preseed. Rotating them requires deleting those keys from the Secret and running `helm upgrade` followed by a DB re-initialization (which is only safe on a fresh install).

Autoscale and VM provider credentials embedded in the preseed are only applied during DB initialization. Changing them after initialization requires updating them via the Kasm API, not through Helm.

## Zones

Zones in the preseed come from `kasmZones`, not from `kasmConfig.config`. Each zone entry produces:

```yaml
- zone_name: <name>
  zone_id: "${uuid:zone_id:N}"
  proxy_hostname: "$request_host$"
  upstream_auth_address: "$request_host$"
  proxy_port: 443
  ...
```

Override zone preseed fields by setting them directly on the `kasmZones` entry:

```yaml
kasmZones:
  - name: us-east
    proxy_hostname: kasm.example.com
    primary: true
    upstream_auth_address: kasm-internal.example.com
    load_strategy: fewest_sessions
```

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
