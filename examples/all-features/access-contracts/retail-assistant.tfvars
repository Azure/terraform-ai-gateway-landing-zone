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
    # Model RBAC, a token limit and the Entra JWT checked by the connection (see the dev-greenfield-private contract).
    policy_xml = <<-XML
      <policies>
        <inbound>
          <base />
          <set-variable name="jwtRequired" value="true" />
          <set-variable name="jwtAudience" value="https://cognitiveservices.azure.com" />
          <set-variable name="jwtIssuer" value="https://sts.windows.net/<tenant-id>/" />
          <set-variable name="jwtOpenIdConfigUrl" value="https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration" />
          <include-fragment fragment-id="set-llm-requested-model" />
          <set-variable name="allowedModels" value="fast,balanced" />
          <include-fragment fragment-id="validate-model-access" />
          <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="50000" estimate-prompt-tokens="false" token-quota="5000000" token-quota-period="Daily" />
        </inbound>
        <backend><base /></backend>
        <outbound><base /></outbound>
        <on-error><base /></on-error>
      </policies>
    XML
  },
  {
    code                 = "SRCH"
    endpoint_secret_name = "RETAIL-SEARCH-ENDPOINT"
    api_key_secret_name  = "RETAIL-SEARCH-KEY"
  },
  {
    code                 = "DOC"
    endpoint_secret_name = "RETAIL-DOC-ENDPOINT"
    api_key_secret_name  = "RETAIL-DOC-KEY"
  },
]

product_terms = "Retail assistant, production"

secret_rotation_days = 30 # rewrite the key secrets monthly

key_vault = { enabled = true }
foundry   = { enabled = true } # one connection per service on the platform's default project
