# Keys are never output (nor stored in state). Read one on demand with:
#   az rest --method post --url "<subscription id>/listSecrets?api-version=2024-05-01"

output "products" {
  description = "Service code => product ID."
  value       = { for k, p in azurerm_api_management_product.service : k => p.product_id }
}

output "subscriptions" {
  description = "Service code => subscription resource ID."
  value       = { for k, s in azapi_resource.subscription : k => s.id }
}

output "endpoints" {
  description = "Service code => gateway endpoint URL."
  value       = local.endpoint_url
}

output "key_vault_secret_names" {
  description = "Service code => { endpoint, key } Key Vault secret names (empty without a Key Vault)."
  value       = { for k, s in azurerm_key_vault_secret.key : k => { endpoint = azurerm_key_vault_secret.endpoint[k].name, key = s.name } }
}

output "foundry_connection_auth" {
  description = "Foundry connection authentication: auth_type, and the token audience the product policy must validate (empty for ApiKey)."
  value = {
    auth_type                 = var.foundry_config.auth_type
    managed_identity_audience = var.foundry_config.auth_type == "ProjectManagedIdentity" ? var.foundry_config.managed_identity_audience : ""
  }
}

output "foundry_connections" {
  description = "Service code => Foundry connection name (empty without a Foundry project)."
  value       = { for k, c in azapi_resource.foundry_connection : k => c.name }
}
