terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.79, < 5.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.9, < 3.0"
    }
  }
}
