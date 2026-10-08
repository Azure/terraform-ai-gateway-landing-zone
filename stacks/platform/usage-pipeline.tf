# The ASE of stacks/app-hosting, found by name (or a shared ASE by ID).
data "azapi_resource" "ase" {
  count     = local.usage_cfg.logic_app.hosting == "ase_v3" && local.usage_cfg.ase.app_service_environment_id == null ? 1 : 0
  type      = "Microsoft.Web/hostingEnvironments@2024-04-01"
  name      = local.names.app_service_environment
  parent_id = local.resource_group_id
}

locals {
  app_service_environment_id = local.usage_cfg.logic_app.hosting != "ase_v3" ? null : coalesce(
    local.usage_cfg.ase.app_service_environment_id, try(data.azapi_resource.ase[0].id, null)
  )
}

# Usage ingestion Logic App (Standard). ase_v3: Isolated v2 plan in the ASE with
# keyless storage and run-from-package; workflow_standard: WS plan (shared key).
module "logic_app" {
  source = "../../modules/logic-app"

  resource_group_id   = local.resource_group_id
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  environment_name    = module.naming.base
  subscription_id     = var.subscription_id
  enable_telemetry    = var.enable_telemetry
  names = {
    storage_account         = local.names.storage_logic
    logic_app               = local.names.logic_app
    content_share           = local.names.logic_content_share
    app_service_plan        = local.names.app_service_plan
    app_service_environment = local.names.app_service_environment
    code_artifact           = local.names.logic_app_code_artifact
  }

  sku_size                   = local.usage_cfg.logic_app.ws_sku
  hosting_model              = local.usage_cfg.logic_app.hosting_model
  app_service_environment_id = local.app_service_environment_id
  ase_sku_size               = local.usage_cfg.logic_app.ase_sku
  ase_worker_count           = local.usage_cfg.logic_app.worker_count
  ase_max_worker_count       = local.usage_cfg.logic_app.max_worker_count
  ase_zone_redundant         = local.usage_cfg.ase.zone_redundant
  deployment_method          = local.usage_cfg.logic_app.deployment
  package_upload_ip_rules    = local.dev_cidrs

  subnet_id                        = coalesce(local.network.subnet_ids.logic_app, "-") == "-" ? "" : local.network.subnet_ids.logic_app
  pe_subnet_id                     = local.network.subnet_ids.pe
  dns_zone_id_blob                 = lookup(local.zone_ids, "storage_blob", "")
  dns_zone_id_file                 = lookup(local.zone_ids, "storage_file", "")
  dns_zone_id_table                = lookup(local.zone_ids, "storage_table", "")
  dns_zone_id_queue                = lookup(local.zone_ids, "storage_queue", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy

  eventhub_endpoint_host      = "${module.eventhub.namespace_name}.servicebus.windows.net"
  eventhub_ai_usage_hub_name  = module.eventhub.apim_usage_hub_name
  eventhub_pii_usage_hub_name = module.eventhub.pii_usage_hub_name

  cosmos_db_endpoint            = module.cosmosdb.endpoint
  cosmos_db_account_name        = module.cosmosdb.account_name
  cosmos_db_account_id          = module.cosmosdb.account_id
  cosmos_db_database_name       = module.cosmosdb.database_name
  cosmos_db_container_config    = module.cosmosdb.config_container_name
  cosmos_db_container_usage     = module.cosmosdb.usage_container_name
  cosmos_db_container_pii       = module.cosmosdb.pii_container_name
  cosmos_db_container_llm_usage = module.cosmosdb.llm_usage_container_name

  app_insights_connection_string = module.monitoring.app_insights_connection_string
  apim_app_insights_name         = module.monitoring.app_insights_name
  apim_app_insights_rg           = local.resource_group_name

  content_share_name = local.usage_cfg.logic_app.content_share_name
  enable_code_deploy = local.usage_cfg.logic_app.code_deploy
  code_source_path   = local.usage_cfg.logic_app.code_source_path != "" ? local.usage_cfg.logic_app.code_source_path : "${path.module}/../../logicapp-src/usage-ingestion-logicapp"

  managed_identity_id           = module.identity["usage"].resource_id
  managed_identity_client_id    = module.identity["usage"].client_id
  managed_identity_principal_id = module.identity["usage"].principal_id

  log_analytics_id = module.monitoring.log_analytics_id
}
