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

output "connection_string" {
  description = "Full Redis connection string (host:port,password=...,ssl=true) for APIM service/caches — Bicep parity."
  value       = "${azapi_resource.redis.output.properties.hostName}:${azapi_resource.redis_db.output.properties.port},password=${azapi_resource_action.redis_keys.output.primaryKey},ssl=true"
  sensitive   = true
  # The APIM external cache connects through the private endpoint.
  depends_on = [azurerm_private_endpoint.redis]
}
