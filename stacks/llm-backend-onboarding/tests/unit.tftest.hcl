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
    condition     = [for b in local.all_llm_backends : b.priority] == [1, 2] && local.all_llm_backends[0].supported_models[0].name == "gpt-4o-mini"
    error_message = "One backend per account (primary first) serving its deployments."
  }
  assert {
    condition     = output.llm_backends["foundry-swedencentral-0"].source == "foundry" && tolist(output.llm_backends["foundry-swedencentral-1"].models) == tolist(["gpt-4o-mini"])
    error_message = "The llm_backends output says where each backend comes from and what it serves."
  }
  assert {
    condition     = local.all_llm_backends[0].circuit_breaker.enabled && local.all_llm_backends[0].circuit_breaker.failure_count == 3 && local.all_llm_backends[0].circuit_breaker.trip_duration == "PT1M"
    error_message = "Derived backends get the default circuit breaker."
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

run "own_backends_only_and_optional_apis" {
  command = plan

  variables {
    foundry_backends = { enabled = false }
    llm_backends = [{
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
    error_message = "foundry_backends.enabled = false: no Foundry lookup; the backend key is a Key Vault named value."
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
    llm_backends = [{
      backend_id       = "ext"
      backend_type     = "external"
      endpoint         = "https://ext.example.com/"
      auth_config      = { named_value_key = "ext-key", secret_value = "do-not-do-this" }
      supported_models = [{ name = "m" }]
    }]
  }

  expect_failures = [check.no_plaintext_backend_secrets]
}

# llm_backends with differently shaped entries (key vs. managed identity)
# are appended to the Foundry-derived ones.
run "own_backends_with_mixed_shapes_are_appended" {
  command = plan

  variables {
    llm_backends = [
      {
        backend_id       = "aoai-mi"
        backend_type     = "azure-openai"
        endpoint         = "https://aoai.openai.azure.com/"
        auth_type        = "managed-identity"
        supported_models = [{ name = "gpt-4.1" }]
      },
      {
        backend_id       = "partner"
        backend_type     = "external"
        endpoint         = "https://partner.example.com"
        auth_type        = "api-key-bearer"
        auth_config      = { named_value_key = "partner-key", key_vault_secret_uri = "https://kv.vault.azure.net/secrets/partner-key" }
        supported_models = [{ name = "partner-large" }]
      },
    ]
  }

  assert {
    condition     = [for b in local.all_llm_backends : b.backend_id] == ["foundry-swedencentral-0", "foundry-swedencentral-1", "aoai-mi", "partner"]
    error_message = "Foundry-derived backends first, then your own in order."
  }
  assert {
    condition     = tolist([for k, b in output.llm_backends : "${k}=${b.source}"]) == tolist(["aoai-mi=llm_backends", "foundry-swedencentral-0=foundry", "foundry-swedencentral-1=foundry", "partner=llm_backends"])
    error_message = "The llm_backends output lists every deployed backend with its source."
  }
}

# A circuit breaker per backend: derived backends share foundry_backends.circuit_breaker,
# each of your own has its own, and one can opt out.
run "circuit_breakers_are_set_per_backend" {
  command = plan

  variables {
    foundry_backends = {
      circuit_breaker = { failure_count = 5, trip_duration = "PT5M" }
    }
    llm_backends = [
      {
        backend_id       = "aoai-strict"
        backend_type     = "azure-openai"
        endpoint         = "https://aoai.openai.azure.com/"
        auth_type        = "managed-identity"
        supported_models = [{ name = "gpt-4.1" }]
        circuit_breaker = {
          failure_interval   = "PT30S"
          status_code_ranges = [{ min = 500, max = 599 }]
          accept_retry_after = false
        }
      },
      {
        backend_id       = "partner"
        backend_type     = "external"
        endpoint         = "https://partner.example.com"
        auth_type        = "api-key-bearer"
        auth_config      = { named_value_key = "partner-key", key_vault_secret_uri = "https://kv.vault.azure.net/secrets/partner-key" }
        supported_models = [{ name = "partner-large" }]
        circuit_breaker  = { enabled = false }
      },
    ]
  }

  assert {
    condition     = [for b in local.foundry_derived : b.circuit_breaker.failure_count] == [5, 5] && [for b in local.foundry_derived : b.circuit_breaker.trip_duration] == ["PT5M", "PT5M"] && local.foundry_derived[0].circuit_breaker.failure_interval == "PT5M"
    error_message = "foundry_backends.circuit_breaker applies to every derived backend; what it doesn't set stays at the default."
  }
  assert {
    condition     = output.llm_backends["aoai-strict"].circuit_breaker.failure_interval == "PT30S" && output.llm_backends["aoai-strict"].circuit_breaker.failure_count == 3 && !output.llm_backends["aoai-strict"].circuit_breaker.accept_retry_after
    error_message = "A backend of your own sets its own properties and keeps the defaults for the rest."
  }
  assert {
    condition     = !output.llm_backends["partner"].circuit_breaker.enabled && output.llm_backends["foundry-swedencentral-0"].circuit_breaker.enabled
    error_message = "One backend can opt out without affecting the others."
  }
}

# A deployment without Foundry and without other backends plans (the routing
# module copes with none) but is flagged.
run "no_backends_is_flagged" {
  command = plan

  variables {
    foundry_backends = { enabled = false }
  }

  assert {
    condition     = length(local.all_llm_backends) == 0 && length(module.llm_routing.pool_ids) == 0
    error_message = "No Foundry and no backends of your own: nothing to route to."
  }

  expect_failures = [check.llm_backends_exist]
}

# Without Foundry the backends are the ones of your own alone.
run "own_backends_stand_alone_without_foundry" {
  command = plan

  variables {
    foundry_backends = { enabled = false }
    llm_backends = [{
      backend_id       = "aoai-mi"
      backend_type     = "azure-openai"
      endpoint         = "https://aoai.openai.azure.com/"
      auth_type        = "managed-identity"
      supported_models = [{ name = "gpt-4.1" }]
    }]
  }

  assert {
    condition     = [for b in local.all_llm_backends : b.backend_id] == ["aoai-mi"] && length(data.azapi_resource_list.foundry_accounts) == 0
    error_message = "Only the backends of llm_backends; no Foundry lookup."
  }
}
