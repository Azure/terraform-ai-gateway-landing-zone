# Everything below is owned by stacks/platform or stacks/gateway-config and
# found by its deterministic name (modules/naming): no remote state.

data "azurerm_api_management" "this" {
  name                = local.names.apim
  resource_group_name = local.names.resource_group
}

data "azurerm_user_assigned_identity" "apim" {
  name                = local.names.uami_apim
  resource_group_name = local.names.resource_group
}

# gateway-config's entra-auth flag: with Entra auth the LLM APIs take a JWT
# instead of a subscription key.
data "azapi_resource" "entra_auth" {
  type      = "Microsoft.ApiManagement/service/namedValues@2024-05-01"
  name      = "entra-auth"
  parent_id = data.azurerm_api_management.this.id

  response_export_values = ["properties.value"]
}

# Shared fragments the LLM policies reference (owned by gateway-config).
data "azapi_resource_list" "fragments" {
  type                   = "Microsoft.ApiManagement/service/policyFragments@2024-05-01"
  parent_id              = data.azurerm_api_management.this.id
  response_export_values = { names = "value[].name" }
}

# Foundry accounts of stacks/platform and their model deployments.
data "azapi_resource_list" "foundry_accounts" {
  count                  = var.foundry_backends.enabled && var.foundry_backends.account_names == null ? 1 : 0
  type                   = "Microsoft.CognitiveServices/accounts@2025-06-01"
  parent_id              = "/subscriptions/${var.subscription_id}/resourceGroups/${local.names.resource_group}"
  response_export_values = { accounts = "value[].{name: name, location: location, endpoint: properties.endpoint}" }
}

data "azurerm_cognitive_account" "foundry" {
  for_each            = toset(local.foundry_account_names)
  name                = each.value
  resource_group_name = local.names.resource_group
}

data "azapi_resource_list" "deployments" {
  for_each               = toset(local.foundry_account_names)
  type                   = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  parent_id              = data.azurerm_cognitive_account.foundry[each.value].id
  response_export_values = { deployments = "value[].{name: name, sku: sku.name, capacity: sku.capacity, format: properties.model.format, version: properties.model.version}" }
}

locals {
  apim_id             = data.azurerm_api_management.this.id
  apim_name           = data.azurerm_api_management.this.name
  resource_group_name = data.azurerm_api_management.this.resource_group_name

  entra_auth_enabled = try(lower(data.azapi_resource.entra_auth.output.properties.value), "false") == "true"

  # Logger names are a contract with platform's apim-telemetry module.
  app_insights_logger_id  = "${local.apim_id}/loggers/appinsights-logger"
  azure_monitor_logger_id = "${local.apim_id}/loggers/azuremonitor"

  foundry_prefix = "aif-${module.naming.base}-"
  foundry_account_names = !var.foundry_backends.enabled ? [] : (
    var.foundry_backends.account_names != null ? var.foundry_backends.account_names : sort([
      for a in try(data.azapi_resource_list.foundry_accounts[0].output.accounts, []) : a.name if startswith(a.name, local.foundry_prefix)
    ])
  )
}

check "shared_fragments_exist" {
  assert {
    condition     = length(setsubtract(local.required_shared_fragments, try(data.azapi_resource_list.fragments.output.names, []))) == 0
    error_message = "Missing shared fragments (apply stacks/gateway-config first): ${join(", ", setsubtract(local.required_shared_fragments, try(data.azapi_resource_list.fragments.output.names, [])))}."
  }
}
