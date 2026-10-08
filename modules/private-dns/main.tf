# =============================================================================
# MODULE: Private DNS
# Creates the privatelink.* zones the gateway's private endpoints use and links
# them to the gateway VNet (plus any extra VNets, e.g. a runner or jump-box
# VNet). Greenfield only: in an ALZ the connectivity hub owns these zones.
# =============================================================================

locals {
  # The Azure Monitor zone is linked only when AMPLS populates it: an empty
  # linked privatelink.monitor.azure.com zone resolves App Insights ingestion
  # endpoints to nothing from inside the VNet and blackholes telemetry.
  linked_zone_keys = [for k in keys(var.zone_names) : k if k != "monitor" || var.link_monitor_zone]
  vnet_links       = merge({ vnet = var.vnet_id }, var.extra_vnet_link_ids)
}

module "zone" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.5.0"
  for_each = var.zone_names

  domain_name      = each.value
  parent_id        = var.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  virtual_network_links = contains(local.linked_zone_keys, each.key) ? {
    for name, id in local.vnet_links : name => {
      name                 = "link-${each.key}-${name}"
      virtual_network_id   = id
      registration_enabled = false
    }
  } : {}
}
