output "backend_ids" {
  description = "LLM backend ID => APIM backend resource ID."
  value       = { for k, b in azapi_resource.llm_backend : k => b.id }
}

output "pool_ids" {
  description = "Backend pool name => APIM backend resource ID (only models served by 2+ backends get a pool)."
  value       = { for k, p in azapi_resource.llm_backend_pool : k => p.id }
}

output "fragment_ids" {
  description = "Routing fragment name => policy fragment resource ID. APIs whose policies include these fragments must depend on them."
  value = {
    "set-backend-pools"    = azurerm_api_management_policy_fragment.set_backend_pools.id
    "get-available-models" = azurerm_api_management_policy_fragment.get_available_models.id
    "metadata-config"      = azurerm_api_management_policy_fragment.metadata_config.id
    "resolve-model-alias"  = azurerm_api_management_policy_fragment.resolve_model_alias.id
  }
}

output "pools" {
  description = "Pool catalogue consumed by the routing fragments (pool name, type, models, auth)."
  value       = local.all_pools
}
