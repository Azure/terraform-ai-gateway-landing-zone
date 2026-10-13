apim = {
  sku             = "StandardV2"
  vnet_mode       = "integration"
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
  logic_app = { hosting = "workflow_standard", sku = "WS1", code_deploy = true }
}

# Laptop runs without a private runner: your public IP through the Key Vault
# and storage firewalls (greenfield, non-prod only).
dev_access = { allowed_cidrs = ["<your-public-ip>/32"] }

# Required for Key Vault secrets in access contracts: the identity that applies them.
secret_writer_principal_ids = { deployer = "<your-object-id>" }
