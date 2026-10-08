provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

# Finds the gateway Entra app by name (Application.Read.All).
provider "azuread" {}
