# Baseline unit tests (Phase 0, WP-0.7) — mocked providers, plan only.
#   terraform init -backend=false && terraform test -test-directory=tests/unit

mock_provider "azurerm" {
  mock_data "azurerm_api_management" {
    defaults = {
      id          = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-test/providers/Microsoft.ApiManagement/service/apim-test"
      gateway_url = "https://apim-test.azure-api.net"
    }
  }
  mock_data "azurerm_api_management_api" {
    defaults = {
      path = "llm"
    }
  }
}

mock_provider "azapi" {}

mock_provider "time" {
  mock_resource "time_rotating" {
    override_during = plan
    defaults = {
      rfc3339 = "2026-01-01T00:00:00Z"
    }
  }
}

variables {
  apim     = { subscription_id = "00000000-0000-0000-0000-000000000002", resource_group_name = "rg-test", name = "apim-test" }
  use_case = { business_unit = "hr", use_case_name = "chatagent", environment = "dev" }
  api_name_mapping = {
    LLM = ["universal-llm-api"]
  }
  services = [
    { code = "LLM", endpoint_secret_name = "LLM_ENDPOINT", api_key_secret_name = "LLM_KEY" },
  ]
  key_vault = { subscription_id = "00000000-0000-0000-0000-000000000002", resource_group_name = "rg-test", name = "kv-test" }
}

run "product_and_subscription_naming" {
  command = plan

  assert {
    condition     = azurerm_api_management_product.service["LLM"].product_id == "LLM-hr-chatagent-dev"
    error_message = "Product ID must be <code>-<business_unit>-<use_case>-<environment>."
  }
}

run "key_vault_secrets_are_alz_compliant" {
  command = plan

  assert {
    condition     = toset(keys(azurerm_key_vault_secret.contract)) == toset(["LLM-endpoint", "LLM-key"])
    error_message = "One endpoint secret and one key secret per service."
  }
  assert {
    condition     = azurerm_key_vault_secret.contract["LLM-key"].name == "llm-key" && azurerm_key_vault_secret.contract["LLM-endpoint"].name == "llm-endpoint"
    error_message = "Secret names must be lower-case with hyphens (Key Vault doesn't allow underscores)."
  }
  assert {
    condition     = azurerm_key_vault_secret.contract["LLM-key"].content_type == "apim-subscription-key" && azurerm_key_vault_secret.contract["LLM-endpoint"].content_type == "url"
    error_message = "Every secret needs a content type (ALZ Enforce-GR-KeyVault)."
  }
  assert {
    condition     = azurerm_key_vault_secret.contract["LLM-key"].expiration_date == "2026-04-01T00:00:00Z"
    error_message = "Secrets must expire secret_validity_days (90) after the last rotation (ALZ Enforce-GR-KeyVault)."
  }
}

run "validity_must_exceed_rotation" {
  command = plan

  variables {
    secret_rotation_days = 90
    secret_validity_days = 60
  }

  expect_failures = [var.secret_validity_days]
}

run "no_keys_in_outputs_without_key_vault" {
  command = plan

  variables {
    use_target_key_vault = false
  }

  assert {
    condition     = length(azurerm_key_vault_secret.contract) == 0
    error_message = "No Key Vault secrets when use_target_key_vault = false."
  }
  assert {
    condition     = !contains(keys(output.endpoints["LLM"]), "api_key")
    error_message = "Subscription keys must never be returned as outputs."
  }
}

# imports.tf: only objects that exist under the APIM service are adopted.
run "existing_contract_objects_are_adopted" {
  command = plan

  override_data {
    target = data.azapi_resource_list.products
    values = { output = { names = ["LLM-hr-chatagent-dev", "OTHER-product"] } }
  }
  override_data {
    target = data.azapi_resource_list.subscriptions
    values = { output = { names = [] } }
  }
  # Mock providers can't import; stand in for the adopted product.
  override_resource {
    target = azurerm_api_management_product.service
    values = {
      id         = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-test/providers/Microsoft.ApiManagement/service/apim-test/products/LLM-hr-chatagent-dev"
      product_id = "LLM-hr-chatagent-dev"
    }
  }

  assert {
    condition     = local.existing_service_products == { LLM = "LLM-hr-chatagent-dev" }
    error_message = "Only the use case's products that exist must be adopted."
  }
}
