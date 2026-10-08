# =============================================================================
# MODULE: Private DNS
# Private DNS zones for the private endpoints (created, or BYO zone IDs) and
# their links to the gateway VNet. The VNet is an input: it comes from
# modules/networking (greenfield) or from an existing network (byo).
# =============================================================================

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

locals {
  # Created zones first; supplied IDs (camelCase keys normalised) override per key.
  zone_ids = merge(
    { for k in keys(local.dns_zone_names) : k => azurerm_private_dns_zone.zones[k].id if var.create_zones },
    { for k, v in var.existing_zone_ids : lookup(local.byo_key_map, k, k) => v if v != "" },
  )
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = var.create_zones ? local.dns_zone_names : {}
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Zones to link to the VNet. The Azure Monitor private-link zone
# (privatelink.monitor.azure.com) is created above (AMPLS references it when
# enabled) but must ONLY be VNet-linked when AMPLS is actually deployed and
# populates it with private-endpoint records. Linking an empty monitor zone
# resolves App Insights / Azure Monitor ingestion endpoints to a dead private
# zone from inside the VNet, blackholing all App Insights telemetry.
locals {
  linked_zone_names = var.link_monitor_zone ? local.dns_zone_names : {
    for k, v in local.dns_zone_names : k => v if k != "monitor"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = var.create_zones ? local.linked_zone_names : {}
  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}
