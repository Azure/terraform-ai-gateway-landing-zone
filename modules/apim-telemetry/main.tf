# =============================================================================
# APIM TELEMETRY — loggers (Application Insights, Azure Monitor, Event Hub ×2),
# the service-level Application Insights diagnostic (+ metrics flag) and the
# service diagnostic setting to Log Analytics.
# =============================================================================

locals {
  # APIM logger `endpointAddress` expects the hostname (optionally with :port), not a URL.
  eventhub_hostname = replace(replace(var.eventhub_endpoint_uri, "https://", ""), "/", "")
}

# -----------------------------------------------------------------------------
# APIM LOGGER: Application Insights
# -----------------------------------------------------------------------------

locals {
  # Connection string (correlates region + resource), else the instrumentation key. With
  # app_insights_managed_identity the logger also authenticates with the APIM identity (Microsoft
  # Entra ingestion), so the connection string can't send telemetry on its own. With
  # credentials_in_key_vault both are {{references}} to Key Vault-backed named values.
  app_insights_credentials = merge(
    local.uses_connection_string ? { connectionString = local.connection_string_ref } : { instrumentationKey = var.app_insights_instrumentation_key },
    var.app_insights_managed_identity ? { identityClientId = local.identity_client_id_ref } : {},
  )
}

# azapi: azurerm only accepts a literal UUID as the identity client ID. An idempotent PUT (like
# the azuremonitor logger below) rather than azapi_resource: when the connection string is a
# {{reference}}, APIM reads the logger back with identityClientId = that same reference (it
# authenticates with the configured identity), which a resource would report as drift on every
# plan. The PUT re-runs whenever the body changes.
resource "azapi_resource_action" "app_insights_logger" {
  type        = "Microsoft.ApiManagement/service/loggers@2024-05-01"
  resource_id = "${var.api_management_id}/loggers/appinsights-logger"
  method      = "PUT"

  body = {
    properties = {
      loggerType  = "applicationInsights"
      description = "Application Insights logger"
      resourceId  = var.app_insights_id
      credentials = local.app_insights_credentials
    }
  }

  # The {{references}} must resolve when the logger is saved.
  depends_on = [azurerm_api_management_named_value.logger_credential]

  lifecycle {
    precondition {
      condition     = !var.app_insights_managed_identity || var.app_insights_connection_string != ""
      error_message = "app_insights_managed_identity needs app_insights_connection_string: managed identity ingestion isn't possible with an instrumentation key alone."
    }
    precondition {
      condition     = !local.credentials_in_key_vault || local.uses_connection_string
      error_message = "credentials_in_key_vault needs app_insights_connection_string: an instrumentation key can't be a Key Vault reference."
    }
    precondition {
      condition     = !local.credentials_in_key_vault || var.credentials_key_vault_id != null
      error_message = "credentials_in_key_vault needs credentials_key_vault_id."
    }
  }
}

# -----------------------------------------------------------------------------
# APIM LOGGER: Azure Monitor (required for the `azureMonitor`
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
# APIM LOGGERS: Event Hub (usage and PII events), managed identity (no SAS).
# azapi: azurerm only accepts a literal UUID as the identity client ID, and the
# Key Vault option (credentials_in_key_vault) passes a {{named value}} reference.
# The names are a contract: the fragments' log-to-eventhub logger-id.
# -----------------------------------------------------------------------------

locals {
  eventhub_loggers = merge(
    { "usage-eventhub-logger" = { hub = var.eventhub_usage_hub_name, description = "AI usage events" } },
    var.enable_pii_redaction ? { "pii-usage-eventhub-logger" = { hub = var.eventhub_pii_hub_name, description = "PII processing events" } } : {},
  )
}

resource "azapi_resource" "eventhub_logger" {
  for_each = local.eventhub_loggers

  type      = "Microsoft.ApiManagement/service/loggers@2024-05-01"
  name      = each.key
  parent_id = var.api_management_id

  body = {
    properties = {
      loggerType  = "azureEventHub"
      description = each.value.description
      credentials = {
        name             = each.value.hub
        endpointAddress  = local.eventhub_hostname
        identityClientId = local.identity_client_id_ref
      }
    }
  }

  # The {{reference}} must resolve when the logger is saved.
  depends_on = [azurerm_api_management_named_value.logger_credential]
}

# -----------------------------------------------------------------------------
# APIM DIAGNOSTIC SETTINGS (API-level logging verbosity)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_diagnostic" "global" {
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = var.api_management_name
  api_management_logger_id = azapi_resource_action.app_insights_logger.resource_id

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
# The azurerm provider does not expose this
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
  count       = var.enable_diagnostics ? 1 : 0
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
