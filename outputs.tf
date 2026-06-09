# =============================================================================
# AI Citadel Governance Hub - Outputs
# =============================================================================

output "resource_group_name" {
  description = "Name of the deployed resource group"
  value       = local.resource_group_name_resolved
}

output "apim_gateway_url" {
  description = "API Management gateway URL"
  value       = module.apim.gateway_url
}

output "apim_name" {
  description = "API Management service name"
  value       = module.apim.apim_name
}

output "cosmos_db_endpoint" {
  description = "Cosmos DB account endpoint"
  value       = module.cosmosdb.endpoint
}

output "cosmos_db_account_name" {
  description = "Cosmos DB account name (Bicep: COSMOS_DB_ACCOUNT_NAME)."
  value       = module.cosmosdb.account_name
}

output "eventhub_namespace" {
  description = "Event Hub namespace name"
  value       = module.eventhub.namespace_name
}

output "event_hub_name" {
  description = "AI usage Event Hub name (Bicep: EVENT_HUB_NAME)."
  value       = module.eventhub.apim_usage_hub_name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = module.monitoring.log_analytics_id
}

output "app_insights_name" {
  description = "Application Insights resource name"
  value       = module.monitoring.app_insights_name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.security.key_vault_uri
}

output "apim_managed_identity_client_id" {
  description = "APIM user-assigned managed identity client ID (Bicep: id-apim-*)"
  value       = azurerm_user_assigned_identity.apim.client_id
}

output "apim_managed_identity_principal_id" {
  description = "APIM user-assigned managed identity principal ID"
  value       = azurerm_user_assigned_identity.apim.principal_id
}

output "usage_managed_identity_client_id" {
  description = "Logic App / usage user-assigned managed identity client ID (Bicep: id-logicapp-*)"
  value       = azurerm_user_assigned_identity.usage.client_id
}

output "usage_managed_identity_principal_id" {
  description = "Logic App / usage user-assigned managed identity principal ID"
  value       = azurerm_user_assigned_identity.usage.principal_id
}

output "vnet_id" {
  description = "Virtual network resource ID"
  value       = module.networking.vnet_id
}

output "ai_foundry_endpoints" {
  description = "AI Foundry instance endpoints"
  value       = module.foundry.foundry_endpoints
}

output "ai_foundry_project_endpoints" {
  description = "AI Foundry project endpoints (one per account)"
  value = [
    for c in module.foundry.extended_ai_services_config : c.foundry_project_endpoint
  ]
}

output "universal_llm_api_url" {
  description = "Universal LLM API endpoint (POST /models/chat/completions)"
  value       = "${module.apim.gateway_url}/models/chat/completions"
}

output "azure_openai_api_url" {
  description = "Azure OpenAI compatible API base URL"
  value       = "${module.apim.gateway_url}/openai"
}

# =============================================================================
# Outputs consumed by the Python validation notebooks (shared/utils.py bridges
# these to the azd-style env var names the notebooks request — see the
# _TF_OUTPUT_ALIASES map). Adding/renaming these requires updating that map.
# =============================================================================

output "location" {
  description = "Primary Azure region (azd parity: AZURE_LOCATION / LOCATION)."
  value       = var.location
}

output "subscription_id" {
  description = "Subscription ID of the deployment (azd parity: AZURE_SUBSCRIPTION_ID)."
  value       = data.azurerm_subscription.current.subscription_id
}

output "key_vault_name" {
  description = "Key Vault name (azd parity: KEY_VAULT_NAME)."
  value       = module.security.key_vault_name
}

output "ai_foundry_services" {
  description = <<-EOT
    AI Foundry accounts in the azd `AI_FOUNDRY_SERVICES` shape consumed by the
    validation notebooks. Each entry exposes `cognitiveServiceName` and
    `foundryProjectEndpoint` (camelCase, matching the Bicep/azd output keys).
  EOT
  value = [
    for c in module.foundry.extended_ai_services_config : {
      cognitiveServiceName    = c.cognitive_service_name
      foundryProjectEndpoint  = c.foundry_project_endpoint
      location                = c.location
      endpoint                = c.endpoint
    }
  ]
}

output "llm_backend_config" {
  description = <<-EOT
    Effective APIM LLM backend configuration (auto-derived from Foundry or the
    full override). azd parity: LLM_BACKEND_CONFIG / LLM_BACKENDS_CONFIG. Used
    by the model-aliases and unified-AI-API validation notebooks.
  EOT
  value = local.effective_llm_backend_config
}
