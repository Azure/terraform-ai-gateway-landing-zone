output "id" {
  description = "Resource ID of the account."
  value       = module.account.resource_id
}

output "name" {
  description = "Account name."
  value       = module.account.name
}

output "endpoint" {
  description = "Base endpoint (https://<custom subdomain>.cognitiveservices.azure.com/), the same shape APIM already uses for Foundry accounts."
  value       = "https://${local.subdomain}.cognitiveservices.azure.com/"
}

output "diagnostic_setting_name" {
  description = "Workload diagnostic setting name (null when policy owns diagnostics)."
  value       = var.enable_diagnostics ? "${var.name}-diagnostics" : null
}
