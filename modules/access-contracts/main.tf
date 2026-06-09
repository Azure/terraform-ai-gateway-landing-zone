# =============================================================================
# MODULE: access-contracts
#
# Bicep parity: citadel-access-contracts/main.bicep + submodules
#   apimOnboardService.bicep + kvSecrets.bicep + foundryConnection.bicep
#
# For each use-case service, this module:
#   1. Creates an APIM product (<code>-<bu>-<usecase>-<env>)
#   2. Attaches one or more APIs to that product
#   3. Attaches an inbound policy to the product
#   4. Creates a named subscription (<code>-<bu>-<usecase>-<env>-SUB-01)
#   5. Optionally writes endpoint + API key secrets to Key Vault
#   6. Optionally creates a Foundry-project → APIM connection
# =============================================================================

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi   = { source = "azure/azapi",       version = "~> 2.0" }
  }
}

locals {
  product_postfix = "${var.use_case.business_unit}-${var.use_case.use_case_name}-${var.use_case.environment}"

  # Flatten services × api_names for product_api
  product_apis = merge([
    for s in var.services : {
      for api_name in lookup(var.api_name_mapping, s.code, []) :
      "${s.code}-${api_name}" => {
        product_id = "${s.code}-${local.product_postfix}"
        api_name   = api_name
      }
    }
  ]...)
}

# -----------------------------------------------------------------------------
# PRODUCTS
# -----------------------------------------------------------------------------

resource "azurerm_api_management_product" "service" {
  for_each = { for s in var.services : s.code => s }

  api_management_name = var.apim_name
  resource_group_name = var.apim_resource_group_name
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

  api_management_name = var.apim_name
  resource_group_name = var.apim_resource_group_name
  product_id          = each.value.product_id
  api_name            = each.value.api_name

  depends_on = [azurerm_api_management_product.service]
}

resource "azurerm_api_management_product_policy" "service" {
  for_each = { for s in var.services : s.code => s }

  api_management_name = var.apim_name
  resource_group_name = var.apim_resource_group_name
  product_id          = azurerm_api_management_product.service[each.key].product_id
  xml_content         = each.value.policy_xml != "" ? each.value.policy_xml : file("${path.module}/policies/default-ai-product-policy.xml")
}

resource "azurerm_api_management_subscription" "service" {
  for_each = { for s in var.services : s.code => s }

  api_management_name = var.apim_name
  resource_group_name = var.apim_resource_group_name
  product_id          = azurerm_api_management_product.service[each.key].id
  display_name        = "${each.value.code}-${local.product_postfix}-SUB-01"
  state               = "active"
}

# -----------------------------------------------------------------------------
# KEY VAULT SECRETS (optional)
# -----------------------------------------------------------------------------

locals {
  kv_entries = var.use_target_key_vault ? merge([
    for s in var.services : {
      "${s.code}-endpoint" = {
        name  = lower(replace(s.endpoint_secret_name, "_", "-"))
        value = "${var.apim_gateway_url}/${lookup(var.api_name_mapping, s.code, [""])[0]}"
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

  key_vault_id = var.key_vault_id
  name         = each.value.name
  value        = each.value.value
}

# -----------------------------------------------------------------------------
# FOUNDRY CONNECTION (optional — per service)
# -----------------------------------------------------------------------------

resource "azapi_resource" "foundry_connection" {
  for_each = var.use_target_foundry ? { for s in var.services : s.code => s } : {}

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2026-03-01"
  name      = "Hub-${var.foundry_connection_name_prefix != "" ? var.foundry_connection_name_prefix : local.product_postfix}-${each.key}"
  parent_id = var.foundry_project_id

  schema_validation_enabled = false

  body = {
    properties = {
      category      = var.foundry_connection_category
      target        = "${var.apim_gateway_url}/${lookup(var.api_name_mapping, each.key, [""])[0]}"
      authType      = "ApiKey"
      isSharedToAll = var.foundry_is_shared_to_all
      credentials = {
        key = azurerm_api_management_subscription.service[each.key].primary_key
      }
      metadata = merge(
        { deploymentInPath = var.foundry_deployment_in_path },
        var.foundry_inference_api_version != "" ? { inferenceAPIVersion = var.foundry_inference_api_version } : {},
        var.foundry_deployment_api_version != "" ? { deploymentAPIVersion = var.foundry_deployment_api_version } : {},
        length(var.foundry_static_models) > 0 ? { models = jsonencode(var.foundry_static_models) } : {},
        # Always emit customHeaders ('{}' when empty) — the Foundry portal
        # requires the field to render the connection.
        { customHeaders = length(var.foundry_custom_headers) > 0 ? jsonencode(var.foundry_custom_headers) : "{}" }
      )
    }
  }

  depends_on = [azurerm_api_management_subscription.service]
}
