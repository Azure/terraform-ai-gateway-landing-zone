# =============================================================================
# Adopt existing v1 resources into Azure Verified Modules (Phase 2)
# =============================================================================
# Some AVM modules manage their resource with azapi, where v1 used azurerm. A
# moved {} block can't cross resource types, so the v1 resource is dropped from
# state with removed { destroy = false } (in the owning module) and imported
# here.
#
# Upgrading an environment deployed before Phase 2: set
# adopt_existing_resources = true for the upgrade run. Each import then runs
# only when the Azure resource exists (probed at plan time); once it is in
# state the import is a no-op. Greenfield deployments leave it false: their
# names contain a random suffix that isn't known until the first apply, so a
# probe can't be planned.
# =============================================================================

locals {
  adopt_rg_id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}"

  adopt_targets = {
    usage_storage = {
      type = "Microsoft.Storage/storageAccounts@2025-01-01"
      id   = "${local.adopt_rg_id}/providers/Microsoft.Storage/storageAccounts/${local.names.storage_logic}"
    }
    usage_service_plan = {
      type = "Microsoft.Web/serverfarms@2024-11-01"
      id   = "${local.adopt_rg_id}/providers/Microsoft.Web/serverfarms/${local.names.app_service_plan}"
    }
  }
  # Content share name exactly as modules/logic-app computes it.
  adopt_content_share = local.usage_cfg.logic_app.content_share_name != "" ? local.usage_cfg.logic_app.content_share_name : local.names.logic_content_share
}

data "azapi_resource" "adopt" {
  for_each = var.adopt_existing_resources ? local.adopt_targets : {}

  type             = each.value.type
  resource_id      = each.value.id
  ignore_not_found = true
}

data "azapi_resource" "adopt_content_share" {
  count = var.adopt_existing_resources && local.usage_cfg.logic_app.hosting == "workflow_standard" ? 1 : 0

  type             = "Microsoft.Storage/storageAccounts/fileServices/shares@2025-01-01"
  resource_id      = "${local.adopt_targets.usage_storage.id}/fileServices/default/shares/${local.adopt_content_share}"
  ignore_not_found = true
}

import {
  for_each = try(data.azapi_resource.adopt["usage_storage"].exists, false) ? toset(["x"]) : toset([])
  to       = module.logic_app.module.storage.azapi_resource.this
  id       = local.adopt_targets.usage_storage.id
}

import {
  for_each = try(data.azapi_resource.adopt_content_share[0].exists, false) ? toset(["x"]) : toset([])
  to       = module.logic_app.module.storage.module.shares["content"].azapi_resource.this
  id       = "${local.adopt_targets.usage_storage.id}/fileServices/default/shares/${local.adopt_content_share}"
}

import {
  for_each = try(data.azapi_resource.adopt["usage_service_plan"].exists, false) ? toset(["x"]) : toset([])
  to       = module.logic_app.module.service_plan.azapi_resource.this
  id       = local.adopt_targets.usage_service_plan.id
}

# -----------------------------------------------------------------------------
# WP-2.6: greenfield network (VNet, subnets, NSGs + rules, private DNS zones and
# their VNet links) on Azure Verified Modules.
# -----------------------------------------------------------------------------

locals {
  adopt_network = var.adopt_existing_resources && !local.network_cfg.byo
  adopt_vnet_id = "${local.adopt_rg_id}/providers/Microsoft.Network/virtualNetworks/${local.vnet_name}"

  adopt_subnets = merge(
    {
      apim      = local.network_cfg.subnets.apim.name
      pe        = local.network_cfg.subnets.private_endpoint.name
      logic_app = local.network_cfg.subnets.logic_app.name
    },
    local.network_cfg.subnets.agent.enabled ? { agent = local.network_cfg.subnets.agent.name } : {},
    local.enable_ase_subnet ? { ase = local.network_cfg.subnets.ase.name } : {},
  )
  # Same rule names modules/networking puts on the APIM NSG.
  adopt_apim_rules = concat(
    local.apim_network_type == "External" && local.is_apim_vnet ? ["AllowHTTPS"] : [],
    local.is_apim_vnet ? ["AllowAPIMManagement", "AllowLoadBalancer", "AllowStorage", "AllowSQL", "AllowMonitor"] : [],
    local.is_apim_vnet || local.is_apim_v2 ? ["AllowKeyVault"] : [],
  )
  adopt_dns_zones = local.adopt_network && local.create_dns_zones ? {
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
  } : {}
  adopt_dns_links = { for k, z in local.adopt_dns_zones : k => z if k != "monitor" || local.monitoring_cfg.private_link_scope }
}

data "azapi_resource" "adopt_vnet" {
  count            = local.adopt_network ? 1 : 0
  type             = "Microsoft.Network/virtualNetworks@2024-07-01"
  resource_id      = local.adopt_vnet_id
  ignore_not_found = true
}

data "azapi_resource" "adopt_nsg" {
  for_each         = local.adopt_network ? local.adopt_subnets : {}
  type             = "Microsoft.Network/networkSecurityGroups@2024-07-01"
  resource_id      = "${local.adopt_rg_id}/providers/Microsoft.Network/networkSecurityGroups/nsg-${each.value}"
  ignore_not_found = true
}

data "azapi_resource" "adopt_dns_link" {
  for_each         = local.adopt_dns_links
  type             = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01"
  resource_id      = "${local.adopt_rg_id}/providers/Microsoft.Network/privateDnsZones/${each.value}/virtualNetworkLinks/link-${each.key}"
  ignore_not_found = true
}

locals {
  adopt_vnet_exists = try(data.azapi_resource.adopt_vnet[0].exists, false)
}

import {
  for_each = local.adopt_vnet_exists ? toset(["x"]) : toset([])
  to       = module.networking[0].module.vnet[0].azapi_resource.vnet
  id       = local.adopt_vnet_id
}

# Subnets exist whenever the v1 VNet does (v1 created them together).
import {
  for_each = local.adopt_vnet_exists ? local.adopt_subnets : {}
  to       = module.networking[0].module.vnet[0].module.subnet[each.key].azapi_resource.subnet[0]
  id       = "${local.adopt_vnet_id}/subnets/${each.value}"
}

import {
  for_each = { for k, n in local.adopt_subnets : k => n if try(data.azapi_resource.adopt_nsg[k].exists, false) }
  to       = module.networking[0].module.nsg[each.key].azapi_resource.this
  id       = "${local.adopt_rg_id}/providers/Microsoft.Network/networkSecurityGroups/nsg-${each.value}"
}

import {
  for_each = try(data.azapi_resource.adopt_nsg["apim"].exists, false) ? toset(local.adopt_apim_rules) : toset([])
  to       = module.networking[0].module.nsg["apim"].azapi_resource.security_rules[each.key]
  id       = "${local.adopt_rg_id}/providers/Microsoft.Network/networkSecurityGroups/nsg-${local.adopt_subnets.apim}/securityRules/${each.key}"
}

# Zones exist whenever the v1 VNet does (v1 created them with the network).
import {
  for_each = local.adopt_vnet_exists ? local.adopt_dns_zones : {}
  to       = module.private_dns.module.zone[each.key].azapi_resource.private_dns_zone
  id       = "${local.adopt_rg_id}/providers/Microsoft.Network/privateDnsZones/${each.value}"
}

import {
  for_each = { for k, z in local.adopt_dns_links : k => z if try(data.azapi_resource.adopt_dns_link[k].exists, false) }
  to       = module.private_dns.module.zone[each.key].module.virtual_network_links["vnet"].azapi_resource.private_dns_zone_network_link
  id       = "${local.adopt_rg_id}/providers/Microsoft.Network/privateDnsZones/${each.value}/virtualNetworkLinks/link-${each.key}"
}
