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
    # policy_xml = "" -> modules/access-contract/policies/default-ai-product-policy.xml.
    # Per-contract model RBAC + capacity:
    policy_xml = <<-XML
      <policies>
        <inbound>
          <base />
          <include-fragment fragment-id="set-llm-requested-model" />
          <set-variable name="allowedModels" value="gpt-4o-mini" />
          <include-fragment fragment-id="validate-model-access" />
          <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="2000" estimate-prompt-tokens="false" token-quota="50000" token-quota-period="Daily" />
        </inbound>
        <backend><base /></backend>
        <outbound><base /></outbound>
        <on-error><base /></on-error>
      </policies>
    XML
  },
]

product_terms = "Dev sample contract"

key_vault = { enabled = true }
foundry   = { enabled = true } # connection on the platform's default Foundry project
