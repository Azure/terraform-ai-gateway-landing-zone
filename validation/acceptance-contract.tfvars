# Validation contract for validation/citadel-acceptance-tests.ipynb: products with small token limits so
# the rate-limit (POL-005), quota (POL-006) and quota-boundary (TOK-002) cases trip after a few requests.
#
#   cp validation/acceptance-contract.tfvars environments/<env>/access-contracts/
#   task contract ENV=<env> USE_CASE=acceptance-contract
#
# Products: RATE-QA-Acceptance-DEV and QUOTA-QA-Acceptance-DEV. No JWT, every model allowed (the notebook
# uses DEFAULT_MODEL or the first chat model behind the gateway). Destroy it after the acceptance run:
#   task destroy STACK=access-contracts ENV=<env> STATE_KEY=acceptance-contract.tfstate \
#     VAR_FILE=environments/<env>/access-contracts/acceptance-contract.tfvars
# then delete the file from environments/<env>/access-contracts/.
use_case = {
  business_unit = "QA"
  use_case_name = "Acceptance"
  environment   = "DEV"
}

api_name_mapping = {
  RATE  = ["universal-llm-api", "azure-openai-api"]
  QUOTA = ["universal-llm-api", "azure-openai-api"]
}

services = [
  {
    code                 = "RATE"
    endpoint_secret_name = "QA-RATE-ENDPOINT"
    api_key_secret_name  = "QA-RATE-KEY"
    # ~400-token requests: the 429 comes after a few calls within a minute.
    token_limit = { tokens_per_minute = 300 }
  },
  {
    code                 = "QUOTA"
    endpoint_secret_name = "QA-QUOTA-ENDPOINT"
    api_key_secret_name  = "QA-QUOTA-KEY"
    # 403 after ~5-10 calls (the counters synchronise within seconds); resets at the top of the next UTC hour.
    token_limit = { token_quota = 2000, token_quota_period = "Hourly" }
  },
]

product_terms = "Acceptance test contract (small limits); remove after the acceptance run"

key_vault = { enabled = true }
