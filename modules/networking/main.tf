# =============================================================================
# MODULE: Networking
# Virtual Network, Subnets, NSGs, Route Tables, Private DNS Zones
# =============================================================================

# -----------------------------------------------------------------------------
# EXISTING VNET DATA SOURCE
# -----------------------------------------------------------------------------

data "azurerm_virtual_network" "existing" {
  count               = var.use_existing_vnet ? 1 : 0
  name                = var.vnet_name
  resource_group_name = var.existing_vnet_rg
}

data "azurerm_subnet" "existing_apim" {
  count                = var.use_existing_vnet ? 1 : 0
  name                 = var.apim_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.existing_vnet_rg
}

data "azurerm_subnet" "existing_pe" {
  count                = var.use_existing_vnet ? 1 : 0
  name                 = var.pe_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.existing_vnet_rg
}

data "azurerm_subnet" "existing_logic_app" {
  count                = var.use_existing_vnet ? 1 : 0
  name                 = var.logic_app_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.existing_vnet_rg
}

data "azurerm_subnet" "existing_agent" {
  count                = var.use_existing_vnet && var.enable_agent_subnet && var.agent_subnet_name != "" ? 1 : 0
  name                 = var.agent_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.existing_vnet_rg
}

# -----------------------------------------------------------------------------
# NEW VNET
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "citadel" {
  count               = var.use_existing_vnet ? 0 : 1
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_prefix]
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# NSG FOR AGENT SUBNET (if enabled)
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "agent" {
  count               = !var.use_existing_vnet && var.enable_agent_subnet ? 1 : 0
  name                = "nsg-${var.agent_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# NSG FOR APIM SUBNET
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "apim" {
  count               = var.use_existing_vnet ? 0 : 1
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

  # Outbound: Key Vault
  dynamic "security_rule" {
    for_each = var.is_apim_vnet ? [1] : []
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
  count               = !var.use_existing_vnet && var.is_apim_vnet ? 1 : 0
  name                = "rt-${var.apim_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  route {
    name                   = "apim-management"
    address_prefix         = "ApiManagement"
    next_hop_type          = "Internet"
  }
}

# -----------------------------------------------------------------------------
# SUBNETS (new VNet)
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "apim" {
  count                = var.use_existing_vnet ? 0 : 1
  name                 = var.apim_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel[0].name
  address_prefixes     = [var.apim_subnet_prefix]
  service_endpoints = ["Microsoft.CognitiveServices"]
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  count                     = var.use_existing_vnet ? 0 : 1
  subnet_id                 = azurerm_subnet.apim[0].id
  network_security_group_id = azurerm_network_security_group.apim[0].id
}

resource "azurerm_subnet_route_table_association" "apim" {
  count          = !var.use_existing_vnet && var.is_apim_vnet ? 1 : 0
  subnet_id      = azurerm_subnet.apim[0].id
  route_table_id = azurerm_route_table.apim[0].id
}

resource "azurerm_subnet" "pe" {
  count                = var.use_existing_vnet ? 0 : 1
  name                 = var.pe_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel[0].name
  address_prefixes     = [var.pe_subnet_prefix]
  service_endpoints = ["Microsoft.CognitiveServices"]
}

resource "azurerm_subnet" "logic_app" {
  count                = var.use_existing_vnet ? 0 : 1
  name                 = var.logic_app_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel[0].name
  address_prefixes     = [var.logic_app_subnet_prefix]
  service_endpoints = ["Microsoft.CognitiveServices"]

  delegation {
    name = "delegation-web"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "agent" {
  count                = !var.use_existing_vnet && var.enable_agent_subnet ? 1 : 0
  name                 = var.agent_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.citadel[0].name
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
  count                     = !var.use_existing_vnet && var.enable_agent_subnet ? 1 : 0
  subnet_id                 = azurerm_subnet.agent[0].id
  network_security_group_id = azurerm_network_security_group.agent[0].id
}

# -----------------------------------------------------------------------------
# PRIVATE DNS ZONES (create new if needed)
# -----------------------------------------------------------------------------

locals {
  dns_zone_names = {
    key_vault          = "privatelink.vaultcore.azure.net"
    cosmos_db          = "privatelink.documents.azure.com"
    event_hub          = "privatelink.servicebus.windows.net"
    cognitive_services = "privatelink.cognitiveservices.azure.com"
    openai             = "privatelink.openai.azure.com"
    storage_blob       = "privatelink.blob.core.windows.net"
    storage_file       = "privatelink.file.core.windows.net"
    storage_table      = "privatelink.table.core.windows.net"
    storage_queue      = "privatelink.queue.core.windows.net"
    monitor            = "privatelink.monitor.azure.com"
    apim_gateway       = "privatelink.azure-api.net"
    ai_services        = "privatelink.services.ai.azure.com"
    redis              = "privatelink.redis.azure.net"
  }

  # Bicep uses camelCase keys in `existingPrivateDnsZones`; normalize them to
  # our internal snake_case so the output map is consistent regardless of which
  # style the caller provides.
  byo_key_map = {
    keyVault          = "key_vault"
    cosmosDb          = "cosmos_db"
    eventHub          = "event_hub"
    cognitiveServices = "cognitive_services"
    openAi            = "openai"
    storageBlob       = "storage_blob"
    storageFile       = "storage_file"
    storageTable      = "storage_table"
    storageQueue      = "storage_queue"
    apimGateway       = "apim_gateway"
    aiServices        = "ai_services"
  }
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = var.create_dns_zones ? local.dns_zone_names : {}
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = var.create_dns_zones ? local.dns_zone_names : {}
  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = var.use_existing_vnet ? data.azurerm_virtual_network.existing[0].id : azurerm_virtual_network.citadel[0].id
  registration_enabled  = false
}
