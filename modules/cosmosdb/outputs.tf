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
}

# Container outputs (Bicep parity)
output "usage_container_name" {
  description = "Name of the AI usage container."
  value       = azurerm_cosmosdb_sql_container.usage.name
}
output "config_container_name" {
  description = "Name of the configuration container."
  value       = azurerm_cosmosdb_sql_container.config.name
}
output "pii_container_name" {
  description = "Name of the PII usage container."
  value       = azurerm_cosmosdb_sql_container.pii.name
}
output "llm_usage_container_name" {
  description = "Name of the LLM usage container."
  value       = azurerm_cosmosdb_sql_container.llm_usage.name
}
output "model_pricing_container_name" {
  description = "Name of the model pricing container."
  value       = azurerm_cosmosdb_sql_container.model_pricing.name
}
