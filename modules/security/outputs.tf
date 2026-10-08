output "key_vault_id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.citadel.id
}
output "key_vault_id_for_secrets" {
  description = "Resource ID of the Key Vault, available once the deployer's RBAC and the network ACLs have propagated. Use it for data-plane writes (secrets)."
  value       = azurerm_key_vault.citadel.id
  depends_on  = [time_sleep.wait_for_kv_rbac, time_sleep.wait_for_kv_acl]
}

output "key_vault_uri" {
  description = "URI of the Key Vault."
  value       = azurerm_key_vault.citadel.vault_uri
}
output "key_vault_name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.citadel.name
}
