# Resource providers are registered once by stacks/bootstrap; the pipeline
# identities are scoped to resource groups and can't register them.
provider "azurerm" {
  subscription_id                 = var.subscription_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}
