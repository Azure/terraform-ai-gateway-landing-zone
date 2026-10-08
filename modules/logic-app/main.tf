# =============================================================================
# MODULE: Logic App (Standard)
# Usage ingestion — reads from Event Hub, writes to Cosmos DB
# Mirrors: src/usage-ingestion-logicapp/
# =============================================================================

# -----------------------------------------------------------------------------
# STORAGE ACCOUNT (required for Logic App Standard runtime) — Azure Verified
# Module. Existing v1 accounts are adopted by the root (adopt.tf).
# -----------------------------------------------------------------------------

module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  name             = var.names.storage_account
  location         = var.location
  parent_id        = local.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  account_kind                    = "StorageV2"
  account_sku_name                = "Standard_LRS"
  access_tier                     = "Hot"
  allow_nested_items_to_be_public = false
  # Workflow Service Plan needs a key-based Azure Files content share; on ASE v3
  # the runtime authenticates with the usage UAMI, so shared keys are disabled.
  shared_access_key_enabled = !local.use_ase
  min_tls_version           = "TLS1_2"
  # v1 behaviour kept (public endpoint open, private endpoints for the runtime);
  # tightening is part of the keyless pipeline (Phase 2b).
  public_network_access_enabled = true
  local_user_enabled            = true
  network_rules = {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  shares = local.use_ase ? {} : {
    content = {
      name  = local.content_share
      quota = 100
    }
  }
}

# Keys and endpoints for the Logic App runtime settings. Read after the account
# exists (depends_on), so a brand-new account doesn't fail the plan.
data "azurerm_storage_account" "logic_app" {
  name                = module.storage.name
  resource_group_name = var.resource_group_name

  depends_on = [module.storage]
}

locals {
  use_ase           = var.hosting_model == "AppServiceEnvironmentV3"
  resource_group_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  logic_app_name    = var.names.logic_app

  content_share = var.content_share_name != "" ? var.content_share_name : var.names.content_share
  storage_key   = data.azurerm_storage_account.logic_app.primary_access_key
}

# -----------------------------------------------------------------------------
# STORAGE PRIVATE ENDPOINTS (Bicep parity: functionapp/storageaccount.bicep)
# Blob / File / Table / Queue — one PE per subresource with its DNS zone.
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.enable_storage_private_endpoints ? 1 : 0
  name                = "pe-${module.storage.name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = module.storage.resource_id
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
  name                = "pe-${module.storage.name}-file"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags
  private_service_connection {
    name                           = "psc-file"
    private_connection_resource_id = module.storage.resource_id
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
  name                = "pe-${module.storage.name}-table"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags
  private_service_connection {
    name                           = "psc-table"
    private_connection_resource_id = module.storage.resource_id
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
  name                = "pe-${module.storage.name}-queue"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags
  private_service_connection {
    name                           = "psc-queue"
    private_connection_resource_id = module.storage.resource_id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "dns-group"
    private_dns_zone_ids = [var.dns_zone_id_queue]
  }
}

# -----------------------------------------------------------------------------
# APP SERVICE PLAN
#   WorkflowStandard        : WS1/WS2/WS3 (Bicep kind=elastic, maxElastic=20)
#   AppServiceEnvironmentV3 : Isolated v2 (I*v2) inside the ASE (see ase.tf)
# -----------------------------------------------------------------------------

module "service_plan" {
  source  = "Azure/avm-res-web-serverfarm/azurerm"
  version = "2.0.8"

  name             = var.names.app_service_plan
  location         = var.location
  parent_id        = local.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  os_type                      = "Windows"
  sku_name                     = local.use_ase ? var.ase_sku_size : var.sku_size
  app_service_environment_id   = local.use_ase ? azurerm_app_service_environment_v3.ase[0].id : null
  worker_count                 = local.use_ase ? var.ase_worker_count : 1
  maximum_elastic_worker_count = local.use_ase ? null : 20 # Bicep parity: hostingPlan.properties.maximumElasticWorkerCount
  zone_balancing_enabled       = false
}

locals {
  # App settings shared by both hosting models (Bicep parity: logicapp.bicep).
  common_app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
    "FUNCTIONS_WORKER_RUNTIME"              = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"          = "~20"

    "eventHub_fullyQualifiedNamespace" = var.eventhub_endpoint_host
    "eventHub_name"                    = var.eventhub_ai_usage_hub_name
    "eventHub_pii_name"                = var.eventhub_pii_usage_hub_name

    "AzureFunctionsJobHost_extensionBundle" = "Microsoft.Azure.Functions.ExtensionBundle.Workflows"

    # Cosmos DB app settings. The AzureCosmosDB connection (connections.json)
    # authenticates with the Logic App system-assigned MI (Cosmos Built-in Data
    # Contributor, see logic_app_system_mi) — no account key.
    "AzureCosmosDB_accountEndpoint" = var.cosmos_db_endpoint
    "CosmosDBAccount"               = var.cosmos_db_account_name
    "CosmosDBDatabase"              = var.cosmos_db_database_name
    "CosmosDBContainerConfig"       = var.cosmos_db_container_config
    "CosmosDBContainerUsage"        = var.cosmos_db_container_usage
    "CosmosDBContainerPII"          = var.cosmos_db_container_pii
    "CosmosDBContainerLLMUsage"     = var.cosmos_db_container_llm_usage

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

  # ASE v3: settings azurerm_logic_app_standard would otherwise inject, plus
  # identity-based runtime storage (UAMI only — system-assigned isn't supported).
  # https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account
  ase_app_settings = merge(local.common_app_settings, {
    "FUNCTIONS_EXTENSION_VERSION"                     = "~4"
    "APP_KIND"                                        = "workflowApp"
    "AzureFunctionsJobHost__extensionBundle__id"      = "Microsoft.Azure.Functions.ExtensionBundle.Workflows"
    "AzureFunctionsJobHost__extensionBundle__version" = "[1.*, 2.0.0)"

    "AzureWebJobsStorage__credential"                = "managedIdentity"
    "AzureWebJobsStorage__managedIdentityResourceId" = var.managed_identity_id
    "AzureWebJobsStorage__blobServiceUri"            = trimsuffix(data.azurerm_storage_account.logic_app.primary_blob_endpoint, "/")
    "AzureWebJobsStorage__queueServiceUri"           = trimsuffix(data.azurerm_storage_account.logic_app.primary_queue_endpoint, "/")
    "AzureWebJobsStorage__tableServiceUri"           = trimsuffix(data.azurerm_storage_account.logic_app.primary_table_endpoint, "/")
  })
}

# -----------------------------------------------------------------------------
# LOGIC APP STANDARD — Workflow Service Plan (default)
# Bicep parity: SystemAssigned + UserAssigned identity.
# -----------------------------------------------------------------------------

resource "azurerm_logic_app_standard" "usage_ingestion" {
  count               = local.use_ase ? 0 : 1
  name                = local.logic_app_name
  location            = var.location
  resource_group_name = var.resource_group_name
  # azurerm expects ".../serverFarms/..."; the AVM (azapi) ID uses ".../serverfarms/".
  app_service_plan_id        = replace(module.service_plan.resource_id, "Microsoft.Web/serverfarms", "Microsoft.Web/serverFarms")
  storage_account_name       = module.storage.name
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
    vnet_route_all_enabled           = true
    ftps_state                       = "FtpsOnly"
    min_tls_version                  = "1.2"
    scm_min_tls_version              = "1.2"
    pre_warmed_instance_count        = 1
    elastic_instance_minimum         = 1
    runtime_scale_monitoring_enabled = true

    cors {
      allowed_origins     = ["https://portal.azure.com", "https://ms.portal.azure.com"]
      support_credentials = false
    }
  }

  # NOTE: the following settings are injected automatically by the
  # azurerm_logic_app_standard provider and MUST NOT be duplicated here
  # (doing so returns 409 "Parameter with name <X> already exists"):
  #   - AzureWebJobsStorage                      (from storage_account_access_key)
  #   - WEBSITE_CONTENTAZUREFILECONNECTIONSTRING (from storage_account_access_key)
  #   - WEBSITE_CONTENTSHARE                     (from storage_account_share_name)
  app_settings = merge(local.common_app_settings, {
    "WEBSITE_VNET_ROUTE_ALL"  = "0"
    "WEBSITE_CONTENTOVERVNET" = "1"
  })

  depends_on = [module.storage]
}

moved {
  from = azurerm_logic_app_standard.usage_ingestion
  to   = azurerm_logic_app_standard.usage_ingestion[0]
}

# -----------------------------------------------------------------------------
# LOGIC APP STANDARD — App Service Environment v3 (opt-in)
# azapi because azurerm_logic_app_standard requires storage_account_access_key
# and always injects a key-based AzureWebJobsStorage connection string.
# The app lives inside the ASE subnet, so no regional VNet integration, content
# share, elastic scale or runtime scale monitoring (unsupported on ASE).
# -----------------------------------------------------------------------------

resource "azapi_resource" "usage_ingestion_ase" {
  count = local.use_ase ? 1 : 0
  type  = "Microsoft.Web/sites@2024-04-01"
  name  = local.logic_app_name
  # Built from inputs (not the data source): module-level depends_on defers the
  # data read to apply time, which would make parent_id unknown and force a
  # replacement whenever an upstream module has pending changes.
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  location  = var.location
  tags      = var.tags

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  body = {
    kind = "functionapp,workflowapp"
    properties = {
      # ARM returns ".../serverfarms/..." (lower-case); match it to avoid a perpetual diff.
      serverFarmId              = replace(module.service_plan.resource_id, "Microsoft.Web/serverFarms", "Microsoft.Web/serverfarms")
      hostingEnvironmentProfile = { id = azurerm_app_service_environment_v3.ase[0].id }
      httpsOnly                 = true
      clientAffinityEnabled     = false
      siteConfig = {
        alwaysOn              = true # dedicated plan: keeps Event Hub triggers polling
        ftpsState             = "FtpsOnly"
        minTlsVersion         = "1.2"
        scmMinTlsVersion      = "1.2"
        use32BitWorkerProcess = false
        cors = {
          allowedOrigins     = ["https://portal.azure.com", "https://ms.portal.azure.com"]
          supportCredentials = false
        }
        appSettings = [for k, v in local.ase_app_settings : { name = k, value = v }]
      }
    }
  }

  # The runtime reaches storage with the UAMI over the storage private
  # endpoints, so roles + PEs must exist before the site starts.
  depends_on = [
    azurerm_role_assignment.storage_blob_owner,
    azurerm_role_assignment.storage_queue_contributor,
    azurerm_role_assignment.storage_table_contributor,
    azurerm_role_assignment.storage_account_contributor,
    azurerm_private_endpoint.storage_blob,
    azurerm_private_endpoint.storage_queue,
    azurerm_private_endpoint.storage_table,
  ]
}

locals {
  logic_app_id = one(concat(
    azurerm_logic_app_standard.usage_ingestion[*].id,
    azapi_resource.usage_ingestion_ase[*].id,
  ))
  logic_app_principal_id = one(concat(
    [for la in azurerm_logic_app_standard.usage_ingestion : la.identity[0].principal_id],
    [for la in azapi_resource.usage_ingestion_ase : la.identity[0].principal_id],
  ))
}

# -----------------------------------------------------------------------------
# API CONNECTION: azuremonitorlogs (Bicep parity: api-connection.json)
# Uses azapi — azurerm provider does not model Microsoft.Web/connections.
# -----------------------------------------------------------------------------

resource "azapi_resource" "azuremonitor_connection" {
  count                     = var.create_azuremonitor_api_connection ? 1 : 0
  schema_validation_enabled = false
  type                      = "Microsoft.Web/connections@2018-07-01-preview"
  name                      = "azuremonitorlogs"
  parent_id                 = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  location                  = var.location
  tags                      = var.tags

  # `kind = "V2"` is REQUIRED for the connection to support `accessPolicies`
  # children. Without it the connection is created as V1 and the subsequent
  # PUT/GET on `.../accessPolicies/...` returns 400 InvalidApiConnectionAccessPolicy.
  body = {
    kind = "V2"
    properties = {
      alternativeParameterValues = {}
      displayName                = "conn-azure-monitor"
      api = {
        id       = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/azuremonitorlogs"
        location = "global"
      }
      authenticatedUser     = {}
      connectionState       = "Enabled"
      customParameterValues = {}
      parameterValueSet = {
        name   = "managedIdentityAuth"
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
          objectId = local.logic_app_principal_id
        }
      }
    }
  }

  depends_on = [azurerm_logic_app_standard.usage_ingestion, azapi_resource.usage_ingestion_ase]
}

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  name                       = "diag-logic-${var.environment_name}"
  target_resource_id         = local.logic_app_id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "WorkflowRuntime" }
  enabled_metric { category = "AllMetrics" }
}

# -----------------------------------------------------------------------------
# RBAC: Storage roles for the UserAssigned MI (identity-based connectors)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "storage_blob_owner" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "storage_queue_contributor" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "storage_table_contributor" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "storage_account_contributor" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Account Contributor"
  principal_id         = var.managed_identity_principal_id
}

# -----------------------------------------------------------------------------
# RBAC on the Logic App SYSTEM-ASSIGNED principal (Bicep parity)
# - Cosmos SQL Role (Data Contributor 00000000-0000-0000-0000-000000000002)
# - Event Hubs Data Owner (RG scope)
# - Monitor Logs Reader (RG scope — for azuremonitorlogs workflows)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_role_assignment" "logic_app_system_mi" {
  count               = var.enable_cosmos_role_assignment ? 1 : 0
  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_db_account_name
  role_definition_id  = "${var.cosmos_db_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = local.logic_app_principal_id
  scope               = var.cosmos_db_account_id
}

resource "azurerm_role_assignment" "logic_app_system_eh_owner" {
  scope                = var.resource_group_id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = local.logic_app_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "logic_app_system_monitor_reader" {
  scope                = var.resource_group_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = local.logic_app_principal_id
  principal_type       = "ServicePrincipal"
}

# -----------------------------------------------------------------------------
# v1 -> AVM (WP-2.3): the azurerm storage account, content share and plan leave
# the state without being destroyed; the root (adopt.tf) imports the same Azure
# resources into the AVM modules.
# -----------------------------------------------------------------------------

removed {
  from = azurerm_storage_account.logic_app
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_storage_share.logic_app_content
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_service_plan.logic_app
  lifecycle {
    destroy = false
  }
}
