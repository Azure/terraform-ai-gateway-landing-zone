# Team-owned Foundry project and Key Vault, ModelGateway connection with a
# static model list and API-key auth (no JWT validation in the policy).
use_case = {
  business_unit = "TeamB"
  use_case_name = "Agents"
  environment   = "DEV"
}

api_name_mapping = {
  LLM = ["universal-llm-api", "azure-openai-api"]
}

services = [
  {
    code                 = "LLM"
    endpoint_secret_name = "TEAMB-LLM-ENDPOINT"
    api_key_secret_name  = "TEAMB-LLM-KEY"
    # Default product policy (no model RBAC, no extra limits).
  },
]

product_terms = "TeamB agents: models reached through the partner and Bedrock backends too."

# The secrets go to the team's vault: the apply identity needs Key Vault Secrets Officer on it.
key_vault = { enabled = true, id = "/subscriptions/<team-sub>/resourceGroups/<team-rg>/providers/Microsoft.KeyVault/vaults/<team-kv>" }

# A project in the team's own Foundry account (any resource group / subscription the
# apply identity can write connections in).
foundry = {
  enabled    = true
  project_id = "/subscriptions/<team-sub>/resourceGroups/<team-rg>/providers/Microsoft.CognitiveServices/accounts/<team-foundry>/projects/<team-project>"
}

foundry_config = {
  auth_type           = "ApiKey"
  connection_category = "ModelGateway"
  # Listed explicitly because the gateway doesn't expose the model discovery endpoints.
  static_models = [
    { name = "fast", properties = { model = { name = "fast", version = "1", format = "OpenAI" } } },
    { name = "balanced", properties = { model = { name = "balanced", version = "1", format = "OpenAI" } } },
    { name = "partner-large", properties = { model = { name = "partner-large", version = "1", format = "OpenAI" } } },
  ]
  deployment_in_path    = "false"
  inference_api_version = "2025-04-01-preview"
}
