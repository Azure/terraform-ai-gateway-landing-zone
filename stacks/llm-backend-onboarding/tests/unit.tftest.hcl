# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_api_management" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiManagement/service/apim-aigw-dev"
      resource_group_name = "rg-aigw-dev"
      gateway_url         = "https://apim-aigw-dev.azure-api.net"
    }
  }
  mock_data "azurerm_user_assigned_identity" {
    defaults = {
      client_id = "00000000-0000-0000-0000-0000000000c1"
    }
  }
  mock_data "azurerm_cognitive_account" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.CognitiveServices/accounts/aif"
      location = "swedencentral"
      endpoint = "https://aif.cognitiveservices.azure.com/"
    }
  }
}
mock_provider "azapi" {
  override_during = plan

  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiCenter/services/apic-aigw-dev"
    }
  }
}

variables {
  workload        = "aigw"
  environment     = "dev"
  location        = "swedencentral"
  subscription_id = "00000000-0000-0000-0000-000000000002"
}

# Two platform accounts (+ one unrelated account) and their deployments.
override_data {
  target = data.azapi_resource_list.foundry_accounts[0]
  values = {
    output = {
      accounts = [
        { name = "aif-aigw-dev-27cbb-1", location = "eastus2", endpoint = "https://b" },
        { name = "aif-aigw-dev-27cbb-0", location = "swedencentral", endpoint = "https://a" },
        { name = "other-account", location = "westeurope", endpoint = "https://c" },
      ]
    }
  }
}
override_data {
  target = data.azapi_resource_list.deployments
  values = {
    output = {
      deployments = [
        { name = "gpt-4o-mini", sku = "GlobalStandard", capacity = 10, format = "OpenAI", version = "2024-07-18" },
      ]
    }
  }
}
override_data {
  target = data.azapi_resource.entra_auth
  values = {
    output = { properties = { value = "false" } }
  }
}
override_data {
  target = data.azapi_resource_list.fragments
  values = {
    output = { names = ["security-handler", "raise-throttling-events", "set-response-headers", "strip-backend-headers", "ai-foundry-compatibility"] }
  }
}

run "backends_derived_from_foundry_deployments" {
  command = plan

  assert {
    condition     = local.foundry_account_names == tolist(["aif-aigw-dev-27cbb-0", "aif-aigw-dev-27cbb-1"])
    error_message = "Only accounts that follow the naming contract, in index order."
  }
  assert {
    condition     = [for b in local.llm_backend_config : b.priority] == [1, 2] && local.llm_backend_config[0].supported_models[0].name == "gpt-4o-mini"
    error_message = "One backend per account (primary first) serving its deployments."
  }
  assert {
    condition     = length(module.llm_routing.pool_ids) == 1
    error_message = "A model served by two accounts gets a pool."
  }
  assert {
    condition     = sort(keys(module.llm_api)) == tolist(["azure-openai-api", "universal-llm-api"]) && module.llm_api["universal-llm-api"].name == "universal-llm-api"
    error_message = "Universal LLM and Azure OpenAI APIs by default."
  }
  assert {
    condition     = local.subscription_required
    error_message = "entra-auth = false: the LLM APIs require a subscription key."
  }
}

run "entra_auth_drops_the_subscription_key" {
  command = plan

  override_data {
    target = data.azapi_resource.entra_auth
    values = {
      output = { properties = { value = "true" } }
    }
  }

  assert {
    condition     = !local.subscription_required
    error_message = "gateway-config's entra-auth = true: APIs take a JWT instead of a key."
  }
}

run "full_override_and_optional_apis" {
  command = plan

  variables {
    foundry_backends = { enabled = false }
    llm_backend_config = [{
      backend_id       = "aoai-external"
      backend_type     = "azure-openai"
      endpoint         = "https://aoai.openai.azure.com/"
      auth_type        = "api-key-header"
      auth_config      = { named_value_key = "aoai-key", key_vault_secret_uri = "https://kv.vault.azure.net/secrets/aoai-key" }
      supported_models = [{ name = "gpt-4.1" }]
    }]
    features = { unified_ai_api = true, ai_model_inference = true, openai_realtime = true }
  }

  assert {
    condition     = length(data.azapi_resource_list.foundry_accounts) == 0 && keys(azurerm_api_management_named_value.backend_api_key) == ["aoai-key"]
    error_message = "Override: no Foundry lookup; the backend key is a Key Vault named value."
  }
  assert {
    condition     = length(module.llm_api) == 5 && contains(keys(local.llm_fragments), "path-builder")
    error_message = "Optional APIs and the Unified AI fragments."
  }
}

run "plaintext_backend_secret_is_flagged" {
  command = plan

  variables {
    foundry_backends = { enabled = false }
    llm_backend_config = [{
      backend_id       = "ext"
      backend_type     = "external"
      endpoint         = "https://ext.example.com/"
      auth_config      = { named_value_key = "ext-key", secret_value = "do-not-do-this" }
      supported_models = [{ name = "m" }]
    }]
  }

  expect_failures = [check.no_plaintext_backend_secrets]
}
