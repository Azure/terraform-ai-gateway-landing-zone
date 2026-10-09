apim = {
  sku             = "Developer"
  vnet_mode       = "external"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
  # public_ip_address_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/publicIPAddresses/<pip>" # your own Standard-SKU IP with a DNS label
}

foundry = {
  instances = [{ location = "swedencentral" }]
  models = [
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 10 },
  ]
}

usage_pipeline = {
  logic_app = { hosting = "workflow_standard", sku = "WS1", code_deploy = true }
}

dev_access = { allowed_cidrs = ["<your-public-ip>/32"] }

secret_writer_principal_ids = { deployer = "<your-object-id>" }
