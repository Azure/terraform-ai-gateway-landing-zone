output "names" {
  description = "Logical role => resource name (generated, or the override when one is set)."
  value       = local.names
}

output "seed" {
  description = "Deterministic 5-character suffix used in globally unique names."
  value       = local.seed
}

output "base" {
  description = "<workload>-<environment>, used by modules that derive child resource names."
  value       = local.base
}

output "foundry_account_names" {
  description = "Foundry (AI Services) account names, one per instance."
  value       = local.foundry_account_names
}

output "private_dns_zones" {
  description = "Logical key => private DNS zone name used by the gateway's private endpoints."
  value       = local.private_dns_zones
}
