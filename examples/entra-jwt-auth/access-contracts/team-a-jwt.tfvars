# API key + JWT: every call needs the subscription key AND a valid token issued for the gateway app
# (aud = its client ID, iss = the tenant's v2.0 issuer: the gateway's JWT-* named values).
# Key only, an invalid token or a token only -> 401.
use_case = {
  business_unit = "TeamA"
  use_case_name = "SecureChat"
  environment   = "DEV"
}

api_name_mapping = {
  LLM = ["universal-llm-api", "azure-openai-api", "unified-ai-api"]
}

services = [
  {
    code                 = "LLM"
    endpoint_secret_name = "TEAMA-LLM-ENDPOINT"
    api_key_secret_name  = "TEAMA-LLM-KEY"
    allowed_models       = ["gpt-5.4-mini", "fast"]
    token_limit          = { tokens_per_minute = 2000, token_quota = 50000, token_quota_period = "Daily" }
    jwt_required         = true
  },
]

product_terms = "JWT sample contract: API key + Entra ID token"

key_vault = { enabled = true }
