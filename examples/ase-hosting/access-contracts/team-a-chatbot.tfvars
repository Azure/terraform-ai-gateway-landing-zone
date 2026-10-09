# One file = one use case = one state (task contract ENV=<env> USE_CASE=<file name>).
use_case = {
  business_unit = "TeamA"
  use_case_name = "Chatbot"
  environment   = "DEV"
}

api_name_mapping = {
  LLM = ["universal-llm-api", "azure-openai-api"]
}

services = [
  {
    code                 = "LLM"
    endpoint_secret_name = "TEAMA-LLM-ENDPOINT"
    api_key_secret_name  = "TEAMA-LLM-KEY"
    # Product policy, generated from these properties (policy_xml is only for advanced policies).
    allowed_models          = ["gpt-5.4-mini", "fast"]
    token_limit             = { tokens_per_minute = 2000, token_quota = 50000, token_quota_period = "Daily" }
    enable_response_headers = true
  },
]

product_terms = "Quickstart sample contract"

# Endpoint + key secrets in the platform Key Vault (keys written write-only).
key_vault = { enabled = true }
# Foundry connection on the platform's default project:
# foundry = { enabled = true }
# The connection then uses the Foundry project's managed identity (foundry_config.auth_type =
# "ProjectManagedIdentity"): set jwt_required = true on the service (as in examples/dev-greenfield-private)
# to validate that token, or set foundry_config = { auth_type = "ApiKey" } for a key-only connection.
