# =============================================================================
# MODULE: Cosmos DB
# Usage analytics store — mirrors Bicep cosmosdb module
# =============================================================================

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
      # Containers stay below: the module always sets partition_key_version = 2,
      # which would replace (empty) the existing v1 containers.
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
# CONTAINER: usage  (token/request records from APIM)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_container" "usage" {
  name                = "ai-usage-container"
  resource_group_name = var.resource_group_name
  account_name        = local.account_name
  database_name       = local.database_name
  partition_key_paths = ["/productName"]

  indexing_policy {
    indexing_mode = "consistent"
    included_path { path = "/*" }
  }

  default_ttl = -1
}

# -----------------------------------------------------------------------------
# CONTAINER: config  (Logic App configuration documents)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_container" "config" {
  name                = "streaming-export-config"
  resource_group_name = var.resource_group_name
  account_name        = local.account_name
  database_name       = local.database_name
  partition_key_paths = ["/type"]

  indexing_policy {
    indexing_mode = "consistent"
    included_path { path = "/*" }
  }
}

# -----------------------------------------------------------------------------
# CONTAINER: pii  (PII anonymization audit records)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_container" "pii" {
  name                = "pii-usage-container"
  resource_group_name = var.resource_group_name
  account_name        = local.account_name
  database_name       = local.database_name
  partition_key_paths = ["/productName"]

  indexing_policy {
    indexing_mode = "consistent"
    included_path { path = "/*" }
  }

  default_ttl = -1
}

# -----------------------------------------------------------------------------
# CONTAINER: llm-usage  (LLM token usage records)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_container" "llm_usage" {
  name                = "llm-usage-container"
  resource_group_name = var.resource_group_name
  account_name        = local.account_name
  database_name       = local.database_name
  partition_key_paths = ["/productName"]

  indexing_policy {
    indexing_mode = "consistent"
    included_path { path = "/*" }
  }

  default_ttl = -1
}

# -----------------------------------------------------------------------------
# CONTAINER: model-pricing  (Bicep parity: model pricing reference data)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_container" "model_pricing" {
  name                = "model-pricing"
  resource_group_name = var.resource_group_name
  account_name        = local.account_name
  database_name       = local.database_name
  partition_key_paths = ["/model"]

  indexing_policy {
    indexing_mode = "consistent"
    included_path { path = "/*" }
  }
}

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  name                       = "diag-cosmos-${var.account_name}"
  target_resource_id         = local.account_id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "DataPlaneRequests" }
  enabled_log { category = "QueryRuntimeStatistics" }
  enabled_metric { category = "Requests" }
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
