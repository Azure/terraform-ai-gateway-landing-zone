output "key_vault_id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.citadel.id
}
output "key_vault_uri" {
  description = "URI of the Key Vault."
  value       = azurerm_key_vault.citadel.vault_uri
}
output "key_vault_name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.citadel.name
}
