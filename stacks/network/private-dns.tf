# Greenfield only: every privatelink.* zone the gateway uses, linked to the
# VNet. platform looks the zones up by name. In an ALZ (alz_spoke) the
# connectivity hub owns these zones and Azure Policy binds them.
module "private_dns" {
  source = "../../modules/private-dns"
  count  = local.greenfield ? 1 : 0

  resource_group_id   = data.azurerm_resource_group.workload.id
  zone_names          = merge(module.naming.private_dns_zones, var.private_dns.logic_app_zone ? module.naming.private_dns_optional_zones : {})
  vnet_id             = module.networking.vnet_id
  extra_vnet_link_ids = var.private_dns.extra_vnet_link_ids
  link_monitor_zone   = var.private_dns.link_monitor_zone
  tags                = local.tags
  enable_telemetry    = var.enable_telemetry
}
