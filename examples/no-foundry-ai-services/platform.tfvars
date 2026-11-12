apim = {
  sku             = "StandardV2"
  vnet_mode       = "integration"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
}

# No Foundry accounts, projects or model deployments.
foundry = { enabled = false }

# Standalone Cognitive Services accounts of a different kind (private endpoint, Entra-only).
language_service       = { enabled = true } # kind TextAnalytics: PII redaction and anonymization
content_safety_service = { enabled = true } # kind ContentSafety
# location = "<region>" on either one when the service isn't available in the stack region.

usage_pipeline = {
  logic_app = { hosting = "workflow_standard", sku = "WS1", code_deploy = true }
}

# Laptop runs without a private runner: your public IP through the Key Vault
# and storage firewalls (greenfield, non-prod only).
dev_access = { allowed_cidrs = ["<your-public-ip>/32"] }

# Required for Key Vault secrets in access contracts: the identity that applies them.
secret_writer_principal_ids = { deployer = "<your-object-id>" }
