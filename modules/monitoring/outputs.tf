output "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace (created or existing)."
  value       = local.log_analytics_id
}

output "log_analytics_workspace_id" {
  description = "Workspace (customer) ID of the Log Analytics workspace."
  value       = local.byo_workspace ? var.existing_log_analytics_workspace.workspace_id : azurerm_log_analytics_workspace.citadel[0].workspace_id
}

output "app_insights_id" {
  description = "Resource ID of the APIM Application Insights component."
  value       = azurerm_application_insights.apim.id
}

output "app_insights_name" {
  description = "Name of the APIM Application Insights component."
  value       = azurerm_application_insights.apim.name
}

output "app_insights_instrumentation_key" {
  description = "Instrumentation key of the APIM Application Insights component."
  value       = azurerm_application_insights.apim.instrumentation_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "Connection string of the APIM Application Insights component."
  value       = azurerm_application_insights.apim.connection_string
  sensitive   = true
}

output "logic_app_insights_connection_string" {
  description = "Connection string of the Logic App Application Insights component."
  value       = azurerm_application_insights.logic_app.connection_string
  sensitive   = true
}

output "foundry_app_insights_id" {
  description = "Resource ID of the Foundry Application Insights component."
  value       = azurerm_application_insights.foundry.id
}

output "foundry_app_insights_name" {
  description = "Name of the Foundry Application Insights component."
  value       = azurerm_application_insights.foundry.name
}

output "foundry_app_insights_instrumentation_key" {
  description = "Instrumentation key of the Foundry Application Insights component."
  value       = azurerm_application_insights.foundry.instrumentation_key
  sensitive   = true
}

output "foundry_app_insights_connection_string" {
  description = "Connection string of the Foundry Application Insights component."
  value       = azurerm_application_insights.foundry.connection_string
  sensitive   = true
}
