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
    { name = "gpt-4o-mini", version = "2024-07-18", capacity = 10 },
  ]
}

usage_pipeline = {
  logic_app = { hosting = "ase_v3", sku = "I1v2", worker_count = 1, code_deploy = true }
}

deny_storage_shared_key = true

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" } # task output STACK=bootstrap NAME=apply_principal_id
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
