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

output "internal_dns_zone_names" {
  description = "Private DNS zones created for the private VIP hostnames (empty when the hub provides them)."
  value       = keys(azurerm_private_dns_zone.internal)
}
