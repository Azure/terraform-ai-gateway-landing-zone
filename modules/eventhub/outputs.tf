output "namespace_name" {
  description = "Name of the Event Hubs namespace."
  value       = azurerm_eventhub_namespace.citadel.name
}
output "namespace_id" {
  description = "Resource ID of the Event Hubs namespace."
  value       = azurerm_eventhub_namespace.citadel.id
}

output "apim_usage_hub_name" {
  description = "Name of the Event Hub that receives AI usage events from APIM."
  value       = azurerm_eventhub.ai_usage.name
}
output "ai_usage_ingestion_cg" {
  description = "Consumer group used by the AI usage ingestion workflow."
  value       = azurerm_eventhub_consumer_group.ai_usage_ingestion.name
}
output "pii_usage_hub_name" {
  description = "Name of the Event Hub that receives PII usage events from APIM."
  value       = azurerm_eventhub.pii_usage.name
}
output "pii_usage_ingestion_cg" {
  description = "Consumer group used by the PII usage ingestion workflow."
  value       = azurerm_eventhub_consumer_group.pii_usage_ingestion.name
}

output "endpoint_uri" {
  description = "HTTPS endpoint of the Event Hubs namespace."
  value       = "https://${azurerm_eventhub_namespace.citadel.name}.servicebus.windows.net"
}
