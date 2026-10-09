output "diagnostic_setting_names" {
  description = "Workload Azure Monitor diagnostic setting names (empty when policy owns diagnostics)."
  value       = [for setting in azapi_resource_action.apim_diagnostics : "diag-${var.api_management_name}"]
}

output "app_insights_logger_id" {
  description = "Resource ID of the Application Insights logger (appinsights-logger)."
  value       = azurerm_api_management_logger.app_insights.id
}

output "azure_monitor_logger_id" {
  description = "Resource ID of the Azure Monitor logger (azuremonitor)."
  value       = "${var.api_management_id}/loggers/azuremonitor"
}

output "dependency_ids" {
  description = "IDs to depend on before creating API diagnostics that use the Azure Monitor logger."
  value       = [azapi_resource_action.azure_monitor_logger.id]
}

output "logger_names" {
  description = "Names of the loggers this module creates (contract for API-level diagnostics)."
  value = {
    app_insights  = azurerm_api_management_logger.app_insights.name
    azure_monitor = "azuremonitor"
    eventhub      = azurerm_api_management_logger.eventhub.name
    pii_eventhub  = one(azurerm_api_management_logger.pii_eventhub[*].name)
  }
}
