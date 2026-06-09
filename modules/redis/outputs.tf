output "redis_id" {
  value = azapi_resource.redis.id
}

output "host_name" {
  value = azapi_resource.redis.output.properties.hostName
}

output "port" {
  value = azapi_resource.redis_db.output.properties.port
}

output "connection_string" {
  description = "Full Redis connection string (host:port,password=...,ssl=true) for APIM service/caches — Bicep parity."
  value       = "${azapi_resource.redis.output.properties.hostName}:${azapi_resource.redis_db.output.properties.port},password=${azapi_resource_action.redis_keys.output.primaryKey},ssl=true"
  sensitive   = true
}
