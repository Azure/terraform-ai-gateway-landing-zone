# =============================================================================
# ACCESS CONTRACT — one use case onboarded to the gateway (citadel-access-contracts). 
# Per service code:
#   product (+ policy) -> mapped APIs -> subscription -> Key Vault secrets ->
#   Foundry connection.
# Subscription keys never enter Terraform state: the subscription is an
# azapi resource (GET returns no keys), the key is read through an ephemeral
# listSecrets action and written only to write-only arguments.
# =============================================================================

locals {
  postfix  = "${var.use_case.business_unit}-${var.use_case.use_case_name}-${var.use_case.environment}"
  services = { for s in var.services : s.code => s }

  endpoint_url = { for code, s in local.services : code => "${var.api_management.gateway_url}/${var.api_paths[code]}" }

  # Product policy: generated from the service's properties (policies/*.tftpl), unless the
  # service brings a complete policy_xml. Services that list tool or agent APIs get the
  # asset-type-aware layout (a <choose> on the asset kind set by the set-asset-kind fragment).
  period_seconds = { Hourly = 3600, Daily = 86400, Weekly = 604800, Monthly = 2592000, Yearly = 31536000 }

  asset_limits = { for code, s in local.services : code => {
    tool  = s.tool_limit
    agent = s.agent_limit
  } }

  # The templates' directive lines leave blank lines; "/\n([ \t]*\n)+/" collapses them.
  policy_llm_rules = { for code, s in local.services : code => trimspace(replace(templatefile("${path.module}/policies/llm-rules.xml.tftpl", {
    allowed_models          = join(",", s.allowed_models)
    enable_response_headers = s.enable_response_headers
    token_limit_attributes = s.token_limit == null ? "" : join(" ", compact([
      s.token_limit.tokens_per_minute == null ? "" : "tokens-per-minute=\"${s.token_limit.tokens_per_minute}\"",
      s.token_limit.token_quota == null ? "" : "token-quota=\"${s.token_limit.token_quota}\" token-quota-period=\"${s.token_limit.token_quota_period}\"",
    ]))
  }), "/\n([ \t]*\n)+/", "\n")) }

  policy_asset_rules = { for code, s in local.services : code => { for kind, limit in local.asset_limits[code] : kind => limit == null ? "" : trimspace(replace(templatefile("${path.module}/policies/asset-rules.xml.tftpl", {
    kind                 = kind
    calls_per_minute     = limit.calls_per_minute == null ? "" : tostring(limit.calls_per_minute)
    call_quota           = limit.call_quota == null ? "" : tostring(limit.call_quota)
    quota_period_seconds = local.period_seconds[limit.call_quota_period]
  }), "/\n([ \t]*\n)+/", "\n")) } }

  # JWT settings per service. Unset = the security-handler falls back to the gateway's JWT-* named
  # values (gateway-config entra_auth). A contract with a ProjectManagedIdentity Foundry connection
  # defaults to the project identity's token instead: audience = the connection's
  # managed_identity_audience, v1 issuer of the tenant (managed identity tokens), v2.0 keys.
  foundry_mi_defaults = var.foundry_project_id != null && var.foundry_config.auth_type == "ProjectManagedIdentity"

  jwt = { for code, s in local.services : code => {
    audience = s.jwt_audience != null ? s.jwt_audience : (local.foundry_mi_defaults ? var.foundry_config.managed_identity_audience : "")
    issuer   = s.jwt_issuer != null ? s.jwt_issuer : (local.foundry_mi_defaults ? "https://sts.windows.net/${var.tenant_id}/" : "")
    openid   = s.jwt_openid_config_url != null ? s.jwt_openid_config_url : (local.foundry_mi_defaults ? "https://login.microsoftonline.com/${var.tenant_id}/v2.0/.well-known/openid-configuration" : "")
    roles    = join(",", s.required_roles)
  } }

  product_policy_xml = {
    for code, s in local.services : code => s.policy_xml != "" ? s.policy_xml : replace(templatefile("${path.module}/policies/product-policy.xml.tftpl", {
      jwt_required = s.jwt_required
      # Escaped for an XML attribute value.
      jwt_audience = replace(replace(replace(local.jwt[code].audience, "&", "&amp;"), "\"", "&quot;"), "<", "&lt;")
      jwt_issuer   = replace(replace(replace(local.jwt[code].issuer, "&", "&amp;"), "\"", "&quot;"), "<", "&lt;")
      jwt_openid   = replace(replace(replace(local.jwt[code].openid, "&", "&amp;"), "\"", "&quot;"), "<", "&lt;")
      jwt_roles    = local.jwt[code].roles
      llm_rules    = local.policy_llm_rules[code]
      multi_asset  = length(s.tool_apis) + length(s.agent_apis) > 0
      tool_apis    = join(",", s.tool_apis)
      agent_apis   = join(",", s.agent_apis)
      tool_rules   = local.policy_asset_rules[code].tool
      agent_rules  = local.policy_asset_rules[code].agent
    }), "/\n([ \t]*\n)+/", "\n")
  }

  product_apis = merge([
    for code, s in local.services : {
      for api in lookup(var.api_name_mapping, code, []) : "${code}-${api}" => { code = code, api = api }
    }
  ]...)
}

resource "azurerm_api_management_product" "service" {
  for_each = local.services

  api_management_name   = var.api_management.name
  resource_group_name   = var.api_management.resource_group_name
  product_id            = "${each.key}-${local.postfix}"
  display_name          = "${each.key} ${var.use_case.business_unit} ${var.use_case.use_case_name} ${var.use_case.environment}"
  description           = "AI Gateway product for ${each.key} - ${var.use_case.use_case_name}"
  terms                 = var.product_terms
  subscription_required = true
  approval_required     = false
  subscriptions_limit   = 100
  published             = true
}

resource "azurerm_api_management_product_api" "service" {
  for_each = local.product_apis

  api_management_name = var.api_management.name
  resource_group_name = var.api_management.resource_group_name
  product_id          = azurerm_api_management_product.service[each.value.code].product_id
  api_name            = each.value.api
}

resource "azurerm_api_management_product_policy" "service" {
  for_each = local.services

  api_management_name = var.api_management.name
  resource_group_name = var.api_management.resource_group_name
  product_id          = azurerm_api_management_product.service[each.key].product_id
  xml_content         = local.product_policy_xml[each.key]
}

resource "azapi_resource" "subscription" {
  for_each = local.services

  type      = "Microsoft.ApiManagement/service/subscriptions@2024-05-01"
  name      = "${each.key}-${local.postfix}-SUB-01"
  parent_id = var.api_management.id

  body = {
    properties = {
      displayName = "${each.key}-${local.postfix}-SUB-01"
      scope       = "${var.api_management.id}/products/${azurerm_api_management_product.service[each.key].product_id}"
      state       = "active"
    }
  }
}

# Rotation clock: the key secrets are rewritten (and their expiry moved) when it ticks.
resource "time_rotating" "secrets" {
  rotation_days = var.secret_rotation_days
}

# Subscription keys, read without storing them. The no-op suffix makes the
# resource ID unknown while the subscription is being created, so the action
# runs at apply time instead of failing at plan time.
ephemeral "azapi_resource_action" "keys" {
  for_each = local.needs_key ? local.services : {}

  type                   = "Microsoft.ApiManagement/service/subscriptions@2024-05-01"
  resource_id            = "${azapi_resource.subscription[each.key].id}${substr(jsonencode(azapi_resource.subscription[each.key].output), 0, 0)}"
  action                 = "listSecrets"
  method                 = "POST"
  response_export_values = ["primaryKey"]
}

locals {
  needs_key   = var.key_vault_id != null || var.foundry_project_id != null
  key_version = time_rotating.secrets.unix
}

# --- Key Vault secrets ---------------------------------------------------------
# Names are normalised: Key Vault doesn't allow underscores.

resource "azurerm_key_vault_secret" "endpoint" {
  for_each = var.key_vault_id == null ? {} : local.services

  key_vault_id    = var.key_vault_id
  name            = lower(replace(each.value.endpoint_secret_name, "_", "-"))
  value           = local.endpoint_url[each.key]
  content_type    = "url"
  expiration_date = timeadd(time_rotating.secrets.rfc3339, "${var.secret_validity_days * 24}h")
}

resource "azurerm_key_vault_secret" "key" {
  for_each = var.key_vault_id == null ? {} : local.services

  key_vault_id     = var.key_vault_id
  name             = lower(replace(each.value.api_key_secret_name, "_", "-"))
  value_wo         = ephemeral.azapi_resource_action.keys[each.key].output.primaryKey
  value_wo_version = local.key_version
  content_type     = "apim-subscription-key"
  # ALZ Enforce-GR-KeyVault: an expiry within 90 days; reads keep working after it.
  expiration_date = timeadd(time_rotating.secrets.rfc3339, "${var.secret_validity_days * 24}h")
}

# --- Foundry connection ----------------------------------------------------------
# customHeaders is always sent: the Foundry portal needs the field to render the connection.
#
# auth_type = ProjectManagedIdentity (upstream accelerator PR #159): the project's managed
# identity presents an Entra JWT for managed_identity_audience, and the subscription key
# travels as the `api-key` custom header, so there is no stored credential. That header
# value is the key, so customHeaders is sent only through the write-only sensitive_body.
# auth_type = ApiKey: the key is the stored credential (credentials.key).

locals {
  foundry_mi = var.foundry_config.auth_type == "ProjectManagedIdentity"

  foundry_prefix               = var.foundry_config.connection_name_prefix != "" ? var.foundry_config.connection_name_prefix : "Hub-${local.postfix}"
  foundry_has_custom_discovery = var.foundry_config.list_models_endpoint != "" && var.foundry_config.get_model_endpoint != "" && var.foundry_config.deployment_provider != ""

  foundry_metadata = merge(
    { deploymentInPath = var.foundry_config.deployment_in_path },
    var.foundry_config.inference_api_version != "" ? { inferenceAPIVersion = var.foundry_config.inference_api_version } : {},
    var.foundry_config.deployment_api_version != "" ? { deploymentAPIVersion = var.foundry_config.deployment_api_version } : {},
    local.foundry_has_custom_discovery ? {
      modelDiscovery = jsonencode({
        listModelsEndpoint = var.foundry_config.list_models_endpoint
        getModelEndpoint   = var.foundry_config.get_model_endpoint
        deploymentProvider = var.foundry_config.deployment_provider
      })
    } : {},
    length(var.foundry_config.static_models) > 0 && !local.foundry_has_custom_discovery ? { models = jsonencode(var.foundry_config.static_models) } : {},
    local.foundry_mi ? {} : { customHeaders = length(var.foundry_config.custom_headers) > 0 ? jsonencode(var.foundry_config.custom_headers) : "{}" },
    local.foundry_mi ? { audience = var.foundry_config.managed_identity_audience } : {},
    length(var.foundry_config.auth_config) > 0 ? { authConfig = jsonencode(var.foundry_config.auth_config) } : {},
  )
}

# The product policy has to validate the project identity's JWT (the key alone no
# longer identifies the caller). Warn rather than fail: custom policies are free-form.
check "foundry_mi_policy_validates_jwt" {
  assert {
    condition     = var.foundry_project_id == null || !local.foundry_mi || alltrue([for s in var.services : s.policy_xml != "" ? strcontains(s.policy_xml, "jwtRequired") : s.jwt_required])
    error_message = "foundry_config.auth_type = ProjectManagedIdentity: every service needs jwt_required = true (or a custom policy_xml that sets jwtRequired=true with jwtAudience = managed_identity_audience, jwtIssuer and jwtOpenIdConfigUrl), otherwise the project identity's JWT is sent but never validated (see DEPLOYMENT_GUIDE, Foundry connection authentication). Use auth_type = ApiKey to skip JWT validation."
  }
}

resource "azapi_resource" "foundry_connection" {
  for_each = var.foundry_project_id == null ? {} : local.services

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "${local.foundry_prefix}-${each.key}"
  parent_id = var.foundry_project_id

  schema_validation_enabled = false

  # Export nothing: Foundry echoes customHeaders (the api-key) in ProjectManagedIdentity mode,
  # and azapi would otherwise store the response in state as `output`.
  response_export_values = []

  body = {
    properties = merge({
      category      = var.foundry_config.connection_category
      target        = local.endpoint_url[each.key]
      authType      = var.foundry_config.auth_type
      isSharedToAll = var.foundry_config.is_shared_to_all
      metadata      = local.foundry_metadata
    }, local.foundry_mi ? { audience = var.foundry_config.managed_identity_audience } : {})
  }

  # Write-only: merged into the request, never stored in state. The two shapes differ,
  # so they are chosen as JSON (a conditional can't return objects of different types).
  sensitive_body = jsondecode(local.foundry_mi ? jsonencode({
    properties = {
      metadata = {
        customHeaders = jsonencode(merge(var.foundry_config.custom_headers, {
          "api-key" = ephemeral.azapi_resource_action.keys[each.key].output.primaryKey
        }))
      }
    }
    }) : jsonencode({
    properties = {
      credentials = {
        key = ephemeral.azapi_resource_action.keys[each.key].output.primaryKey
      }
    }
  }))
  sensitive_body_version = local.foundry_mi ? {
    "properties.metadata.customHeaders" = tostring(local.key_version)
    } : {
    "properties.credentials.key" = tostring(local.key_version)
  }
}
