output "diagnostic_setting_names" {
  description = "Workload diagnostic setting names (empty when policy owns diagnostics)."
  value       = [for setting in azurerm_monitor_diagnostic_setting.cosmos : setting.name]
}

output "endpoint" {
  description = "Cosmos DB account endpoint."
  value       = module.cosmos.endpoint
}
output "account_id" {
  description = "Resource ID of the Cosmos DB account."
  value       = module.cosmos.resource_id
}
output "account_name" {
  description = "Name of the Cosmos DB account."
  value       = module.cosmos.name
}
output "database_name" {
  description = "Name of the usage database."
  value       = local.database_name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, module.cosmos]
}

# Container outputs (Bicep parity)
output "usage_container_name" {
  description = "Name of the AI usage container."
  value       = local.containers.usage.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, module.cosmos]
}
output "config_container_name" {
  description = "Name of the configuration container."
  value       = local.containers.config.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, module.cosmos]
}
output "pii_container_name" {
  description = "Name of the PII usage container."
  value       = local.containers.pii.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, module.cosmos]
}
output "llm_usage_container_name" {
  description = "Name of the LLM usage container."
  value       = local.containers.llm_usage.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, module.cosmos]
}
output "model_pricing_container_name" {
  description = "Name of the model pricing container."
  value       = local.containers.model_pricing.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, module.cosmos]
}
