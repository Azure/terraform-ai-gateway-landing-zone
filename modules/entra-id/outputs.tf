output "client_id" {
  description = "Entra ID app registration client ID (used by APIM JWT-AppRegistrationId named value)."
  value       = azuread_application.gateway.client_id
}

output "object_id" {
  description = "Application object ID."
  value       = azuread_application.gateway.object_id
}

output "service_principal_id" {
  description = "Service principal object ID."
  value       = azuread_service_principal.gateway.object_id
}

output "tenant_id" {
  description = "Entra ID tenant ID."
  value       = data.azuread_client_config.current.tenant_id
}

output "display_name" {
  description = "App registration display name."
  value       = azuread_application.gateway.display_name
}

output "audience" {
  description = "App ID URI (audience for JWT tokens)."
  value       = azuread_application_identifier_uri.gateway.identifier_uri
}

output "client_secret" {
  description = "Generated client secret value."
  value       = azuread_application_password.gateway.value
  sensitive   = true
}

output "key_vault_secret_id" {
  description = "Key Vault secret ID of the stored client secret."
  value       = azurerm_key_vault_secret.client_secret.id
}
