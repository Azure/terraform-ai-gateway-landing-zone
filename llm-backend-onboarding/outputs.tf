# =============================================================================
# LLM Backend Onboarding — Outputs
# =============================================================================

output "apim_name" {
  description = "Name of the APIM service."
  value       = data.azurerm_api_management.citadel.name
}

output "apim_gateway_url" {
  description = "Gateway URL for the APIM service."
  value       = data.azurerm_api_management.citadel.gateway_url
}

output "backend_ids" {
  description = "Array of created backend IDs."
  value       = [for b in azapi_resource.llm_backend : b.name]
}

output "pool_names" {
  description = "Array of created backend pool names."
  value       = [for p in azapi_resource.llm_backend_pool : p.name]
}

output "model_to_pool_map" {
  description = "Mapping of models to their backend pool names (models with 2+ backends)."
  value = {
    for pool_name, cfg in local.pool_configs : cfg.model_name => pool_name
  }
}

output "model_to_backend_map" {
  description = "Mapping of models to direct backend IDs (models with a single backend)."
  value = {
    for m, b in local.direct_backends : m => b.backend_id
  }
}

output "supported_models" {
  description = "All supported models across all backends."
  value       = distinct([for m in local.flattened_models : m.name])
}

output "policy_fragments" {
  description = "Names of the deployed policy fragments."
  value = {
    set_backend_pools         = try(azurerm_api_management_policy_fragment.set_backend_pools.name, null)
    get_available_models      = try(azurerm_api_management_policy_fragment.get_available_models.name, null)
    metadata_config           = try(azurerm_api_management_policy_fragment.metadata_config.name, null)
    set_backend_authorization = try(azurerm_api_management_policy_fragment.static["set-backend-authorization"].name, null)
    set_target_backend_pool   = try(azurerm_api_management_policy_fragment.static["set-target-backend-pool"].name, null)
    set_llm_requested_model   = try(azurerm_api_management_policy_fragment.static["set-llm-requested-model"].name, null)
    set_llm_usage             = try(azurerm_api_management_policy_fragment.static["set-llm-usage"].name, null)
  }
}
