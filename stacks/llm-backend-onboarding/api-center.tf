data "azapi_resource" "api_center" {
  count     = var.features.api_center_onboarding ? 1 : 0
  type      = "Microsoft.ApiCenter/services@2024-03-01"
  name      = local.names.api_center
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.names.resource_group}"
}

# Registers the LLM APIs in the API Center of stacks/platform.
locals {
  api_center_targets = merge(
    {
      "universal-llm-api" = { display_name = "Universal LLM API", description = "OpenAI-compatible unified LLM endpoint", kind = "rest", path = local.universal_llm_api_path, environment = "api-dev" }
      "azure-openai-api"  = { display_name = "Azure OpenAI API", description = "Azure OpenAI compatibility API", kind = "rest", path = "openai", environment = "api-dev" }
    },
    var.features.unified_ai_api ? {
      "unified-ai-api" = { display_name = "Unified AI API", description = "Unified AI wildcard routing API", kind = "rest", path = "unified-ai", environment = "api-dev" }
    } : {},
    var.features.ai_model_inference ? {
      "ai-model-inference-api" = { display_name = "Azure AI Model Inference API", description = "Azure AI Model Inference unified API", kind = "rest", path = "ai-inference", environment = "api-dev" }
    } : {},
    var.features.openai_realtime ? {
      "openai-realtime-ws-api" = { display_name = "OpenAI Realtime WebSocket API", description = "OpenAI Realtime API over WebSocket", kind = "websocket", path = "openai-realtime", environment = "api-dev" }
    } : {},
  )
}

module "api_center_registration" {
  source = "../../modules/api-center-registration"

  enabled        = var.features.api_center_onboarding
  api_center_id  = try(data.azapi_resource.api_center[0].id, "")
  workspace_name = "default"
  gateway_url    = data.azurerm_api_management.this.gateway_url
  apis           = local.api_center_targets

  depends_on = [module.llm_api]
}
