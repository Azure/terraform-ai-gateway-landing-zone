# API Management service (network matrix: docs/operations/apim-network-modes.md)
# and its telemetry. Child configuration belongs to other stacks (review 7.8).
module "apim" {
  source = "../../modules/apim"

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  subscription_id     = var.subscription_id
  enable_telemetry    = var.enable_telemetry

  apim_name       = local.names.apim
  sku_name        = local.apim_cfg.sku
  sku_capacity    = local.apim_cfg.capacity
  publisher_email = local.apim_cfg.publisher_email
  publisher_name  = local.apim_cfg.publisher_name

  vnet_mode                     = local.apim_cfg.vnet_mode
  public_ip_address_id          = local.apim_cfg.public_ip_address_id
  apim_subnet_id                = coalesce(local.network.subnet_ids.apim, "-") == "-" ? "" : local.network.subnet_ids.apim
  pe_subnet_id                  = local.network.subnet_ids.pe
  vnet_id                       = local.network.vnet_id
  apim_v2_use_private_endpoint  = local.apim_cfg.private_endpoint
  apim_v2_public_network_access = local.apim_cfg.public_network_access

  managed_identity_id = module.identity["apim"].resource_id

  dns_zone_id_apim                 = lookup(local.zone_ids, "apim_gateway", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy
  # Private VIP hostnames: greenfield creates the zones; in an ALZ the hub does.
  create_internal_dns = local.greenfield

  # Availability zones (Bicep parity: Premium + more than one unit).
  apim_zones = local.apim_cfg.sku == "Premium" && local.apim_cfg.capacity > 1 ? (
    local.apim_cfg.capacity == 2 ? ["1", "2"] : ["1", "2", "3"]
  ) : []

  enable_redis_cache            = var.features.semantic_cache
  redis_cache_connection_string = var.features.semantic_cache ? module.redis[0].connection_string : ""
}

# Loggers (appinsights-logger, azuremonitor, usage-eventhub-logger,
# pii-usage-eventhub-logger) and service-level diagnostics. The logger names
# are a contract: gateway-config and llm-backend-onboarding reference them.
module "apim_telemetry" {
  source = "../../modules/apim-telemetry"

  api_management_id   = module.apim.apim_id
  api_management_name = module.apim.apim_name
  resource_group_name = local.resource_group_name

  app_insights_id                  = module.monitoring.app_insights_id
  app_insights_connection_string   = module.monitoring.app_insights_connection_string
  app_insights_instrumentation_key = module.monitoring.app_insights_instrumentation_key
  log_analytics_id                 = module.monitoring.log_analytics_id

  eventhub_endpoint_uri      = module.eventhub.endpoint_uri
  eventhub_usage_hub_name    = module.eventhub.apim_usage_hub_name
  eventhub_pii_hub_name      = module.eventhub.pii_usage_hub_name
  enable_pii_redaction       = true
  managed_identity_client_id = module.identity["apim"].client_id

  log_verbosity  = var.apim_logging.verbosity
  log_body_bytes = var.apim_logging.body_bytes
}
