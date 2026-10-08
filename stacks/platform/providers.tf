# Resource providers are registered once by stacks/bootstrap; the pipeline
# identities are scoped to resource groups and can't register them.
provider "azurerm" {
  subscription_id                 = var.subscription_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = var.purge_soft_delete_on_destroy
      recover_soft_deleted_key_vaults = true
    }
    api_management {
      purge_soft_delete_on_destroy = var.purge_soft_delete_on_destroy
      recover_soft_deleted         = false
    }
    cognitive_account {
      purge_soft_delete_on_destroy = var.purge_soft_delete_on_destroy
    }
  }
}

# BYO Log Analytics workspace in another subscription (monitoring.log_analytics_subscription_id).
provider "azurerm" {
  alias = "loganalytics"
  # The BYO workspace's subscription: explicit, else taken from its resource ID.
  subscription_id                 = coalesce(var.monitoring.log_analytics_subscription_id, try(split("/", var.monitoring.log_analytics_workspace_id)[2], null), var.subscription_id)
  resource_provider_registrations = "none"

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}
