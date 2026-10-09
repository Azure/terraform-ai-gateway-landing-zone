apim = {
  sku             = "StandardV2"
  vnet_mode       = "integration"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
}

# Two accounts in two regions: models listed for both indexes form a backend pool.
foundry = {
  instances = [{ location = "swedencentral" }, { location = "eastus2" }]
  models = [
    { name = "gpt-5.4", version = "2026-03-05", capacity = 50, ai_service_index = 0 },
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 50, ai_service_index = 0 },
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 50, ai_service_index = 1 },
  ]
}

usage_pipeline = {
  logic_app = { hosting = "workflow_standard", sku = "WS1", code_deploy = true }
}

dev_access = { allowed_cidrs = ["<your-public-ip>/32"] }

secret_writer_principal_ids = { deployer = "<your-object-id>" }
