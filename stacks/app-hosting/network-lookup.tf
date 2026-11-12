# greenfield: the ASE subnet and VNet come from stacks/network, found by name.
# alz_spoke / byo: explicit IDs in app-hosting.tfvars.
data "azurerm_virtual_network" "greenfield" {
  count               = local.greenfield && (var.ase.subnet_id == null || var.dns.vnet_link_ids == null) ? 1 : 0
  name                = local.names.virtual_network
  resource_group_name = local.names.resource_group
}

data "azurerm_subnet" "ase" {
  count                = local.greenfield && var.ase.subnet_id == null ? 1 : 0
  name                 = local.names.subnet_ase
  virtual_network_name = local.names.virtual_network
  resource_group_name  = local.names.resource_group
}

locals {
  ase_subnet_id     = coalesce(var.ase.subnet_id, try(data.azurerm_subnet.ase[0].id, null), "-")
  dns_vnet_link_ids = var.dns.vnet_link_ids != null ? var.dns.vnet_link_ids : (local.greenfield ? { spoke = data.azurerm_virtual_network.greenfield[0].id } : {})
}
