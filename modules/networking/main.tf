# =============================================================================
# MODULE: Networking — Azure Verified Modules
#   greenfield  creates the gateway VNet with its subnets.
#   alz_spoke   creates the subnets inside the platform-vended spoke VNet
#               (existing_vnet_id), each with a UDR sending 0.0.0.0/0 to the hub
#               firewall (hub_firewall_ip).
# Every subnet gets an NSG (ALZ Deny-Subnet-Without-Nsg). An existing (byo)
# network is looked up by the root module instead; private DNS lives in
# modules/private-dns.
# =============================================================================

locals {
  # The ASE v3 subnet needs far more room than the default /24 VNet has left.
  # If its prefix is not already inside vnet_address_prefix, append it as an
  # extra VNet address space. cidrhost() masks host bits, so re-basing the ASE
  # network address onto the VNet prefix length tests containment.
  vnet_prefix_length = tonumber(split("/", var.vnet_address_prefix)[1])
  ase_prefix_in_vnet = var.enable_ase_subnet ? (
    tonumber(split("/", var.ase_subnet_prefix)[1]) >= local.vnet_prefix_length &&
    cidrhost(format("%s/%d", split("/", var.ase_subnet_prefix)[0], local.vnet_prefix_length), 0) == cidrhost(var.vnet_address_prefix, 0)
  ) : true

  vnet_address_space = local.ase_prefix_in_vnet ? [var.vnet_address_prefix] : [var.vnet_address_prefix, var.ase_subnet_prefix]
}

locals {
  alz_spoke         = var.existing_vnet_id != null
  resource_group_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"

  classic_injection = contains(["external", "internal"], var.apim_vnet_mode)

  apim_rules = merge(
    var.apim_vnet_mode == "external" ? {
      AllowHTTPS = { priority = 3000, direction = "Inbound", ports = ["443"], source = "Internet", destination = "VirtualNetwork" }
    } : {},
    local.classic_injection ? {
      AllowAPIMManagement = { priority = 3010, direction = "Inbound", ports = ["3443"], source = "ApiManagement", destination = "VirtualNetwork" }
      AllowLoadBalancer   = { priority = 3020, direction = "Inbound", ports = ["6390"], source = "AzureLoadBalancer", destination = "VirtualNetwork" }
      AllowStorage        = { priority = 3000, direction = "Outbound", ports = ["443"], source = "VirtualNetwork", destination = "Storage" }
      AllowSQL            = { priority = 3010, direction = "Outbound", ports = ["1433"], source = "VirtualNetwork", destination = "Sql" }
      AllowMonitor        = { priority = 3030, direction = "Outbound", ports = ["443", "1886"], source = "VirtualNetwork", destination = "AzureMonitor" }
    } : {},
    # Key Vault is a dependency in every mode that puts APIM in the subnet.
    var.apim_vnet_mode != "none" ? {
      AllowKeyVault = { priority = 3020, direction = "Outbound", ports = ["443"], source = "VirtualNetwork", destination = "AzureKeyVault" }
    } : {},
  )

  web_delegation = [{ name = "delegation-web", service_delegation = { name = "Microsoft.Web/serverFarms" } }]

  # APIM subnet per vnet_mode (none = no subnet):
  #   external/internal  classic injection: no delegation, management route table
  #   integration        v2 outbound integration: delegated to Microsoft.Web/serverFarms
  #   injection          Premium v2 injection: delegated to Microsoft.Web/hostingEnvironments
  apim_delegation = lookup({
    integration = [{ name = "delegation-apim-v2", service_delegation = { name = "Microsoft.Web/serverFarms" } }]
    injection   = [{ name = "delegation-apim-v2-injection", service_delegation = { name = "Microsoft.Web/hostingEnvironments" } }]
  }, var.apim_vnet_mode, null)

  subnets = merge(
    var.apim_vnet_mode != "none" ? {
      apim = {
        name              = var.apim_subnet_name
        prefix            = var.apim_subnet_prefix
        service_endpoints = ["Microsoft.CognitiveServices"]
        delegations       = local.apim_delegation
        rules             = local.apim_rules
      }
    } : {},
    {
      pe = {
        name              = var.pe_subnet_name
        prefix            = var.pe_subnet_prefix
        service_endpoints = ["Microsoft.CognitiveServices"]
        delegations       = null
        rules             = {}
      }
      logic_app = {
        name              = var.logic_app_subnet_name
        prefix            = var.logic_app_subnet_prefix
        service_endpoints = ["Microsoft.CognitiveServices"]
        delegations       = local.web_delegation
        rules             = {}
      }
    },
    var.enable_agent_subnet ? {
      agent = {
        name              = var.agent_subnet_name
        prefix            = var.agent_subnet_prefix
        service_endpoints = ["Microsoft.CognitiveServices"]
        delegations       = [{ name = "Microsoft.app/environments", service_delegation = { name = "Microsoft.App/environments" } }]
        rules             = {}
      }
    } : {},
    # ASE v3: an empty subnet delegated to Microsoft.Web/hostingEnvironments.
    var.enable_ase_subnet ? {
      ase = {
        name              = var.ase_subnet_name
        prefix            = var.ase_subnet_prefix
        service_endpoints = null
        delegations       = [{ name = "Microsoft.Web.hostingEnvironments", service_delegation = { name = "Microsoft.Web/hostingEnvironments" } }]
        rules             = {}
      }
    } : {},
  )
}

module "nsg" {
  source   = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version  = "0.6.0"
  for_each = local.subnets

  name             = "nsg-${each.value.name}"
  location         = var.location
  parent_id        = local.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  # No custom rules on the non-APIM subnets: the default NSG rules apply.
  security_rules = {
    for name, r in each.value.rules : name => {
      name                       = name
      priority                   = r.priority
      direction                  = r.direction
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = length(r.ports) == 1 ? r.ports[0] : null
      destination_port_ranges    = length(r.ports) > 1 ? toset(r.ports) : null
      source_address_prefix      = r.source
      destination_address_prefix = r.destination
    }
  }
}

resource "azurerm_route_table" "apim" {
  count               = local.classic_injection && !local.alz_spoke ? 1 : 0
  name                = "rt-${var.apim_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  route {
    name           = "apim-management"
    address_prefix = "ApiManagement"
    next_hop_type  = "Internet"
  }
}

# alz_spoke: every subnet routes 0.0.0.0/0 through the hub firewall. Classic
# APIM keeps its management route to the ApiManagement service tag.
resource "azurerm_route_table" "spoke" {
  for_each = { for k, sn in local.subnets : k => sn.name if local.alz_spoke }

  name                          = "rt-${each.value}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tags                          = var.tags
  bgp_route_propagation_enabled = false

  route {
    name                   = "default-to-hub-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.hub_firewall_ip
  }

  dynamic "route" {
    for_each = each.key == "apim" && local.classic_injection ? [1] : []
    content {
      name           = "apim-management"
      address_prefix = "ApiManagement"
      next_hop_type  = "Internet"
    }
  }

  lifecycle {
    precondition {
      condition     = var.hub_firewall_ip != null
      error_message = "network.mode = \"alz_spoke\" needs network.hub_firewall_ip (the hub firewall's private IP)."
    }
  }
}

locals {
  subnet_config = {
    for k, sn in local.subnets : k => {
      name                            = sn.name
      address_prefixes                = [sn.prefix]
      service_endpoints               = sn.service_endpoints == null ? null : toset(sn.service_endpoints)
      delegations                     = sn.delegations
      network_security_group          = { id = module.nsg[k].resource_id }
      route_table                     = local.alz_spoke ? { id = azurerm_route_table.spoke[k].id } : (k == "apim" && local.classic_injection ? { id = azurerm_route_table.apim[0].id } : null)
      default_outbound_access_enabled = var.default_outbound_access_enabled
    }
  }
}

module "spoke_subnet" {
  source   = "Azure/avm-res-network-virtualnetwork/azurerm//modules/subnet"
  version  = "0.22.2"
  for_each = { for k, sn in local.subnet_config : k => sn if local.alz_spoke }

  parent_id                       = var.existing_vnet_id
  name                            = each.value.name
  address_prefixes                = each.value.address_prefixes
  service_endpoints               = each.value.service_endpoints
  delegations                     = each.value.delegations
  network_security_group          = each.value.network_security_group
  route_table                     = each.value.route_table
  default_outbound_access_enabled = each.value.default_outbound_access_enabled
}

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"
  count   = local.alz_spoke ? 0 : 1

  name             = var.vnet_name
  location         = var.location
  parent_id        = local.resource_group_id
  address_space    = local.vnet_address_space
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  subnets = local.subnet_config
}
