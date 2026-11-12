# Key-less contract: no secrets are written (key_vault.enabled = false) and no
# Foundry connection. The consumer reads the endpoint from the stack outputs
# and gets the key from APIM on demand (e.g. a CI job with APIM Subscription
# Contributor); useful when the team keeps its own secret store.
use_case = {
  business_unit = "Finance"
  use_case_name = "Batch"
  environment   = "PROD"
}

api_name_mapping = {
  LLM = ["universal-llm-api"]
}

services = [
  {
    code                 = "LLM"
    endpoint_secret_name = "FIN-LLM-ENDPOINT" # unused while the vault is off
    api_key_secret_name  = "FIN-LLM-KEY"
  },
]

product_terms = "Finance batch scoring"

key_vault = { enabled = false }
