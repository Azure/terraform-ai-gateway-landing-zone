apim = {
  sku             = "Premium"
  capacity        = 3
  vnet_mode       = "internal"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
}

foundry = {
  instances = [{ location = "swedencentral" }]
  models = [
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 10 },
  ]
}

usage_pipeline = {
  logic_app = { hosting = "ase_v3", sku = "I1v2", code_deploy = true }
}

deny_storage_shared_key = true

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" }
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
