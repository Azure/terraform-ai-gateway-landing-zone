# Bootstrap runs once per environment as a human with Owner (task bootstrap).
# It is the only stack that registers resource providers: the pipeline
# identities are scoped to resource groups and can't register them.
provider "azurerm" {
  subscription_id                 = var.subscription_id
  storage_use_azuread             = true
  resource_provider_registrations = "core"
  resource_providers_to_register  = var.resource_providers

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "azuread" {}
