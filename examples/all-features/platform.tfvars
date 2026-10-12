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

api_center = {
  sku = "Standard"

  # Third-party MCP servers catalogued next to the gateway's own APIs (an MCP API, version,
  # definition and deployment each). The gateway doesn't serve them.
  remote_mcp_servers = [
    {
      name              = "microsoft-learn"
      description       = "Microsoft Learn documentation search"
      url               = "https://learn.microsoft.com/api/mcp"
      documentation_url = "https://learn.microsoft.com/training/support/mcp" # optional
    },
  ]
}

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
  private_link_scope = true # needs network.tfvars private_dns.link_monitor_zone
  # Open: the VNet still reaches Azure Monitor resources outside the scope. PrivateOnly only the
  # scope's, for every network sharing this DNS: switch once everything it needs is in the scope.
  private_link_scope_access_mode = { ingestion = "Open", query = "Open" }
  public_ingestion_enabled       = false # telemetry only through the private endpoint
  public_query_enabled           = false # except the workspace and the APIM component (the usage pipeline's Logic App connector reads it through Resource Manager)
  app_insights_dashboards        = true
}

deny_storage_shared_key = false # Workflow Standard needs shared-key storage

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" } # task output STACK=bootstrap NAME=apply_principal_id
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
