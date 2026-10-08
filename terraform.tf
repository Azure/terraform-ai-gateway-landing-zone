# =============================================================================
# AI Citadel Governance Hub - Terraform Version Constraints
# =============================================================================

terraform {
  required_version = "~> 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.12"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    # Azure Verified Modules report usage telemetry through modtm
    # (disabled per module with enable_telemetry = false).
    modtm = {
      source  = "azure/modtm"
      version = "~> 0.3"
    }
  }

  # Uncomment for remote state (recommended for team environments)
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "stterraformstate"
  #   container_name       = "citadel-tfstate"
  #   key                  = "citadel.terraform.tfstate"
  # }
}
