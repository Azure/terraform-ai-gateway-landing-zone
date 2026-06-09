# =============================================================================
# Citadel Access Contracts — Main
#
# Standalone Terraform deployment that onboards a use-case to an existing AI
# Governance Hub APIM instance. Mirrors the Bicep citadel-access-contracts
# module (main.bicep + apimOnboardService.bicep + kvSecrets.bicep +
# foundryConnection.bicep) as an independently-applyable root module.
#
# For each requested service this module:
#   1. Creates an APIM product            (<code>-<bu>-<usecase>-<env>)
#   2. Attaches the mapped APIs            (api_name_mapping[code])
#   3. Applies an inbound product policy   (per-service XML or default)
#   4. Creates a named subscription        (<code>-<bu>-<usecase>-<env>-SUB-01)
#   5. Optionally writes endpoint + key secrets to Key Vault
#   6. Optionally creates a Foundry connection pointing at the gateway
# =============================================================================

# -----------------------------------------------------------------------------
# DATA SOURCES — Reference the existing APIM + its published APIs
# -----------------------------------------------------------------------------

data "azurerm_api_management" "target" {
  name                = var.apim.name
  resource_group_name = var.apim.resource_group_name
}

# First API per service — used to resolve the real API path for endpoint URLs
# (Bicep parity: apimOnboardService.bicep outputs apiPath = api.properties.path).
data "azurerm_api_management_api" "first" {
  for_each = { for s in var.services : s.code => s }

  name                = lookup(var.api_name_mapping, each.value.code, [""])[0]
  api_management_name = var.apim.name
  resource_group_name = var.apim.resource_group_name
  revision            = "1"
}

# -----------------------------------------------------------------------------
# LOCALS
# -----------------------------------------------------------------------------

locals {
  product_postfix = "${var.use_case.business_unit}-${var.use_case.use_case_name}-${var.use_case.environment}"

  gateway_url = data.azurerm_api_management.target.gateway_url

  # Per-service gateway endpoint URL (gateway + first API path).
  service_endpoint_url = {
    for s in var.services :
    s.code => "${local.gateway_url}/${data.azurerm_api_management_api.first[s.code].path}"
  }

  # Flatten services × api_names → product-API attachments.
  product_apis = merge([
    for s in var.services : {
      for api_name in lookup(var.api_name_mapping, s.code, []) :
      "${s.code}-${api_name}" => {
        product_id = "${s.code}-${local.product_postfix}"
        api_name   = api_name
      }
    }
  ]...)

  # Fully-qualified Key Vault ID (supports a Key Vault in another subscription/RG).
  key_vault_id = var.use_target_key_vault ? "/subscriptions/${var.key_vault.subscription_id}/resourceGroups/${var.key_vault.resource_group_name}/providers/Microsoft.KeyVault/vaults/${var.key_vault.name}" : ""

  # Fully-qualified Foundry project ID (azapi parent_id for the connection).
  foundry_project_id = var.use_target_foundry ? "/subscriptions/${var.foundry.subscription_id}/resourceGroups/${var.foundry.resource_group_name}/providers/Microsoft.CognitiveServices/accounts/${var.foundry.account_name}/projects/${var.foundry.project_name}" : ""

  # Connection-name prefix (Bicep parity: connectionNamePrefix || "Hub-<postfix>").
  foundry_connection_prefix = var.foundry_config.connection_name_prefix != "" ? var.foundry_config.connection_name_prefix : "Hub-${local.product_postfix}"
}

# -----------------------------------------------------------------------------
# APIM PRODUCTS
# -----------------------------------------------------------------------------

resource "azurerm_api_management_product" "service" {
  for_each = { for s in var.services : s.code => s }

  api_management_name = var.apim.name
  resource_group_name = var.apim.resource_group_name
  product_id          = "${each.value.code}-${local.product_postfix}"
  display_name        = "${each.value.code} ${var.use_case.business_unit} ${var.use_case.use_case_name} ${var.use_case.environment}"
  description         = "AI Gateway product for ${each.value.code} - ${var.use_case.use_case_name}"
  terms               = var.product_terms

  subscription_required = true
  approval_required     = false
  subscriptions_limit   = 100
  published             = true
}

resource "azurerm_api_management_product_api" "service" {
  for_each = local.product_apis

  api_management_name = var.apim.name
  resource_group_name = var.apim.resource_group_name
  product_id          = each.value.product_id
  api_name            = each.value.api_name

  depends_on = [azurerm_api_management_product.service]
}

resource "azurerm_api_management_product_policy" "service" {
  for_each = { for s in var.services : s.code => s }

  api_management_name = var.apim.name
  resource_group_name = var.apim.resource_group_name
  product_id          = azurerm_api_management_product.service[each.key].product_id
  xml_content         = each.value.policy_xml != "" ? each.value.policy_xml : file("${path.module}/policies/default-ai-product-policy.xml")
}

resource "azurerm_api_management_subscription" "service" {
  for_each = { for s in var.services : s.code => s }

  api_management_name = var.apim.name
  resource_group_name = var.apim.resource_group_name
  product_id          = azurerm_api_management_product.service[each.key].id
  # Deterministic subscription resource name (Bicep parity: subscriptionName).
  subscription_id = "${each.value.code}-${local.product_postfix}-SUB-01"
  display_name    = "${each.value.code}-${local.product_postfix}-SUB-01"
  state           = "active"
}

# -----------------------------------------------------------------------------
# KEY VAULT SECRETS (optional)
# -----------------------------------------------------------------------------
# Secret names are normalized — Key Vault does not permit underscores.

locals {
  kv_entries = var.use_target_key_vault ? merge([
    for s in var.services : {
      "${s.code}-endpoint" = {
        name  = lower(replace(s.endpoint_secret_name, "_", "-"))
        value = local.service_endpoint_url[s.code]
      }
      "${s.code}-key" = {
        name  = lower(replace(s.api_key_secret_name, "_", "-"))
        value = azurerm_api_management_subscription.service[s.code].primary_key
      }
    }
  ]...) : {}
}

resource "azurerm_key_vault_secret" "contract" {
  for_each = local.kv_entries

  key_vault_id = local.key_vault_id
  name         = each.value.name
  value        = each.value.value
  content_type = "string"
}

# -----------------------------------------------------------------------------
# AZURE AI FOUNDRY CONNECTION (optional — per service)
# -----------------------------------------------------------------------------
# Bicep parity: foundryConnection.bicep. Metadata is assembled conditionally so
# only populated fields are emitted (customHeaders is always present — the
# Foundry portal requires the field to render the connection).

locals {
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
    { customHeaders = length(var.foundry_config.custom_headers) > 0 ? jsonencode(var.foundry_config.custom_headers) : "{}" },
    length(var.foundry_config.auth_config) > 0 ? { authConfig = jsonencode(var.foundry_config.auth_config) } : {}
  )
}

resource "azapi_resource" "foundry_connection" {
  for_each = var.use_target_foundry ? { for s in var.services : s.code => s } : {}

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2026-03-01"
  name      = "${local.foundry_connection_prefix}-${each.key}"
  parent_id = local.foundry_project_id

  schema_validation_enabled = false

  body = {
    properties = {
      category      = var.foundry_config.connection_category
      target        = local.service_endpoint_url[each.key]
      authType      = "ApiKey"
      isSharedToAll = var.foundry_config.is_shared_to_all
      credentials = {
        key = azurerm_api_management_subscription.service[each.key].primary_key
      }
      metadata = local.foundry_metadata
    }
  }

  depends_on = [azurerm_api_management_subscription.service]
}
