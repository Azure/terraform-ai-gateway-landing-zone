# Microsoft Foundry accounts, default projects and model deployments.
# Foundry -> APIM connections are access contracts (stacks/access-contracts).
module "foundry" {
  source = "../../modules/foundry"

  resource_group_id  = local.resource_group_id
  tags               = local.tags
  enable_telemetry   = var.enable_telemetry
  enable_diagnostics = !contains(var.monitoring.policy_managed_diagnostics, "foundry")
  account_names      = module.naming.foundry_account_names

  foundry_external_access = var.foundry.external_access
  foundry_instances       = local.foundry_instances
  foundry_models          = var.foundry.models
  outbound_allowed_fqdns  = var.foundry.outbound_allowed_fqdns

  apim_principal_id  = module.identity["apim"].principal_id
  deployer_object_id = data.azurerm_client_config.current.object_id

  log_analytics_id = module.monitoring.log_analytics_id
  # Null (no Foundry App Insights) when Foundry is disabled; the module then has no accounts.
  app_insights_id                  = module.monitoring.foundry_app_insights_id != null ? module.monitoring.foundry_app_insights_id : ""
  app_insights_instrumentation_key = module.monitoring.foundry_app_insights_instrumentation_key != null ? module.monitoring.foundry_app_insights_instrumentation_key : ""

  subnet_id                         = local.network.subnet_ids.pe
  dns_zone_ids                      = local.zone_ids
  dns_zone_group_managed_by_policy  = local.network.dns_zone_groups_managed_by_policy
  foundry_network_injection_enabled = var.foundry.network_injection_enabled
  agent_subnet_id                   = coalesce(local.network.subnet_ids.agent, "-") == "-" ? "" : local.network.subnet_ids.agent
}
