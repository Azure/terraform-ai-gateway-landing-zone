output "api_names" {
  description = "LLM APIs published by this stack (access contracts attach them to products)."
  value       = concat([for a in module.llm_api : a.name], [for a in module.llm_api_universal : a.name])
}

output "backend_ids" {
  description = "LLM backends."
  value       = module.llm_routing.backend_ids
}

output "llm_backends" {
  description = "What was deployed, per APIM backend: where it comes from (foundry = derived from a platform Foundry account, llm_backends = listed in tfvars), its type, endpoint, load-balancing priority and weight, the models it serves and its circuit breaker."
  value = merge(
    {
      for b in local.foundry_derived : b.backend_id => {
        source          = "foundry"
        type            = b.backend_type
        endpoint        = b.endpoint
        priority        = b.priority
        weight          = b.weight
        models          = [for m in b.supported_models : m.name]
        circuit_breaker = b.circuit_breaker
      }
    },
    {
      for b in var.llm_backends : b.backend_id => {
        source          = "llm_backends"
        type            = b.backend_type
        endpoint        = b.endpoint
        priority        = b.priority
        weight          = b.weight
        models          = [for m in b.supported_models : m.name]
        circuit_breaker = b.circuit_breaker
      }
    },
  )
}

output "pool_ids" {
  description = "LLM backend pools (a model served by more than one backend of the same type)."
  value       = module.llm_routing.pool_ids
}

output "models" {
  description = "Model name => the backends or pools that serve it (more than one when the model is hosted under two backend types)."
  value       = { for p in module.llm_routing.pools : p.supported_models[0] => p.pool_name... }
}

output "universal_llm_api_url" {
  description = "Universal LLM API endpoint."
  value       = "${data.azurerm_api_management.this.gateway_url}/${local.universal_llm_api_path}"
}
