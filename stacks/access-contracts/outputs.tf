output "products" {
  description = "Service code => product ID."
  value       = module.contract.products
}

output "subscriptions" {
  description = "Service code => subscription resource ID (keys are never in state: read them from Key Vault or APIM)."
  value       = module.contract.subscriptions
}

output "endpoints" {
  description = "Service code => gateway endpoint URL."
  value       = module.contract.endpoints
}

output "key_vault_secret_names" {
  description = "Service code => { endpoint, key } Key Vault secret names."
  value       = module.contract.key_vault_secret_names
}

output "foundry_connections" {
  description = "Service code => Foundry connection name."
  value       = module.contract.foundry_connections
}
