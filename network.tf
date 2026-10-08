# =============================================================================
# NETWORK — the root decides where the network comes from (WP-1.4, WP-2.6):
#   greenfield  modules/networking creates the VNet, subnets and NSGs.
#   alz_spoke   the platform-vended spoke VNet is looked up here; modules/networking
#               creates the subnets (NSG + UDR to the hub firewall) inside it.
#   byo         the existing VNet and subnets are looked up here by name.
# Either way the rest of the configuration reads local.network, and
# modules/private-dns creates (or takes) the private DNS zones.
# =============================================================================

locals {
  enable_ase_subnet = local.usage_cfg.logic_app.hosting_model == "AppServiceEnvironmentV3"
}

module "networking" {
  source = "./modules/networking"
  count  = local.network_cfg.byo ? 0 : 1

  resource_group_name = local.resource_group_name_resolved
  subscription_id     = var.subscription_id
  location            = var.location
  tags                = local.all_tags
  enable_telemetry    = var.enable_telemetry

  default_outbound_access_enabled = local.network_cfg.default_outbound_access
  existing_vnet_id                = local.network_cfg.alz_spoke ? data.azurerm_virtual_network.byo[0].id : null
  hub_firewall_ip                 = local.network_cfg.hub_firewall_ip

  vnet_name           = local.vnet_name
  vnet_address_prefix = local.network_cfg.address_space

  apim_subnet_name        = local.network_cfg.subnets.apim.name
  apim_subnet_prefix      = local.network_cfg.subnets.apim.prefix
  pe_subnet_name          = local.network_cfg.subnets.private_endpoint.name
  pe_subnet_prefix        = local.network_cfg.subnets.private_endpoint.prefix
  logic_app_subnet_name   = local.network_cfg.subnets.logic_app.name
  logic_app_subnet_prefix = local.network_cfg.subnets.logic_app.prefix
  enable_agent_subnet     = local.network_cfg.subnets.agent.enabled
  agent_subnet_name       = local.network_cfg.subnets.agent.name
  agent_subnet_prefix     = local.network_cfg.subnets.agent.prefix
  enable_ase_subnet       = local.enable_ase_subnet
  ase_subnet_name         = local.network_cfg.subnets.ase.name
  ase_subnet_prefix       = local.network_cfg.subnets.ase.prefix

  apim_network_type = local.apim_network_type
  is_apim_vnet      = local.is_apim_vnet
  is_apim_v2        = local.is_apim_v2
}

# --- byo: look up the existing VNet and subnets ------------------------------

data "azurerm_virtual_network" "byo" {
  count               = local.network_cfg.byo || local.network_cfg.alz_spoke ? 1 : 0
  name                = local.vnet_name
  resource_group_name = local.network_cfg.resource_group_name
}

data "azurerm_subnet" "byo" {
  for_each = local.network_cfg.byo ? merge(
    {
      apim             = local.network_cfg.subnets.apim.name
      private_endpoint = local.network_cfg.subnets.private_endpoint.name
      logic_app        = local.network_cfg.subnets.logic_app.name
    },
    local.network_cfg.subnets.agent.enabled && local.network_cfg.subnets.agent.name != "" ? { agent = local.network_cfg.subnets.agent.name } : {},
    local.enable_ase_subnet ? { ase = local.network_cfg.subnets.ase.name } : {},
  ) : {}

  name                 = each.value
  virtual_network_name = local.vnet_name
  resource_group_name  = local.network_cfg.resource_group_name
}

locals {
  network = local.network_cfg.byo ? {
    vnet_id             = data.azurerm_virtual_network.byo[0].id
    apim_subnet_id      = data.azurerm_subnet.byo["apim"].id
    pe_subnet_id        = data.azurerm_subnet.byo["private_endpoint"].id
    logic_app_subnet_id = data.azurerm_subnet.byo["logic_app"].id
    agent_subnet_id     = try(data.azurerm_subnet.byo["agent"].id, "")
    ase_subnet_id       = try(data.azurerm_subnet.byo["ase"].id, "")
    } : {
    vnet_id             = module.networking[0].vnet_id
    apim_subnet_id      = module.networking[0].apim_subnet_id
    pe_subnet_id        = module.networking[0].pe_subnet_id
    logic_app_subnet_id = module.networking[0].logic_app_subnet_id
    agent_subnet_id     = module.networking[0].agent_subnet_id
    ase_subnet_id       = module.networking[0].ase_subnet_id
  }
}

# --- private DNS ---------------------------------------------------------------

module "private_dns" {
  source = "./modules/private-dns"

  resource_group_name = local.resource_group_name_resolved
  subscription_id     = var.subscription_id
  tags                = local.all_tags
  vnet_id             = local.network.vnet_id
  enable_telemetry    = var.enable_telemetry

  create_zones      = local.create_dns_zones
  existing_zone_ids = local.network_cfg.private_dns_zone_ids
  # Only VNet-link privatelink.monitor.azure.com when AMPLS is enabled; an empty
  # linked monitor zone blackholes App Insights ingestion DNS from the VNet.
  link_monitor_zone = local.monitoring_cfg.private_link_scope

  # Zones the root dereferences below (module.private_dns.zone_ids["..."]).
  required_zone_keys = local.network_cfg.zone_groups_managed_by_policy ? [] : concat(
    ["key_vault", "cosmos_db", "event_hub", "storage_blob", "storage_file", "storage_table", "storage_queue", "apim_gateway"],
    local.features.semantic_cache ? ["redis"] : [],
    local.monitoring_cfg.private_link_scope ? ["monitor"] : [],
  )
}
