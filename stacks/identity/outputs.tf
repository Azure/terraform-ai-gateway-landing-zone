output "display_name" {
  description = "Display name of the gateway app (gateway-config looks it up by this name)."
  value       = module.gateway_app.display_name
}

output "client_id" {
  description = "Client ID of the gateway app (gateway-config entra.client_id)."
  value       = module.gateway_app.client_id
}

output "tenant_id" {
  description = "Entra tenant ID (gateway-config entra.tenant_id)."
  value       = module.gateway_app.tenant_id
}

output "audience" {
  description = "Token audience, api://<client_id> (gateway-config entra.audience)."
  value       = module.gateway_app.audience
}
