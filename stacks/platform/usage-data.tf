# Usage pipeline data plane: Cosmos DB (usage records) and Event Hub (APIM usage events).
module "cosmosdb" {
  source = "../../modules/cosmosdb"

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  enable_telemetry    = var.enable_telemetry
  enable_diagnostics  = !contains(var.monitoring.policy_managed_diagnostics, "cosmosdb")

  account_name                  = local.names.cosmos
  public_network_access         = local.usage_cfg.cosmos.public_network_access
  local_authentication_enabled  = local.usage_cfg.cosmos.local_auth_enabled
  managed_identity_principal_id = module.identity["usage"].principal_id

  subnet_id                        = local.network.subnet_ids.pe
  dns_zone_id                      = lookup(local.zone_ids, "cosmos_db", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy

  log_analytics_id = module.monitoring.log_analytics_id
}

module "eventhub" {
  source = "../../modules/eventhub"

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  enable_telemetry    = var.enable_telemetry
  enable_diagnostics  = !contains(var.monitoring.policy_managed_diagnostics, "eventhub")

  namespace_name        = local.names.eventhub_namespace
  capacity_units        = local.usage_cfg.eventhub.capacity
  public_network_access = local.usage_cfg.eventhub.public_network_access

  # APIM identity = Sender; usage identity = Receiver + Owner (Bicep parity).
  apim_identity_principal_id  = module.identity["apim"].principal_id
  usage_identity_principal_id = module.identity["usage"].principal_id

  subnet_id                        = local.network.subnet_ids.pe
  dns_zone_id                      = lookup(local.zone_ids, "event_hub", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy

  log_analytics_id         = module.monitoring.log_analytics_id
  disaster_recovery_config = local.usage_cfg.eventhub.disaster_recovery
}
