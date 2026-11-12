output "redis_id" {
  description = "Resource ID of the Azure Managed Redis cluster."
  value       = azapi_resource.redis.id
}

output "host_name" {
  description = "Host name of the Azure Managed Redis cluster."
  value       = azapi_resource.redis.output.properties.hostName
}

output "port" {
  description = "Port of the Redis database."
  value       = azapi_resource.redis_db.output.properties.port
}

output "connection_string_secret_id" {
  description = "Versionless ID of the Key Vault secret with the connection string (host:port,password=<key>,ssl=true) for the APIM external cache."
  value       = azurerm_key_vault_secret.connection_string.versionless_id
  # The APIM external cache connects through the private endpoint.
  depends_on = [azurerm_private_endpoint.redis, azurerm_private_endpoint.redis_policy_dns]
}
