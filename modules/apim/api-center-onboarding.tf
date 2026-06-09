# =============================================================================
# API CENTER ONBOARDING — Bicep parity: api-center-onboarding.bicep
#
# Registers each APIM-hosted API (OpenAI, Universal-LLM, Unified-AI, AI Search,
# Realtime, Doc Intelligence, AI Model Inference, Weather, Weather-MCP,
# MS-Learn-MCP) in API Center with Version + Definition + Deployment.
# =============================================================================

locals {
  # Build map of APIs to onboard. Only entries whose feature flag is enabled
  # are included.
  apic_api_targets = merge(
    {
      "universal-llm-api" = {
        display_name   = "Universal LLM API"
        description    = "OpenAI-compatible unified LLM endpoint"
        kind           = "rest"
        path           = "models"
        environment    = var.api_center_environment_name
      }
      "azure-openai-api" = {
        display_name = "Azure OpenAI API"
        description  = "Azure OpenAI compatibility API"
        kind         = "rest"
        path         = "openai"
        environment  = var.api_center_environment_name
      }
    },
    var.enable_unified_ai_api ? {
      "unified-ai-api" = {
        display_name = "Unified AI API"
        description  = "Unified AI wildcard routing API"
        kind         = "rest"
        path         = "unified-ai"
        environment  = var.api_center_environment_name
      }
    } : {},
    var.enable_azure_ai_search ? {
      "azure-ai-search-index-api" = {
        display_name = "Azure AI Search Index API"
        description  = "Azure AI Search index query API"
        kind         = "rest"
        path         = "search"
        environment  = var.api_center_environment_name
      }
    } : {},
    var.enable_ai_model_inference ? {
      "ai-model-inference-api" = {
        display_name = "Azure AI Model Inference API"
        description  = "Azure AI Model Inference unified API"
        kind         = "rest"
        path         = "ai-inference"
        environment  = var.api_center_environment_name
      }
    } : {},
    var.enable_document_intelligence ? {
      "document-intelligence-api" = {
        display_name = "Document Intelligence API"
        description  = "Document Intelligence API (documentintelligence path)"
        kind         = "rest"
        path         = "documentintelligence"
        environment  = var.api_center_environment_name
      }
    } : {},
    var.enable_openai_realtime ? {
      "openai-realtime-ws-api" = {
        display_name = "OpenAI Realtime WebSocket API"
        description  = "OpenAI Realtime API over WebSocket"
        kind         = "websocket"
        path         = "openai-realtime"
        environment  = var.api_center_environment_name
      }
    } : {},
    var.is_mcp_sample_deployed ? {
      "weather-api" = {
        display_name = "Weather API"
        description  = "Sample Weather API"
        kind         = "rest"
        path         = "weather"
        environment  = var.api_center_environment_name
      }
      "weather-mcp" = {
        display_name = "Weather MCP"
        description  = "MCP server derived from the Weather sample API"
        kind         = "mcp"
        path         = "weather-mcp"
        environment  = var.api_center_mcp_environment_name
      }
      "ms-learn-mcp" = {
        display_name = "Microsoft Learn MCP"
        description  = "Microsoft Learn MCP server"
        kind         = "mcp"
        path         = "ms-learn-mcp"
        environment  = var.api_center_mcp_environment_name
      }
    } : {}
  )

  # NOTE: Only reference statically-known values here. `var.api_center_service_name`
  # comes from `module.ai_services.api_center_name`, which Terraform treats as
  # not-yet-known at plan time (even though the underlying name is an input).
  # Including it in `apic_enabled` causes `Invalid count argument` on the
  # data/resource blocks below. The caller in main.tf already gates
  # `enable_api_center_onboarding` on `var.enable_api_center`, so this bool
  # is sufficient.
  apic_enabled = var.enable_api_center_onboarding
}

# Reference existing API Center service (created by ai-services module)
data "azapi_resource" "api_center_existing" {
  count     = local.apic_enabled ? 1 : 0
  type      = "Microsoft.ApiCenter/services@2024-06-01-preview"
  name      = var.api_center_service_name
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
}

resource "azapi_resource" "apic_api" {
  for_each = local.apic_enabled ? local.apic_api_targets : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview"
  name      = each.key
  parent_id = "${data.azapi_resource.api_center_existing[0].id}/workspaces/${var.api_center_workspace_name}"

  body = {
    properties = {
      title            = each.value.display_name
      kind             = each.value.kind
      contacts         = []
      customProperties = {}
      summary          = each.value.description
      description      = each.value.description
    }
  }
}

resource "azapi_resource" "apic_api_version" {
  for_each = local.apic_enabled ? local.apic_api_targets : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview"
  name      = "1-0-0"
  parent_id = azapi_resource.apic_api[each.key].id

  body = {
    properties = {
      title          = "1.0.0"
      lifecycleStage = "development"
    }
  }
}

resource "azapi_resource" "apic_api_definition" {
  for_each = local.apic_enabled ? local.apic_api_targets : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-06-01-preview"
  name      = "${each.key}-definition"
  parent_id = azapi_resource.apic_api_version[each.key].id

  body = {
    properties = {
      description = "${each.value.display_name} Definition for version 1-0-0"
      title       = "${each.value.display_name} Definition"
    }
  }
}

resource "azapi_resource" "apic_api_deployment" {
  for_each = local.apic_enabled ? local.apic_api_targets : {}

  type      = "Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-06-01-preview"
  name      = "${each.key}-deployment"
  parent_id = azapi_resource.apic_api[each.key].id

  body = {
    properties = {
      description   = "${each.value.display_name} Deployment"
      title         = "${each.value.display_name} Deployment"
      environmentId = "/workspaces/${var.api_center_workspace_name}/environments/${each.value.environment}"
      definitionId  = "/workspaces/${var.api_center_workspace_name}/apis/${each.key}/versions/1-0-0/definitions/${each.key}-definition"
      state         = "active"
      server = {
        runtimeUri = ["${azurerm_api_management.citadel.gateway_url}/${each.value.path}"]
      }
    }
  }

  depends_on = [azapi_resource.apic_api_definition]
}
