{{/*
Resolve an ID from a config object or a named collection.

Supports:
- matchKey: single match field, backward-compatible
- matchKeys: ordered list of match fields, e.g. ["config_name", "name"]

Resolution order:
1. Prefer explicit ID on config.
2. Prefer alternate explicit ID keys on config.
3. Lookup collection item by config[nameKey] == item[matchKeys...].
4. Prefer item[idKey].
5. Prefer item alternate ID keys.
6. Generate ${uuid:<uuidKey>:<1-based index>}.
7. Fail if no match.
*/}}
{{- define "kasm.configId" -}}
  {{- $config := .config -}}
  {{- $collection := .collection | default list -}}
  {{- $idKey := .idKey -}}
  {{- $alternateIdKeys := .alternateIdKeys | default list -}}
  {{- $nameKey := .nameKey -}}
  {{- $matchKey := .matchKey | default "name" -}}
  {{- $matchKeys := .matchKeys | default (list $matchKey) -}}
  {{- $uuidKey := .uuidKey | default $idKey -}}
  {{- $resourceType := .resourceType | default "config" -}}
  {{- $resolvedId := "" -}}

  {{- if and (hasKey $config $idKey) (index $config $idKey) -}}
    {{- $resolvedId = index $config $idKey -}}
  {{- else -}}
    {{- range $alternateIdKey := $alternateIdKeys -}}
      {{- if and (not $resolvedId) (hasKey $config $alternateIdKey) (index $config $alternateIdKey) -}}
        {{- $resolvedId = index $config $alternateIdKey -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- if not $resolvedId -}}
    {{- $lookupName := required (printf "%s is required to resolve %s" $nameKey $resourceType) (index $config $nameKey) -}}
    {{- $configName := $config.name | default $lookupName | default "unnamed config" -}}
    {{- $resourceFound := false -}}

    {{- range $itemIndex, $item := $collection -}}
      {{- $itemMatched := false -}}

      {{- range $candidateMatchKey := $matchKeys -}}
        {{- if and (not $itemMatched) (hasKey $item $candidateMatchKey) (eq (index $item $candidateMatchKey) $lookupName) -}}
          {{- $itemMatched = true -}}
        {{- end -}}
      {{- end -}}

      {{- if $itemMatched -}}
        {{- $resourceFound = true -}}

        {{- if and (hasKey $item $idKey) (index $item $idKey) -}}
          {{- $resolvedId = index $item $idKey -}}
        {{- else -}}
          {{- range $alternateIdKey := $alternateIdKeys -}}
            {{- if and (not $resolvedId) (hasKey $item $alternateIdKey) (index $item $alternateIdKey) -}}
              {{- $resolvedId = index $item $alternateIdKey -}}
            {{- end -}}
          {{- end -}}
        {{- end -}}

        {{- if not $resolvedId -}}
          {{- $resolvedId = printf "${uuid:%s:%s}" $uuidKey ((add $itemIndex 1) | toString) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}

    {{- if not $resourceFound -}}
      {{- fail (printf "No matching %s found for config '%s': %s='%s'" $resourceType $configName $nameKey $lookupName) -}}
    {{- end -}}
  {{- end -}}

  {{- $resolvedId -}}
{{- end -}}

{{/*
Resolve one VM provider config ID for an autoscale config.

This intentionally resolves only one provider per call. An autoscale config may
reference multiple VM providers, so call this once for each provider-specific ID.

Resolution:
1. autoscale.<provider_id_key> wins
2. autoscale.<provider_name_key> resolves against provider collection by config_name/name
3. missing provider reference returns null

Usage:
{{ include "kasm.vmProviderConfigId" (dict
  "autoscale" $autoscale
  "collection" $ociVmConfigs
  "idKey" "config_id"
  "autoscaleIdKey" "oci_vm_config_id"
  "autoscaleNameKey" "oci_vm_config_name"
  "uuidKey" "oci_vm_config_id"
  "resourceType" "OCI VM config"
) }}
*/}}
{{- define "kasm.vmProviderConfigId" -}}
  {{- $autoscale := .autoscale -}}
  {{- $collection := .collection | default list -}}
  {{- $idKey := .idKey | default "config_id" -}}
  {{- $alternateIdKeys := .alternateIdKeys | default list -}}
  {{- $autoscaleIdKey := .autoscaleIdKey -}}
  {{- $autoscaleNameKey := .autoscaleNameKey -}}
  {{- $uuidKey := .uuidKey -}}
  {{- $resourceType := .resourceType | default "VM provider config" -}}

  {{- if and (hasKey $autoscale $autoscaleIdKey) (index $autoscale $autoscaleIdKey) -}}
    {{- index $autoscale $autoscaleIdKey -}}
  {{- else if and (hasKey $autoscale $autoscaleNameKey) (index $autoscale $autoscaleNameKey) -}}
    {{- include "kasm.configId" (dict
      "config" $autoscale
      "collection" $collection
      "idKey" $idKey
      "alternateIdKeys" $alternateIdKeys
      "nameKey" $autoscaleNameKey
      "matchKeys" (list "config_name" "name")
      "uuidKey" $uuidKey
      "resourceType" $resourceType
    ) -}}
  {{- else -}}
    {{- "null" -}}
  {{- end -}}
{{- end -}}

{{/*
Validate autoscale references:
- zone_name -> zones
- pool_name -> serverPools
- each provider-specific *_config_name -> matching provider collection
*/}}
{{- define "kasm.validateAutoscaleRefs" -}}
  {{- $kasmConfig := .kasmConfig | default dict -}}
  {{- $zones := .zones | default list -}}
  {{- $serverPools := .serverPools | default list -}}
  {{- $autoscaleConfigs := get $kasmConfig "autoscale" | default list -}}

  {{- $providerDefs := list
    (dict "provider" "aws" "collection" .awsVmConfigs "idKey" "aws_config_id" "alternateIdKeys" (list "config_id") "autoscaleIdKey" "aws_config_id" "autoscaleNameKey" "aws_config_name" "uuidKey" "aws_config_id" "resourceType" "AWS VM config")
    (dict "provider" "azure" "collection" .azureVmConfigs "idKey" "azure_config_id" "alternateIdKeys" (list "config_id") "autoscaleIdKey" "azure_config_id" "autoscaleNameKey" "azure_config_name" "uuidKey" "azure_config_id" "resourceType" "Azure VM config")
    (dict "provider" "digital_ocean" "collection" .digitalOceanVmConfigs "idKey" "config_id" "autoscaleIdKey" "digital_ocean_vm_config_id" "autoscaleNameKey" "digital_ocean_vm_config_name" "uuidKey" "digital_ocean_vm_config_id" "resourceType" "DigitalOcean VM config")
    (dict "provider" "gcp" "collection" .gcpVmConfigs "idKey" "config_id" "autoscaleIdKey" "gcp_vm_config_id" "autoscaleNameKey" "gcp_vm_config_name" "uuidKey" "gcp_vm_config_id" "resourceType" "GCP VM config")
    (dict "provider" "harvester" "collection" .harvesterVmConfigs "idKey" "config_id" "autoscaleIdKey" "harvester_vm_config_id" "autoscaleNameKey" "harvester_vm_config_name" "uuidKey" "harvester_vm_config_id" "resourceType" "Harvester VM config")
    (dict "provider" "kubevirt" "collection" .kubevirtVmConfigs "idKey" "config_id" "autoscaleIdKey" "kubevirt_vm_config_id" "autoscaleNameKey" "kubevirt_vm_config_name" "uuidKey" "kubevirt_vm_config_id" "resourceType" "KubeVirt VM config")
    (dict "provider" "nutanix" "collection" .nutanixVmConfigs "idKey" "config_id" "autoscaleIdKey" "nutanix_vm_config_id" "autoscaleNameKey" "nutanix_vm_config_name" "uuidKey" "nutanix_vm_config_id" "resourceType" "Nutanix VM config")
    (dict "provider" "oci" "collection" .ociVmConfigs "idKey" "config_id" "autoscaleIdKey" "oci_vm_config_id" "autoscaleNameKey" "oci_vm_config_name" "uuidKey" "oci_vm_config_id" "resourceType" "OCI VM config")
    (dict "provider" "openstack" "collection" .openstackVmConfigs "idKey" "config_id" "autoscaleIdKey" "openstack_vm_config_id" "autoscaleNameKey" "openstack_vm_config_name" "uuidKey" "openstack_vm_config_id" "resourceType" "OpenStack VM config")
    (dict "provider" "proxmox" "collection" .proxmoxVmConfigs "idKey" "config_id" "autoscaleIdKey" "proxmox_vm_config_id" "autoscaleNameKey" "proxmox_vm_config_name" "uuidKey" "proxmox_vm_config_id" "resourceType" "Proxmox VM config")
    (dict "provider" "vsphere" "collection" .vsphereVmConfigs "idKey" "config_id" "autoscaleIdKey" "vsphere_vm_config_id" "autoscaleNameKey" "vsphere_vm_config_name" "uuidKey" "vsphere_vm_config_id" "resourceType" "vSphere VM config")
  -}}

  {{- range $autoscaleIndex, $autoscale := $autoscaleConfigs -}}
    {{- if and (not $autoscale.zone_id) $autoscale.zone_name -}}
      {{- $_ := include "kasm.configId" (dict
        "config" $autoscale
        "collection" $zones
        "idKey" "zone_id"
        "nameKey" "zone_name"
        "matchKeys" (list "name" "zone_name")
        "uuidKey" "zone_id"
        "resourceType" "zone"
      ) -}}
    {{- end -}}

    {{- if and (not $autoscale.server_pool_id) $autoscale.pool_name -}}
      {{- $_ := include "kasm.configId" (dict
        "config" $autoscale
        "collection" $serverPools
        "idKey" "server_pool_id"
        "nameKey" "pool_name"
        "matchKeys" (list "name" "server_pool_name")
        "uuidKey" "server_pool_id"
        "resourceType" "server pool"
      ) -}}
    {{- end -}}

    {{- range $providerDef := $providerDefs -}}
      {{- $autoscaleNameKey := get $providerDef "autoscaleNameKey" -}}
      {{- $autoscaleIdKey := get $providerDef "autoscaleIdKey" -}}
      {{- if or
        (and (hasKey $autoscale $autoscaleNameKey) (index $autoscale $autoscaleNameKey))
        (and (hasKey $autoscale $autoscaleIdKey) (index $autoscale $autoscaleIdKey))
      -}}
        {{- $_ := include "kasm.vmProviderConfigId" (merge (dict "autoscale" $autoscale) $providerDef) | replace "\n" "" -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Resolve group_id by group key or display name.

Usage:
{{ include "kasm.groupId" (dict "groupName" "admins" "groups" $groups) }}
*/}}
{{- define "kasm.groupId" -}}
  {{- $groupName := .groupName -}}
  {{- $groups := .groups | default list -}}
  {{- $resolvedId := "" -}}

  {{- range $groupIndex, $group := $groups -}}
    {{- $candidateKey := default "" $group.key -}}
    {{- $candidateName := default "" $group.name -}}
    {{- if or (eq $candidateKey $groupName) (eq $candidateName $groupName) -}}
      {{- $resolvedId = default (printf "${uuid:group_id:%s}" ((add $groupIndex 1) | toString)) $group.group_id -}}
    {{- end -}}
  {{- end -}}

  {{- if not $resolvedId -}}
    {{- fail (printf "No matching group found for group '%s'" $groupName) -}}
  {{- end -}}

  {{- $resolvedId -}}
{{- end -}}

{{/*
Resolve user_id by username or user key.

Usage:
{{ include "kasm.userId" (dict "username" "siteadmin@kasm.local" "users" $users) }}
*/}}
{{- define "kasm.userId" -}}
  {{- $username := .username -}}
  {{- $users := .users | default list -}}
  {{- $resolvedId := "" -}}

  {{- range $userIndex, $user := $users -}}
    {{- $candidateUsername := default $user.name $user.username -}}
    {{- if eq $candidateUsername $username -}}
      {{- $resolvedId = default (printf "${uuid:user_id:%s}" ((add $userIndex 1) | toString)) $user.user_id -}}
    {{- end -}}
  {{- end -}}

  {{- if not $resolvedId -}}
    {{- fail (printf "No matching user found for username '%s'" $username) -}}
  {{- end -}}

  {{- $resolvedId -}}
{{- end -}}

{{/*
Resolve api_id by API config name/key.

Usage:
{{ include "kasm.apiConfigId" (dict "apiName" "kcs_api" "apiConfigs" $apiConfigs) }}
*/}}
{{- define "kasm.apiConfigId" -}}
  {{- $apiName := .apiName -}}
  {{- $apiConfigs := .apiConfigs | default list -}}
  {{- $resolvedId := "" -}}

  {{- range $apiIndex, $apiConfig := $apiConfigs -}}
    {{- $candidateName := default $apiConfig.name $apiConfig.key -}}
    {{- if eq $candidateName $apiName -}}
      {{- $resolvedId = default (printf "${uuid:api_id:%s}" ((add $apiIndex 1) | toString)) $apiConfig.api_id -}}
    {{- end -}}
  {{- end -}}

  {{- if not $resolvedId -}}
    {{- fail (printf "No matching API config found for api '%s'" $apiName) -}}
  {{- end -}}

  {{- $resolvedId -}}
{{- end -}}

{{/*
Resolve a Kasm permission name to numeric permission_id.

This intentionally fails hard for unknown permissions. Silent bad permissions
in preseed data are worse than a failed Helm render.

Usage:
{{ include "kasm.permissionId" "users_view" }}
*/}}
{{- define "kasm.permissionId" -}}
  {{- $permissions := dict
    "kasm_session" 50
    "agent" 60
    "server_agent" 70
    "guac" 80
    "rdp_gateway" 90
    "rdp_gateway_connect" 91
    "network_sidecar" 92

    "user" 100
    "global_admin" 200

    "users_view" 300
    "users_modify" 301
    "users_create" 302
    "users_delete" 303
    "users_modify_admin" 351
    "users_auth_session" 352

    "groups_view" 400
    "groups_modify" 401
    "groups_create" 402
    "groups_delete" 403
    "groups_view_ifmember" 420
    "groups_modify_ifmember" 421
    "groups_view_system" 440
    "groups_modify_system" 441
    "groups_delete_system" 443

    "agents_view" 500
    "agents_modify" 501
    "agents_create" 502
    "agents_delete" 503

    "staging_view" 600
    "staging_modify" 601
    "staging_create" 602
    "staging_delete" 603

    "casting_view" 700
    "casting_modify" 701
    "casting_create" 702
    "casting_delete" 703

    "sessions_view" 800
    "sessions_modify" 801
    "sessions_delete" 803

    "session_recordings_view" 850

    "images_view" 900
    "images_modify" 901
    "images_create" 902
    "images_delete" 903
    "images_modify_resources" 904

    "devapi_view" 1000
    "devapi_modify" 1001
    "devapi_create" 1002
    "devapi_delete" 1003

    "webfilters_view" 1100
    "webfilters_modify" 1101
    "webfilters_create" 1102
    "webfilters_delete" 1103

    "brandings_view" 1200
    "brandings_modify" 1201
    "brandings_create" 1202
    "brandings_delete" 1203

    "settings_view" 1300
    "settings_modify" 1301
    "settings_modify_auth" 1302
    "settings_modify_cast" 1303
    "settings_modify_images" 1304
    "settings_modify_license" 1305
    "settings_modify_logging" 1306
    "settings_modify_manager" 1307
    "settings_modify_scale" 1308
    "settings_modify_subscription" 1309
    "settings_modify_filter" 1310
    "settings_modify_storage" 1311
    "settings_modify_connections" 1312
    "settings_modify_theme" 1313
    "settings_modify_auth_captcha" 1314

    "auth_view" 1400
    "auth_modify" 1401
    "auth_create" 1402
    "auth_delete" 1403

    "licenses_view" 1500
    "licenses_create" 1502
    "licenses_delete" 1503

    "system_view" 1600
    "system_export_schema" 1604
    "system_import_data" 1605
    "system_export_data" 1606

    "reports_view" 1700

    "managers_view" 1800
    "managers_modify" 1801
    "managers_create" 1802
    "managers_delete" 1803

    "zones_view" 1900
    "zones_modify" 1901
    "zones_create" 1902
    "zones_delete" 1903

    "companies_view" 2000
    "companies_modify" 2001
    "companies_create" 2002
    "companies_delete" 2003

    "connection_proxy_view" 2100
    "connection_proxy_modify" 2101
    "connection_proxy_create" 2102
    "connection_proxy_delete" 2103

    "physical_tokens_view" 2200
    "physical_tokens_modify" 2201
    "physical_tokens_create" 2202
    "physical_tokens_delete" 2203

    "servers_view" 2300
    "servers_modify" 2301
    "servers_create" 2302
    "servers_delete" 2303

    "server_pools_view" 2400
    "server_pools_modify" 2401
    "server_pools_create" 2402
    "server_pools_delete" 2403

    "autoscale_view" 2500
    "autoscale_modify" 2501
    "autoscale_create" 2502
    "autoscale_delete" 2503

    "vm_provider_view" 2600
    "vm_provider_modify" 2601
    "vm_provider_create" 2602
    "vm_provider_delete" 2603

    "autoscale_schedule_view" 2700
    "autoscale_schedule_modify" 2701
    "autoscale_schedule_create" 2702
    "autoscale_schedule_delete" 2703

    "dns_providers_view" 2800
    "dns_providers_modify" 2801
    "dns_providers_create" 2802
    "dns_providers_delete" 2803

    "registries_view" 2900
    "registries_modify" 2901
    "registries_create" 2902
    "registries_delete" 2903

    "storage_providers_view" 3000
    "storage_providers_modify" 3001
    "storage_providers_create" 3002
    "storage_providers_delete" 3003

    "egress_providers_view" 4000
    "egress_providers_modify" 4001
    "egress_providers_create" 4002
    "egress_providers_delete" 4003

    "egress_gateways_view" 4100
    "egress_gateways_modify" 4101
    "egress_gateways_create" 4102
    "egress_gateways_delete" 4103

    "egress_credentials_view" 4200
    "egress_credentials_modify" 4201
    "egress_credentials_create" 4202
    "egress_credentials_delete" 4203

    "ad_user_management_view" 4300
    "ad_user_management_modify" 4301
    "ad_user_management_create" 4302
    "ad_user_management_delete" 4303

    "banners_view" 4400
    "banners_modify" 4401
    "banners_create" 4402
    "banners_delete" 4403

    "server_templates_view" 4500
    "server_templates_modify" 4501
    "server_templates_create" 4502
    "server_templates_delete" 4503

    "labels_view" 4600
  -}}

  {{- if not (hasKey $permissions .) -}}
    {{- fail (printf "Unknown Kasm permission '%s'" .) -}}
  {{- end -}}

  {{- index $permissions . -}}
{{- end -}}

{{/*
Return default optional users when kasmConfig.defaultUsers=true.

Produces admin@kasm.local by default. Set kasmConfig.adminUsername to override the
login username on the seeded admin account (e.g. system@kasm.local for Kasm internal
deployments). admin@kasm.local and user@kasm.local are the only true built-in accounts:
their pw_hash/salt are the fixed built-in values backed by the admin-password/user-password
keys in the passwords Secret. If adminUsername is set to anything other than admin@kasm.local,
the seeded admin entry gets a secretKey derived from the local part of the username (e.g.
system@kasm.local -> "system"), so its password/salt are generated and stored under
<local-part>-password/<local-part>-salt in the passwords/salts Secrets, the same convention
used by the other non-built-in default users (site_admin, workspace_admin). pw_hash/salt are
computed from that generated credential rather than the built-in admin's fixed values; both
db-preseed-secret.yaml and db-init-job.yaml skip creating/using the admin-password Secret key
entirely once defaultUsers replaces admin@kasm.local with a renamed admin account.
User-supplied kasmConfig.users entries with the same username win.
*/}}
{{- define "kasm.defaultUsers" -}}
{{- if dig "defaultUsers" false .Values.kasmConfig }}
{{- $adminUsername := dig "adminUsername" "admin@kasm.local" .Values.kasmConfig -}}
{{- $adminSecretKey := (splitList "@" $adminUsername) | first | replace "." "-" | replace "_" "-" | lower -}}
- key: admin
  username: {{ $adminUsername }}
  realm: local
  user_id: "${uuid:user_id:2}"
  crypt_password: "${crypt:password:2}"
  crypt_salt: "${crypt:salt:2}"
  {{- if eq $adminUsername "admin@kasm.local" }}
  pw_hash: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  salt: "${uuid:user_salt:2}"
  {{- else }}
  secretKey: {{ $adminSecretKey }}
  {{- end }}
  groups:
    - all_users
    - admins
- key: user
  username: user@kasm.local
  realm: local
  user_id: "${uuid:user_id:1}"
  crypt_password: "${crypt:password:1}"
  crypt_salt: "${crypt:salt:1}"
  pw_hash: ef812e6cd523e95742921d31bd61856c62a14d76b03d422bc528f0fe37c8187d
  salt: "${uuid:user_salt:1}"
  groups:
    - all_users
- key: site_admin
  username: siteadmin@kasm.local
  secretKey: site-admin
  realm: local
  crypt_password: "${crypt:password:3}"
  crypt_salt: "${crypt:salt:3}"
  groups:
    - site_admins
    - all_site_users
    - all_users
- key: workspace_admin
  username: workspaceadmin@kasm.local
  secretKey: workspace-admin
  realm: local
  crypt_password: "${crypt:password:4}"
  crypt_salt: "${crypt:salt:4}"
  groups:
    - workspace_admins
    - all_site_users
    - all_users
{{- end }}
{{- end }}

{{/*
Return default groups when kasmConfig.defaultUsers=true.

User-supplied kasmConfig.groups entries win when they use the same key or name.
*/}}
{{- define "kasm.defaultGroups" -}}
{{- if dig "defaultUsers" false .Values.kasmConfig }}
- key: all_users
  name: All Users
  group_id: 68d557ac-4cac-42cc-a9f3-1c7c853de0f3
  description: Default Kasm users group.
  priority: 1000
  is_system: true
  permissions:
    - user
  settings:
    allow_kasm_pause:
      value: "False"
      value_type: bool
    allow_kasm_stop:
      value: "False"
      value_type: bool
    keepalive_expiration_action:
      value: delete
      value_type: string
    usage_limit:
      value: "{}"
      value_type: usage_limit

- key: admins
  name: Administrators
  group_id: "${uuid:group_id:2}"
  description: Default Kasm administrators group.
  priority: 1
  is_system: true
  permissions:
    - global_admin
  settings:
    allow_kasm_pause:
      value: "True"
      value_type: bool
    allow_kasm_stop:
      value: "True"
      value_type: bool
    allow_totp_2fa:
      value: "True"
      value_type: bool
    disabled_image_message:
      value: "This image is currently disabled."
      value_type: string
    require_2fa:
      value: "False"
      value_type: bool
    show_disabled_images:
      value: "True"
      value_type: bool

- key: all_site_users
  name: All Site Users
  description: Kasm All site users group.
  priority: 1000
  is_system: false
  program_data: {}
  permissions:
    - user
  settings:
    allow_2fa_self_enrollment:
      value: "True"
      value_type: bool
    allow_kasm_audio:
      value: "True"
      value_type: bool
    allow_kasm_clipboard_down:
      value: "True"
      value_type: bool
    allow_kasm_clipboard_seamless:
      value: "True"
      value_type: bool
    allow_kasm_clipboard_up:
      value: "True"
      value_type: bool
    allow_kasm_delete:
      value: "True"
      value_type: bool
    allow_kasm_downloads:
      value: "True"
      value_type: bool
    allow_kasm_gamepad:
      value: "True"
      value_type: bool
    allow_kasm_microphone:
      value: "True"
      value_type: bool
    allow_kasm_printing:
      value: "True"
      value_type: bool
    allow_kasm_sharing:
      value: "True"
      value_type: bool
    allow_kasm_uploads:
      value: "True"
      value_type: bool
    allow_kasm_webcam:
      value: "True"
      value_type: bool
    allow_persistent_profile:
      value: "True"
      value_type: bool
    allow_totp_2fa:
      value: "True"
      value_type: bool
    allow_user_storage_mapping:
      value: "True"
      value_type: bool
    allow_webauthn_2fa:
      value: "True"
      value_type: bool
    auto_add_local_users:
      value: "True"
      value_type: bool
    control_panel.advanced_settings.show_game_mode:
      value: "True"
      value_type: bool
    control_panel.advanced_settings.show_ime_input_mode:
      value: "True"
      value_type: bool
    control_panel.advanced_settings.show_keyboard_controls:
      value: "True"
      value_type: bool
    control_panel.advanced_settings.show_pointer_lock:
      value: "True"
      value_type: bool
    control_panel.advanced_settings.show_prefer_local_cursor:
      value: "True"
      value_type: bool
    control_panel.show_delete_session:
      value: "True"
      value_type: bool
    control_panel.show_fullscreen:
      value: "True"
      value_type: bool
    control_panel.show_logout:
      value: "True"
      value_type: bool
    control_panel.show_return_to_workspaces:
      value: "True"
      value_type: bool
    control_panel.show_streaming_quality:
      value: "True"
      value_type: bool
    idle_disconnect:
      value: "20"
      value_type: float
    kasm_audio_default_on:
      value: "True"
      value_type: bool
    keepalive_expiration:
      value: "3600"
      value_type: int
    keepalive_expiration_action:
      value: delete
      value_type: string
    max_kasms_per_user:
      value: "5"
      value_type: int
    max_user_storage_mappings:
      value: "2"
      value_type: int
    read_only_user_storage_mapping:
      value: "False"
      value_type: bool

- key: site_admins
  name: Site Administrators
  description: Kasm SaaS administrators group.
  priority: 3
  is_system: false
  program_data: {}
  permissions:
    - user
    - users_view
    - users_modify
    - users_create
    - users_delete
    - users_auth_session
    - groups_view
    - groups_modify
    - groups_create
    - groups_delete
    - groups_view_ifmember
    - groups_modify_ifmember
    - agents_view
    - staging_view
    - casting_view
    - casting_modify
    - casting_create
    - casting_delete
    - sessions_view
    - sessions_modify
    - sessions_delete
    - session_recordings_view
    - images_view
    - images_modify
    - images_create
    - images_delete
    - images_modify_resources
    - devapi_view
    - webfilters_view
    - webfilters_modify
    - webfilters_create
    - webfilters_delete
    - brandings_view
    - brandings_modify
    - brandings_create
    - brandings_delete
    - settings_view
    - settings_modify_auth
    - settings_modify_storage
    - auth_view
    - auth_modify
    - auth_create
    - auth_delete
    - licenses_view
    - system_view
    - system_export_schema
    - reports_view
    - zones_view
    - connection_proxy_view
    - physical_tokens_view
    - physical_tokens_modify
    - physical_tokens_create
    - physical_tokens_delete
    - servers_view
    - autoscale_schedule_view
    - registries_view
    - registries_modify
    - registries_create
    - registries_delete
    - storage_providers_view
    - storage_providers_modify
    - storage_providers_create
    - storage_providers_delete
    - egress_gateways_view
    - egress_gateways_modify
    - egress_gateways_create
    - egress_gateways_delete
    - egress_credentials_view
    - egress_credentials_modify
    - egress_credentials_create
    - egress_credentials_delete
    - egress_providers_view
    - egress_providers_modify
    - egress_providers_create
    - egress_providers_delete
    - ad_user_management_view
    - ad_user_management_modify
    - ad_user_management_create
    - ad_user_management_delete
    - banners_view
    - banners_modify
    - banners_create
    - banners_delete
    - labels_view

- key: workspace_admins
  name: Workspace Administrators
  description: Kasm Workspace administrators group.
  priority: 4
  is_system: false
  program_data: {}
  permissions:
    - user
    - users_view
    - groups_view
    - agents_view
    - staging_view
    - casting_view
    - casting_modify
    - casting_create
    - casting_delete
    - sessions_view
    - sessions_modify
    - sessions_delete
    - images_view
    - images_modify
    - images_create
    - images_delete
    - images_modify_resources
    - webfilters_view
    - system_view
    - reports_view
    - zones_view
    - servers_view
    - server_pools_view
    - registries_view
    - registries_modify
    - registries_create
    - registries_delete
    - storage_providers_view
{{- end }}
{{- end }}

{{/*
Return default API configs when kasmConfig.defaultApiUsers=true.

User-supplied kasmConfig.apiConfigs entries win when they use the same key.
*/}}
{{- define "kasm.defaultApiConfigs" -}}
{{- if dig "defaultApiUsers" false .Values.kasmConfig }}
- key: kasm_engineering_api
  name: Kasm Engineering Automation
  secretKey: kasm-engineering-api
  api_key: KasmRWApiKey
  enabled: true
  expires: null
  read_only: false
  permissions:
    - autoscale_create
    - autoscale_delete
    - autoscale_modify
    - autoscale_schedule_create
    - autoscale_schedule_delete
    - autoscale_schedule_modify
    - autoscale_schedule_view
    - autoscale_view
    - managers_view
    - server_pools_view
    - servers_view
    - vm_provider_create
    - vm_provider_delete
    - vm_provider_modify
    - vm_provider_view
    - zones_view
- key: kcs_api
  name: Kasm Customer Support
  secretKey: kcs-api
  api_key: KcsReadApiKy
  enabled: true
  expires: null
  read_only: true
  permissions:
    - user
    - users_view
    - groups_view
    - groups_view_ifmember
    - groups_view_system
    - agents_view
    - staging_view
    - casting_view
    - images_view
    - sessions_view
    - session_recordings_view
    - webfilters_view
    - brandings_view
    - settings_view
    - auth_view
    - licenses_view
    - system_view
    - reports_view
    - managers_view
    - zones_view
    - companies_view
    - connection_proxy_view
    - physical_tokens_view
    - servers_view
    - server_pools_view
    - autoscale_view
    - vm_provider_view
    - autoscale_schedule_view
    - dns_providers_view
    - registries_view
    - storage_providers_view
    - egress_providers_view
    - egress_gateways_view
    - ad_user_management_view
    - banners_view
    - server_templates_view
    - labels_view
{{- end }}
{{- end }}

{{/*
Return configured groups merged with default groups when kasmConfig.defaultUsers=true.
Configured groups win when key or name matches a default group.
*/}}
{{- define "kasm.mergedGroups" -}}
{{- $kasmConfig := .Values.kasmConfig.config | default dict -}}
{{- $configuredGroups := get $kasmConfig "groups" | default list -}}
{{- $defaultGroups := include "kasm.defaultGroups" . | fromYamlArray | default list -}}
{{- $groups := list -}}
{{- $configuredGroupKeys := dict -}}
{{- range $group := $configuredGroups -}}
  {{- $groups = append $groups $group -}}
  {{- if $group.name -}}
    {{- $_ := set $configuredGroupKeys $group.name true -}}
  {{- end -}}
  {{- if $group.key -}}
    {{- $_ := set $configuredGroupKeys $group.key true -}}
  {{- end -}}
{{- end -}}
{{- range $defaultGroup := $defaultGroups -}}
  {{- $defaultGroupKey := default $defaultGroup.name $defaultGroup.key -}}
  {{- if not (hasKey $configuredGroupKeys $defaultGroupKey) -}}
    {{- $groups = append $groups $defaultGroup -}}
  {{- end -}}
{{- end -}}
{{- $groups | toYaml -}}
{{- end -}}

{{/*
Return configured users merged with default optional users when kasmConfig.defaultUsers=true.
Configured users win when username matches a default user.
*/}}
{{- define "kasm.mergedUsers" -}}
{{- $kasmConfig := .Values.kasmConfig.config | default dict -}}
{{- $configuredUsers := get $kasmConfig "users" | default list -}}
{{- $defaultUsers := include "kasm.defaultUsers" . | fromYamlArray | default list -}}
{{- $users := list -}}
{{- $configuredUsernames := dict -}}
{{- range $user := $configuredUsers -}}
  {{- $users = append $users $user -}}
  {{- if $user.username -}}
    {{- $_ := set $configuredUsernames $user.username true -}}
  {{- end -}}
{{- end -}}
{{- range $defaultUser := $defaultUsers -}}
  {{- if not (hasKey $configuredUsernames $defaultUser.username) -}}
    {{- $users = append $users $defaultUser -}}
  {{- end -}}
{{- end -}}
{{- $users | toYaml -}}
{{- end -}}

{{/*
Return configured API configs merged with default API configs when kasmConfig.defaultUsers=true.
Configured API configs win when key or name matches a default API config.
*/}}
{{- define "kasm.mergedApiConfigs" -}}
{{- $kasmConfig := .Values.kasmConfig.config | default dict -}}
{{- $configuredApiConfigs := get $kasmConfig "apiConfigs" | default list -}}
{{- $defaultApiConfigs := include "kasm.defaultApiConfigs" . | fromYamlArray | default list -}}
{{- $apiConfigs := list -}}
{{- $configuredApiKeys := dict -}}
{{- range $apiConfig := $configuredApiConfigs -}}
  {{- $apiConfigs = append $apiConfigs $apiConfig -}}
  {{- if $apiConfig.key -}}
    {{- $_ := set $configuredApiKeys $apiConfig.key true -}}
  {{- end -}}
  {{- if $apiConfig.name -}}
    {{- $_ := set $configuredApiKeys $apiConfig.name true -}}
  {{- end -}}
{{- end -}}
{{- range $defaultApiConfig := $defaultApiConfigs -}}
  {{- $defaultApiKey := default $defaultApiConfig.name $defaultApiConfig.key -}}
  {{- if not (hasKey $configuredApiKeys $defaultApiKey) -}}
    {{- $apiConfigs = append $apiConfigs $defaultApiConfig -}}
  {{- end -}}
{{- end -}}
{{- $apiConfigs | toYaml -}}
{{- end -}}

{{/*
Build a stable Secret key prefix for a user or API config.
Prefer .secretKey. Otherwise derive from username or name.
*/}}
{{- define "kasm.identitySecretKey" -}}
  {{- $item := .item -}}
  {{- $prefix := .prefix | default "identity" -}}
  {{- if $item.secretKey -}}
    {{- $item.secretKey -}}
  {{- else if $item.username -}}
    {{- printf "%s-%s" $prefix ($item.username | replace "@" "-" | replace "." "-" | replace "_" "-" | lower) -}}
  {{- else if $item.name -}}
    {{- printf "%s-%s" $prefix ($item.name | replace " " "-" | replace "_" "-" | replace "." "-" | lower) -}}
  {{- else if $item.key -}}
    {{- printf "%s-%s" $prefix ($item.key | replace "_" "-" | replace "." "-" | lower) -}}
  {{- else -}}
    {{- fail "identitySecretKey requires secretKey, username, name, or key" -}}
  {{- end -}}
{{- end -}}

{{/*
Read a base64 encoded value from a Kubernetes Secret data map and decode it.
*/}}
{{- define "kasm.secretValue" -}}
  {{- $data := .data | default dict -}}
  {{- $key := required "key is required for kasm.secretValue" .key -}}
  {{- $encodedValue := required (printf "Secret key '%s' was not found" $key) (get $data $key) -}}
  {{- $encodedValue | b64dec -}}
{{- end -}}

{{/*
Resolve a credential field from an inline value or an existing Kubernetes Secret via lookup.
Call: include "kasm.credentialValue" (list <rootCtx> <configItem> <fieldName>)
  rootCtx    — Helm root context (provides Release.Namespace)
  configItem — the config dict (oidcConfig, awsConfig, etc.)
  fieldName  — the credential field key (e.g. "client_secret")
If configItem.existingSecret (Secret name) and configItem.existingSecretKey (data key) are both set,
the value is read from that Secret via lookup and base64-decoded. Otherwise, the inline
configItem[fieldName] value is returned. Returns empty string when neither path yields a value.
*/}}
{{- define "kasm.credentialValue" -}}
{{- $ctx := index . 0 -}}
{{- $item := index . 1 -}}
{{- $field := index . 2 -}}
{{- $inline := get $item $field | default "" -}}
{{- $secretName := get $item "existingSecret" | default "" -}}
{{- $secretKey := get $item "existingSecretKey" | default "" -}}
{{- if and $secretName $secretKey -}}
  {{- $obj := lookup "v1" "Secret" $ctx.Release.Namespace $secretName | default dict -}}
  {{- $data := get $obj "data" | default dict -}}
  {{- $encoded := get $data $secretKey | default "" -}}
  {{- if $encoded -}}{{ $encoded | b64dec }}{{ else }}{{ $inline }}{{ end -}}
{{- else -}}
  {{- $inline -}}
{{- end -}}
{{- end -}}

{{/*
Emit a quoted YAML string value, or the literal null token, for an optional field.
Call: include "kasm.nullableQuoted" $value
*/}}
{{- define "kasm.nullableQuoted" -}}
{{- if . -}}{{ . | quote }}{{- else -}}null{{- end -}}
{{- end -}}

{{/*
Emit all VM provider config ID and interspersed DNS config ID fields for a single autoscale entry.
Call: include "kasm.autoscaleVmConfigIds" (dict "autoscale" $autoscale "collections" $vmCollections)
$vmCollections maps provider short names to their config slices:
  "aws", "azure", "digitalOcean", "gcp", "harvester", "kubevirt",
  "nutanix", "oci", "openstack", "proxmox", "vsphere"
*/}}
{{- define "kasm.autoscaleVmConfigIds" -}}
{{- $a := .autoscale -}}
{{- $c := .collections -}}
aws_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "aws") "idKey" "aws_config_id" "alternateIdKeys" (list "config_id") "autoscaleIdKey" "aws_config_id" "autoscaleNameKey" "aws_config_name" "uuidKey" "aws_config_id" "resourceType" "AWS VM config") }}
aws_dns_config_id: {{ default "null" $a.aws_dns_config_id }}
azure_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "azure") "idKey" "azure_config_id" "alternateIdKeys" (list "config_id") "autoscaleIdKey" "azure_config_id" "autoscaleNameKey" "azure_config_name" "uuidKey" "azure_config_id" "resourceType" "Azure VM config") }}
azure_dns_config_id: {{ default "null" $a.azure_dns_config_id }}
digital_ocean_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "digitalOcean") "idKey" "config_id" "autoscaleIdKey" "digital_ocean_vm_config_id" "autoscaleNameKey" "digital_ocean_vm_config_name" "uuidKey" "digital_ocean_vm_config_id" "resourceType" "DigitalOcean VM config") }}
digital_ocean_dns_config_id: {{ default "null" $a.digital_ocean_dns_config_id }}
gcp_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "gcp") "idKey" "config_id" "autoscaleIdKey" "gcp_vm_config_id" "autoscaleNameKey" "gcp_vm_config_name" "uuidKey" "gcp_vm_config_id" "resourceType" "GCP VM config") }}
harvester_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "harvester") "idKey" "config_id" "autoscaleIdKey" "harvester_vm_config_id" "autoscaleNameKey" "harvester_vm_config_name" "uuidKey" "harvester_vm_config_id" "resourceType" "Harvester VM config") }}
kubevirt_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "kubevirt") "idKey" "config_id" "autoscaleIdKey" "kubevirt_vm_config_id" "autoscaleNameKey" "kubevirt_vm_config_name" "uuidKey" "kubevirt_vm_config_id" "resourceType" "KubeVirt VM config") }}
nutanix_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "nutanix") "idKey" "config_id" "autoscaleIdKey" "nutanix_vm_config_id" "autoscaleNameKey" "nutanix_vm_config_name" "uuidKey" "nutanix_vm_config_id" "resourceType" "Nutanix VM config") }}
oci_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "oci") "idKey" "config_id" "autoscaleIdKey" "oci_vm_config_id" "autoscaleNameKey" "oci_vm_config_name" "uuidKey" "oci_vm_config_id" "resourceType" "OCI VM config") }}
openstack_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "openstack") "idKey" "config_id" "autoscaleIdKey" "openstack_vm_config_id" "autoscaleNameKey" "openstack_vm_config_name" "uuidKey" "openstack_vm_config_id" "resourceType" "OpenStack VM config") }}
proxmox_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "proxmox") "idKey" "config_id" "autoscaleIdKey" "proxmox_vm_config_id" "autoscaleNameKey" "proxmox_vm_config_name" "uuidKey" "proxmox_vm_config_id" "resourceType" "Proxmox VM config") }}
vsphere_vm_config_id: {{ include "kasm.vmProviderConfigId" (dict "autoscale" $a "collection" (get $c "vsphere") "idKey" "config_id" "autoscaleIdKey" "vsphere_vm_config_id" "autoscaleNameKey" "vsphere_vm_config_name" "uuidKey" "vsphere_vm_config_id" "resourceType" "vSphere VM config") }}
{{- end -}}

{{/*
Generate a Kasm-compatible SHA-256 hash: sha256(password + salt).
*/}}
{{- define "kasm.passwordHash" -}}
  {{- $password := required "password is required for kasm.passwordHash" .password -}}
  {{- $salt := required "salt is required for kasm.passwordHash" .salt -}}
  {{- sha256sum (printf "%s%s" $password $salt) -}}
{{- end -}}
