output "apim_name" {
  description = "Name of the API Management service."
  value       = azurerm_api_management.citadel.name
}
output "apim_id" {
  description = "Resource ID of the API Management service."
  value       = azurerm_api_management.citadel.id
}
output "gateway_url" {
  description = "Gateway URL of the API Management service."
  value       = azurerm_api_management.citadel.gateway_url
}
output "portal_url" {
  description = "Developer portal URL (classic SKUs)."
  value       = azurerm_api_management.citadel.portal_url
}
output "management_api_url" {
  description = "Management API URL of the API Management service."
  value       = azurerm_api_management.citadel.management_api_url
}
output "private_ip_addresses" {
  description = "Private IP addresses of the APIM gateway (VNet-injected SKUs)."
  value       = azurerm_api_management.citadel.private_ip_addresses
}

# Primary key of the dedicated subscription used for Foundry → APIM connections.
# Empty if the foundry connection subscription is not enabled.
output "foundry_connection_primary_key" {
  description = "Primary key of the APIM subscription used by the Foundry connection (sensitive; internal wiring only)."
  value       = try(azurerm_api_management_subscription.foundry_connection[0].primary_key, "")
  sensitive   = true
}

output "llm_backend_ids" {
  description = "Map of LLM backend ID => APIM backend resource ID."
  value       = { for k, b in azapi_resource.llm_backend : k => b.id }
}

output "llm_backend_pool_ids" {
  description = "Map of backend pool name => APIM backend resource ID (only models served by 2+ backends get a pool)."
  value       = { for k, p in azapi_resource.llm_backend_pool : k => p.id }
}
