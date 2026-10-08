output "names" {
  description = "Logical role => resource name (generated, or the override when one is set)."
  value       = local.names
}

output "resource_token" {
  description = "Deterministic 10-character token used in v1 names."
  value       = local.resource_token
}

output "foundry_account_names" {
  description = "Foundry (AI Services) account names, one per instance."
  value       = local.foundry_account_names
}

output "convention" {
  description = "Naming convention used to produce the names."
  value       = var.convention
}
