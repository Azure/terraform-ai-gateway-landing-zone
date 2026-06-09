# =============================================================================
# MODULE: Monitoring
# Log Analytics Workspace + Application Insights
# =============================================================================

# -----------------------------------------------------------------------------
# EXISTING LOG ANALYTICS DATA SOURCE
# -----------------------------------------------------------------------------

data "azurerm_log_analytics_workspace" "existing" {
  provider            = azurerm.loganalytics
  count               = var.use_existing_log_analytics ? 1 : 0
  name                = split("/", var.existing_log_analytics_id)[8]
  resource_group_name = split("/", var.existing_log_analytics_id)[4]
}

# -----------------------------------------------------------------------------
# LOG ANALYTICS WORKSPACE
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "citadel" {
  count               = var.use_existing_log_analytics ? 0 : 1
  name                = var.log_analytics_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30 # Bicep parity (was 90)
  tags                = var.tags

  # Bicep parity: when AMPLS is in use, disable public ingestion; queries remain enabled.
  internet_ingestion_enabled = !var.use_azure_monitor_private_link_scope
  internet_query_enabled     = true
}

# -----------------------------------------------------------------------------
# APPLICATION INSIGHTS (for APIM monitoring)
# -----------------------------------------------------------------------------

resource "azurerm_application_insights" "apim" {
  name                = "appi-apim-${var.environment_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = var.use_existing_log_analytics ? var.existing_log_analytics_id : azurerm_log_analytics_workspace.citadel[0].id
  application_type    = "web"
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# APPLICATION INSIGHTS (for Logic App monitoring)
# -----------------------------------------------------------------------------

resource "azurerm_application_insights" "logic_app" {
  name                = "appi-logic-${var.environment_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = var.use_existing_log_analytics ? var.existing_log_analytics_id : azurerm_log_analytics_workspace.citadel[0].id
  application_type    = "web"
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# APPLICATION INSIGHTS (for AI Foundry monitoring — Bicep: appi-aif-*)
# -----------------------------------------------------------------------------

resource "azurerm_application_insights" "foundry" {
  name                = "appi-aif-${var.environment_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = var.use_existing_log_analytics ? var.existing_log_analytics_id : azurerm_log_analytics_workspace.citadel[0].id
  application_type    = "web"
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# DASHBOARDS — Bicep parity (applicationinsights-dashboard.bicep deployed 3×)
# One dashboard per App Insights component (APIM / Logic App / Foundry),
# rendered from the shared template in ./dashboards/.
# -----------------------------------------------------------------------------

locals {
  dashboard_components = var.create_dashboards ? {
    apim = {
      suffix = "apim"
      ai_id  = azurerm_application_insights.apim.id
      ai_name = azurerm_application_insights.apim.name
    }
    logic = {
      suffix = "func"
      ai_id  = azurerm_application_insights.logic_app.id
      ai_name = azurerm_application_insights.logic_app.name
    }
    foundry = {
      suffix = "aif"
      ai_id  = azurerm_application_insights.foundry.id
      ai_name = azurerm_application_insights.foundry.name
    }
  } : {}
}

resource "azurerm_portal_dashboard" "app_insights" {
  for_each            = local.dashboard_components
  name                = "dash-citadel-${each.value.suffix}-${var.environment_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  dashboard_properties = templatefile("${path.module}/dashboards/appinsights-dashboard.json.tftpl", {
    subscription_id     = var.subscription_id
    resource_group_name = var.resource_group_name
    app_insights_name   = each.value.ai_name
  })
}

# =============================================================================
# AZURE MONITOR PRIVATE LINK SCOPE (AMPLS) — Bicep parity
# Creates a scope, associates the LAW and 3 App Insights components, and
# optionally creates a private endpoint with amazon DNS groups for the
# Azure Monitor / OMS / ODS / Agent subresources.
# =============================================================================

resource "azurerm_monitor_private_link_scope" "ampls" {
  count               = var.use_azure_monitor_private_link_scope ? 1 : 0
  name                = "ampls-${var.environment_name}"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_monitor_private_link_scoped_service" "law" {
  count               = var.use_azure_monitor_private_link_scope && !var.use_existing_log_analytics ? 1 : 0
  name                = "scoped-law"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.ampls[0].name
  linked_resource_id  = azurerm_log_analytics_workspace.citadel[0].id
}

resource "azurerm_monitor_private_link_scoped_service" "appi_apim" {
  count               = var.use_azure_monitor_private_link_scope ? 1 : 0
  name                = "scoped-appi-apim"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.ampls[0].name
  linked_resource_id  = azurerm_application_insights.apim.id
}

resource "azurerm_monitor_private_link_scoped_service" "appi_logic" {
  count               = var.use_azure_monitor_private_link_scope ? 1 : 0
  name                = "scoped-appi-logic"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.ampls[0].name
  linked_resource_id  = azurerm_application_insights.logic_app.id
}

resource "azurerm_monitor_private_link_scoped_service" "appi_foundry" {
  count               = var.use_azure_monitor_private_link_scope ? 1 : 0
  name                = "scoped-appi-foundry"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.ampls[0].name
  linked_resource_id  = azurerm_application_insights.foundry.id
}

resource "azurerm_private_endpoint" "ampls" {
  # Gate on the bool only — `ampls_subnet_id` comes from a module output and
  # isn't known at plan time, which Terraform forbids in `count`.
  count               = var.use_azure_monitor_private_link_scope ? 1 : 0
  name                = "pe-ampls-${var.environment_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.ampls_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-ampls"
    private_connection_resource_id = azurerm_monitor_private_link_scope.ampls[0].id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.use_azure_monitor_private_link_scope ? [1] : []
    content {
      name                 = "ampls-dns-group"
      private_dns_zone_ids = [var.ampls_dns_zone_id_monitor]
    }
  }
}
