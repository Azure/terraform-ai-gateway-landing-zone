# Azure Managed Redis: the APIM external cache for semantic caching.
module "redis" {
  source = "../../modules/redis"
  count  = var.features.semantic_cache ? 1 : 0

  name                = local.names.redis
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = local.tags

  sku_name              = var.redis.sku_name
  sku_capacity          = var.redis.capacity
  public_network_access = var.redis.public_network_access
  minimum_tls_version   = var.redis.minimum_tls_version

  subnet_id                        = local.network.subnet_ids.pe
  dns_zone_id                      = lookup(local.zone_ids, "redis", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy
}

# Azure API Center (API registrations come from gateway-config and llm-backend-onboarding).
module "apic" {
  source = "../../modules/apic"

  resource_group_id = local.resource_group_id
  tags              = local.tags
  api_center_name   = local.names.api_center
  enable_api_center = var.features.api_center
  apic_location     = coalesce(var.api_center.location, var.location)
  api_center_sku    = var.api_center.sku
}
