# =============================================================================
# PRIVATE DNS for Internal (VNet-injected) APIM — Developer / Premium SKUs
# -----------------------------------------------------------------------------
# In Internal mode the *.azure-api.net endpoints only listen on the private VIP
# and are not published in public DNS, so clients in the VNet need private
# resolution. One zone per hostname (instead of a single "azure-api.net" zone)
# keeps every other public *.azure-api.net service resolvable from the VNet.
# https://learn.microsoft.com/azure/api-management/api-management-using-with-internal-vnet#dns-configuration
# =============================================================================

locals {
  create_internal_dns = local.is_vnet_injection && local.is_internal && var.create_internal_dns

  internal_dns_hostnames = local.create_internal_dns ? toset([
    "${var.apim_name}.azure-api.net",
    "${var.apim_name}.portal.azure-api.net",
    "${var.apim_name}.developer.azure-api.net",
    "${var.apim_name}.management.azure-api.net",
    "${var.apim_name}.scm.azure-api.net",
  ]) : toset([])
}

resource "azurerm_private_dns_zone" "internal" {
  for_each            = local.internal_dns_hostnames
  name                = each.key
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "internal" {
  for_each            = local.internal_dns_hostnames
  name                = "@"
  zone_name           = azurerm_private_dns_zone.internal[each.key].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = azurerm_api_management.citadel.private_ip_addresses
}

resource "azurerm_private_dns_zone_virtual_network_link" "internal" {
  for_each              = local.internal_dns_hostnames
  name                  = "link-apim"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.internal[each.key].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}
