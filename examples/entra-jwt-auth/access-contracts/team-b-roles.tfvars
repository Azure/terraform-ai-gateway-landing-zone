# App role authorization on top of the JWT: the token's roles claim must hold one of required_roles
# (OR logic), otherwise 403 insufficient_role. Roles are app roles of the gateway app (stacks/identity),
# assigned to the client's service principal (scripts/entra_id_setup.py --client-roles, or Entra groups).
# Two products of one use case: model readers, and full access.
use_case = {
  business_unit = "TeamB"
  use_case_name = "RoleAuth"
  environment   = "DEV"
}

api_name_mapping = {
  MODELS = ["universal-llm-api", "azure-openai-api"]
  FULL   = ["universal-llm-api", "azure-openai-api", "unified-ai-api"]
}

services = [
  {
    code                 = "MODELS"
    endpoint_secret_name = "TEAMB-MODELS-ENDPOINT"
    api_key_secret_name  = "TEAMB-MODELS-KEY"
    allowed_models       = ["gpt-5.4-mini", "fast"]
    jwt_required         = true
    required_roles       = ["Models.Read"]
  },
  {
    code                 = "FULL"
    endpoint_secret_name = "TEAMB-FULL-ENDPOINT"
    api_key_secret_name  = "TEAMB-FULL-KEY"
    allowed_models       = ["gpt-5.4-mini", "fast"]
    jwt_required         = true
    required_roles       = ["Task.ReadWrite"]
  },
]

product_terms = "Role sample contract: API key + Entra ID token with an app role"

key_vault = { enabled = true }
