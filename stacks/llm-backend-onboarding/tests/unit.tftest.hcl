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
    output = { names = ["security-handler", "raise-alert-events", "set-response-headers", "strip-backend-headers", "ai-foundry-compatibility"] }
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
    condition     = sort(concat(keys(module.llm_api), keys(module.llm_api_universal))) == tolist(["azure-openai-api", "universal-llm-api"]) && module.llm_api_universal["universal-llm-api"].name == "universal-llm-api"
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
    condition     = length(module.llm_api) + length(module.llm_api_universal) == 5 && contains(keys(local.llm_fragments), "path-builder")
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

# The release version API serves the version and the generated backend contract.
run "release_version_api_is_published_with_the_contract" {
  command = plan

  assert {
    condition     = module.release_version_api.name == "release-version-api" && contains(keys(module.llm_routing.fragment_ids), "backend-contract")
    error_message = "GET /version and GET /version/backend-contract come from this stack."
  }
  assert {
    condition     = !contains(output.api_names, "release-version-api")
    error_message = "The version API is not an LLM API: access contracts don't attach it."
  }
}

# Stateful Foundry models get session affinity on their pools; the new backend fields pass through.
run "session_affinity_model_path_and_native_provider_keys_reach_the_module" {
  command = plan

  variables {
    foundry_backends  = { session_aware_models = ["gpt-4o-mini"] }
    session_affinity  = { cookie_name = "my-affinity" }
    anthropic_version = "2023-06-01"
    llm_backends = [
      { backend_id = "claude", backend_type = "anthropic", endpoint = "https://api.anthropic.com", auth_config = { named_value_key = "claude-key", key_vault_secret_uri = "https://kv.vault.azure.net/secrets/claude-key" }, supported_models = [{ name = "claude-sonnet" }] },
      { backend_id = "flux", backend_type = "azure-flux", endpoint = "https://flux.services.ai.azure.com", supported_models = [{ name = "FLUX.2-pro", modelPath = "flux-2-pro" }] },
    ]
  }

  assert {
    condition     = local.foundry_derived[0].supported_models[0].sessionAwareModel && local.foundry_derived[0].supported_models[0].modelPath == ""
    error_message = "A model listed in foundry_backends.session_aware_models is flagged stateful."
  }
  assert {
    condition     = contains(keys(azurerm_api_management_named_value.backend_api_key), "claude-key") && azurerm_api_management_named_value.anthropic_version.value == "2023-06-01"
    error_message = "The Anthropic key and the anthropic-version named value exist before the backends."
  }
  assert {
    condition     = strcontains(module.llm_routing.pools[0].pool_name, "backend-pool") && length(module.llm_routing.pool_ids) == 1
    error_message = "The gpt-4o-mini pool of the two Foundry accounts."
  }
}

# A model hosted natively and OpenAI-compatibly has two routes; the models output lists both.
run "a_model_under_two_backend_types_keeps_both_routes" {
  command = plan

  variables {
    foundry_backends = { enabled = false }
    llm_backends = [
      { backend_id = "native", backend_type = "aws-bedrock", endpoint = "https://bedrock-runtime.us-east-1.amazonaws.com", supported_models = [{ name = "claude" }] },
      { backend_id = "mantle", backend_type = "aws-bedrock-mantle", endpoint = "https://bedrock-mantle.us-east-1.api.aws", auth_config = { named_value_key = "mantle-key", key_vault_secret_uri = "https://kv.vault.azure.net/secrets/mantle-key" }, supported_models = [{ name = "claude" }] },
    ]
  }

  assert {
    condition     = sort(tolist(output.models["claude"])) == tolist(["mantle", "native"])
    error_message = "One model, two routes: the native and the OpenAI-compatible backend."
  }
}

# Regression: context.Request.Url.Host is null on an API without a serviceUrl, which made the
# SigV4 canonical-headers step throw a NullReferenceException (HTTP 500). The host is derived
# from the signing region instead.
run "bedrock_sigv4_does_not_depend_on_the_request_url_host" {
  command = plan

  assert {
    condition     = strcontains(file("${path.module}/fragments/frag-set-backend-authorization.xml"), "bedrock-runtime.{region}.amazonaws.com") && !strcontains(file("${path.module}/fragments/frag-set-backend-authorization.xml"), "var host = uri.Host")
    error_message = "The SigV4 signing host must come from the AWS region, not from context.Request.Url.Host."
  }
}

# Regression: the Universal LLM and Azure OpenAI specs share tag names (Chat, Embeddings, Responses,
# Vector Stores) and APIM creates import tags service-wide, so importing both in parallel
# intermittently failed with "Tag with the same name already exists". The Universal LLM API is its own
# module block and waits for the Azure OpenAI API; planning proves the dependency has no cycle.
run "universal_llm_api_is_imported_after_the_azure_openai_api" {
  command = plan

  assert {
    condition     = contains(keys(local.first_wave), "azure-openai-api") && !contains(keys(local.first_wave), "universal-llm-api")
    error_message = "The Azure OpenAI API is imported in the first wave, without the Universal LLM API."
  }
  assert {
    condition     = tolist(keys(local.second_wave)) == tolist(["universal-llm-api"]) && tolist(keys(module.llm_api_universal)) == tolist(["universal-llm-api"])
    error_message = "The Universal LLM API is the only API of the second wave (its own module block)."
  }
  assert {
    condition     = sort(concat(keys(local.first_wave), keys(local.second_wave))) == sort(keys(local.llm_apis))
    error_message = "Every LLM API is in exactly one wave."
  }
}
