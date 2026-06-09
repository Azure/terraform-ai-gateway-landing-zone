output "endpoint"     { value = azurerm_cosmosdb_account.citadel.endpoint }
output "account_id"   { value = azurerm_cosmosdb_account.citadel.id }
output "account_name" { value = azurerm_cosmosdb_account.citadel.name }
output "database_name" { value = azurerm_cosmosdb_sql_database.usage.name }
output "connection_string" {
  value     = azurerm_cosmosdb_account.citadel.primary_sql_connection_string
  sensitive = true
}

# Container outputs (Bicep parity)
output "usage_container_name"                   { value = azurerm_cosmosdb_sql_container.usage.name }
output "config_container_name"                  { value = azurerm_cosmosdb_sql_container.config.name }
output "pii_container_name"                     { value = azurerm_cosmosdb_sql_container.pii.name }
output "llm_usage_container_name"               { value = azurerm_cosmosdb_sql_container.llm_usage.name }
output "model_pricing_container_name"           { value = azurerm_cosmosdb_sql_container.model_pricing.name }
