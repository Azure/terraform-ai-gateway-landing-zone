# One use case consuming several services: LLM, AI Search and Document
# Intelligence. Each service gets its own APIM product subscription and its own
# endpoint/key secret pair in the platform Key Vault, plus a Foundry connection.
use_case = {
  business_unit = "Retail"
  use_case_name = "Assistant"
  environment   = "PROD"
}

api_name_mapping = {
  LLM  = ["universal-llm-api", "azure-openai-api"]
  SRCH = ["azure-ai-search-index-api"]
  DOC  = ["document-intelligence-api"]
}

services = [
  {
    code                 = "LLM"
    endpoint_secret_name = "RETAIL-LLM-ENDPOINT"
    api_key_secret_name  = "RETAIL-LLM-KEY"
    # Product policy, generated from these properties (policy_xml is only for advanced policies).
    allowed_models          = ["fast", "balanced"]
    token_limit             = { tokens_per_minute = 50000, token_quota = 5000000, token_quota_period = "Daily" }
    enable_response_headers = true
    jwt_required            = true # also validate the token the Foundry project identity sends (audience: foundry_config)
    semantic_cache          = true # similar chat prompts are answered from Redis (gateway-config semantic_cache)
  },
  {
    code                 = "SRCH"
    endpoint_secret_name = "RETAIL-SEARCH-ENDPOINT"
    api_key_secret_name  = "RETAIL-SEARCH-KEY"
    jwt_required         = true # its Foundry connection sends the project identity's token too
  },
  {
    code                 = "DOC"
    endpoint_secret_name = "RETAIL-DOC-ENDPOINT"
    api_key_secret_name  = "RETAIL-DOC-KEY"
    jwt_required         = true # its Foundry connection sends the project identity's token too
  },
]

product_terms = "Retail assistant, production"

secret_rotation_days = 30 # rewrite the key secrets monthly

key_vault = { enabled = true }
foundry   = { enabled = true } # one connection per service on the platform's default project
