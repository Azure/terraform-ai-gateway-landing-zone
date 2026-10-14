output "diagnostic_setting_names" {
  description = "Workload Azure Monitor diagnostic setting names (empty when policy owns diagnostics)."
  value       = [for setting in azapi_resource_action.apim_diagnostics : "diag-${var.api_management_name}"]
}

output "app_insights_logger_id" {
  description = "Resource ID of the Application Insights logger (appinsights-logger)."
  value       = azapi_resource_action.app_insights_logger.resource_id
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
    app_insights  = "appinsights-logger"
    azure_monitor = "azuremonitor"
    eventhub      = azapi_resource.eventhub_logger["usage-eventhub-logger"].name
    pii_eventhub  = try(azapi_resource.eventhub_logger["pii-usage-eventhub-logger"].name, null)
  }
}

output "logger_credential_named_values" {
  description = "Key Vault-backed named values holding the logger credentials (name => Key Vault secret versionless ID); empty when credentials_in_key_vault = false."
  value       = { for k, nv in azurerm_api_management_named_value.logger_credential : k => azurerm_key_vault_secret.logger_credential[k].versionless_id }
}

output "logger_identity_client_id" {
  description = "Identity client ID the loggers are configured with: a {{named value}} reference with credentials_in_key_vault, else the client ID."
  value       = local.identity_client_id_ref
}
