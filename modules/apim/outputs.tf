output "apim_name" {
  description = "Name of the API Management service."
  value       = local.apim.name
}
output "apim_id" {
  description = "Resource ID of the API Management service."
  value       = local.apim.id
}
output "gateway_url" {
  description = "Gateway URL of the API Management service."
  value       = local.apim.gateway_url
}
output "portal_url" {
  description = "Developer portal URL (classic SKUs)."
  value       = local.apim.portal_url
}
output "management_api_url" {
  description = "Management API URL of the API Management service."
  value       = local.apim.management_api_url
}
output "private_ip_addresses" {
  description = "Private IP addresses of the APIM gateway (VNet-injected SKUs)."
  value       = local.apim.private_ip_addresses
}

# Primary key of the dedicated subscription used for Foundry → APIM connections.
# Empty if the foundry connection subscription is not enabled.
output "foundry_connection_primary_key" {
  description = "Primary key of the APIM subscription used by the Foundry connection (sensitive; internal wiring only)."
  value       = try(azurerm_api_management_subscription.foundry_connection[0].primary_key, "")
  sensitive   = true
}


output "named_value_ids" {
  description = "IDs of the named values that policy fragments reference (fragments must be created after them)."
  value = concat(
    azurerm_api_management_named_value.uami_client_id[*].id,
    azurerm_api_management_named_value.entra_tenant_id[*].id,
    azurerm_api_management_named_value.entra_client_id[*].id,
    azurerm_api_management_named_value.entra_audience[*].id,
    azurerm_api_management_named_value.entra_auth_flag[*].id,
    azurerm_api_management_named_value.pii_service_url[*].id,
    azurerm_api_management_named_value.content_safety_url[*].id,
    azurerm_api_management_named_value.jwt_tenant_id[*].id,
    azurerm_api_management_named_value.jwt_app_registration_id[*].id,
    azurerm_api_management_named_value.jwt_issuer[*].id,
    azurerm_api_management_named_value.jwt_openid_config_url[*].id,
  )
}

output "ms_learn_mcp_backend_id" {
  description = "Resource ID of the MS Learn MCP backend (null when the MCP samples are off)."
  value       = one(azapi_resource.ms_learn_mcp_backend[*].id)
}
