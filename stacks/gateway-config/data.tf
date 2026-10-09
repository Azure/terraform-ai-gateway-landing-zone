# Everything below is owned by stacks/platform (or stacks/identity) and found
# by its deterministic name (modules/naming): no remote state.

data "azurerm_api_management" "this" {
  name                = local.names.apim
  resource_group_name = local.names.resource_group
}

data "azurerm_user_assigned_identity" "apim" {
  name                = local.names.uami_apim
  resource_group_name = local.names.resource_group
}

# The Language / Content Safety endpoint comes from the primary Foundry account, a
# standalone account of stacks/platform (found by name) or an explicit URL.
data "azurerm_cognitive_account" "primary" {
  count = (
    (var.features.pii_redaction && var.pii_service.source == "foundry") ||
    (var.features.content_safety && var.content_safety_service.source == "foundry")
  ) ? 1 : 0
  name                = module.naming.foundry_account_names[0]
  resource_group_name = local.names.resource_group
}

data "azurerm_cognitive_account" "language" {
  count               = var.features.pii_redaction && var.pii_service.source == "dedicated" ? 1 : 0
  name                = local.names.language_service
  resource_group_name = local.names.resource_group
}

data "azurerm_cognitive_account" "content_safety" {
  count               = var.features.content_safety && var.content_safety_service.source == "dedicated" ? 1 : 0
  name                = local.names.content_safety
  resource_group_name = local.names.resource_group
}

data "azapi_resource" "api_center" {
  count     = var.features.api_center_onboarding ? 1 : 0
  type      = "Microsoft.ApiCenter/services@2024-03-01"
  name      = local.names.api_center
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.names.resource_group}"
}

data "azuread_client_config" "current" {}

# The gateway app of stacks/identity (only when its values aren't given explicitly).
data "azuread_application" "gateway" {
  count        = var.entra_auth.enabled && var.entra_auth.client_id == null ? 1 : 0
  display_name = local.names.gateway_app
}

locals {
  apim_id             = data.azurerm_api_management.this.id
  apim_name           = data.azurerm_api_management.this.name
  resource_group_name = data.azurerm_api_management.this.resource_group_name

  # Logger names are a contract with platform's apim-telemetry module.
  app_insights_logger_id  = "${local.apim_id}/loggers/appinsights-logger"
  azure_monitor_logger_id = "${local.apim_id}/loggers/azuremonitor"

  foundry_endpoint = try(data.azurerm_cognitive_account.primary[0].endpoint, "")

  pii_endpoint = {
    foundry   = local.foundry_endpoint
    dedicated = try(data.azurerm_cognitive_account.language[0].endpoint, "")
    url       = var.pii_service.url != null ? var.pii_service.url : ""
  }[var.pii_service.source]

  content_safety_endpoint = {
    foundry   = local.foundry_endpoint
    dedicated = try(data.azurerm_cognitive_account.content_safety[0].endpoint, "")
    url       = var.content_safety_service.url != null ? var.content_safety_service.url : ""
  }[var.content_safety_service.source]

  entra = {
    tenant_id = coalesce(var.entra_auth.tenant_id, data.azuread_client_config.current.tenant_id)
    client_id = var.entra_auth.client_id != null ? var.entra_auth.client_id : try(data.azuread_application.gateway[0].client_id, "")
    audience  = var.entra_auth.audience != null ? var.entra_auth.audience : try(tolist(data.azuread_application.gateway[0].identifier_uris)[0], "")
  }
}
