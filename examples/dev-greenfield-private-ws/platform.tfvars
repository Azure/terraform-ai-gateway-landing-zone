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

deny_storage_shared_key = false # Workflow Standard needs shared-key storage

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" } # task output STACK=bootstrap NAME=apply_principal_id
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
