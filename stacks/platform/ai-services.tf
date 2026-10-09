# Standalone Language (TextAnalytics) and Content Safety (ContentSafety) accounts:
# Microsoft.CognitiveServices accounts like the Foundry ones, but a different kind.
# For customers that don't deploy Foundry, or want these services separate from it.
# stacks/gateway-config points PII redaction and the content-safety backend at them
# (pii_service / content_safety_service = { source = "dedicated" }), finding them by
# name (modules/naming), like everything else.

module "language_service" {
  source = "../../modules/cognitive-service"
  count  = var.language_service.enabled ? 1 : 0

  name              = local.names.language_service
  kind              = "TextAnalytics"
  sku_name          = var.language_service.sku
  location          = coalesce(var.language_service.location, var.location)
  resource_group_id = local.resource_group_id
  tags              = local.tags
  enable_telemetry  = var.enable_telemetry

  public_network_access_enabled = var.language_service.public_network_access
  apim_principal_id             = module.identity["apim"].principal_id

  subnet_id                        = local.network.subnet_ids.pe
  dns_zone_id                      = lookup(local.zone_ids, "cognitive_services", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy

  enable_diagnostics = !contains(var.monitoring.policy_managed_diagnostics, "foundry")
  log_analytics_id   = module.monitoring.log_analytics_id
}

module "content_safety_service" {
  source = "../../modules/cognitive-service"
  count  = var.content_safety_service.enabled ? 1 : 0

  name              = local.names.content_safety
  kind              = "ContentSafety"
  sku_name          = var.content_safety_service.sku
  location          = coalesce(var.content_safety_service.location, var.location)
  resource_group_id = local.resource_group_id
  tags              = local.tags
  enable_telemetry  = var.enable_telemetry

  public_network_access_enabled = var.content_safety_service.public_network_access
  apim_principal_id             = module.identity["apim"].principal_id

  subnet_id                        = local.network.subnet_ids.pe
  dns_zone_id                      = lookup(local.zone_ids, "cognitive_services", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy

  enable_diagnostics = !contains(var.monitoring.policy_managed_diagnostics, "foundry")
  log_analytics_id   = module.monitoring.log_analytics_id
}
