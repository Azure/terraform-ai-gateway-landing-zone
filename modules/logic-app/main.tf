# =============================================================================
# MODULE: Logic App (Standard)
# Usage ingestion — reads from Event Hub, writes to Cosmos DB
# Mirrors: src/usage-ingestion-logicapp/
# =============================================================================

# -----------------------------------------------------------------------------
# STORAGE ACCOUNT (required for Logic App Standard runtime)
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "logic_app" {
  name                     = "stla${var.random_suffix}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags

  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = true
  min_tls_version                  = "TLS1_2"
}

resource "azurerm_storage_share" "logic_app_content" {
  name                 = local.content_share
  storage_account_id   = azurerm_storage_account.logic_app.id
  quota                = 100
}

locals {
  content_share = var.content_share_name != "" ? var.content_share_name : "logic-content-${var.random_suffix}"
  storage_key   = azurerm_storage_account.logic_app.primary_access_key
  storage_cs    = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.logic_app.name};AccountKey=${local.storage_key};EndpointSuffix=core.windows.net"
}

# -----------------------------------------------------------------------------
# STORAGE PRIVATE ENDPOINTS (Bicep parity: functionapp/storageaccount.bicep)
# Blob / File / Table / Queue — one PE per subresource with its DNS zone.
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.enable_storage_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.logic_app.name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.logic_app.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "dns-group"
    private_dns_zone_ids = [var.dns_zone_id_blob]
  }
}

resource "azurerm_private_endpoint" "storage_file" {
  count               = var.enable_storage_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.logic_app.name}-file"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags
  private_service_connection {
    name                           = "psc-file"
    private_connection_resource_id = azurerm_storage_account.logic_app.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "dns-group"
    private_dns_zone_ids = [var.dns_zone_id_file]
  }
}

resource "azurerm_private_endpoint" "storage_table" {
  count               = var.enable_storage_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.logic_app.name}-table"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags
  private_service_connection {
    name                           = "psc-table"
    private_connection_resource_id = azurerm_storage_account.logic_app.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "dns-group"
    private_dns_zone_ids = [var.dns_zone_id_table]
  }
}

resource "azurerm_private_endpoint" "storage_queue" {
  count               = var.enable_storage_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.logic_app.name}-queue"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags
  private_service_connection {
    name                           = "psc-queue"
    private_connection_resource_id = azurerm_storage_account.logic_app.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "dns-group"
    private_dns_zone_ids = [var.dns_zone_id_queue]
  }
}

# -----------------------------------------------------------------------------
# APP SERVICE PLAN (Workflow Standard — Bicep kind=elastic, maxElastic=20)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "logic_app" {
  name                         = "asp-logic-${var.environment_name}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  os_type                      = "Windows"
  sku_name                     = var.sku_size
  maximum_elastic_worker_count = 20 # Bicep parity: hostingPlan.properties.maximumElasticWorkerCount
  tags                         = var.tags
}

# -----------------------------------------------------------------------------
# LOGIC APP STANDARD
# Bicep parity: SystemAssigned + UserAssigned identity.
# -----------------------------------------------------------------------------

resource "azurerm_logic_app_standard" "usage_ingestion" {
  name                       = "logic-usage-${var.environment_name}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  app_service_plan_id        = azurerm_service_plan.logic_app.id
  storage_account_name       = azurerm_storage_account.logic_app.name
  storage_account_access_key = local.storage_key
  storage_account_share_name = local.content_share
  virtual_network_subnet_id  = var.subnet_id
  tags                       = var.tags

  version = "~4"

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # Bicep parity: functionAppSiteConfig — TLS 1.2, FTPS-only, pre-warmed, CORS.
  site_config {
    vnet_route_all_enabled                    = true
    ftps_state                                = "FtpsOnly"
    min_tls_version                           = "1.2"
    scm_min_tls_version                       = "1.2"
    pre_warmed_instance_count                 = 1
    elastic_instance_minimum                  = 1
    runtime_scale_monitoring_enabled          = true

    cors {
      allowed_origins     = ["https://portal.azure.com", "https://ms.portal.azure.com"]
      support_credentials = false
    }
  }

  app_settings = {
    # Bicep parity: full app-settings block from logicapp.bicep.
    # NOTE: the following settings are injected automatically by the
    # azurerm_logic_app_standard provider and MUST NOT be duplicated here
    # (doing so returns 409 "Parameter with name <X> already exists"):
    #   - AzureWebJobsStorage                      (from storage_account_access_key)
    #   - WEBSITE_CONTENTAZUREFILECONNECTIONSTRING (from storage_account_access_key)
    #   - WEBSITE_CONTENTSHARE                     (from storage_account_share_name)
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
    "FUNCTIONS_WORKER_RUNTIME"              = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"          = "~20"
    "WEBSITE_VNET_ROUTE_ALL"                = "0"
    "WEBSITE_CONTENTOVERVNET"               = "1"

    "eventHub_fullyQualifiedNamespace" = var.eventhub_endpoint_host
    "eventHub_name"                    = var.eventhub_ai_usage_hub_name
    "eventHub_pii_name"                = var.eventhub_pii_usage_hub_name

    "AzureFunctionsJobHost_extensionBundle" = "Microsoft.Azure.Functions.ExtensionBundle.Workflows"

    # Cosmos DB app settings
    "AzureCosmosDB_connectionString" = var.cosmos_db_connection_string
    "CosmosDBAccount"           = var.cosmos_db_account_name
    "CosmosDBDatabase"          = var.cosmos_db_database_name
    "CosmosDBContainerConfig"   = var.cosmos_db_container_config
    "CosmosDBContainerUsage"    = var.cosmos_db_container_usage
    "CosmosDBContainerPII"      = var.cosmos_db_container_pii
    "CosmosDBContainerLLMUsage" = var.cosmos_db_container_llm_usage

    # App Insights workbook lookup info
    "AppInsights_SubscriptionId" = var.subscription_id
    "AppInsights_ResourceGroup"  = var.apim_app_insights_rg != "" ? var.apim_app_insights_rg : var.resource_group_name
    "AppInsights_Name"           = var.apim_app_insights_name

    # Azure Monitor API connection (set once the connection exists)
    "AzureMonitor_Resource_Id"        = var.create_azuremonitor_api_connection ? azapi_resource.azuremonitor_connection[0].id : ""
    "AzureMonitor_Api_Id"             = var.create_azuremonitor_api_connection ? "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/azuremonitorlogs" : ""
    "AzureMonitor_ConnectRuntime_Url" = var.create_azuremonitor_api_connection ? try(azapi_resource.azuremonitor_connection[0].output.properties.connectionRuntimeUrl, "") : ""

    # Identity-based pointers used by workflows
    "EVENTHUB_CONNECTION__fullyQualifiedNamespace" = var.eventhub_endpoint_host
    "EVENTHUB_CONNECTION__credential"              = "managedidentity"
    "EVENTHUB_CONNECTION__clientId"                = var.managed_identity_client_id
    "EVENTHUB_HUB_NAME"                            = var.eventhub_ai_usage_hub_name
    "EVENTHUB_CONSUMER_GROUP"                      = "aiUsageIngestion"

    "COSMOSDB_ENDPOINT"  = var.cosmos_db_endpoint
    "COSMOSDB_DATABASE"  = var.cosmos_db_database_name
    "COSMOSDB_CONTAINER" = var.cosmos_db_container_usage
  }
}

# -----------------------------------------------------------------------------
# API CONNECTION: azuremonitorlogs (Bicep parity: api-connection.json)
# Uses azapi — azurerm provider does not model Microsoft.Web/connections.
# -----------------------------------------------------------------------------

resource "azapi_resource" "azuremonitor_connection" {
  count     = var.create_azuremonitor_api_connection ? 1 : 0
  schema_validation_enabled = false
  type      = "Microsoft.Web/connections@2018-07-01-preview"
  name      = "azuremonitorlogs"
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  location  = var.location
  tags      = var.tags

  # `kind = "V2"` is REQUIRED for the connection to support `accessPolicies`
  # children. Without it the connection is created as V1 and the subsequent
  # PUT/GET on `.../accessPolicies/...` returns 400 InvalidApiConnectionAccessPolicy.
  body = {
    kind = "V2"
    properties = {
      alternativeParameterValues = {}
      displayName = "conn-azure-monitor"
      api = {
        id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/azuremonitorlogs"
        location = "global"
      }
      authenticatedUser = {}
      connectionState = "Enabled"
      customParameterValues = {}
      parameterValueSet = {
                    name = "managedIdentityAuth"
                    values = {}
      }
    }
  }

  response_export_values = ["properties.connectionRuntimeUrl"]
}

# Access policy on the API connection for Logic App's system-assigned MI.
resource "azapi_resource" "azuremonitor_connection_access" {
  count                     = var.create_azuremonitor_api_connection ? 1 : 0
  type                      = "Microsoft.Web/connections/accessPolicies@2016-06-01"
  name                      = "azuremonitorlogs-access"
  parent_id                 = azapi_resource.azuremonitor_connection[0].id
  location                  = var.location
  tags                      = var.tags
  schema_validation_enabled = false

  body = {
    properties = {
      principal = {
        type = "ActiveDirectory"
        identity = {
          tenantId = data.azurerm_client_config.current.tenant_id
          objectId = azurerm_logic_app_standard.usage_ingestion.identity[0].principal_id
        }
      }
    }
  }

  depends_on = [azurerm_logic_app_standard.usage_ingestion]
}

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  name                       = "diag-logic-${var.environment_name}"
  target_resource_id         = azurerm_logic_app_standard.usage_ingestion.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "WorkflowRuntime" }
  enabled_metric { category = "AllMetrics" }
}

# -----------------------------------------------------------------------------
# RBAC: Storage roles for the UserAssigned MI (identity-based connectors)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "storage_blob_owner" {
  scope                = azurerm_storage_account.logic_app.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "storage_queue_contributor" {
  scope                = azurerm_storage_account.logic_app.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "storage_table_contributor" {
  scope                = azurerm_storage_account.logic_app.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "storage_account_contributor" {
  scope                = azurerm_storage_account.logic_app.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = var.managed_identity_principal_id
}

# -----------------------------------------------------------------------------
# RBAC on the Logic App SYSTEM-ASSIGNED principal (Bicep parity)
# - Cosmos SQL Role (Data Contributor 00000000-0000-0000-0000-000000000002)
# - Event Hubs Data Owner (RG scope)
# - Monitor Logs Reader (RG scope — for azuremonitorlogs workflows)
# -----------------------------------------------------------------------------

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

resource "azurerm_cosmosdb_sql_role_assignment" "logic_app_system_mi" {
  count               = var.enable_cosmos_role_assignment ? 1 : 0
  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_db_account_name
  role_definition_id  = "${var.cosmos_db_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_logic_app_standard.usage_ingestion.identity[0].principal_id
  scope               = var.cosmos_db_account_id
}

resource "azurerm_role_assignment" "logic_app_system_eh_owner" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = azurerm_logic_app_standard.usage_ingestion.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "logic_app_system_monitor_reader" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_logic_app_standard.usage_ingestion.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
