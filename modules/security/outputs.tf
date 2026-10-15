output "key_vault_id"  { value = azurerm_key_vault.citadel.id }
output "key_vault_uri" { value = azurerm_key_vault.citadel.vault_uri }
output "key_vault_name" { value = azurerm_key_vault.citadel.name }

# Same vault, but only known once the APIM identity can read secrets through the
# private endpoint: consumers that make APIM resolve Key Vault references
# (Key Vault-backed named values) wait on this instead of the whole module.
output "key_vault_for_apim_secrets" {
  value = {
    id           = azurerm_key_vault.citadel.id
    uri          = azurerm_key_vault.citadel.vault_uri
    rbac_enabled = azurerm_key_vault.citadel.rbac_authorization_enabled
  }
  depends_on = [
    azurerm_role_assignment.uami_kv_secrets_user,
    time_sleep.wait_for_kv_rbac,
    azurerm_private_endpoint.key_vault,
  ]
}
