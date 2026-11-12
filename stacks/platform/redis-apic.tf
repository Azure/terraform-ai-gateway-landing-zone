# Azure Managed Redis: the APIM external cache for semantic caching.
module "redis" {
  source = "../../modules/redis"
  count  = var.features.semantic_cache ? 1 : 0

  providers = {
    azapi   = azapi.keys
    azurerm = azurerm
  }

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

  # The APIM external cache reads the connection string from here (never in state).
  key_vault_id = module.key_vault.key_vault_id_for_secrets
}

# The semantic cache lookup calls the embeddings deployment as APIM's system-assigned identity.
resource "azurerm_role_assignment" "apim_system_openai_user" {
  for_each = var.features.semantic_cache ? { for i, inst in local.foundry_instances : tostring(i) => i } : {}

  scope                = module.foundry[0].foundry_ids[each.value]
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.apim.system_assigned_principal_id
  principal_type       = "ServicePrincipal"
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

  remote_mcp_servers = var.api_center.remote_mcp_servers
}
