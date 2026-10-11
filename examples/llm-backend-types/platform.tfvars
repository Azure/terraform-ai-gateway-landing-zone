apim = {
  sku             = "StandardV2"
  vnet_mode       = "integration"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
}

# The Foundry account of this repository: its deployments become the first backend
# (derived by stacks/llm-backend-onboarding, nothing to repeat there).
foundry = {
  instances = [{ location = "swedencentral" }]
  models = [
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 50 },
  ]
}

usage_pipeline = {
  logic_app = { hosting = "workflow_standard", sku = "WS1", code_deploy = true }
}

dev_access = { allowed_cidrs = ["<your-public-ip>/32"] }

# Required for the Key Vault secrets of the access contract: the identity that applies it.
secret_writer_principal_ids = { deployer = "<your-object-id>" }
