# One file = one use case = one state (task contract ENV=<env> USE_CASE=<file name>).
use_case = {
  business_unit = "TeamA"
  use_case_name = "Chatbot"
  environment   = "PROD"
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
    allowed_models          = ["gpt-5.4", "gpt-5.4-mini", "fast"]
    token_limit             = { tokens_per_minute = 10000, token_quota = 1000000, token_quota_period = "Daily" }
    enable_response_headers = true
  },
]

product_terms = "Production contract"

key_vault = { enabled = true }
