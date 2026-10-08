# LLM APIs (review 7.8): Universal LLM, Azure OpenAI, Unified AI, AI Model
# Inference and the OpenAI Realtime WebSocket API. Assets live in apis/<name>/.

locals {
  apis_dir = "${path.module}/apis"

  # Universal LLM API flavour (Bicep parity: inferenceAPIType).
  universal_llm_api_path = lookup({ AzureOpenAI = "openai", AzureAI = "inference", OpenAI = "openai", OpenAIV1 = "models" }, var.inference_api_type, "models")
  universal_llm_spec_path = lookup({
    AzureOpenAI = "${local.apis_dir}/azure-openai-api/AIFoundryOpenAI.json"
    AzureAI     = "${local.apis_dir}/universal-llm-api/AIFoundryAzureAI.json"
    OpenAI      = "${local.apis_dir}/universal-llm-api/AIFoundryAzureAI.json"
    OpenAIV1    = "${local.apis_dir}/universal-llm-api/AIFoundryOpenAIV1.json"
  }, var.inference_api_type, "${local.apis_dir}/universal-llm-api/PassThrough.json")

  has_llm_backends = length(local.llm_backend_config) > 0

  # With Entra auth (gateway-config) the APIs take a JWT instead of a key.
  subscription_required = !local.entra_auth_enabled
  api_key_names         = { header = "api-key", query = "api-key" }

  llm_app_insights_diagnostic = {
    logger_id  = local.app_insights_logger_id
    verbosity  = "verbose"
    body_bytes = 0
    headers    = ["Content-type", "User-agent", "x-ms-region", "x-ratelimit-remaining-tokens", "x-ratelimit-remaining-requests"]
  }

  azure_monitor_no_body = {
    request  = { headers = [], body = { bytes = 0 } }
    response = { headers = [], body = { bytes = 0 } }
  }

  llm_azure_monitor_diagnostic = {
    response_export_values = []
    properties = {
      alwaysLog   = "allErrors"
      verbosity   = "verbose"
      logClientIp = true
      loggerId    = local.azure_monitor_logger_id
      sampling    = { samplingType = "fixed", percentage = 100 }
      frontend    = local.azure_monitor_no_body
      backend     = local.azure_monitor_no_body
      largeLanguageModel = {
        logs      = "enabled"
        requests  = { messages = "all", maxSizeInBytes = 262144 }
        responses = { messages = "all", maxSizeInBytes = 262144 }
      }
    }
  }

  deployments_operation_policies = local.has_llm_backends ? {
    "deployments"        = file("${local.apis_dir}/shared/universal-llm-api-deployments-policy.xml")
    "deployment-by-name" = file("${local.apis_dir}/shared/universal-llm-api-deployment-by-name-policy.xml")
  } : {}

  llm_apis_raw = merge(
    {
      "universal-llm-api" = {
        api = {
          name                   = "universal-llm-api"
          display_name           = "Universal LLM API"
          description            = "Universal LLM API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models."
          path                   = local.universal_llm_api_path
          subscription_required  = local.subscription_required
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi+json", value = file(local.universal_llm_spec_path) }
          policy_xml             = file("${local.apis_dir}/universal-llm-api/universal-llm-api-policy-v2.xml")
        }
        operation_policies = merge(
          local.deployments_operation_policies,
          local.has_llm_backends && var.inference_api_type == "OpenAIV1" ? {
            "listModels"    = file("${local.apis_dir}/shared/universal-llm-api-deployments-policy.xml")
            "retrieveModel" = file("${local.apis_dir}/shared/universal-llm-api-deployment-by-name-policy.xml")
          } : {},
        )
        app_insights_diagnostic  = local.llm_app_insights_diagnostic
        azure_monitor_diagnostic = local.llm_azure_monitor_diagnostic
      }
      "azure-openai-api" = {
        api = {
          name                   = "azure-openai-api"
          display_name           = "Azure OpenAI API"
          description            = "Azure OpenAI API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models."
          path                   = "openai"
          subscription_required  = local.subscription_required
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi+json", value = file("${local.apis_dir}/azure-openai-api/AIFoundryOpenAI.json") }
          policy_xml             = file("${local.apis_dir}/azure-openai-api/azure-open-ai-api-policy.xml")
        }
        operation_policies       = local.deployments_operation_policies
        app_insights_diagnostic  = local.llm_app_insights_diagnostic
        azure_monitor_diagnostic = local.llm_azure_monitor_diagnostic
      }
    },
    var.features.unified_ai_api ? {
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
        azapi_operation_policies = {
          "deployments"        = file("${local.apis_dir}/unified-ai-api/unified-ai-api-deployments-policy.xml")
          "deployment-by-name" = file("${local.apis_dir}/unified-ai-api/unified-ai-api-deployment-by-name-policy.xml")
        }
        azure_monitor_diagnostic = local.llm_azure_monitor_diagnostic
        product = {
          id                  = "unified-ai-product"
          display_name        = "Unified AI Gateway"
          description         = "Unified AI Gateway product - provides access to all AI model providers through a single wildcard endpoint."
          subscriptions_limit = 10
          policy_xml          = file("${local.apis_dir}/unified-ai-api/unified-ai-product-subscription.xml")
        }
      }
    } : {},
    var.features.ai_model_inference ? {
      "ai-model-inference-api" = {
        api = {
          name                   = "ai-model-inference-api"
          display_name           = "AI Model Inference API"
          description            = "Azure AI Model Inference unified API"
          path                   = "ai-inference"
          subscription_required  = true
          subscription_key_names = local.api_key_names
          spec                   = { format = "openapi", value = file("${local.apis_dir}/ai-model-inference-api/ai-model-inference-api-spec.yaml") }
          policy_xml             = file("${local.apis_dir}/ai-model-inference-api/ai-model-inference-api-policy.xml")
        }
      }
    } : {},
    var.features.openai_realtime ? {
      # WebSocket APIs don't accept an API-scope policy: openai-realtime-policy.xml
      # belongs on the operation scope of the upgraded WebSocket operation.
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
            subscriptionRequired          = local.subscription_required
            protocols                     = ["wss"]
            serviceUrl                    = "wss://to-be-replaced-by-policy"
            subscriptionKeyParameterNames = local.api_key_names
          })
        }
      }
    } : {},
  )

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
  }
  llm_apis = { for k, v in local.llm_apis_raw : k => merge(local.api_entry_defaults, v, { api = merge(local.api_defaults, v.api) }) }

  # APIM validates fragment / named-value references when a policy is saved.
  api_policy_depends_on = concat(
    values(module.llm_fragments.ids),
    values(module.llm_routing.fragment_ids),
  )
}

module "llm_api" {
  source   = "../../modules/gateway-api"
  for_each = local.llm_apis

  api_management_id   = local.apim_id
  api_management_name = local.apim_name
  resource_group_name = local.resource_group_name

  api                      = each.value.api
  operation_policies       = each.value.operation_policies
  azapi_operation_policies = each.value.azapi_operation_policies
  app_insights_diagnostic  = each.value.app_insights_diagnostic
  azure_monitor_diagnostic = each.value.azure_monitor_diagnostic
  product                  = each.value.product
  policy_depends_on        = local.api_policy_depends_on
}
