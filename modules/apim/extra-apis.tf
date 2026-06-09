# =============================================================================
# APIM — Unified AI wildcard API + Extra APIs + MCP servers
# Bicep parity:
#   unified-ai-api.bicep, inference-api.bicep (extra types),
#   apim.bicep (aiSearchApi, openAIRealtimeApi, docIntelApi×2, aiModelInferenceApi,
#   weatherApi, weatherMcp, msLearnMcp)
# =============================================================================

locals {
  ai_search_spec_path = "${path.module}/ai-search-api/ai-search-index-2024-07-01-api-spec.json"
  # Bicep uses the compressed YAML variant. The full JSON spec exceeds APIM's
  # import size/complexity limit and triggers ValidationError 400.
  doc_intel_spec_path = "${path.module}/doc-intel-api/document-intelligence-2024-11-30-compressed.openapi.yaml"
}

# -----------------------------------------------------------------------------
# UNIFIED AI WILDCARD API (sub-module)
# Bicep parity: ./unified-ai-api.bicep called from apim.bicep with
# `enabled = enableUnifiedAiApi`. The submodule imports UnifiedAIWildcard.json
# so the wildcard catch-all + `deployments` / `deployment-by-name` operations
# are present, and creates the unified-ai product + product-API binding +
# product policy + azuremonitor diagnostic with LLM logs.
# -----------------------------------------------------------------------------

module "unified_ai" {
  source = "./unified-ai-api"
  count  = var.enable_unified_ai_api ? 1 : 0

  apim_name             = azurerm_api_management.citadel.name
  apim_id               = azurerm_api_management.citadel.id
  resource_group_name   = var.resource_group_name
  subscription_required = true

  openapi_spec_path                     = "${path.module}/unified-ai-api/UnifiedAIWildcard.json"
  policy_xml_path                       = "${path.module}/policies/unified-ai-api-policy.xml"
  deployments_op_policy_xml_path        = "${path.module}/policies/unified-ai-api-deployments-policy.xml"
  deployment_by_name_op_policy_xml_path = "${path.module}/policies/unified-ai-api-deployment-by-name-policy.xml"
  product_policy_xml_path               = "${path.module}/policies/unified-ai-product-subscription.xml"

  azure_monitor_logger_id = "${azurerm_api_management.citadel.id}/loggers/azuremonitor"

  policy_dependencies = [
    azurerm_api_management_policy_fragment.static,
    azurerm_api_management_policy_fragment.set_backend_pools,
    azurerm_api_management_policy_fragment.get_available_models,
    azurerm_api_management_policy_fragment.metadata_config,
    azurerm_api_management_named_value.uami_client_id,
    azurerm_api_management_named_value.entra_tenant_id,
    azurerm_api_management_named_value.entra_client_id,
    azurerm_api_management_named_value.entra_audience,
    azurerm_api_management_named_value.entra_auth_flag,
    terraform_data.azure_monitor_logger_posix,
    terraform_data.azure_monitor_logger_windows,
  ]
}

# -----------------------------------------------------------------------------
# AI SEARCH API (enable_azure_ai_search)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api" "ai_search" {
  count               = var.enable_azure_ai_search ? 1 : 0
  name                = "azure-ai-search-index-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.citadel.name
  display_name        = "Azure AI Search Index API (index services)"
  description         = "Azure AI Search Index Client APIs"
  revision            = "1"
  path                = "search"
  protocols           = ["https"]
  service_url         = "https://to-be-replaced-by-policy"

  # Bicep parity: api.bicep `subscriptionRequired = entraAuth ? false : true`.
  subscription_required = !var.entra_auth_enabled

  # Bicep parity: api.bicep only sets the header name (subscriptionKeyName='api-key');
  # azurerm requires both header and query, so we mirror them.
  subscription_key_parameter_names {
    header = "api-key"
    query  = "api-key"
  }

  import {
    content_format = "openapi+json"
    content_value  = file(local.ai_search_spec_path)
  }
}

resource "azurerm_api_management_api_policy" "ai_search" {
  count               = var.enable_azure_ai_search ? 1 : 0
  api_name            = azurerm_api_management_api.ai_search[0].name
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/policies/ai-search-index-api-policy.xml")
}

# -----------------------------------------------------------------------------
# DOCUMENT INTELLIGENCE — legacy (formrecognizer) + current (documentintelligence)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api" "doc_intelligence_legacy" {
  count               = var.enable_document_intelligence ? 1 : 0
  name                = "document-intelligence-api-legacy"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.citadel.name
  display_name        = "Document Intelligence API (Legacy)"
  description         = "Uses (/formrecognizer) url path. Extracts content, layout, and structured data from documents."
  revision            = "1"
  path                = "formrecognizer"
  protocols           = ["https"]
  service_url         = "https://to-be-replaced-by-policy"

  subscription_required = !var.entra_auth_enabled

  # Bicep parity: subscriptionKeyName='Ocp-Apim-Subscription-Key'.
  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }

  import {
    content_format = "openapi"
    content_value  = file(local.doc_intel_spec_path)
  }
}

resource "azurerm_api_management_api_policy" "doc_intelligence_legacy" {
  count               = var.enable_document_intelligence ? 1 : 0
  api_name            = azurerm_api_management_api.doc_intelligence_legacy[0].name
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/policies/doc-intelligence-api-policy.xml")
}

resource "azurerm_api_management_api" "doc_intelligence" {
  count               = var.enable_document_intelligence ? 1 : 0
  name                = "document-intelligence-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.citadel.name
  display_name        = "Document Intelligence API"
  description         = "Uses (/documentintelligence) url path. Extracts content, layout, and structured data from documents."
  revision            = "1"
  path                = "documentintelligence"
  protocols           = ["https"]
  service_url         = "https://to-be-replaced-by-policy"

  subscription_required = !var.entra_auth_enabled

  # Bicep parity: subscriptionKeyName='Ocp-Apim-Subscription-Key'.
  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }

  import {
    content_format = "openapi"
    content_value  = file(local.doc_intel_spec_path)
  }

  # Serialize Doc Intel imports. Importing the same large spec twice in
  # parallel intermittently trips APIM validation (400).
  depends_on = [azurerm_api_management_api.doc_intelligence_legacy]
}

resource "azurerm_api_management_api_policy" "doc_intelligence" {
  count               = var.enable_document_intelligence ? 1 : 0
  api_name            = azurerm_api_management_api.doc_intelligence[0].name
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/policies/doc-intelligence-api-policy.xml")
}

# -----------------------------------------------------------------------------
# AI MODEL INFERENCE API
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api" "ai_model_inference" {
  count               = var.enable_ai_model_inference ? 1 : 0
  name                = "ai-model-inference-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.citadel.name
  display_name        = "Azure AI Model Inference API"
  description         = "Azure AI Model Inference unified API"
  revision            = "1"
  path                = "ai-inference"
  protocols           = ["https"]
  subscription_required = true

  subscription_key_parameter_names {
    header = "api-key"
    query  = "api-key"
  }

  import {
    content_format = "openapi"
    content_value  = file("${path.module}/ai-model-inference/ai-model-inference-api-spec.yaml")
  }
}

resource "azurerm_api_management_api_policy" "ai_model_inference" {
  count               = var.enable_ai_model_inference ? 1 : 0
  api_name            = azurerm_api_management_api.ai_model_inference[0].name
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/policies/ai-model-inference-api-policy.xml")
}

# -----------------------------------------------------------------------------
# OPENAI REALTIME (WebSocket) — created via azapi (azurerm doesn't model WS APIs)
# -----------------------------------------------------------------------------

resource "azapi_resource" "openai_realtime" {
  count     = var.enable_openai_realtime ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name      = "openai-realtime-ws-api"
  parent_id = azurerm_api_management.citadel.id

  body = {
    properties = {
      apiType              = "websocket"
      displayName          = "Azure OpenAI Realtime API"
      description          = "Access Azure OpenAI Realtime API for real-time voice and text conversion."
      type                 = "websocket"
      path                 = "openai/realtime"
      apiRevision          = "1"
      subscriptionRequired = !var.entra_auth_enabled
      protocols            = ["wss"]
      serviceUrl           = "wss://to-be-replaced-by-policy"
      subscriptionKeyParameterNames = {
        header = "api-key"
        query  = "api-key"
      }
    }
  }
}

resource "azapi_resource" "openai_realtime_policy" {
  # NOTE: Api-scope policies are not supported for WebSocket APIs
  # ("Not allowed at 'Api' scope for 'WEBSOCKET' api type").
  # Realtime policy must be attached at the operation scope on the upgraded
  # API variant, not here. Keep disabled until that path is ported.
  count     = 0
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = azapi_resource.openai_realtime[0].id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/openai-realtime-policy.xml")
    }
  }
}

# -----------------------------------------------------------------------------
# SAMPLE: WEATHER API + MCP (is_mcp_sample_deployed)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api" "weather" {
  count               = var.is_mcp_sample_deployed ? 1 : 0
  name                = "weather-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.citadel.name
  display_name        = "Weather API"
  description         = "Sample Weather API used to demonstrate the MCP-from-API pattern."
  revision            = "1"
  path                = "weather"
  protocols           = ["https"]
  subscription_required = false

  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/sample/weather/openapi.json")
  }
}

resource "azurerm_api_management_api_policy" "weather" {
  count               = var.is_mcp_sample_deployed ? 1 : 0
  api_name            = azurerm_api_management_api.weather[0].name
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/sample/weather/policy.xml")
}

# MCP server derived FROM the weather API (mcp-from-api.bicep).
# The source weather API defines a single operation `get-weather`; mirror the
# Bicep `operationNames: ['get-weather']` list here. Azure rejects the PUT
# with "MCP tools collection cannot be empty" if mcpTools is [].
locals {
  weather_mcp_operation_ids = ["get-weather"]
}

resource "azapi_resource" "weather_mcp" {
  count     = var.is_mcp_sample_deployed ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name      = "weather-mcp"
  parent_id = azurerm_api_management.citadel.id

  schema_validation_enabled = false

  body = {
    properties = {
      type                 = "mcp"
      displayName          = "Weather MCP"
      description          = "MCP server derived from the Weather sample API."
      subscriptionRequired = false
      path                 = "weather-mcp"
      protocols            = ["https"]
      mcpTools = [
        for op_id in local.weather_mcp_operation_ids : {
          name = op_id
          # Must reference the API without the `;rev=X` suffix that Terraform's
          # id attribute includes, otherwise APIM rejects with
          # "Tools must come from a single existing HTTP API."
          operationId = "${azurerm_api_management.citadel.id}/apis/${azurerm_api_management_api.weather[0].name}/operations/${op_id}"
          description = "Weather MCP tool derived from ${op_id}"
        }
      ]
    }
  }

  depends_on = [azurerm_api_management_api.weather]
}

resource "azapi_resource" "weather_mcp_policy" {
  count     = var.is_mcp_sample_deployed ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = azapi_resource.weather_mcp[0].id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/mcp-default-policy.xml")
    }
  }
}

# MS Learn MCP — registering an external MCP endpoint (mcp-existing.bicep)
resource "azapi_resource" "ms_learn_mcp_backend" {
  count     = var.is_mcp_sample_deployed ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "ms-learn-mcp-backend"
  parent_id = azurerm_api_management.citadel.id

  body = {
    properties = {
      description = "MS Learn MCP server backend"
      url         = var.ms_learn_mcp_backend_url
      protocol    = "http"
    }
  }
}

resource "azapi_resource" "ms_learn_mcp" {
  count     = var.is_mcp_sample_deployed ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name      = "ms-learn-mcp"
  parent_id = azurerm_api_management.citadel.id

  schema_validation_enabled = false

  body = {
    properties = {
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
    }
  }

  depends_on = [azapi_resource.ms_learn_mcp_backend]
}

resource "azapi_resource" "ms_learn_mcp_policy" {
  count     = var.is_mcp_sample_deployed ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = azapi_resource.ms_learn_mcp[0].id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/mcp-default-policy.xml")
    }
  }
}

# =============================================================================
# Per-API DIAGNOSTICS for the Bicep-parity APIs (api.bicep `apiDiagnostics` +
# `apiDiagnosticsAppInsights`).
#
# In api.bicep these are gated by `enableAPIDiagnostics && enableAPIDeployment
# && !isWebSotcketAPI`. The four apim.bicep callers that route through
# api.bicep (AI Search, Doc Intel ×2, OpenAI Realtime) all pass
# enableAPIDiagnostics=false, so we mirror that default via
# `var.enable_extra_api_diagnostics` (default false). OpenAI Realtime is a
# WebSocket API and is excluded from per-API diagnostics in Bicep, so we
# exclude it here too.
#
# `azurerm_api_management_api_diagnostic` does not surface the
# `largeLanguageModel` block that Bicep `azuremonitor` includes, so the
# azuremonitor diagnostic is created via `azapi_resource` for full parity.
# =============================================================================

locals {
  extra_api_diag_enabled = var.enable_extra_api_diagnostics ? 1 : 0
  extra_api_diag_log_settings = {
    headers = var.extra_api_log_settings.headers
    body    = { bytes = var.extra_api_log_settings.body.bytes }
  }
  extra_api_diag_llm_block = {
    logs = "enabled"
    requests = {
      messages       = "all"
      maxSizeInBytes = 262144
    }
    responses = {
      messages       = "all"
      maxSizeInBytes = 262144
    }
  }
  azuremonitor_logger_id = "${azurerm_api_management.citadel.id}/loggers/azuremonitor"
}

# -----------------------------------------------------------------------------
# AI SEARCH
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_diagnostic" "ai_search_appinsights" {
  count                    = (var.enable_azure_ai_search && var.enable_extra_api_diagnostics) ? 1 : 0
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = azurerm_api_management.citadel.name
  api_name                 = azurerm_api_management_api.ai_search[0].name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  frontend_response {
    body_bytes = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  backend_request {
    body_bytes = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  backend_response {
    body_bytes = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
}

# Bicep parity: enable `metrics: true` on the App Insights diagnostic so
# `<emit-metric>` / `<llm-emit-token-metric>` samples reach customMetrics.
# The azurerm provider doesn't expose this property.
resource "azapi_update_resource" "ai_search_appinsights_metrics" {
  count       = (var.enable_azure_ai_search && var.enable_extra_api_diagnostics) ? 1 : 0
  type        = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  resource_id = "${azurerm_api_management_api.ai_search[0].id}/diagnostics/applicationinsights"

  body = {
    properties = {
      metrics = true
    }
  }

  depends_on = [azurerm_api_management_api_diagnostic.ai_search_appinsights]
}

resource "azapi_resource" "ai_search_azuremonitor" {
  count     = (var.enable_azure_ai_search && var.enable_extra_api_diagnostics) ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  name      = "azuremonitor"
  parent_id = azurerm_api_management_api.ai_search[0].id

  body = {
    properties = {
      alwaysLog   = "allErrors"
      verbosity   = "Information"
      logClientIp = true
      loggerId    = local.azuremonitor_logger_id
      sampling = {
        samplingType = "fixed"
        percentage   = 100
      }
      frontend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
      backend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
      largeLanguageModel = local.extra_api_diag_llm_block
    }
  }

  depends_on = [
    terraform_data.azure_monitor_logger_posix,
    terraform_data.azure_monitor_logger_windows,
  ]
}

# -----------------------------------------------------------------------------
# DOC INTELLIGENCE (LEGACY /formrecognizer)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_diagnostic" "doc_intelligence_legacy_appinsights" {
  count                    = (var.enable_document_intelligence && var.enable_extra_api_diagnostics) ? 1 : 0
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = azurerm_api_management.citadel.name
  api_name                 = azurerm_api_management_api.doc_intelligence_legacy[0].name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  frontend_response {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  backend_request {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  backend_response {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
}

# Bicep parity: enable `metrics: true` on the App Insights diagnostic.
resource "azapi_update_resource" "doc_intelligence_legacy_appinsights_metrics" {
  count       = (var.enable_document_intelligence && var.enable_extra_api_diagnostics) ? 1 : 0
  type        = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  resource_id = "${azurerm_api_management_api.doc_intelligence_legacy[0].id}/diagnostics/applicationinsights"

  body = {
    properties = {
      metrics = true
    }
  }

  depends_on = [azurerm_api_management_api_diagnostic.doc_intelligence_legacy_appinsights]
}

resource "azapi_resource" "doc_intelligence_legacy_azuremonitor" {
  count     = (var.enable_document_intelligence && var.enable_extra_api_diagnostics) ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  name      = "azuremonitor"
  parent_id = azurerm_api_management_api.doc_intelligence_legacy[0].id

  body = {
    properties = {
      alwaysLog   = "allErrors"
      verbosity   = "Information"
      logClientIp = true
      loggerId    = local.azuremonitor_logger_id
      sampling = {
        samplingType = "fixed"
        percentage   = 100
      }
      frontend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
      backend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
      largeLanguageModel = local.extra_api_diag_llm_block
    }
  }

  depends_on = [
    terraform_data.azure_monitor_logger_posix,
    terraform_data.azure_monitor_logger_windows,
  ]
}

# -----------------------------------------------------------------------------
# DOC INTELLIGENCE (/documentintelligence)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_diagnostic" "doc_intelligence_appinsights" {
  count                    = (var.enable_document_intelligence && var.enable_extra_api_diagnostics) ? 1 : 0
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = azurerm_api_management.citadel.name
  api_name                 = azurerm_api_management_api.doc_intelligence[0].name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  frontend_response {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  backend_request {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
  backend_response {
    body_bytes     = var.extra_api_log_settings.body.bytes
    headers_to_log = var.extra_api_log_settings.headers
  }
}

# Bicep parity: enable `metrics: true` on the App Insights diagnostic.
resource "azapi_update_resource" "doc_intelligence_appinsights_metrics" {
  count       = (var.enable_document_intelligence && var.enable_extra_api_diagnostics) ? 1 : 0
  type        = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  resource_id = "${azurerm_api_management_api.doc_intelligence[0].id}/diagnostics/applicationinsights"

  body = {
    properties = {
      metrics = true
    }
  }

  depends_on = [azurerm_api_management_api_diagnostic.doc_intelligence_appinsights]
}

resource "azapi_resource" "doc_intelligence_azuremonitor" {
  count     = (var.enable_document_intelligence && var.enable_extra_api_diagnostics) ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  name      = "azuremonitor"
  parent_id = azurerm_api_management_api.doc_intelligence[0].id

  body = {
    properties = {
      alwaysLog   = "allErrors"
      verbosity   = "Information"
      logClientIp = true
      loggerId    = local.azuremonitor_logger_id
      sampling = {
        samplingType = "fixed"
        percentage   = 100
      }
      frontend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
      backend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
      largeLanguageModel = local.extra_api_diag_llm_block
    }
  }

  depends_on = [
    terraform_data.azure_monitor_logger_posix,
    terraform_data.azure_monitor_logger_windows,
  ]
}
