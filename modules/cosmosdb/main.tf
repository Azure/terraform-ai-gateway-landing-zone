# =============================================================================
# MODULE: Cosmos DB
# Usage analytics store — mirrors Bicep cosmosdb module
# =============================================================================

resource "azurerm_cosmosdb_account" "citadel" {
  name                = var.account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = merge(var.tags, { "azd-service-name" = var.account_name })

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  public_network_access_enabled = var.public_network_access == "Enabled" ? true : false

  ip_range_filter = var.public_network_access == "Enabled" ? toset(["0.0.0.0"]) : null

  is_virtual_network_filter_enabled = false

  # Bicep parity: enableAutomaticFailover=true, disableKeyBasedMetadataWriteAccess=true
  automatic_failover_enabled            = true
  access_key_metadata_writes_enabled    = false

  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Local"
  }

  local_authentication_disabled = false
}

# -----------------------------------------------------------------------------
# DATABASE: usage-db
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_database" "usage" {
  name                = "usage-db"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.citadel.name
}

# -----------------------------------------------------------------------------
# CONTAINER: usage  (token/request records from APIM)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_container" "usage" {
  name                = "ai-usage-container"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.citadel.name
  database_name       = azurerm_cosmosdb_sql_database.usage.name
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
  account_name        = azurerm_cosmosdb_account.citadel.name
  database_name       = azurerm_cosmosdb_sql_database.usage.name
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
  account_name        = azurerm_cosmosdb_account.citadel.name
  database_name       = azurerm_cosmosdb_sql_database.usage.name
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
  account_name        = azurerm_cosmosdb_account.citadel.name
  database_name       = azurerm_cosmosdb_sql_database.usage.name
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
  account_name        = azurerm_cosmosdb_account.citadel.name
  database_name       = azurerm_cosmosdb_sql_database.usage.name
  partition_key_paths = ["/model"]

  indexing_policy {
    indexing_mode = "consistent"
    included_path { path = "/*" }
  }
}

# -----------------------------------------------------------------------------
# PRIVATE ENDPOINT
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-${var.account_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.account_name}"
    private_connection_resource_id = azurerm_cosmosdb_account.citadel.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.dns_zone_id != "" ? [1] : []
    content {
      name                 = "cosmos-dns-group"
      private_dns_zone_ids = [var.dns_zone_id]
    }
  }
}

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  name                       = "diag-cosmos-${var.account_name}"
  target_resource_id         = azurerm_cosmosdb_account.citadel.id
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
  account_name        = azurerm_cosmosdb_account.citadel.name
  role_definition_id  = "${azurerm_cosmosdb_account.citadel.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.managed_identity_principal_id
  scope               = azurerm_cosmosdb_account.citadel.id
}
