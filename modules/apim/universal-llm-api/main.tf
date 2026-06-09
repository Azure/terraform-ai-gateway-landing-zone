# =============================================================================
# Universal LLM API submodule
# Mirrors bicep/infra/modules/apim/inference-api.bicep with
# inferenceAPIType='AzureAI' and the universal-llm wiring from apim.bicep.
#
# Bicep parity surfaces:
#   - Microsoft.ApiManagement/service/apis (api)            -> azurerm_api_management_api.this
#   - Microsoft.ApiManagement/service/apis/policies         -> azurerm_api_management_api_policy.this
#   - Microsoft.ApiManagement/service/apis/operations/policies (deployments,
#     deployment-by-name) — operations themselves come from the imported
#     OpenAPI spec (AIFoundryAzureAI.json), which provides all 7 paths:
#       /chat/completions, /embeddings, /images/embeddings,
#       /images/generations, /info, /deployments, /deployments/{deployment-id}
#   - Microsoft.ApiManagement/service/apis/diagnostics (azuremonitor)
#     including largeLanguageModel logs (azapi — azurerm doesn't expose LLM logs)
#   - Microsoft.ApiManagement/service/apis/diagnostics (applicationinsights)
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# API resource — Bicep parity: imports the OpenAPI spec so operations match
# the Bicep deployment exactly (chat/completions, embeddings, images/*, info,
# deployments, deployments/{deployment-id}).
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api" "this" {
  name                  = var.api_name
  display_name          = var.api_display_name
  description           = var.api_description
  resource_group_name   = var.resource_group_name
  api_management_name   = var.apim_name
  revision              = "1"
  path                  = var.api_path
  protocols             = ["https"]
  api_type              = "http"
  subscription_required = var.subscription_required

  subscription_key_parameter_names {
    header = "api-key"
    query  = "api-key"
  }

  # Bicep parity: format='openapi+json' + value=loadJsonContent(...).
  # Importing the spec here populates all operations from AIFoundryAzureAI.json.
  import {
    content_format = "openapi+json"
    content_value  = file(var.openapi_spec_path)
  }
}

# -----------------------------------------------------------------------------
# API-level inbound policy (Bicep parity: apiPolicy / format='rawxml').
# References policy fragments + named values defined in the parent module;
# `policy_dependencies` is forwarded so ordering is preserved.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_policy" "this" {
  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name

  xml_content = file(var.policy_xml_path)

  depends_on = [var.policy_dependencies]
}

# -----------------------------------------------------------------------------
# Operation-level policies for the two AI-Foundry-integration operations.
# Both reference the dynamic `get-available-models` fragment which only
# exists when llmBackendConfig has entries — gate via has_llm_backends.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_operation_policy" "deployments" {
  count = var.has_llm_backends && var.deployments_op_policy_xml_path != "" ? 1 : 0

  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  operation_id        = "deployments"
  xml_content         = file(var.deployments_op_policy_xml_path)

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_dependencies,
  ]
}

resource "azurerm_api_management_api_operation_policy" "deployment_by_name" {
  count = var.has_llm_backends && var.deployment_by_name_op_policy_xml_path != "" ? 1 : 0

  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  operation_id        = "deployment-by-name"
  xml_content         = file(var.deployment_by_name_op_policy_xml_path)

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_dependencies,
  ]
}

# -----------------------------------------------------------------------------
# OpenAIV1-only operations (Bicep parity: apim.bicep universalLlmListModels /
# universalLlmRetrieveModel). These operations only exist in
# AIFoundryOpenAIV1.json, so they are gated on inference_api_type == "OpenAIV1".
#   listModels    -> universal-llm-api-deployments-policy.xml
#   retrieveModel -> universal-llm-api-deployment-by-name-policy.xml
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_operation_policy" "list_models" {
  count = var.has_llm_backends && var.inference_api_type == "OpenAIV1" && var.list_models_op_policy_xml_path != "" ? 1 : 0

  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  operation_id        = "listModels"
  xml_content         = file(var.list_models_op_policy_xml_path)

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_dependencies,
  ]
}

resource "azurerm_api_management_api_operation_policy" "retrieve_model" {
  count = var.has_llm_backends && var.inference_api_type == "OpenAIV1" && var.retrieve_model_op_policy_xml_path != "" ? 1 : 0

  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  operation_id        = "retrieveModel"
  xml_content         = file(var.retrieve_model_op_policy_xml_path)

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_dependencies,
  ]
}

# -----------------------------------------------------------------------------
# Diagnostic: applicationinsights (Bicep parity: apiDiagnosticsAppInsights).
# Uses the azurerm provider since it natively supports per-API AI diagnostics.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_diagnostic" "app_insights" {
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = var.apim_name
  api_name                 = azurerm_api_management_api.this.name
  api_management_logger_id = var.app_insights_logger_id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "verbose"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes     = var.app_insights_log_settings.body.bytes
    headers_to_log = var.app_insights_log_settings.headers
  }

  frontend_response {
    body_bytes     = var.app_insights_log_settings.body.bytes
    headers_to_log = var.app_insights_log_settings.headers
  }

  backend_request {
    body_bytes     = var.app_insights_log_settings.body.bytes
    headers_to_log = var.app_insights_log_settings.headers
  }

  backend_response {
    body_bytes     = var.app_insights_log_settings.body.bytes
    headers_to_log = var.app_insights_log_settings.headers
  }
}

# Bicep parity: inference-api.bicep sets `metrics: true` on the per-API
# applicationinsights diagnostic. The azurerm provider does not expose this
# property, so we PATCH it here. Without this flag, `<llm-emit-token-metric>`
# (used by frag-set-llm-usage / frag-llm-usage) executes but APIM drops the
# samples before they reach App Insights customMetrics.
resource "azapi_update_resource" "app_insights_metrics" {
  type        = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  resource_id = "${azurerm_api_management_api.this.id}/diagnostics/applicationinsights"

  body = {
    properties = {
      metrics = true
    }
  }

  depends_on = [azurerm_api_management_api_diagnostic.app_insights]
}

# -----------------------------------------------------------------------------
# Diagnostic: azuremonitor (Bicep parity: apiDiagnostics).
# Uses azapi because azurerm_api_management_api_diagnostic does not expose
# the `largeLanguageModel` block required for LLM request/response logging.
# -----------------------------------------------------------------------------

resource "azapi_resource" "azure_monitor_diagnostic" {
  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  name      = "azuremonitor"
  parent_id = azurerm_api_management_api.this.id

  body = {
    properties = {
      alwaysLog   = "allErrors"
      verbosity   = "verbose"
      logClientIp = true
      loggerId    = var.azure_monitor_logger_id
      sampling = {
        samplingType = "fixed"
        percentage   = 100
      }
      frontend = {
        request = {
          headers = var.azure_monitor_log_settings.frontend.request.headers
          body    = { bytes = var.azure_monitor_log_settings.frontend.request.body.bytes }
        }
        response = {
          headers = var.azure_monitor_log_settings.frontend.response.headers
          body    = { bytes = var.azure_monitor_log_settings.frontend.response.body.bytes }
        }
      }
      backend = {
        request = {
          headers = var.azure_monitor_log_settings.backend.request.headers
          body    = { bytes = var.azure_monitor_log_settings.backend.request.body.bytes }
        }
        response = {
          headers = var.azure_monitor_log_settings.backend.response.headers
          body    = { bytes = var.azure_monitor_log_settings.backend.response.body.bytes }
        }
      }
      largeLanguageModel = {
        logs = var.azure_monitor_log_settings.largeLanguageModel.logs
        requests = {
          messages       = var.azure_monitor_log_settings.largeLanguageModel.requests.messages
          maxSizeInBytes = var.azure_monitor_log_settings.largeLanguageModel.requests.maxSizeInBytes
        }
        responses = {
          messages       = var.azure_monitor_log_settings.largeLanguageModel.responses.messages
          maxSizeInBytes = var.azure_monitor_log_settings.largeLanguageModel.responses.maxSizeInBytes
        }
      }
    }
  }

  response_export_values = []
}
