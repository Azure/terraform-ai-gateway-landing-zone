output "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace (created or existing)."
  value       = local.log_analytics_id
}

output "log_analytics_workspace_id" {
  description = "Workspace (customer) ID of the Log Analytics workspace."
  value       = local.byo_workspace ? var.existing_log_analytics_workspace.workspace_id : nonsensitive(module.log_analytics[0].resource.workspace_id)
}

output "app_insights_id" {
  description = "Resource ID of the APIM Application Insights component."
  value       = module.app_insights["apim"].resource_id
}

output "app_insights_name" {
  description = "Name of the APIM Application Insights component."
  value       = module.app_insights["apim"].name
}

output "app_insights_instrumentation_key" {
  description = "Instrumentation key of the APIM Application Insights component."
  value       = module.app_insights["apim"].instrumentation_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "Connection string of the APIM Application Insights component."
  value       = module.app_insights["apim"].connection_string
  sensitive   = true
}

output "logic_app_insights_connection_string" {
  description = "Connection string of the Logic App Application Insights component."
  value       = module.app_insights["logic_app"].connection_string
  sensitive   = true
}

output "foundry_app_insights_id" {
  description = "Resource ID of the Foundry Application Insights component (null without Foundry)."
  value       = try(module.app_insights["foundry"].resource_id, null)
}

output "foundry_app_insights_name" {
  description = "Name of the Foundry Application Insights component."
  value       = try(module.app_insights["foundry"].name, null)
}

output "foundry_app_insights_instrumentation_key" {
  description = "Instrumentation key of the Foundry Application Insights component."
  value       = try(module.app_insights["foundry"].instrumentation_key, null)
  sensitive   = true
}

output "foundry_app_insights_connection_string" {
  description = "Connection string of the Foundry Application Insights component."
  value       = try(module.app_insights["foundry"].connection_string, null)
  sensitive   = true
}
