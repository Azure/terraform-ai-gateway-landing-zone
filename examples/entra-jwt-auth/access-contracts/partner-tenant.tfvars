# Another identity provider for one contract: a partner team signs in with its own Entra ID tenant
# (or any OpenID Connect provider, e.g. Auth0: audience "https://my-api.example.com", issuer
# "https://my-company.auth0.com/", OpenID config "https://my-company.auth0.com/.well-known/openid-configuration").
# The overrides apply to this product only; other contracts keep the gateway's JWT-* named values.
# Setting only jwt_audience keeps the gateway's issuer and OpenID configuration.
use_case = {
  business_unit = "Partner"
  use_case_name = "External"
  environment   = "DEV"
}

api_name_mapping = {
  LLM = ["universal-llm-api"]
}

services = [
  {
    code                  = "LLM"
    endpoint_secret_name  = "PARTNER-LLM-ENDPOINT"
    api_key_secret_name   = "PARTNER-LLM-KEY"
    allowed_models        = ["fast"]
    jwt_required          = true
    jwt_audience          = "<partner-gateway-app-client-id>"
    jwt_issuer            = "https://login.microsoftonline.com/<partner-tenant-id>/v2.0"
    jwt_openid_config_url = "https://login.microsoftonline.com/<partner-tenant-id>/v2.0/.well-known/openid-configuration"
  },
]

product_terms = "Partner sample contract: API key + a token of the partner's tenant"

key_vault = { enabled = true }
