# Monitoring module: declares the aliased `azurerm.loganalytics` provider
# passed from the root so the existing LAW data source can live in a
# different subscription (Bicep parity: existingLogAnalyticsSubscriptionId).
terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 4.0"
      configuration_aliases = [azurerm.loganalytics]
    }
  }
}
