# =============================================================================
# Unified AI Wildcard API submodule
# Mirrors bicep/infra/modules/apim/unified-ai-api.bicep
#
# Bicep parity surfaces:
#   - Microsoft.ApiManagement/service/apis (api)              -> azurerm_api_management_api.this
#   - Microsoft.ApiManagement/service/apis/policies           -> azurerm_api_management_api_policy.this
#   - Microsoft.ApiManagement/service/products                -> azurerm_api_management_product.this
#   - Microsoft.ApiManagement/service/products/apis           -> azurerm_api_management_product_api.this
#   - Microsoft.ApiManagement/service/products/policies       -> azurerm_api_management_product_policy.this
#   - Microsoft.ApiManagement/service/apis/operations/policies (deployments,
#     deployment-by-name) — operations themselves come from the imported
#     OpenAPI spec (UnifiedAIWildcard.json).
#   - Microsoft.ApiManagement/service/apis/diagnostics (azuremonitor) with
#     largeLanguageModel logs (azapi — azurerm doesn't expose that block).
# =============================================================================

# -----------------------------------------------------------------------------
# API resource — Bicep parity: imports the OpenAPI spec so wildcard +
# `deployments` / `deployment-by-name` operations match exactly.
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
  import {
    content_format = "openapi+json"
    content_value  = file(var.openapi_spec_path)
  }
}

# -----------------------------------------------------------------------------
# API-level inbound policy (Bicep parity: unifiedAiApiPolicy / format='rawxml').
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_policy" "this" {
  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name

  xml_content = file(var.policy_xml_path)

  depends_on = [var.policy_dependencies]
}

# -----------------------------------------------------------------------------
# Product (Bicep parity: unifiedAiProduct) + product-API binding +
# product policy.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_product" "this" {
  product_id            = var.product_id
  display_name          = var.product_display_name
  description           = var.product_description
  api_management_name   = var.apim_name
  resource_group_name   = var.resource_group_name
  subscription_required = true
  approval_required     = false
  subscriptions_limit   = var.product_subscriptions_limit
  published             = true
}

resource "azurerm_api_management_product_api" "this" {
  api_name            = azurerm_api_management_api.this.name
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_api_management_product_policy" "this" {
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  xml_content         = file(var.product_policy_xml_path)
}

# -----------------------------------------------------------------------------
# Operation-level policies for deployments + deployment-by-name.
# Bicep parity: deploymentsOperationPolicy / deploymentByNameOperationPolicy.
# Uses azapi (mirrors the prior inline implementation) to avoid azurerm's
# operation-policy import validation that intermittently returns 400 during
# the PUT after a fresh OpenAPI import.
# -----------------------------------------------------------------------------

resource "azapi_resource" "deployments_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = "${azurerm_api_management_api.this.id}/operations/deployments"

  body = {
    properties = {
      format = "rawxml"
      value  = file(var.deployments_op_policy_xml_path)
    }
  }

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_dependencies,
  ]
}

resource "azapi_resource" "deployment_by_name_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = "${azurerm_api_management_api.this.id}/operations/deployment-by-name"

  body = {
    properties = {
      format = "rawxml"
      value  = file(var.deployment_by_name_op_policy_xml_path)
    }
  }

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_dependencies,
  ]
}

# -----------------------------------------------------------------------------
# Diagnostic: azuremonitor (Bicep parity: apiDiagnostics).
# Uses azapi because azurerm_api_management_api_diagnostic does not expose
# the `largeLanguageModel` block required for LLM request/response logging.
# Bicep gates on `length(apimLoggerId) > 0`; we do the same with a string
# compare so the diagnostic is skipped when the parent didn't supply a logger.
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
