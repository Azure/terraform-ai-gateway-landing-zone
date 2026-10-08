# =============================================================================
# API CENTER REGISTRATION (was modules/apim/api-center-onboarding.tf)
# Registers every enabled gateway API in API Center.
# =============================================================================

locals {
  api_center_environment_name     = "api-dev"
  api_center_mcp_environment_name = "mcp-dev"

  # Only the APIs whose feature flag is on are registered.
  api_center_targets = merge(
    {
      "universal-llm-api" = {
        display_name = "Universal LLM API"
        description  = "OpenAI-compatible unified LLM endpoint"
        kind         = "rest"
        path         = "models"
        environment  = local.api_center_environment_name
      }
      "azure-openai-api" = {
        display_name = "Azure OpenAI API"
        description  = "Azure OpenAI compatibility API"
        kind         = "rest"
        path         = "openai"
        environment  = local.api_center_environment_name
      }
    },
    local.features.unified_ai_api ? {
      "unified-ai-api" = {
        display_name = "Unified AI API"
        description  = "Unified AI wildcard routing API"
        kind         = "rest"
        path         = "unified-ai"
        environment  = local.api_center_environment_name
      }
    } : {},
    local.features.azure_ai_search ? {
      "azure-ai-search-index-api" = {
        display_name = "Azure AI Search Index API"
        description  = "Azure AI Search index query API"
        kind         = "rest"
        path         = "search"
        environment  = local.api_center_environment_name
      }
    } : {},
    local.features.ai_model_inference ? {
      "ai-model-inference-api" = {
        display_name = "Azure AI Model Inference API"
        description  = "Azure AI Model Inference unified API"
        kind         = "rest"
        path         = "ai-inference"
        environment  = local.api_center_environment_name
      }
    } : {},
    local.features.document_intelligence ? {
      "document-intelligence-api" = {
        display_name = "Document Intelligence API"
        description  = "Document Intelligence API (documentintelligence path)"
        kind         = "rest"
        path         = "documentintelligence"
        environment  = local.api_center_environment_name
      }
    } : {},
    local.features.openai_realtime ? {
      "openai-realtime-ws-api" = {
        display_name = "OpenAI Realtime WebSocket API"
        description  = "OpenAI Realtime API over WebSocket"
        kind         = "websocket"
        path         = "openai-realtime"
        environment  = local.api_center_environment_name
      }
    } : {},
    local.features.mcp_sample ? {
      "weather-api" = {
        display_name = "Weather API"
        description  = "Sample Weather API"
        kind         = "rest"
        path         = "weather"
        environment  = local.api_center_environment_name
      }
      "weather-mcp" = {
        display_name = "Weather MCP"
        description  = "MCP server derived from the Weather sample API"
        kind         = "mcp"
        path         = "weather-mcp"
        environment  = local.api_center_mcp_environment_name
      }
      "ms-learn-mcp" = {
        display_name = "Microsoft Learn MCP"
        description  = "Microsoft Learn MCP server"
        kind         = "mcp"
        path         = "ms-learn-mcp"
        environment  = local.api_center_mcp_environment_name
      }
    } : {}
  )

}

module "api_center_registration" {
  source = "./modules/api-center-registration"

  # Plan-time flag only: module.apic.api_center_name is unknown until apply on
  # a fresh deployment and must not drive count/for_each.
  enabled        = local.features.api_center && local.features.api_center_onboarding
  api_center_id  = module.apic.api_center_id
  workspace_name = "default"
  gateway_url    = module.apim.gateway_url
  apis           = local.api_center_targets
}
