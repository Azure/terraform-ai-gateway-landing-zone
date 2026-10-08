# Unit tests (plan only, no Azure access):
#   terraform init -backend=false && terraform test
# azapi is NOT mocked (mock providers don't support the ephemeral key read);
# these runs never open it (no Key Vault, no Foundry), so the real provider
# plans without credentials.

mock_provider "azurerm" {
  override_during = plan
}
mock_provider "time" {
  override_during = plan
}

variables {
  api_management = {
    id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiManagement/service/apim-aigw-dev"
    name                = "apim-aigw-dev"
    resource_group_name = "rg-aigw-dev"
    gateway_url         = "https://apim-aigw-dev.azure-api.net"
  }
  use_case         = { business_unit = "HR", use_case_name = "ChatAgent", environment = "DEV" }
  api_name_mapping = { LLM = ["universal-llm-api", "azure-openai-api"], DOC = ["document-intelligence-api"] }
  api_paths        = { LLM = "models", DOC = "documentintelligence" }
  services = [
    { code = "LLM", endpoint_secret_name = "HR_LLM_ENDPOINT", api_key_secret_name = "HR_LLM_KEY" },
    { code = "DOC", endpoint_secret_name = "HR_DOC_ENDPOINT", api_key_secret_name = "HR_DOC_KEY", policy_xml = "<policies><inbound><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>" },
  ]
}

run "products_apis_and_keyless_subscriptions" {
  command = plan

  assert {
    condition     = output.products == { LLM = "LLM-HR-ChatAgent-DEV", DOC = "DOC-HR-ChatAgent-DEV" }
    error_message = "Products are named <code>-<bu>-<usecase>-<env>."
  }
  assert {
    condition     = sort(keys(azurerm_api_management_product_api.service)) == tolist(["DOC-document-intelligence-api", "LLM-azure-openai-api", "LLM-universal-llm-api"])
    error_message = "Every mapped API is attached to its product."
  }
  assert {
    condition     = azapi_resource.subscription["LLM"].name == "LLM-HR-ChatAgent-DEV-SUB-01" && endswith(azapi_resource.subscription["LLM"].body.properties.scope, "/products/LLM-HR-ChatAgent-DEV")
    error_message = "One subscription per product, scoped to it (azapi: APIM never returns keys on GET)."
  }
  assert {
    condition     = strcontains(azurerm_api_management_product_policy.service["LLM"].xml_content, "<policies>") && azurerm_api_management_product_policy.service["DOC"].xml_content == var.services[1].policy_xml
    error_message = "Default policy unless policy_xml is set."
  }
  assert {
    condition     = output.endpoints == { LLM = "https://apim-aigw-dev.azure-api.net/models", DOC = "https://apim-aigw-dev.azure-api.net/documentintelligence" }
    error_message = "Endpoints are the gateway URL plus the first API's path."
  }
  assert {
    condition     = length(azurerm_key_vault_secret.key) == 0 && length(azapi_resource.foundry_connection) == 0 && !local.needs_key
    error_message = "No Key Vault and no Foundry: the key is never read."
  }
}

run "secret_validity_must_exceed_rotation" {
  command = plan

  variables {
    secret_rotation_days = 90
    secret_validity_days = 60
  }

  expect_failures = [var.secret_validity_days]
}
