# =============================================================================
# AI Citadel Governance Hub - Provider Configuration
# =============================================================================

provider "azurerm" {
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

  storage_use_azuread = true

  subscription_id = var.subscription_id
}

# Aliased provider for a BYO Log Analytics Workspace that lives in a different
# subscription than the deployment (Bicep parity: existingLogAnalyticsSubscriptionId).
# When no override is supplied, it points at the deployment subscription so the
# same code path works for same-subscription BYO too.
provider "azurerm" {
  alias = "loganalytics"

  features {}

  subscription_id = coalesce(
    var.existing_log_analytics_subscription_id,
    var.subscription_id
  )
}

provider "azapi" {}

provider "azuread" {}

provider "random" {}
