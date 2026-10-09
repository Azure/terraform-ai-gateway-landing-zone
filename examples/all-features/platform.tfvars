apim = {
  sku                   = "StandardV2"
  capacity              = 2
  vnet_mode             = "integration"
  private_endpoint      = true
  public_network_access = true # set false after the first apply to close the public endpoint
  publisher_name        = "Contoso"
  publisher_email       = "ai-gateway@contoso.com"
}

features = {
  api_center     = true
  semantic_cache = true # Azure Managed Redis as the APIM external cache
}

redis = { sku_name = "Balanced_B10" }

api_center = { sku = "Standard" }

apim_logging = { verbosity = "verbose", body_bytes = 8192 }

foundry = {
  instances = [{ location = "swedencentral" }, { location = "eastus2" }]
  models = [
    { name = "gpt-5.4", version = "2026-03-05", capacity = 100, ai_service_index = 0 },
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 100, ai_service_index = 0 },
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 100, ai_service_index = 1 },
    { name = "text-embedding-3-large", version = "1", capacity = 50, ai_service_index = 0 },
  ]
}

key_vault = { purge_protection_enabled = true, soft_delete_retention_days = 30 }

usage_pipeline = {
  eventhub  = { capacity = 2 }
  logic_app = { hosting = "workflow_standard", sku = "WS1", code_deploy = true }
}

monitoring = {
  private_link_scope      = true # needs network.tfvars private_dns.link_monitor_zone
  app_insights_dashboards = true
}

deny_storage_shared_key = false # Workflow Standard needs shared-key storage

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" } # task output STACK=bootstrap NAME=apply_principal_id
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
