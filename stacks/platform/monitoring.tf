# BYO Log Analytics workspace, possibly in another subscription.
data "azurerm_log_analytics_workspace" "byo" {
  provider            = azurerm.loganalytics
  count               = local.byo_workspace ? 1 : 0
  name                = split("/", var.monitoring.log_analytics_workspace_id)[8]
  resource_group_name = split("/", var.monitoring.log_analytics_workspace_id)[4]
}

# Log Analytics, Application Insights (APIM, Logic App, Foundry), dashboards, AMPLS.
module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  environment_name    = module.naming.base
  subscription_id     = var.subscription_id
  enable_telemetry    = var.enable_telemetry

  log_analytics_name = local.names.log_analytics
  existing_log_analytics_workspace = local.byo_workspace ? {
    id           = var.monitoring.log_analytics_workspace_id
    workspace_id = data.azurerm_log_analytics_workspace.byo[0].workspace_id
  } : null

  create_dashboards = var.monitoring.app_insights_dashboards

  use_azure_monitor_private_link_scope = var.monitoring.private_link_scope
  ampls_subnet_id                      = var.monitoring.private_link_scope ? local.network.subnet_ids.pe : ""
  ampls_dns_zone_id_monitor            = var.monitoring.private_link_scope ? lookup(local.zone_ids, "monitor", "") : ""
  dns_zone_group_managed_by_policy     = local.network.dns_zone_groups_managed_by_policy
}
