output "api_names" {
  description = "LLM APIs published by this stack (access contracts attach them to products)."
  value       = [for a in module.llm_api : a.name]
}

output "backend_ids" {
  description = "LLM backends."
  value       = module.llm_routing.backend_ids
}

output "pool_ids" {
  description = "LLM backend pools (models served by more than one backend)."
  value       = module.llm_routing.pool_ids
}

output "models" {
  description = "Model name => backend or pool that serves it."
  value       = { for p in module.llm_routing.pools : p.supported_models[0] => p.pool_name }
}

output "universal_llm_api_url" {
  description = "Universal LLM API endpoint."
  value       = "${data.azurerm_api_management.this.gateway_url}/${local.universal_llm_api_path}"
}
