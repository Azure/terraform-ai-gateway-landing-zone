# =============================================================================
# GATEWAY APIs — one module.api instance per API (modules/gateway-api).
# Assets (OpenAPI specs, policy XML) live in apis/<api-name>/; operation
# policies shared by several APIs live in apis/shared/.
# Replaces the universal-llm-api / azure-openai-api / unified-ai-api submodules
# and the inline APIs of modules/apim (Phase 1, WP-1.2).
# =============================================================================

locals {
  apis_dir = "${path.module}/apis"

  # Universal LLM API flavour (Bicep parity: inferenceAPIType)
  universal_llm_api_path = (
    var.inference_api_type == "AzureOpenAI" ? "openai" :
    var.inference_api_type == "AzureAI" ? "inference" :
    var.inference_api_type == "OpenAI" ? "openai" :
    var.inference_api_type == "OpenAIV1" ? "models" : "models"
  )
  universal_llm_spec_path = (
    var.inference_api_type == "AzureOpenAI" ? "${local.apis_dir}/azure-openai-api/AIFoundryOpenAI.json" :
    var.inference_api_type == "AzureAI" ? "${local.apis_dir}/universal-llm-api/AIFoundryAzureAI.json" :
    var.inference_api_type == "OpenAI" ? "${local.apis_dir}/universal-llm-api/AIFoundryAzureAI.json" :
    var.inference_api_type == "OpenAIV1" ? "${local.apis_dir}/universal-llm-api/AIFoundryOpenAIV1.json" :
    "${local.apis_dir}/universal-llm-api/PassThrough.json"
  )

  has_llm_backends = length(local.effective_llm_backend_config) > 0

  # Diagnostics shapes (Bicep parity: api.bicep logSettings / azuremonitor diagnostic)
  llm_api_log_headers = ["Content-type", "User-agent", "x-ms-region", "x-ratelimit-remaining-tokens", "x-ratelimit-remaining-requests"]

  llm_app_insights_diagnostic = {
    logger_id  = module.apim_telemetry.app_insights_logger_id
    verbosity  = "verbose"
    body_bytes = 0
    headers    = local.llm_api_log_headers
  }

  azure_monitor_llm_block = {
    logs      = "enabled"
    requests  = { messages = "all", maxSizeInBytes = 262144 }
    responses = { messages = "all", maxSizeInBytes = 262144 }
  }

  azure_monitor_no_body = {
    request  = { headers = [], body = { bytes = 0 } }
    response = { headers = [], body = { bytes = 0 } }
  }

  llm_azure_monitor_diagnostic = {
    response_export_values = []
    properties = {
      alwaysLog          = "allErrors"
      verbosity          = "verbose"
      logClientIp        = true
      loggerId           = module.apim_telemetry.azure_monitor_logger_id
      sampling           = { samplingType = "fixed", percentage = 100 }
      frontend           = local.azure_monitor_no_body
      backend            = local.azure_monitor_no_body
      largeLanguageModel = local.azure_monitor_llm_block
    }
  }

  extra_app_insights_diagnostic = var.enable_extra_api_diagnostics ? {
    logger_id  = module.apim_telemetry.app_insights_logger_id
    verbosity  = "information"
    body_bytes = var.extra_api_log_settings.body.bytes
    headers    = var.extra_api_log_settings.headers
  } : null

  extra_azure_monitor_diagnostic = var.enable_extra_api_diagnostics ? {
    response_export_values = null
    properties = {
      alwaysLog          = "allErrors"
      verbosity          = "Information"
      logClientIp        = true
      loggerId           = module.apim_telemetry.azure_monitor_logger_id
      sampling           = { samplingType = "fixed", percentage = 100 }
      frontend           = local.azure_monitor_no_body
      backend            = local.azure_monitor_no_body
      largeLanguageModel = local.azure_monitor_llm_block
    }
  } : null

  api_key_names          = { header = "api-key", query = "api-key" }
  subscription_key_names = { header = "Ocp-Apim-Subscription-Key", query = "subscription-key" }

  # --- Catalogue: only enabled APIs are created -------------------------------
  gateway_apis_raw = merge(
    {
      "universal-llm-api" = {
        api = {
          name                   = "universal-llm-api"
          display_name           = "Universal LLM API"
          description            = "Universal LLM API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models."
          path                   = local.universal_llm_api_path
          subscription_required  = !var.entra_auth_enabled
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi+json", value = file(local.universal_llm_spec_path) }
          policy_xml             = file("${local.apis_dir}/universal-llm-api/universal-llm-api-policy-v2.xml")
        }
        operation_policies = merge(
          local.has_llm_backends ? {
            "deployments"        = file("${local.apis_dir}/shared/universal-llm-api-deployments-policy.xml")
            "deployment-by-name" = file("${local.apis_dir}/shared/universal-llm-api-deployment-by-name-policy.xml")
          } : {},
          local.has_llm_backends && var.inference_api_type == "OpenAIV1" ? {
            "listModels"    = file("${local.apis_dir}/shared/universal-llm-api-deployments-policy.xml")
            "retrieveModel" = file("${local.apis_dir}/shared/universal-llm-api-deployment-by-name-policy.xml")
          } : {},
        )
        azapi_operation_policies = {}
        app_insights_diagnostic  = local.llm_app_insights_diagnostic
        azure_monitor_diagnostic = local.llm_azure_monitor_diagnostic
        product                  = null
      }
      "azure-openai-api" = {
        api = {
          name                   = "azure-openai-api"
          display_name           = "Azure OpenAI API"
          description            = "Azure OpenAI API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models."
          path                   = "openai"
          subscription_required  = !var.entra_auth_enabled
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi+json", value = file("${local.apis_dir}/azure-openai-api/AIFoundryOpenAI.json") }
          policy_xml             = file("${local.apis_dir}/azure-openai-api/azure-open-ai-api-policy.xml")
        }
        operation_policies = local.has_llm_backends ? {
          "deployments"        = file("${local.apis_dir}/shared/universal-llm-api-deployments-policy.xml")
          "deployment-by-name" = file("${local.apis_dir}/shared/universal-llm-api-deployment-by-name-policy.xml")
        } : {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = local.llm_app_insights_diagnostic
        azure_monitor_diagnostic = local.llm_azure_monitor_diagnostic
        product                  = null
      }
    },
    local.features.unified_ai_api ? {
      "unified-ai-api" = {
        api = {
          name                   = "unified-ai-api"
          display_name           = "Unified AI API"
          description            = "Unified AI Gateway API - Routes requests to multiple AI model providers (Azure OpenAI, AI Foundry, Gemini) using dynamic path-based routing with support for multiple API types."
          path                   = "unified-ai"
          subscription_required  = true
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi+json", value = file("${local.apis_dir}/unified-ai-api/UnifiedAIWildcard.json") }
          policy_xml             = file("${local.apis_dir}/unified-ai-api/unified-ai-api-policy.xml")
        }
        operation_policies = {}
        azapi_operation_policies = {
          "deployments"        = file("${local.apis_dir}/unified-ai-api/unified-ai-api-deployments-policy.xml")
          "deployment-by-name" = file("${local.apis_dir}/unified-ai-api/unified-ai-api-deployment-by-name-policy.xml")
        }
        app_insights_diagnostic  = null
        azure_monitor_diagnostic = local.llm_azure_monitor_diagnostic
        product = {
          id                  = "unified-ai-product"
          display_name        = "Unified AI Gateway"
          description         = "Unified AI Gateway product - provides access to all AI model providers through a single wildcard endpoint."
          subscriptions_limit = 10
          policy_xml          = file("${local.apis_dir}/unified-ai-api/unified-ai-product-subscription.xml")
        }
        api_depends_on = []
      }
    } : {},
    local.features.azure_ai_search ? {
      "azure-ai-search-index-api" = {
        api = {
          name                   = "azure-ai-search-index-api"
          display_name           = "Azure AI Search Index API (index services)"
          description            = "Azure AI Search Index Client APIs"
          path                   = "search"
          service_url            = "https://to-be-replaced-by-policy"
          subscription_required  = !var.entra_auth_enabled
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi+json", value = file("${local.apis_dir}/azure-ai-search-index-api/ai-search-index-2024-07-01-api-spec.json") }
          policy_xml             = file("${local.apis_dir}/azure-ai-search-index-api/ai-search-index-api-policy.xml")
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = local.extra_app_insights_diagnostic
        azure_monitor_diagnostic = local.extra_azure_monitor_diagnostic
        product                  = null
      }
    } : {},
    local.features.document_intelligence ? {
      "document-intelligence-api-legacy" = {
        api = {
          name                   = "document-intelligence-api-legacy"
          display_name           = "Document Intelligence API (Legacy)"
          description            = "Uses (/formrecognizer) url path. Extracts content, layout, and structured data from documents."
          path                   = "formrecognizer"
          service_url            = "https://to-be-replaced-by-policy"
          subscription_required  = !var.entra_auth_enabled
          subscription_key_names = local.subscription_key_names
          spec                   = { format = "openapi", value = file("${local.apis_dir}/document-intelligence-api/document-intelligence-2024-11-30-compressed.openapi.yaml") }
          policy_xml             = file("${local.apis_dir}/document-intelligence-api/doc-intelligence-api-policy.xml")
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = local.extra_app_insights_diagnostic
        azure_monitor_diagnostic = local.extra_azure_monitor_diagnostic
        product                  = null
      }
    } : {},
    local.features.ai_model_inference ? {
      "ai-model-inference-api" = {
        api = {
          name                   = "ai-model-inference-api"
          display_name           = "Azure AI Model Inference API"
          description            = "Azure AI Model Inference unified API"
          path                   = "ai-inference"
          subscription_required  = true
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi", value = file("${local.apis_dir}/ai-model-inference-api/ai-model-inference-api-spec.yaml") }
          policy_xml             = file("${local.apis_dir}/ai-model-inference-api/ai-model-inference-api-policy.xml")
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = null
        azure_monitor_diagnostic = null
        product                  = null
      }
    } : {},
    local.features.openai_realtime ? {
      # WebSocket APIs don't accept an API-scope policy, so
      # apis/openai-realtime-ws-api/openai-realtime-policy.xml is not attached here
      # (it belongs on the operation scope of the upgraded WebSocket operation).
      "openai-realtime-ws-api" = {
        api = {
          name = "openai-realtime-ws-api"
          type = "websocket"
          azapi_properties_json = jsonencode({
            apiType                       = "websocket"
            displayName                   = "Azure OpenAI Realtime API"
            description                   = "Access Azure OpenAI Realtime API for real-time voice and text conversion."
            type                          = "websocket"
            path                          = "openai/realtime"
            apiRevision                   = "1"
            subscriptionRequired          = !var.entra_auth_enabled
            protocols                     = ["wss"]
            serviceUrl                    = "wss://to-be-replaced-by-policy"
            subscriptionKeyParameterNames = local.api_key_names
          })
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = null
        azure_monitor_diagnostic = null
        product                  = null
      }
    } : {},
    local.features.mcp_sample ? {
      "weather-api" = {
        api = {
          name                  = "weather-api"
          display_name          = "Weather API"
          description           = "Sample Weather API used to demonstrate the MCP-from-API pattern."
          path                  = "weather"
          subscription_required = false
          spec                  = { format = "openapi+json", value = file("${local.apis_dir}/weather-api/openapi.json") }
          policy_xml            = file("${local.apis_dir}/weather-api/policy.xml")
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = null
        azure_monitor_diagnostic = null
        product                  = null
      }
    } : {},
  )

  # Second wave: APIs that must be created after another API or a backend
  # (a for_each instance can't depend on a sibling instance of the same call).
  dependent_apis_raw = merge(
    local.features.document_intelligence ? {
      "document-intelligence-api" = {
        api = {
          name                   = "document-intelligence-api"
          display_name           = "Document Intelligence API"
          description            = "Uses (/documentintelligence) url path. Extracts content, layout, and structured data from documents."
          path                   = "documentintelligence"
          service_url            = "https://to-be-replaced-by-policy"
          subscription_required  = !var.entra_auth_enabled
          subscription_key_names = local.subscription_key_names
          spec                   = { format = "openapi", value = file("${local.apis_dir}/document-intelligence-api/document-intelligence-2024-11-30-compressed.openapi.yaml") }
          policy_xml             = file("${local.apis_dir}/document-intelligence-api/doc-intelligence-api-policy.xml")
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = local.extra_app_insights_diagnostic
        azure_monitor_diagnostic = local.extra_azure_monitor_diagnostic
        product                  = null
        api_depends_on           = [module.api["document-intelligence-api-legacy"].id] # same spec as the legacy API; created after it
      }
    } : {},
    local.features.mcp_sample ? {
      "weather-mcp" = {
        api = {
          name                    = "weather-mcp"
          type                    = "mcp"
          azapi_schema_validation = false
          policy_xml              = file("${local.apis_dir}/shared/mcp-default-policy.xml")
          azapi_properties_json = jsonencode({
            type                 = "mcp"
            displayName          = "Weather MCP"
            description          = "MCP server derived from the Weather sample API."
            subscriptionRequired = false
            path                 = "weather-mcp"
            protocols            = ["https"]
            mcpTools = [
              for op_id in ["get-weather"] : {
                name        = op_id
                operationId = "${module.apim.apim_id}/apis/${module.api["weather-api"].name}/operations/${op_id}"
                description = "Weather MCP tool derived from ${op_id}"
              }
            ]
          })
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = null
        azure_monitor_diagnostic = null
        product                  = null
        api_depends_on           = [module.api["weather-api"].id]
      }
      "ms-learn-mcp" = {
        api = {
          name                    = "ms-learn-mcp"
          type                    = "mcp"
          azapi_schema_validation = false
          policy_xml              = file("${local.apis_dir}/shared/mcp-default-policy.xml")
          azapi_properties_json = jsonencode({
            type                 = "mcp"
            displayName          = "Microsoft Learn MCP"
            description          = "Microsoft Learn MCP server"
            subscriptionRequired = false
            path                 = "ms-learn-mcp"
            protocols            = ["https"]
            backendId            = "ms-learn-mcp-backend"
            mcpPropperties = {
              transportType = "streamable"
            }
          })
        }
        operation_policies       = {}
        azapi_operation_policies = {}
        app_insights_diagnostic  = null
        azure_monitor_diagnostic = null
        product                  = null
        api_depends_on           = [module.apim.ms_learn_mcp_backend_id]
      }
    } : {},
  )

  # Normalise every catalogue entry to one shape (for_each needs a map whose
  # values share a type).
  gateway_apis   = { for k, v in local.gateway_apis_raw : k => merge(local.api_entry_defaults, v, { api = merge(local.api_defaults, v.api) }) }
  dependent_apis = { for k, v in local.dependent_apis_raw : k => merge(local.api_entry_defaults, v, { api = merge(local.api_defaults, v.api) }) }

  api_defaults = {
    type                    = "http"
    display_name            = null
    description             = null
    path                    = null
    protocols               = ["https"]
    service_url             = null
    subscription_required   = true
    subscription_key_names  = null
    spec                    = null
    policy_xml              = null
    azapi_properties_json   = null
    azapi_schema_validation = true
  }

  api_entry_defaults = {
    operation_policies       = {}
    azapi_operation_policies = {}
    app_insights_diagnostic  = null
    azure_monitor_diagnostic = null
    product                  = null
    api_depends_on           = []
  }

  # APIM validates fragment / named-value / logger references when a policy is saved.
  api_policy_depends_on = concat(
    values(module.policy_fragments.ids),
    values(module.llm_routing.fragment_ids),
    module.apim.named_value_ids,
    module.apim_telemetry.dependency_ids,
  )
}

module "api" {
  source   = "./modules/gateway-api"
  for_each = local.gateway_apis

  api_management_id   = module.apim.apim_id
  api_management_name = module.apim.apim_name
  resource_group_name = local.resource_group_name_resolved

  api                      = each.value.api
  operation_policies       = each.value.operation_policies
  azapi_operation_policies = each.value.azapi_operation_policies
  app_insights_diagnostic  = each.value.app_insights_diagnostic
  azure_monitor_diagnostic = each.value.azure_monitor_diagnostic
  product                  = each.value.product
  policy_depends_on        = local.api_policy_depends_on
}

module "api_dependent" {
  source   = "./modules/gateway-api"
  for_each = local.dependent_apis

  api_management_id   = module.apim.apim_id
  api_management_name = module.apim.apim_name
  resource_group_name = local.resource_group_name_resolved

  api                      = each.value.api
  operation_policies       = each.value.operation_policies
  azapi_operation_policies = each.value.azapi_operation_policies
  app_insights_diagnostic  = each.value.app_insights_diagnostic
  azure_monitor_diagnostic = each.value.azure_monitor_diagnostic
  product                  = each.value.product
  api_depends_on           = each.value.api_depends_on
  policy_depends_on        = local.api_policy_depends_on
}
