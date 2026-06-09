output "apim_name"    { value = azurerm_api_management.citadel.name }
output "apim_id"      { value = azurerm_api_management.citadel.id }
output "gateway_url"  { value = azurerm_api_management.citadel.gateway_url }
output "portal_url"   { value = azurerm_api_management.citadel.portal_url }
output "management_api_url" { value = azurerm_api_management.citadel.management_api_url }
output "private_ip_addresses" { value = azurerm_api_management.citadel.private_ip_addresses }

# Primary key of the dedicated subscription used for Foundry → APIM connections.
# Empty if the foundry connection subscription is not enabled.
output "foundry_connection_primary_key" {
  value     = try(azurerm_api_management_subscription.foundry_connection[0].primary_key, "")
  sensitive = true
}
