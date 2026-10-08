# =============================================================================
# MODULE: Logic App — App Service Environment v3 hosting (opt-in)
# Enabled when var.hosting_model = "AppServiceEnvironmentV3". Lets the Logic App
# run with shared-key access disabled on its storage account, which the
# Workflow Service Plan does not support.
# =============================================================================

locals {
  ase_is_internal        = var.ase_internal_load_balancing_mode != "None"
  create_ase_private_dns = local.use_ase && local.ase_is_internal && var.ase_create_private_dns_zone
}

resource "azurerm_app_service_environment_v3" "ase" {
  count                        = local.use_ase ? 1 : 0
  name                         = var.names.app_service_environment
  resource_group_name          = var.resource_group_name
  subnet_id                    = var.ase_subnet_id
  internal_load_balancing_mode = var.ase_internal_load_balancing_mode
  zone_redundant               = var.ase_zone_redundant
  tags                         = var.tags

  cluster_setting {
    name  = "DisableTls1.0"
    value = "1"
  }

  lifecycle {
    precondition {
      condition     = var.ase_subnet_id != ""
      error_message = "hosting_model = AppServiceEnvironmentV3 requires ase_subnet_id (a dedicated subnet delegated to Microsoft.Web/hostingEnvironments)."
    }
  }
}

# -----------------------------------------------------------------------------
# PRIVATE DNS for an internal (ILB) ASE: <ase>.appserviceenvironment.net with
# *, *.scm and @ pointing at the ASE inbound IP, linked to the VNet.
# -----------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "ase" {
  count               = local.create_ase_private_dns ? 1 : 0
  name                = azurerm_app_service_environment_v3.ase[0].dns_suffix
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "ase" {
  for_each            = local.create_ase_private_dns ? toset(["*", "*.scm", "@"]) : toset([])
  name                = each.key
  zone_name           = azurerm_private_dns_zone.ase[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = azurerm_app_service_environment_v3.ase[0].internal_inbound_ip_addresses
}

resource "azurerm_private_dns_zone_virtual_network_link" "ase" {
  count                 = local.create_ase_private_dns ? 1 : 0
  name                  = "link-ase"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.ase[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  lifecycle {
    precondition {
      condition     = var.vnet_id != ""
      error_message = "vnet_id is required to link the ASE private DNS zone."
    }
  }
}
