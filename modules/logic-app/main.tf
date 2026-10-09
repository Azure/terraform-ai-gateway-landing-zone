# =============================================================================
# MODULE: Logic App (Standard)
# Usage ingestion — reads from Event Hub, writes to Cosmos DB
# Mirrors: src/usage-ingestion-logicapp/
# =============================================================================

# -----------------------------------------------------------------------------
# STORAGE ACCOUNT for the Logic App runtime (Azure Verified Module)
#   workflow_standard  WS plans need a key-based Azure Files content share
#                      (documented shared-key exception, ALZ Deny-Storage-Shared-Key).
#   ase_v3             keyless: shared keys off, OAuth by default, no public
#                      network access, private endpoints only (blob/queue/table),
#                      the runtime uses the usage UAMI (WP-2b.3).
# -----------------------------------------------------------------------------

module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  name             = var.names.storage_account
  location         = var.location
  parent_id        = local.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  account_kind                      = "StorageV2"
  account_sku_name                  = "Standard_LRS"
  access_tier                       = "Hot"
  allow_nested_items_to_be_public   = false
  min_tls_version                   = "TLS1_2"
  local_user_enabled                = false
  cross_tenant_replication_enabled  = false
  shared_access_key_enabled         = !local.use_ase
  default_to_oauth_authentication   = local.use_ase ? true : null
  infrastructure_encryption_enabled = local.use_ase
  allowed_copy_scope                = local.use_ase ? "PrivateLink" : null
  # ase_v3: private endpoints only, unless package uploads are allowed from
  # listed deployer IPs (default action stays Deny).
  public_network_access_enabled = !local.use_ase || local.package_upload_from_ips
  network_rules = local.use_ase ? {
    default_action = "Deny"
    bypass         = toset([])
    ip_rules       = local.package_upload_from_ips ? toset([for r in var.package_upload_ip_rules : trimsuffix(r, "/32")]) : toset([])
    } : {
    default_action = "Allow"
    bypass         = toset(["AzureServices"])
    ip_rules       = toset([])
  }

  blob_properties = local.use_ase ? {
    container_delete_retention_policy = {
      enabled = true
      days    = 7
    }
  } : null

  # Bicep parity (functionapp/storageaccount.bicep): one PE per subresource with
  # its DNS zone (no file PE on ASE: no content share). With ALZ
  # Deploy-Private-DNS-Zones the policy owns the zone groups.
  private_endpoints_manage_dns_zone_group = !var.dns_zone_group_managed_by_policy
  private_endpoints = var.enable_storage_private_endpoints ? {
    for sub, zone in merge(
      {
        blob  = var.dns_zone_id_blob
        table = var.dns_zone_id_table
        queue = var.dns_zone_id_queue
      },
      local.use_ase ? {} : { file = var.dns_zone_id_file },
      ) : sub => {
      name                            = "pe-${var.names.storage_account}-${sub}"
      private_service_connection_name = "psc-${sub}"
      subnet_resource_id              = var.pe_subnet_id
      subresource_name                = sub
      private_dns_zone_group_name     = "dns-group"
      # Zone IDs are always supplied unless policy owns the groups (plan-time known).
      private_dns_zone_resource_ids = var.dns_zone_group_managed_by_policy ? [] : [zone]
      tags                          = var.tags
    }
  } : {}

  shares = local.use_ase ? {} : {
    content = {
      name  = local.content_share
      quota = 100
    }
  }

  # Workflow packages for run-from-package deployments (WP-2b.4).
  containers = local.run_from_package ? {
    deployments = { name = "deployments" }
  } : {}
}

# Workflow Standard only: the runtime connection string needs the account key.
# The keyless (ASE) path never reads keys, so no key ends up in state.
data "azurerm_storage_account" "logic_app" {
  count               = local.use_ase ? 0 : 1
  name                = module.storage.name
  resource_group_name = var.resource_group_name

  depends_on = [module.storage]
}

locals {
  use_ase                 = var.hosting_model == "AppServiceEnvironmentV3"
  run_from_package        = local.use_ase && var.deployment_method == "run_from_package"
  package_upload_from_ips = local.run_from_package && length(var.package_upload_ip_rules) > 0
  resource_group_id       = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  logic_app_name          = var.names.logic_app

  content_share = var.content_share_name != "" ? var.content_share_name : var.names.content_share
  storage_key   = one(data.azurerm_storage_account.logic_app[*].primary_access_key)
  storage_endpoints = {
    for svc in ["blob", "queue", "table"] : svc => "https://${var.names.storage_account}.${svc}.${var.storage_endpoint_suffix}"
  }
}

# -----------------------------------------------------------------------------
# APP SERVICE PLAN (Azure Verified Module)
#   workflow_standard : WS1/WS2/WS3 (Bicep kind=elastic, maxElastic=20)
#   ase_v3            : Isolated v2 (I*v2) in the App Service Environment v3
#                       (modules/app-hosting, or a shared/BYO ASE), with CPU
#                       autoscale between worker_count and max_worker_count.
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
  app_service_environment_id   = local.use_ase ? var.app_service_environment_id : null
  worker_count                 = local.use_ase ? var.ase_worker_count : 1
  maximum_elastic_worker_count = local.use_ase ? null : 20 # Bicep parity: hostingPlan.properties.maximumElasticWorkerCount
  zone_balancing_enabled       = local.use_ase && var.ase_zone_redundant
}

resource "azurerm_monitor_autoscale_setting" "service_plan" {
  count               = local.use_ase ? 1 : 0
  name                = "autoscale-${var.names.app_service_plan}"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = module.service_plan.resource_id
  tags                = var.tags

  profile {
    name = "cpu"

    capacity {
      default = var.ase_worker_count
      minimum = var.ase_worker_count
      maximum = max(var.ase_worker_count, var.ase_max_worker_count)
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = module.service_plan.resource_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = module.service_plan.resource_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT20M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT20M"
      }
    }
  }
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
  ase_app_settings = merge(local.common_app_settings, local.run_from_package && var.enable_code_deploy ? {
    # Workflows run from the package blob, fetched with the usage UAMI (WP-2b.4).
    "WEBSITE_RUN_FROM_PACKAGE"                     = local.package_url
    "WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID" = var.managed_identity_id
    } : {}, {
    "FUNCTIONS_EXTENSION_VERSION"                     = "~4"
    "APP_KIND"                                        = "workflowApp"
    "AzureFunctionsJobHost__extensionBundle__id"      = "Microsoft.Azure.Functions.ExtensionBundle.Workflows"
    "AzureFunctionsJobHost__extensionBundle__version" = "[1.*, 2.0.0)"

    "AzureWebJobsStorage__credential"                = "managedIdentity"
    "AzureWebJobsStorage__managedIdentityResourceId" = var.managed_identity_id
    "AzureWebJobsStorage__blobServiceUri"            = local.storage_endpoints.blob
    "AzureWebJobsStorage__queueServiceUri"           = local.storage_endpoints.queue
    "AzureWebJobsStorage__tableServiceUri"           = local.storage_endpoints.table
  })

  # Keyless guardrail: settings that carry storage keys or connection strings.
  forbidden_keyless_settings = ["AzureWebJobsStorage", "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING", "WEBSITE_CONTENTSHARE", "AzureCosmosDB_connectionString"]
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
      hostingEnvironmentProfile = { id = var.app_service_environment_id }
      httpsOnly                 = true
      clientAffinityEnabled     = false
      publicNetworkAccess       = "Disabled"
      siteConfig = {
        alwaysOn               = true # dedicated plan: keeps Event Hub triggers polling
        ftpsState              = "Disabled"
        minTlsVersion          = "1.2"
        scmMinTlsVersion       = "1.2"
        remoteDebuggingEnabled = false
        use32BitWorkerProcess  = false
        cors = {
          allowedOrigins     = ["https://portal.azure.com", "https://ms.portal.azure.com"]
          supportCredentials = false
        }
        appSettings = [for k, v in local.ase_app_settings : { name = k, value = v }]
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.app_service_environment_id != null
      error_message = "ase_v3 hosting needs app_service_environment_id (modules/app-hosting or a shared ASE)."
    }
    precondition {
      condition     = length(setintersection(keys(local.ase_app_settings), local.forbidden_keyless_settings)) == 0
      error_message = "The keyless (ase_v3) Logic App must not carry key-based settings: ${join(", ", local.forbidden_keyless_settings)}."
    }
  }

  # The runtime reaches storage with the UAMI over the storage private
  # endpoints, so roles + PEs must exist before the site starts.
  depends_on = [
    azurerm_role_assignment.storage_blob_owner,
    azurerm_role_assignment.storage_queue_contributor,
    azurerm_role_assignment.storage_table_contributor,
    azurerm_role_assignment.storage_account_contributor,
    module.storage, # private endpoints
  ]
}

# No basic-auth (FTP / SCM) publishing on the keyless app: deployments use
# Entra ID (run-from-package via the usage UAMI, or Kudu with a bearer token).
resource "azapi_update_resource" "publishing_credentials" {
  for_each = local.use_ase ? toset(["ftp", "scm"]) : toset([])

  type        = "Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01"
  resource_id = "${azapi_resource.usage_ingestion_ase[0].id}/basicPublishingCredentialsPolicies/${each.key}"

  body = {
    properties = {
      allow = false
    }
  }
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

# An ARM PUT is a create-or-update: it succeeds even when Azure Policy already
# created a setting with this name. Azure deletes it with the site.
resource "azapi_resource_action" "logic_app_diagnostics" {
  count = var.enable_diagnostics ? 1 : 0

  type        = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  resource_id = "${local.logic_app_id}/providers/Microsoft.Insights/diagnosticSettings/diag-logic-${var.environment_name}"
  method      = "PUT"

  body = {
    properties = {
      workspaceId = var.log_analytics_id
      logs        = [{ category = "WorkflowRuntime", enabled = true }]
      metrics     = [{ category = "AllMetrics", enabled = true }]
    }
  }
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
