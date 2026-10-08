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
    { for k, m in module.zone : k => m.resource_id },
    { for k, v in var.existing_zone_ids : lookup(local.byo_key_map, k, k) => v if v != "" },
  )
}

# Zones to link to the VNet. The Azure Monitor private-link zone
# (privatelink.monitor.azure.com) is created (AMPLS references it when enabled)
# but must ONLY be VNet-linked when AMPLS is actually deployed and populates it
# with private-endpoint records. Linking an empty monitor zone resolves App
# Insights / Azure Monitor ingestion endpoints to a dead private zone from
# inside the VNet, blackholing all App Insights telemetry.
locals {
  resource_group_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  linked_zone_keys  = [for k in keys(local.dns_zone_names) : k if k != "monitor" || var.link_monitor_zone]
}

module "zone" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.5.0"
  for_each = var.create_zones ? local.dns_zone_names : {}

  domain_name      = each.value
  parent_id        = local.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  virtual_network_links = contains(local.linked_zone_keys, each.key) ? {
    vnet = {
      name                 = "link-${each.key}"
      virtual_network_id   = var.vnet_id
      registration_enabled = false
    }
  } : {}
}

