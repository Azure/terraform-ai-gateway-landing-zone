terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = ">= 4.79, < 5.0"
      configuration_aliases = [azurerm.loganalytics]
    }
  }
}
