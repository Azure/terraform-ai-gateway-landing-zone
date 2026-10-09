output "diagnostic_setting_names" {
  description = "Workload diagnostic setting names (empty when policy owns diagnostics)."
  value       = [for setting in azapi_resource_action.eventhub_diagnostics : "diag-${var.namespace_name}"]
}

output "namespace_name" {
  description = "Name of the Event Hubs namespace."
  value       = local.namespace_name
}
output "namespace_id" {
  description = "Resource ID of the Event Hubs namespace."
  value       = module.namespace.resource_id
}

output "apim_usage_hub_name" {
  description = "Name of the Event Hub that receives AI usage events from APIM."
  value       = nonsensitive(module.namespace.resource_eventhubs["ai-usage"].name)
  # Consumers (APIM loggers, Logic App) send/receive with managed identities: wait for their roles and the PE.
  depends_on = [module.namespace]
}
output "ai_usage_ingestion_cg" {
  description = "Consumer group used by the AI usage ingestion workflow."
  value       = azurerm_eventhub_consumer_group.ai_usage_ingestion.name
}
output "pii_usage_hub_name" {
  description = "Name of the Event Hub that receives PII usage events from APIM."
  value       = nonsensitive(module.namespace.resource_eventhubs["pii-usage"].name)
  # Consumers (APIM loggers, Logic App) send/receive with managed identities: wait for their roles and the PE.
  depends_on = [module.namespace]
}
output "pii_usage_ingestion_cg" {
  description = "Consumer group used by the PII usage ingestion workflow."
  value       = azurerm_eventhub_consumer_group.pii_usage_ingestion.name
}

output "endpoint_uri" {
  description = "HTTPS endpoint of the Event Hubs namespace."
  value       = "https://${local.namespace_name}.servicebus.windows.net"
}
