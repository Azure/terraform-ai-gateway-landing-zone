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
    jwt_required            = true # also validate the token the Foundry project identity sends (audience: foundry_config)
  },
]

product_terms = "Dev sample contract"

key_vault = { enabled = true }
foundry   = { enabled = true } # connection on the platform's default Foundry project
# foundry_config = { auth_type = "ApiKey" } # key-only connection: then drop jwt_required above
