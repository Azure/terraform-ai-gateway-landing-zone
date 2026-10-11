# One use case calling every backend type: two services, because the Unified AI API has
# its own path (/unified-ai) and therefore its own endpoint secret.
use_case = {
  business_unit = "TeamC"
  use_case_name = "MultiCloud"
  environment   = "DEV"
}

api_name_mapping = {
  LLM = ["universal-llm-api", "azure-openai-api"] # Foundry and the external provider
  UAI = ["unified-ai-api"]                        # Gemini, Bedrock Mantle, Bedrock, and the multi-cloud alias
}

services = [
  {
    code                 = "LLM"
    endpoint_secret_name = "TEAMC-LLM-ENDPOINT"
    api_key_secret_name  = "TEAMC-LLM-KEY"
    allowed_models       = ["gpt-5.4-mini", "partner-large"]
  },
  {
    code                 = "UAI"
    endpoint_secret_name = "TEAMC-UAI-ENDPOINT"
    api_key_secret_name  = "TEAMC-UAI-KEY"
    allowed_models = [
      "gpt-5.4-mini",
      "gemini-2.5-flash",
      "openai.gpt-oss-120b",
      "us.anthropic.claude-3-5-haiku-20241022-v1:0",
      "multi-cloud",
    ]
    token_limit = { tokens_per_minute = 5000, token_quota = 200000, token_quota_period = "Daily" }
  },
]

product_terms = "Multi-cloud sample contract"

# Endpoint + key secrets in the platform Key Vault (keys written write-only).
key_vault = { enabled = true }
