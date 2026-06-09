output "namespace_name" { value = azurerm_eventhub_namespace.citadel.name }
output "namespace_id"   { value = azurerm_eventhub_namespace.citadel.id }

output "apim_usage_hub_name"    { value = azurerm_eventhub.ai_usage.name }
output "ai_usage_ingestion_cg"  { value = azurerm_eventhub_consumer_group.ai_usage_ingestion.name }
output "pii_usage_hub_name"     { value = azurerm_eventhub.pii_usage.name }
output "pii_usage_ingestion_cg" { value = azurerm_eventhub_consumer_group.pii_usage_ingestion.name }

output "endpoint_uri" {
  value = "https://${azurerm_eventhub_namespace.citadel.name}.servicebus.windows.net"
}
