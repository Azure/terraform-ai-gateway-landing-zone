# =============================================================================
# MODULE: Redis (Azure Managed Redis / Redis Enterprise)
#
# Uses azapi with the `2025-07-01` API version to 
# support the newer Balanced_* SKUs that azurerm 4.x doesn't yet model natively.
# =============================================================================



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

# -----------------------------------------------------------------------------
# CONNECTION STRING -> KEY VAULT (the APIM external cache reads it from there)
# APIM can't use Entra auth for Azure Managed Redis, so it needs the access key.
# The key is read with an ephemeral listKeys and written only to the write-only
# value of a Key Vault secret: it's never in Terraform state. The no-op suffix
# keeps the action's resource ID unknown until the database exists, so the read
# runs at apply time on a first deployment.
# -----------------------------------------------------------------------------

ephemeral "azapi_resource_action" "redis_keys" {
  type                   = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id            = "${azapi_resource.redis_db.id}${substr(jsonencode(azapi_resource.redis_db.output), 0, 0)}"
  action                 = "listKeys"
  method                 = "POST"
  response_export_values = ["primaryKey"]
}

# Rewrites the secret (re-reading the key) and pushes its expiry forward: an expiry within
# 90 days satisfies ALZ Enforce-GR-KeyVault, and reads keep working after it. After
# regenerating the Redis keys, re-apply with -replace on this resource to refresh at once.
resource "time_rotating" "connection_string" {
  rotation_days = 60
}

resource "azurerm_key_vault_secret" "connection_string" {
  key_vault_id     = var.key_vault_id
  name             = var.connection_string_secret_name
  value_wo         = "${azapi_resource.redis.output.properties.hostName}:${azapi_resource.redis_db.output.properties.port},password=${ephemeral.azapi_resource_action.redis_keys.output.primaryKey},ssl=true"
  value_wo_version = time_rotating.connection_string.unix
  content_type     = "redis-connection-string"
  expiration_date  = timeadd(time_rotating.connection_string.rfc3339, "${90 * 24}h")
}

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# PRIVATE ENDPOINT
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "redis" {
  count               = var.use_private_endpoint && !var.dns_zone_group_managed_by_policy ? 1 : 0
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

resource "azurerm_private_endpoint" "redis_policy_dns" {
  count               = var.use_private_endpoint && var.dns_zone_group_managed_by_policy ? 1 : 0
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

  # Azure Policy (ALZ Deploy-Private-DNS-Zones) creates the DNS zone group.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}
