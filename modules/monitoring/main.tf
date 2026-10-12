# =============================================================================
# MODULE: Monitoring
# Log Analytics Workspace + Application Insights
# =============================================================================

locals {
  byo_workspace    = var.existing_log_analytics_workspace != null
  log_analytics_id = local.byo_workspace ? var.existing_log_analytics_workspace.id : module.log_analytics[0].resource_id

  # Private link: a scope created here, or an existing one (e.g. the hub's) that the
  # workspace and components join.
  create_scope = var.use_azure_monitor_private_link_scope
  join_scope   = var.existing_private_link_scope_id != null
  private_link = local.create_scope || local.join_scope
  scope_id     = local.create_scope ? azurerm_monitor_private_link_scope.ampls[0].id : var.existing_private_link_scope_id

  # Public query per resource: off with public_query_enabled = false, except the resources in
  # public_query_components (their queries come through Resource Manager, which can't use
  # private links).
  public_query = {
    for k in concat(["log_analytics"], keys(local.app_insights)) : k => var.public_query_enabled || contains(var.public_query_components, k)
  }
}

# -----------------------------------------------------------------------------
# LOG ANALYTICS WORKSPACE
# -----------------------------------------------------------------------------

module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"
  count   = local.byo_workspace ? 0 : 1

  name                = var.log_analytics_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry

  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_retention_in_days = 30
  # Public network access. Diagnostic settings aren't affected (Microsoft's private channel).
  log_analytics_workspace_internet_ingestion_enabled = var.public_ingestion_enabled ? "true" : "false"
  log_analytics_workspace_internet_query_enabled     = local.public_query["log_analytics"] ? "true" : "false"
}

# -----------------------------------------------------------------------------
# APPLICATION INSIGHTS
# -----------------------------------------------------------------------------

locals {
  app_insights = merge(
    {
      apim      = "appi-apim-${var.environment_name}"
      logic_app = "appi-logic-${var.environment_name}"
    },
    var.create_foundry_app_insights ? { foundry = "appi-aif-${var.environment_name}" } : {},
  )
}

module "app_insights" {
  source   = "Azure/avm-res-insights-component/azurerm"
  version  = "0.4.0"
  for_each = local.app_insights

  name                = each.value
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = local.log_analytics_id
  application_type    = "web"
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry

  internet_ingestion_enabled = var.public_ingestion_enabled
  internet_query_enabled     = local.public_query[each.key]
}

# -----------------------------------------------------------------------------
# One dashboard per App Insights component (APIM / Logic App / Foundry),
# rendered from the shared template in ./dashboards/.
# -----------------------------------------------------------------------------

locals {
  dashboard_components = var.create_dashboards ? merge({
    apim = {
      suffix  = "apim"
      ai_id   = module.app_insights["apim"].resource_id
      ai_name = module.app_insights["apim"].name
    }
    logic = {
      suffix  = "func"
      ai_id   = module.app_insights["logic_app"].resource_id
      ai_name = module.app_insights["logic_app"].name
    }
    },
    var.create_foundry_app_insights ? {
      foundry = {
        suffix  = "aif"
        ai_id   = module.app_insights["foundry"].resource_id
        ai_name = module.app_insights["foundry"].name
      }
    } : {},
  ) : {}
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
# AZURE MONITOR PRIVATE LINK SCOPE (AMPLS)
# Either a scope created here (with its private endpoint and the five Azure
# Monitor DNS zones), or an existing scope that the workspace and components
# join: in a hub-and-spoke network that shares DNS, use the hub's single scope,
# because a second scope overwrites the hub's records in the shared zones.
# =============================================================================

resource "azurerm_monitor_private_link_scope" "ampls" {
  count               = local.create_scope ? 1 : 0
  name                = "ampls-${var.environment_name}"
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Open: the VNet still reaches Azure Monitor resources outside this scope (when they accept
  # public traffic). PrivateOnly: only resources in the scope (prevents exfiltration), for every
  # network that shares this DNS.
  ingestion_access_mode = var.private_link_scope_access_mode.ingestion
  query_access_mode     = var.private_link_scope_access_mode.query
}

# The workspace (only when this module created it: a BYO workspace belongs to its owner) and the
# components. azapi: an existing scope can live in another subscription (the hub's).
resource "azapi_resource" "scoped" {
  for_each = local.private_link ? merge(
    local.byo_workspace ? {} : { log_analytics = { name = var.log_analytics_name, id = module.log_analytics[0].resource_id } },
    { for k, ai in module.app_insights : k => { name = ai.name, id = ai.resource_id } },
  ) : {}

  type      = "Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01"
  name      = each.value.name # unique within a scope shared with other workloads
  parent_id = local.scope_id
  body = {
    # Lowercase: Azure stores and returns the ID lowercased, and azapi compares case-sensitively
    # (any other casing is a permanent in-place diff).
    properties = { linkedResourceId = lower(each.value.id) }
  }
}

resource "azurerm_private_endpoint" "ampls" {
  # Gate on the bool only — `ampls_subnet_id` comes from a module output and
  # isn't known at plan time, which Terraform forbids in `count`.
  count               = local.create_scope && !var.dns_zone_group_managed_by_policy ? 1 : 0
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

  # privatelink.monitor.azure.com, .oms.opinsights.azure.com, .ods.opinsights.azure.com,
  # .agentsvc.azure-automation.net and .blob.core.windows.net.
  dynamic "private_dns_zone_group" {
    for_each = length(var.ampls_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "ampls-dns-group"
      private_dns_zone_ids = var.ampls_dns_zone_ids
    }
  }
}

resource "azurerm_private_endpoint" "ampls_policy_dns" {
  # Gate on the bool only — `ampls_subnet_id` comes from a module output and
  # isn't known at plan time, which Terraform forbids in `count`.
  count               = local.create_scope && var.dns_zone_group_managed_by_policy ? 1 : 0
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

  # Azure Policy (ALZ Deploy-Private-DNS-Zones) creates the DNS zone group.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}
