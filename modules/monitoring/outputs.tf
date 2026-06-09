output "log_analytics_id" {
  value = var.use_existing_log_analytics ? var.existing_log_analytics_id : azurerm_log_analytics_workspace.citadel[0].id
}

output "log_analytics_workspace_id" {
  value = var.use_existing_log_analytics ? data.azurerm_log_analytics_workspace.existing[0].workspace_id : azurerm_log_analytics_workspace.citadel[0].workspace_id
}

output "app_insights_id" {
  value = azurerm_application_insights.apim.id
}

output "app_insights_name" {
  value = azurerm_application_insights.apim.name
}

output "app_insights_instrumentation_key" {
  value     = azurerm_application_insights.apim.instrumentation_key
  sensitive = true
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.apim.connection_string
  sensitive = true
}

output "logic_app_insights_connection_string" {
  value     = azurerm_application_insights.logic_app.connection_string
  sensitive = true
}

output "foundry_app_insights_id" {
  value = azurerm_application_insights.foundry.id
}

output "foundry_app_insights_name" {
  value = azurerm_application_insights.foundry.name
}

output "foundry_app_insights_instrumentation_key" {
  value     = azurerm_application_insights.foundry.instrumentation_key
  sensitive = true
}

output "foundry_app_insights_connection_string" {
  value     = azurerm_application_insights.foundry.connection_string
  sensitive = true
}
