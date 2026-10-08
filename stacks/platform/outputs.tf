# IDs, names and URLs only (no keys). Downstream stacks find these resources
# by name (modules/naming); the outputs are for people and checks.

output "resource_group_name" {
  description = "Workload resource group."
  value       = local.resource_group_name
}

output "apim_name" {
  description = "API Management service name."
  value       = module.apim.apim_name
}

output "apim_gateway_url" {
  description = "API Management gateway URL."
  value       = module.apim.gateway_url
}

output "apim_private_ip_addresses" {
  description = "Private IPs of the APIM gateway (private VIP modes)."
  value       = module.apim.private_ip_addresses
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = module.security.key_vault_name
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.security.key_vault_uri
}

output "foundry_account_names" {
  description = "Foundry (AI Services) account names, one per instance."
  value       = module.foundry.foundry_names
}

output "foundry_endpoints" {
  description = "Foundry account endpoints, one per instance."
  value       = module.foundry.foundry_endpoints
}

output "foundry_project_names" {
  description = "Default Foundry project per instance."
  value       = module.foundry.project_names
}

output "apim_identity_client_id" {
  description = "Client ID of the APIM user-assigned identity."
  value       = module.identity["apim"].client_id
}

output "usage_identity_client_id" {
  description = "Client ID of the usage-pipeline user-assigned identity."
  value       = module.identity["usage"].client_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = module.monitoring.log_analytics_id
}

output "cosmos_db_endpoint" {
  description = "Cosmos DB endpoint (usage records)."
  value       = module.cosmosdb.endpoint
}

output "eventhub_namespace" {
  description = "Event Hub namespace (APIM usage events)."
  value       = module.eventhub.namespace_name
}

output "logic_app_name" {
  description = "Usage ingestion Logic App."
  value       = module.logic_app.logic_app_name
}

output "logic_app_hosting" {
  description = "Usage ingestion hosting details."
  value       = module.logic_app.hosting
}

output "apim_logger_names" {
  description = "APIM logger names (contract for API diagnostics in gateway-config and llm-backend-onboarding)."
  value       = module.apim_telemetry.logger_names
}
