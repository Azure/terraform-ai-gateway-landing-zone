# =============================================================================
# MODULE: Cosmos DB
# Usage analytics store — mirrors Bicep cosmosdb module
# =============================================================================

locals {
  # Every container: consistent indexing over /*; usage containers never expire items.
  containers = {
    usage         = { name = "ai-usage-container", partition_key = "/productName", default_ttl = -1 }  # token/request records from APIM
    config        = { name = "streaming-export-config", partition_key = "/type", default_ttl = null }  # Logic App configuration documents
    pii           = { name = "pii-usage-container", partition_key = "/productName", default_ttl = -1 } # PII anonymization audit records
    llm_usage     = { name = "llm-usage-container", partition_key = "/productName", default_ttl = -1 } # LLM token usage records
    model_pricing = { name = "model-pricing", partition_key = "/model", default_ttl = null }           # Bicep parity: model pricing reference data
  }
}

module "cosmos" {
  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "0.11.0"

  name                = var.account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { "azd-service-name" = var.account_name })
  enable_telemetry    = var.enable_telemetry

  consistency_policy = {
    consistency_level = "Session"
  }
  geo_locations = [{
    location          = var.location
    failover_priority = 0
    zone_redundant    = false
  }]
  capabilities = [{ name = "EnableServerless" }]

  public_network_access_enabled = var.public_network_access == "Enabled"
  ip_range_filter               = var.public_network_access == "Enabled" ? ["0.0.0.0"] : []

  # Bicep parity: enableAutomaticFailover=true, disableKeyBasedMetadataWriteAccess=true
  automatic_failover_enabled         = true
  access_key_metadata_writes_enabled = false

  backup = {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Local"
  }

  local_authentication_disabled = !var.local_authentication_enabled

  sql_databases = {
    usage = {
      name = "usage-db"
      containers = {
        for k, c in local.containers : k => {
          name                = c.name
          partition_key_paths = [c.partition_key]
          default_ttl         = c.default_ttl
          indexing_policy = {
            indexing_mode  = "consistent"
            included_paths = [{ path = "/*" }]
          }
        }
      }
    }
  }

  private_endpoints_manage_dns_zone_group = !var.dns_zone_group_managed_by_policy
  private_endpoints = {
    sql = {
      name                            = "pe-${var.account_name}"
      private_service_connection_name = "psc-${var.account_name}"
      subnet_resource_id              = var.subnet_id
      subresource_name                = "Sql"
      private_dns_zone_group_name     = "cosmos-dns-group"
      private_dns_zone_resource_ids   = var.dns_zone_id != "" && !var.dns_zone_group_managed_by_policy ? [var.dns_zone_id] : []
      tags                            = var.tags
    }
  }
}

locals {
  account_id    = module.cosmos.resource_id
  account_name  = module.cosmos.name
  database_name = keys(module.cosmos.sql_databases)[0]
}

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
#
# Azure Policy (DeployIfNotExists) may create a setting with this name first.
# An ARM PUT is a true create-or-update, so it succeeds whether the setting
# exists or not (azurerm / azapi_resource would fail with "already exists").
# Azure deletes the setting together with the account.
# -----------------------------------------------------------------------------

resource "azapi_resource_action" "cosmos_diagnostics" {
  count = var.enable_diagnostics ? 1 : 0

  type        = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  resource_id = "${local.account_id}/providers/Microsoft.Insights/diagnosticSettings/diag-cosmos-${var.account_name}"
  method      = "PUT"

  body = {
    properties = {
      workspaceId = var.log_analytics_id
      logs = [
        { category = "DataPlaneRequests", enabled = true },
        { category = "QueryRuntimeStatistics", enabled = true },
      ]
      metrics = [
        { category = "Requests", enabled = true },
      ]
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC: Grant UAMI "Cosmos DB Built-in Data Contributor" for data operations
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_role_assignment" "uami_data_contributor" {
  resource_group_name = var.resource_group_name
  account_name        = local.account_name
  role_definition_id  = "${local.account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.managed_identity_principal_id
  scope               = local.account_id
}
