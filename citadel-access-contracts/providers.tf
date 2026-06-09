# =============================================================================
# Citadel Access Contracts — Providers
#
# The provider subscription is pinned to the APIM subscription (apim.subscription_id).
# Key Vault and Foundry are referenced by fully-qualified resource IDs, so they may
# live in different subscriptions/resource groups (cross-subscription writes require
# the authenticated principal to have access in those subscriptions).
# =============================================================================

provider "azurerm" {
  features {}
  subscription_id = var.apim.subscription_id
}

provider "azapi" {}
