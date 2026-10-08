# =============================================================================
# How platform finds the network (review 7.5.3.1).
#   greenfield         subnets and private DNS zones of stacks/network, by name.
#   alz_spoke / byo    the explicit `network` object (IDs from vending / the hub).
# Everything else reads local.network.
# =============================================================================

locals {
  greenfield_subnets = !local.greenfield ? {} : merge(
    { pe = local.names.subnet_pe },
    local.apim_cfg.vnet_mode != "none" ? { apim = local.names.subnet_apim } : {},
    var.usage_pipeline.logic_app.hosting == "workflow_standard" ? { logic_app = local.names.subnet_logic_app } : {},
    var.foundry.network_injection_enabled ? { agent = local.names.subnet_agent } : {},
  )
}

data "azurerm_virtual_network" "greenfield" {
  count               = local.greenfield ? 1 : 0
  name                = local.names.virtual_network
  resource_group_name = local.names.resource_group
}

data "azurerm_subnet" "greenfield" {
  for_each             = local.greenfield_subnets
  name                 = each.value
  virtual_network_name = local.names.virtual_network
  resource_group_name  = local.names.resource_group
}

data "azurerm_private_dns_zone" "greenfield" {
  for_each            = local.greenfield ? module.naming.private_dns_zones : {}
  name                = each.value
  resource_group_name = local.names.resource_group
}

locals {
  network = local.greenfield ? {
    vnet_id = data.azurerm_virtual_network.greenfield[0].id
    subnet_ids = {
      pe        = data.azurerm_subnet.greenfield["pe"].id
      apim      = try(data.azurerm_subnet.greenfield["apim"].id, null)
      logic_app = try(data.azurerm_subnet.greenfield["logic_app"].id, null)
      agent     = try(data.azurerm_subnet.greenfield["agent"].id, null)
    }
    private_dns_zone_ids = { for k, z in data.azurerm_private_dns_zone.greenfield : k => z.id }
    # Greenfield has no DINE policy: Terraform binds every zone.
    dns_zone_groups_managed_by_policy = false
  } : var.network

  zone_ids = local.network.private_dns_zone_ids
}
