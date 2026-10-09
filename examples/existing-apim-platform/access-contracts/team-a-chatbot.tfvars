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
          <set-variable name="allowedModels" value="gpt-5.4-mini,fast" />
          <include-fragment fragment-id="validate-model-access" />
          <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="2000" estimate-prompt-tokens="false" token-quota="50000" token-quota-period="Daily" />
          <!-- Enable advanced response headers offered by set-response-headers fragment -->
          <set-variable name="enableResponseHeaders" value="@(true)" />
        </inbound>
        <backend><base /></backend>
        <outbound><base /></outbound>
        <on-error>
          <base />
          <!-- Raising throttling events (http 429 only) can help in setting up alerts in App Insights -->
          <!-- Set the following variables to customize the throttling event details -->
          <!-- <set-variable name="productName" value="@(context.Product?.Name?.ToString() ?? "Portal-Admin")" />
          <set-variable name="deploymentName" value="@((string)context.Variables.GetValueOrDefault<string>("requestedModel", "DefaultModel"))" />
          <set-variable name="appId" value="@((string)context.Variables.GetValueOrDefault<string>("appId", context.Subscription?.Id ?? "Portal-Admin-Sub"))" />
          <include-fragment fragment-id="raise-throttling-events" /> -->
        </on-error>
      </policies>
    XML
  },
]

product_terms = "Quickstart sample contract"

# Endpoint + key secrets in the platform Key Vault (keys written write-only).
key_vault = { enabled = true, id = "/subscriptions/<sub>/resourceGroups/<rg-kv>/providers/Microsoft.KeyVault/vaults/<existing-key-vault>" }
# Foundry connection on the platform's default project:
# foundry = { enabled = true }
# The connection then uses the Foundry project's managed identity (foundry_config.auth_type =
# "ProjectManagedIdentity"): add the jwt* variables from examples/dev-greenfield-private to the
# policy above, or set foundry_config = { auth_type = "ApiKey" } for a key-only connection.
