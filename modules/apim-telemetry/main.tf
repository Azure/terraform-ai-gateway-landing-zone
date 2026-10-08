# =============================================================================
# APIM TELEMETRY — loggers (Application Insights, Azure Monitor, Event Hub ×2),
# the service-level Application Insights diagnostic (+ metrics flag) and the
# service diagnostic setting to Log Analytics. Moved from modules/apim (Phase 1).
# =============================================================================

locals {
  # APIM logger `endpointAddress` expects hostname (optionally with :port), not a
  # URL. Bicep does: replace(eventHubEndpoint, 'https://', ''). Terraform's
  # azurerm_api_management_logger.eventhub.endpoint_uri is forwarded verbatim,
  # so we strip the scheme + any trailing slash/port suffix here.
  eventhub_hostname = replace(replace(var.eventhub_endpoint_uri, "https://", ""), "/", "")
}

# -----------------------------------------------------------------------------
# APIM LOGGER: Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_api_management_logger" "app_insights" {
  name                = "appinsights-logger"
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  resource_id         = var.app_insights_id

  application_insights {
    # Bicep parity: prefer connection_string (correlates region+resource) when
    # available; fall back to instrumentation_key.
    connection_string   = var.app_insights_connection_string != "" ? var.app_insights_connection_string : null
    instrumentation_key = var.app_insights_connection_string == "" ? var.app_insights_instrumentation_key : null
  }
}

# -----------------------------------------------------------------------------
# APIM LOGGER: Azure Monitor (Bicep parity — required for the `azureMonitor`
# diagnostic destination on inference APIs). Not exposed by azurerm.
#
# APIM can materialise the `azuremonitor` logger server-side, so a create with
# azapi_resource (GET-before-create) fails with "already exists", and an
# import {} block can't target a logger whose APIM doesn't exist yet
# (greenfield). An ARM PUT is idempotent (exists => update, missing =>
# create), so the logger is upserted with azapi_resource_action: declarative,
# uses the provider's credentials, no az CLI / shell. It re-runs whenever the
# APIM ID or the body changes. Nothing is deleted on destroy (the logger goes
# with the APIM service).
# -----------------------------------------------------------------------------

resource "azapi_resource_action" "azure_monitor_logger" {
  type        = "Microsoft.ApiManagement/service/loggers@2024-05-01"
  resource_id = "${var.api_management_id}/loggers/azuremonitor"
  method      = "PUT"

  body = {
    properties = {
      loggerType  = "azureMonitor"
      description = "Azure Monitor logger for gateway diagnostics"
    }
  }
}

# -----------------------------------------------------------------------------
# APIM LOGGER: Event Hub (for usage streaming)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_logger" "eventhub" {
  name                = "usage-eventhub-logger"
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  eventhub {
    name                             = var.eventhub_usage_hub_name
    endpoint_uri                     = local.eventhub_hostname
    user_assigned_identity_client_id = var.managed_identity_client_id
  }
}

resource "azurerm_api_management_logger" "pii_eventhub" {
  count               = var.enable_pii_redaction ? 1 : 0
  name                = "pii-usage-eventhub-logger"
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  eventhub {
    name                             = var.eventhub_pii_hub_name
    endpoint_uri                     = local.eventhub_hostname
    user_assigned_identity_client_id = var.managed_identity_client_id
  }
}

# -----------------------------------------------------------------------------
# APIM DIAGNOSTIC SETTINGS (API-level logging verbosity)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_diagnostic" "global" {
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = var.api_management_name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id

  sampling_percentage   = 100
  always_log_errors     = true
  log_client_ip         = true
  verbosity             = var.log_verbosity
  operation_name_format = "Url"

  frontend_request {
    body_bytes = var.log_body_bytes
    headers_to_log = [
      "Content-Type", "User-Agent", "x-ms-client-request-id"
    ]
  }

  frontend_response {
    body_bytes     = var.log_body_bytes
    headers_to_log = ["Content-Type", "x-ms-request-id"]
  }

  backend_request {
    body_bytes = var.log_body_bytes
  }

  backend_response {
    body_bytes = var.log_body_bytes
  }
}

# -----------------------------------------------------------------------------
# Bicep parity: apim.bicep sets `metrics: true` on the service-level
# applicationinsights diagnostic. The azurerm provider does not expose this
# property, so we PATCH it here. Without this flag, `<emit-metric>` and
# `<llm-emit-token-metric>` policies execute successfully but APIM drops the
# samples before forwarding them to App Insights (no customMetrics emitted).
# -----------------------------------------------------------------------------
resource "azapi_update_resource" "global_appinsights_metrics" {
  type        = "Microsoft.ApiManagement/service/diagnostics@2024-05-01"
  resource_id = "${var.api_management_id}/diagnostics/applicationinsights"

  body = {
    properties = {
      metrics = true
    }
  }

  depends_on = [azurerm_api_management_diagnostic.global]
}

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
#
# Azure Policy (DeployIfNotExists) auto-creates a diagnostic setting named
# `diag-<apim>` on APIM instances. Using azapi_resource_action with PUT sends
# an ARM "Create or Update" that succeeds whether the resource exists or not.
# -----------------------------------------------------------------------------

resource "azapi_resource_action" "apim_diagnostics" {
  type        = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  resource_id = "${var.api_management_id}/providers/Microsoft.Insights/diagnosticSettings/diag-${var.api_management_name}"
  method      = "PUT"

  body = {
    properties = {
      workspaceId                 = var.log_analytics_id
      logAnalyticsDestinationType = "Dedicated"
      logs = [
        { categoryGroup = "AllLogs", enabled = true }
      ]
      metrics = [
        { category = "AllMetrics", enabled = true }
      ]
    }
  }
}

