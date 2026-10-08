# APIM, Key Vault and the Foundry project are owned by stacks/platform and
# found by name; the APIs by stacks/gateway-config / llm-backend-onboarding.

data "azurerm_api_management" "this" {
  name                = local.names.apim
  resource_group_name = local.names.resource_group
}

data "azurerm_api_management_api" "first" {
  for_each = { for s in var.services : s.code => s }

  name                = lookup(var.api_name_mapping, each.key, [""])[0]
  api_management_name = data.azurerm_api_management.this.name
  resource_group_name = data.azurerm_api_management.this.resource_group_name
  revision            = "1"
}

data "azurerm_key_vault" "platform" {
  count               = var.key_vault.enabled && var.key_vault.id == null ? 1 : 0
  name                = local.names.key_vault
  resource_group_name = local.names.resource_group
}

locals {
  key_vault_id = !var.key_vault.enabled ? null : coalesce(var.key_vault.id, try(data.azurerm_key_vault.platform[0].id, null))
  foundry_project_id = !var.foundry.enabled ? null : coalesce(
    var.foundry.project_id,
    "/subscriptions/${var.subscription_id}/resourceGroups/${local.names.resource_group}/providers/Microsoft.CognitiveServices/accounts/${module.naming.foundry_account_names[0]}/projects/${var.foundry.project_name}",
  )
}

module "contract" {
  source = "../../modules/access-contract"

  api_management = {
    id                  = data.azurerm_api_management.this.id
    name                = data.azurerm_api_management.this.name
    resource_group_name = data.azurerm_api_management.this.resource_group_name
    gateway_url         = data.azurerm_api_management.this.gateway_url
  }

  use_case         = var.use_case
  api_name_mapping = var.api_name_mapping
  api_paths        = { for k, a in data.azurerm_api_management_api.first : k => a.path }
  services         = var.services
  product_terms    = var.product_terms

  key_vault_id         = local.key_vault_id
  secret_rotation_days = var.secret_rotation_days
  secret_validity_days = var.secret_validity_days

  foundry_project_id = local.foundry_project_id
  foundry_config     = var.foundry_config
}
