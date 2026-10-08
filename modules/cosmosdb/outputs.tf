output "endpoint" {
  description = "Cosmos DB account endpoint."
  value       = azurerm_cosmosdb_account.citadel.endpoint
}
output "account_id" {
  description = "Resource ID of the Cosmos DB account."
  value       = azurerm_cosmosdb_account.citadel.id
}
output "account_name" {
  description = "Name of the Cosmos DB account."
  value       = azurerm_cosmosdb_account.citadel.name
}
output "database_name" {
  description = "Name of the usage database."
  value       = azurerm_cosmosdb_sql_database.usage.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, azurerm_private_endpoint.cosmos]
}

# Container outputs (Bicep parity)
output "usage_container_name" {
  description = "Name of the AI usage container."
  value       = azurerm_cosmosdb_sql_container.usage.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, azurerm_private_endpoint.cosmos]
}
output "config_container_name" {
  description = "Name of the configuration container."
  value       = azurerm_cosmosdb_sql_container.config.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, azurerm_private_endpoint.cosmos]
}
output "pii_container_name" {
  description = "Name of the PII usage container."
  value       = azurerm_cosmosdb_sql_container.pii.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, azurerm_private_endpoint.cosmos]
}
output "llm_usage_container_name" {
  description = "Name of the LLM usage container."
  value       = azurerm_cosmosdb_sql_container.llm_usage.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, azurerm_private_endpoint.cosmos]
}
output "model_pricing_container_name" {
  description = "Name of the model pricing container."
  value       = azurerm_cosmosdb_sql_container.model_pricing.name
  # Consumers (Logic App) use the data plane with a managed identity: wait for its role and the PE.
  depends_on = [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor, azurerm_private_endpoint.cosmos]
}
