apim = {
  sku                   = "StandardV2"
  vnet_mode             = "integration"
  private_endpoint      = true
  public_network_access = false # the first apply creates it public, the next one closes it
  publisher_name        = "Contoso"
  publisher_email       = "ai-gateway@contoso.com"
}

foundry = {
  instances = [{ location = "swedencentral" }]
  models = [
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 10 },
  ]
}

usage_pipeline = {
  logic_app = {
    hosting               = "workflow_standard"
    sku                   = "WS1"
    code_deploy           = true
    private_endpoint      = true  # one `sites` endpoint for the website and SCM
    public_network_access = false # publishing then needs the runner in snet-cicd
  }
}

# Private Log Analytics and App Insights: an Azure Monitor Private Link Scope with a private endpoint
# (network.tfvars private_dns.link_monitor_zone), public ingestion off everywhere and public query off
# on the Logic App and Foundry components. The workspace and the APIM component keep public query:
# the usage pipeline's Logic App connector reads the APIM component through Resource Manager.
monitoring = {
  private_link_scope       = true
  public_ingestion_enabled = false
  public_query_enabled     = false
  # Managed identity ingestion only (the default): no instrumentation-key ingestion.
  app_insights_entra_ingestion = true
}

deny_storage_shared_key = false # Workflow Standard needs shared-key storage

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" } # task output STACK=bootstrap NAME=apply_principal_id
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
