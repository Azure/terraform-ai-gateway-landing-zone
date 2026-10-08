output "api_names" {
  description = "Service APIs published by this stack."
  value       = concat([for a in module.api : a.name], [for a in module.api_dependent : a.name])
}

output "fragment_names" {
  description = "Shared policy fragments owned by this stack (llm-backend-onboarding policies reference them)."
  value       = keys(module.shared_fragments.ids)
}

output "named_value_names" {
  description = "Named values owned by this stack."
  value       = keys(azurerm_api_management_named_value.plain)
}
