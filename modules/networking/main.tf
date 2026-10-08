# =============================================================================
# MODULE: Networking (greenfield)
# Creates the gateway VNet, subnets, NSGs and the APIM route table. An existing
# (byo) network is looked up by the root module instead; private DNS lives in
# modules/private-dns.
# =============================================================================

# -----------------------------------------------------------------------------
# NEW VNET
# -----------------------------------------------------------------------------

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

resource "azurerm_virtual_network" "citadel" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = local.vnet_address_space
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# NSG FOR AGENT SUBNET (if enabled)
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "agent" {
  count               = var.enable_agent_subnet ? 1 : 0
  name                = "nsg-${var.agent_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# NSG FOR APIM SUBNET
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "apim" {
  name                = "nsg-${var.apim_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Inbound: Allow HTTPS from Internet (External mode)
  dynamic "security_rule" {
    for_each = var.apim_network_type == "External" && var.is_apim_vnet ? [1] : []
    content {
      name                       = "AllowHTTPS"
      priority                   = 3000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = "VirtualNetwork"
    }
  }

  # Inbound: APIM Management (required for Developer/Premium)
  dynamic "security_rule" {
    for_each = var.is_apim_vnet ? [1] : []
    content {
      name                       = "AllowAPIMManagement"
      priority                   = 3010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3443"
      source_address_prefix      = "ApiManagement"
      destination_address_prefix = "VirtualNetwork"
    }
  }

  # Inbound: Azure Load Balancer health probes
  dynamic "security_rule" {
    for_each = var.is_apim_vnet ? [1] : []
    content {
      name                       = "AllowLoadBalancer"
      priority                   = 3020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "6390"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "VirtualNetwork"
    }
  }

  # Outbound: Storage
  dynamic "security_rule" {
    for_each = var.is_apim_vnet ? [1] : []
    content {
      name                       = "AllowStorage"
      priority                   = 3000
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "Storage"
    }
  }

  # Outbound: SQL
  dynamic "security_rule" {
    for_each = var.is_apim_vnet ? [1] : []
    content {
      name                       = "AllowSQL"
      priority                   = 3010
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1433"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "Sql"
    }
  }

  # Outbound: Key Vault (also required for V2 VNet integration)
  dynamic "security_rule" {
    for_each = var.is_apim_vnet || var.is_apim_v2 ? [1] : []
    content {
      name                       = "AllowKeyVault"
      priority                   = 3020
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "AzureKeyVault"
    }
  }

  # Outbound: Azure Monitor
  dynamic "security_rule" {
    for_each = var.is_apim_vnet ? [1] : []
    content {
      name                       = "AllowMonitor"
      priority                   = 3030
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["443", "1886"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "AzureMonitor"
    }
  }
}

# -----------------------------------------------------------------------------
# ROUTE TABLE FOR APIM (Developer/Premium SKUs only)
# -----------------------------------------------------------------------------

resource "azurerm_route_table" "apim" {
  count               = var.is_apim_vnet ? 1 : 0
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

# -----------------------------------------------------------------------------
# SUBNETS (new VNet)
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "apim" {
  name                 = var.apim_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel.name
  address_prefixes     = [var.apim_subnet_prefix]
  service_endpoints    = ["Microsoft.CognitiveServices"]

  # V2 SKUs: outbound VNet integration requires a dedicated subnet delegated to Microsoft.Web/serverFarms.
  dynamic "delegation" {
    for_each = var.is_apim_v2 ? [1] : []
    content {
      name = "delegation-apim-v2"
      service_delegation {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

resource "azurerm_subnet_route_table_association" "apim" {
  count          = var.is_apim_vnet ? 1 : 0
  subnet_id      = azurerm_subnet.apim.id
  route_table_id = azurerm_route_table.apim[0].id
}

resource "azurerm_subnet" "pe" {
  name                 = var.pe_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel.name
  address_prefixes     = [var.pe_subnet_prefix]
  service_endpoints    = ["Microsoft.CognitiveServices"]
}

resource "azurerm_subnet" "logic_app" {
  name                 = var.logic_app_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel.name
  address_prefixes     = [var.logic_app_subnet_prefix]
  service_endpoints    = ["Microsoft.CognitiveServices"]

  delegation {
    name = "delegation-web"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "agent" {
  count                = var.enable_agent_subnet ? 1 : 0
  name                 = var.agent_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel.name
  address_prefixes     = [var.agent_subnet_prefix]
  service_endpoints    = ["Microsoft.CognitiveServices"]

  delegation {
    name = "Microsoft.app/environments"
    service_delegation {
      name = "Microsoft.App/environments"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "agent" {
  count                     = var.enable_agent_subnet ? 1 : 0
  subnet_id                 = azurerm_subnet.agent[0].id
  network_security_group_id = azurerm_network_security_group.agent[0].id
}

# -----------------------------------------------------------------------------
# ASE v3 SUBNET (only when the Logic App is hosted on App Service Environment v3)
# Must be empty and delegated to Microsoft.Web/hostingEnvironments.
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "ase" {
  count                = var.enable_ase_subnet ? 1 : 0
  name                 = var.ase_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel.name
  address_prefixes     = [var.ase_subnet_prefix]

  delegation {
    name = "Microsoft.Web.hostingEnvironments"
    service_delegation {
      name    = "Microsoft.Web/hostingEnvironments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_network_security_group" "ase" {
  count               = var.enable_ase_subnet ? 1 : 0
  name                = "nsg-${var.ase_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "ase" {
  count                     = var.enable_ase_subnet ? 1 : 0
  subnet_id                 = azurerm_subnet.ase[0].id
  network_security_group_id = azurerm_network_security_group.ase[0].id
}

# -----------------------------------------------------------------------------
# NSGs FOR THE PRIVATE-ENDPOINT AND LOGIC APP SUBNETS (opt-in, Phase 0 draft)
# Azure Landing Zone policy Deny-Subnet-Without-Nsg requires an NSG on every
# subnet. Associating an NSG with an existing subnet is allowed, so existing
# deployments can turn this on in place. The AVM-based network stack (Phase 2,
# WP-2.6) creates the NSG inline with the subnet, which new ALZ deployments need.
# No rules are added: the default NSG rules keep today's behaviour.
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "pe" {
  count               = var.nsg_on_all_subnets ? 1 : 0
  name                = "nsg-${var.pe_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  count                     = var.nsg_on_all_subnets ? 1 : 0
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe[0].id
}

resource "azurerm_network_security_group" "logic_app" {
  count               = var.nsg_on_all_subnets ? 1 : 0
  name                = "nsg-${var.logic_app_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "logic_app" {
  count                     = var.nsg_on_all_subnets ? 1 : 0
  subnet_id                 = azurerm_subnet.logic_app.id
  network_security_group_id = azurerm_network_security_group.logic_app[0].id
}
