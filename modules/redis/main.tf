# =============================================================================
# MODULE: Redis (Azure Managed Redis / Redis Enterprise)
# Bicep parity: bicep/infra/modules/redis/redis.bicep
#
# Uses azapi with the `2025-07-01` API version to match Bicep exactly and to
# support the newer Balanced_* SKUs that azurerm 4.x doesn't yet model natively.
# =============================================================================

terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

locals {
  uses_sku_capacity = startswith(var.sku_name, "Enterprise_") || startswith(var.sku_name, "EnterpriseFlash_")

  redis_sku = local.uses_sku_capacity ? {
    name     = var.sku_name
    capacity = var.sku_capacity
    } : {
    name = var.sku_name
  }
}

resource "azapi_resource" "redis" {
  type      = "Microsoft.Cache/redisEnterprise@2025-07-01"
  name      = var.name
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  tags      = merge(var.tags, { "azd-service-name" = var.name })

  body = {
    sku = local.redis_sku
    properties = {
      minimumTlsVersion   = var.minimum_tls_version
      publicNetworkAccess = var.public_network_access
    }
  }

  response_export_values = ["properties.hostName"]
}

resource "azapi_resource" "redis_db" {
  type      = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  name      = "default"
  parent_id = azapi_resource.redis.id

  body = {
    properties = {
      accessKeysAuthentication = "Enabled"
      evictionPolicy           = "NoEviction"
      clusteringPolicy         = "EnterpriseCluster"
      clientProtocol           = "Encrypted"
      modules = [
        { name = "RediSearch" }
      ]
      # Azure Managed Redis Private Link guidance: clients connect on 10000.
      port = 10000
    }
  }

  response_export_values = ["properties.port"]
}

# Bicep parity: redisDb.listKeys().primaryKey — used for the APIM service/caches
# connection string.
resource "azapi_resource_action" "redis_keys" {
  type                   = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id            = azapi_resource.redis_db.id
  action                 = "listKeys"
  method                 = "POST"
  response_export_values = ["primaryKey"]
}

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# PRIVATE ENDPOINT
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "redis" {
  count               = var.use_private_endpoint ? 1 : 0
  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azapi_resource.redis.id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.dns_zone_id != "" ? [1] : []
    content {
      name                 = "redis-dns-group"
      private_dns_zone_ids = [var.dns_zone_id]
    }
  }
}
