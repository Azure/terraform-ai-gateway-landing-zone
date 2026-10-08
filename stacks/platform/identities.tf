# The workload resource group is created by stacks/bootstrap.
data "azurerm_resource_group" "workload" {
  name = local.names.resource_group
}

data "azurerm_client_config" "current" {}

locals {
  resource_group_name = data.azurerm_resource_group.workload.name
  resource_group_id   = data.azurerm_resource_group.workload.id
}

# User-assigned identities (Bicep parity):
#   apim   APIM -> Foundry, Content Safety, Language, Event Hub logger, Key Vault.
#   usage  Logic App -> Cosmos DB, storage, Event Hub.
module "identity" {
  source   = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version  = "0.5.3"
  for_each = { apim = local.names.uami_apim, usage = local.names.uami_usage }

  name                = each.value
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  enable_telemetry    = var.enable_telemetry
}
