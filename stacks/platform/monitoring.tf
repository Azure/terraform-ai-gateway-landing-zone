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

  create_foundry_app_insights = var.foundry.enabled
  enable_telemetry            = var.enable_telemetry

  log_analytics_name = local.names.log_analytics
  existing_log_analytics_workspace = local.byo_workspace ? {
    id           = var.monitoring.log_analytics_workspace_id
    workspace_id = data.azurerm_log_analytics_workspace.byo[0].workspace_id
  } : null

  create_dashboards = var.monitoring.app_insights_dashboards

  use_azure_monitor_private_link_scope = var.monitoring.private_link_scope
  existing_private_link_scope_id       = var.monitoring.existing_private_link_scope_id
  private_link_scope_access_mode       = var.monitoring.private_link_scope_access_mode
  ampls_subnet_id                      = var.monitoring.private_link_scope ? local.network.subnet_ids.pe : ""
  ampls_dns_zone_ids = var.monitoring.private_link_scope ? [
    for k in ["monitor", "monitor_oms", "monitor_ods", "monitor_agentsvc", "storage_blob"] : local.zone_ids[k] if lookup(local.zone_ids, k, "") != ""
  ] : []
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy

  public_ingestion_enabled = var.monitoring.public_ingestion_enabled
  public_query_enabled     = var.monitoring.public_query_enabled
  # The usage pipeline's llm-usage-ingestion and ai-usage-streaming-ingestion workflows query the
  # APIM component with the azuremonitorlogs managed connector: through Resource Manager, which
  # can't use private links. The component's data lives in the workspace, and a workspace that
  # blocks public query returns those queries empty (no error), so both keep public query.
  public_query_components = ["log_analytics", "apim"]
}
