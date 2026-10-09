# =============================================================================
# ACCESS CONTRACT — one use case onboarded to the gateway (Bicep parity:
# citadel-access-contracts). Per service code:
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
  xml_content         = each.value.policy_xml != "" ? each.value.policy_xml : file("${path.module}/policies/default-ai-product-policy.xml")
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
    condition     = var.foundry_project_id == null || !local.foundry_mi || alltrue([for s in var.services : strcontains(s.policy_xml, "jwtRequired")])
    error_message = "foundry_config.auth_type = ProjectManagedIdentity: every service's product policy_xml must set jwtRequired=true with jwtAudience = managed_identity_audience, jwtIssuer and jwtOpenIdConfigUrl, otherwise the project identity's JWT is sent but never validated (see DEPLOYMENT_GUIDE, Foundry connection authentication). Use auth_type = ApiKey to skip JWT validation."
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
