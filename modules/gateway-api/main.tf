# =============================================================================
# GATEWAY API — publishes one API on API Management with its policy,
# operation policies, diagnostics and (optionally) a product.
# Replaces the near-identical universal-llm-api / azure-openai-api /
# unified-ai-api submodules and the inline APIs of modules/apim (Phase 1).
# =============================================================================

locals {
  is_http = var.api.type == "http"
}

# --- API ---------------------------------------------------------------------

resource "azurerm_api_management_api" "this" {
  count = local.is_http ? 1 : 0

  name                  = var.api.name
  display_name          = var.api.display_name
  description           = var.api.description
  resource_group_name   = var.resource_group_name
  api_management_name   = var.api_management_name
  revision              = "1"
  path                  = var.api.path
  protocols             = var.api.protocols
  api_type              = "http"
  service_url           = var.api.service_url
  subscription_required = var.api.subscription_required

  dynamic "subscription_key_parameter_names" {
    for_each = var.api.subscription_key_names == null ? [] : [var.api.subscription_key_names]
    content {
      header = subscription_key_parameter_names.value.header
      query  = subscription_key_parameter_names.value.query
    }
  }

  dynamic "import" {
    for_each = var.api.spec == null ? [] : [var.api.spec]
    content {
      content_format = import.value.format
      content_value  = import.value.value
    }
  }

  depends_on = [var.api_depends_on]
}

# WebSocket and MCP APIs: azurerm doesn't model them.
resource "azapi_resource" "this" {
  count = local.is_http ? 0 : 1

  type                      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name                      = var.api.name
  parent_id                 = var.api_management_id
  schema_validation_enabled = var.api.azapi_schema_validation

  body = {
    properties = jsondecode(var.api.azapi_properties_json)
  }

  depends_on = [var.api_depends_on]
}

locals {
  api_id   = local.is_http ? azurerm_api_management_api.this[0].id : azapi_resource.this[0].id
  api_name = local.is_http ? azurerm_api_management_api.this[0].name : azapi_resource.this[0].name
}

# --- API policy ----------------------------------------------------------------

resource "azurerm_api_management_api_policy" "this" {
  count = local.is_http && var.api.policy_xml != null ? 1 : 0

  api_name            = azurerm_api_management_api.this[0].name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content         = var.api.policy_xml

  depends_on = [var.policy_depends_on]
}

# WebSocket APIs don't accept an API-scope policy ("Not allowed at 'Api' scope
# for 'WEBSOCKET' api type"), so pass policy_xml = null for them.
resource "azapi_resource" "policy" {
  count = !local.is_http && var.api.policy_xml != null ? 1 : 0

  type      = "Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = azapi_resource.this[0].id

  body = {
    properties = {
      format = "rawxml"
      value  = var.api.policy_xml
    }
  }

  depends_on = [var.policy_depends_on]
}

# --- Operation policies --------------------------------------------------------

resource "azurerm_api_management_api_operation_policy" "this" {
  for_each = var.operation_policies

  api_name            = azurerm_api_management_api.this[0].name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  operation_id        = each.key
  xml_content         = each.value

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_depends_on,
  ]
}

resource "azapi_resource" "operation_policy" {
  for_each = var.azapi_operation_policies

  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = "${local.api_id}/operations/${each.key}"

  body = {
    properties = {
      format = "rawxml"
      value  = each.value
    }
  }

  depends_on = [
    azurerm_api_management_api.this,
    var.policy_depends_on,
  ]
}

# --- Diagnostics ---------------------------------------------------------------

resource "azurerm_api_management_api_diagnostic" "app_insights" {
  count = var.app_insights_diagnostic == null ? 0 : 1

  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = var.api_management_name
  api_name                 = local.api_name
  api_management_logger_id = var.app_insights_diagnostic.logger_id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = var.app_insights_diagnostic.verbosity
  http_correlation_protocol = var.app_insights_diagnostic.http_correlation_protocol

  frontend_request {
    body_bytes     = var.app_insights_diagnostic.body_bytes
    headers_to_log = var.app_insights_diagnostic.headers
  }
  frontend_response {
    body_bytes     = var.app_insights_diagnostic.body_bytes
    headers_to_log = var.app_insights_diagnostic.headers
  }
  backend_request {
    body_bytes     = var.app_insights_diagnostic.body_bytes
    headers_to_log = var.app_insights_diagnostic.headers
  }
  backend_response {
    body_bytes     = var.app_insights_diagnostic.body_bytes
    headers_to_log = var.app_insights_diagnostic.headers
  }
}

# Bicep parity: `metrics: true` on the API-level applicationinsights diagnostic.
# azurerm doesn't expose it; without it <emit-metric>/<llm-emit-token-metric>
# samples are dropped.
resource "azapi_update_resource" "app_insights_metrics" {
  count = var.app_insights_diagnostic == null ? 0 : 1

  type        = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  resource_id = "${local.api_id}/diagnostics/applicationinsights"

  body = {
    properties = {
      metrics = true
    }
  }

  depends_on = [azurerm_api_management_api_diagnostic.app_insights]
}

# azurerm doesn't surface the largeLanguageModel block of the azuremonitor
# diagnostic, so it is managed with azapi.
resource "azapi_resource" "azure_monitor_diagnostic" {
  count = var.azure_monitor_diagnostic == null ? 0 : 1

  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  name      = "azuremonitor"
  parent_id = local.api_id

  body = {
    properties = var.azure_monitor_diagnostic.properties
  }

  response_export_values = var.azure_monitor_diagnostic.response_export_values

  depends_on = [var.policy_depends_on]
}

# --- Product -----------------------------------------------------------------

resource "azurerm_api_management_product" "this" {
  count = var.product == null ? 0 : 1

  product_id            = var.product.id
  display_name          = var.product.display_name
  description           = var.product.description
  api_management_name   = var.api_management_name
  resource_group_name   = var.resource_group_name
  subscription_required = true
  approval_required     = false
  subscriptions_limit   = var.product.subscriptions_limit
  published             = true
}

resource "azurerm_api_management_product_api" "this" {
  count = var.product == null ? 0 : 1

  api_name            = local.api_name
  product_id          = azurerm_api_management_product.this[0].product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_api_management_product_policy" "this" {
  count = var.product == null ? 0 : (var.product.policy_xml == null ? 0 : 1)

  product_id          = azurerm_api_management_product.this[0].product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content         = var.product.policy_xml
}
