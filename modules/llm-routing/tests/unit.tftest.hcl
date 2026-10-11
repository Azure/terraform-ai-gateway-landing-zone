# Unit tests (plan only, no Azure access):
#   terraform init -backend=false && terraform test

mock_provider "azapi" {
  override_during = plan
}
mock_provider "azurerm" {
  override_during = plan
}

variables {
  api_management_id          = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiManagement/service/apim-aigw-dev"
  managed_identity_client_id = "00000000-0000-0000-0000-0000000000aa"
  llm_backend_config = [
    {
      backend_id       = "default-breaker"
      backend_type     = "ai-foundry"
      endpoint         = "https://a.cognitiveservices.azure.com/"
      auth_scheme      = "managedIdentity"
      auth_type        = "managed-identity"
      supported_models = [{ name = "gpt-4.1" }]
    },
    {
      backend_id       = "tuned-breaker"
      backend_type     = "azure-openai"
      endpoint         = "https://b.openai.azure.com/"
      auth_type        = "managed-identity"
      supported_models = [{ name = "gpt-4.1" }]
      circuit_breaker = {
        failure_count      = 5
        failure_interval   = "PT30S"
        trip_duration      = "PT10M"
        status_code_ranges = [{ min = 500, max = 599 }]
        error_reasons      = ["Server errors", "Timeouts"]
        accept_retry_after = false
      }
    },
    {
      backend_id       = "no-breaker"
      backend_type     = "external"
      endpoint         = "https://partner.example.com"
      auth_type        = "api-key-bearer"
      auth_config      = { named_value_key = "partner-key" }
      supported_models = [{ name = "partner-large" }]
      circuit_breaker  = { enabled = false }
    },
  ]
}

run "default_rule_matches_the_previous_global_behaviour" {
  command = plan

  assert {
    condition = jsondecode(jsonencode(azapi_resource.llm_backend["default-breaker"].body)).properties.circuitBreaker.rules[0] == {
      name             = "default-breaker-breaker-rule"
      tripDuration     = "PT1M"
      acceptRetryAfter = true
      failureCondition = {
        count            = 3
        interval         = "PT5M"
        errorReasons     = ["Server errors"]
        statusCodeRanges = [{ min = 429, max = 429 }, { min = 500, max = 503 }]
      }
    }
    error_message = "No circuit_breaker set: 3 failures in 5 minutes (429 and 500-503) trip the backend for 1 minute, Retry-After honoured."
  }
}

run "each_backend_has_its_own_rule" {
  command = plan

  assert {
    condition = jsondecode(jsonencode(azapi_resource.llm_backend["tuned-breaker"].body)).properties.circuitBreaker.rules[0] == {
      name             = "tuned-breaker-breaker-rule"
      tripDuration     = "PT10M"
      acceptRetryAfter = false
      failureCondition = {
        count            = 5
        interval         = "PT30S"
        errorReasons     = ["Server errors", "Timeouts"]
        statusCodeRanges = [{ min = 500, max = 599 }]
      }
    }
    error_message = "The properties of circuit_breaker land in that backend's rule and nowhere else."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["default-breaker"].body)).properties.circuitBreaker.rules[0].failureCondition.count == 3
    error_message = "Tuning one backend leaves the others on the defaults."
  }
}

run "a_backend_can_opt_out" {
  command = plan

  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["no-breaker"].body)).properties.circuitBreaker == null
    error_message = "circuit_breaker.enabled = false: the backend has no rule."
  }
}

run "iso_durations_with_days_hours_and_minutes_are_accepted" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "a", backend_type = "external", endpoint = "https://a.example.com", supported_models = [{ name = "m" }], circuit_breaker = { failure_interval = "P1D", trip_duration = "PT1H30M" } },
    ]
  }

  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["a"].body)).properties.circuitBreaker.rules[0].tripDuration == "PT1H30M"
    error_message = "P1D and PT1H30M are valid ISO 8601 durations."
  }
}

# How each backend authenticates to its endpoint: the explicit auth_type, else the default
# of the backend type. The header of a key-based backend is the named value, as a whole.
run "backend_credentials_follow_the_effective_auth_type" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "foundry", backend_type = "ai-foundry", endpoint = "https://a.example.com", supported_models = [{ name = "m1" }] },
      { backend_id = "aoai-key", backend_type = "azure-openai", endpoint = "https://b.example.com", auth_type = "api-key-header", auth_config = { named_value_key = "aoai-key" }, supported_models = [{ name = "m2" }] },
      { backend_id = "partner", backend_type = "external", endpoint = "https://c.example.com/v1", auth_type = "api-key-bearer", auth_config = { named_value_key = "partner-key" }, supported_models = [{ name = "m3" }] },
      { backend_id = "open-endpoint", backend_type = "external", endpoint = "https://d.example.com/v1", supported_models = [{ name = "m4" }] },
      { backend_id = "gemini", backend_type = "gemini-openai", endpoint = "https://generativelanguage.googleapis.com", auth_config = { named_value_key = "gemini-key" }, supported_models = [{ name = "m5" }] },
      { backend_id = "mantle", backend_type = "aws-bedrock-mantle", endpoint = "https://bedrock-mantle.us-east-1.api.aws", auth_config = { named_value_key = "mantle-key" }, supported_models = [{ name = "m6" }] },
      { backend_id = "bedrock", backend_type = "aws-bedrock", endpoint = "https://bedrock-runtime.us-east-1.amazonaws.com", supported_models = [{ name = "m7" }] },
    ]
  }

  assert {
    condition     = local.effective_auth_type == { foundry = "managed-identity", aoai-key = "api-key-header", partner = "api-key-bearer", open-endpoint = "none", gemini = "api-key-bearer", mantle = "api-key-bearer", bedrock = "aws-sigv4" }
    error_message = "auth_type wins; otherwise ai-foundry/azure-openai = managed identity, external = none, gemini-openai and aws-bedrock-mantle = bearer key, aws-bedrock = SigV4."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["foundry"].body)).properties.credentials == { managedIdentity = { clientId = "00000000-0000-0000-0000-0000000000aa", resource = "https://cognitiveservices.azure.com" }, header = { "x-ms-client-id" = ["00000000-0000-0000-0000-0000000000aa"] } }
    error_message = "Managed identity: the backend acquires the Cognitive Services token itself, even without the legacy auth_scheme."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["partner"].body)).properties.credentials == { managedIdentity = null, header = { Authorization = ["{{partner-key}}"] } }
    error_message = "api-key-bearer: the Authorization header is the whole named value."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["aoai-key"].body)).properties.credentials.header == { "api-key" = ["{{aoai-key}}"] }
    error_message = "api-key-header: the api-key header is the named value."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["gemini"].body)).properties.credentials.header == { Authorization = ["{{gemini-key}}"] } && jsondecode(jsonencode(azapi_resource.llm_backend["mantle"].body)).properties.credentials.header == { Authorization = ["{{mantle-key}}"] }
    error_message = "gemini-openai and aws-bedrock-mantle default to a bearer key."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["bedrock"].body)).properties.credentials == { managedIdentity = null, header = null } && jsondecode(jsonencode(azapi_resource.llm_backend["open-endpoint"].body)).properties.credentials == { managedIdentity = null, header = null }
    error_message = "aws-sigv4 is signed in the policy and none sends no credentials: nothing on the backend."
  }
}

run "a_key_backend_needs_its_named_value" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "gemini", backend_type = "gemini-openai", endpoint = "https://generativelanguage.googleapis.com", supported_models = [{ name = "m" }] },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "an_explicit_key_auth_needs_its_named_value" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "partner", backend_type = "external", endpoint = "https://c.example.com", auth_type = "api-key-bearer", supported_models = [{ name = "m" }] },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "duplicate_backend_ids_are_rejected" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "same", backend_type = "external", endpoint = "https://a.example.com", supported_models = [{ name = "m" }] },
      { backend_id = "same", backend_type = "external", endpoint = "https://b.example.com", supported_models = [{ name = "m" }] },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "failure_count_must_be_positive" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "a", backend_type = "external", endpoint = "https://a.example.com", supported_models = [{ name = "m" }], circuit_breaker = { failure_count = 0 } },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "durations_must_be_iso_8601" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "a", backend_type = "external", endpoint = "https://a.example.com", supported_models = [{ name = "m" }], circuit_breaker = { trip_duration = "5 minutes" } },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "an_empty_duration_is_rejected" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "a", backend_type = "external", endpoint = "https://a.example.com", supported_models = [{ name = "m" }], circuit_breaker = { failure_interval = "PT" } },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "status_ranges_stay_inside_what_apim_accepts" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "a", backend_type = "external", endpoint = "https://a.example.com", supported_models = [{ name = "m" }], circuit_breaker = { status_code_ranges = [{ min = 100, max = 199 }] } },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "an_inverted_status_range_is_rejected" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "a", backend_type = "external", endpoint = "https://a.example.com", supported_models = [{ name = "m" }], circuit_breaker = { status_code_ranges = [{ min = 503, max = 500 }] } },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

# Pools are per (model, backend type): the same model served natively and OpenAI-compatibly
# stays two routes, and a model with several backends of one type gets a pool.
run "pools_are_keyed_by_model_and_backend_type" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "f1", backend_type = "ai-foundry", endpoint = "https://f1.example.com", supported_models = [{ name = "gpt-4.1" }, { name = "solo" }] },
      { backend_id = "f2", backend_type = "ai-foundry", endpoint = "https://f2.example.com", priority = 2, supported_models = [{ name = "gpt-4.1" }] },
      { backend_id = "native", backend_type = "aws-bedrock", endpoint = "https://bedrock-runtime.us-east-1.amazonaws.com", supported_models = [{ name = "us.anthropic.claude:0" }] },
      { backend_id = "mantle", backend_type = "aws-bedrock-mantle", endpoint = "https://bedrock-mantle.us-east-1.api.aws", auth_config = { named_value_key = "mantle-key" }, supported_models = [{ name = "us.anthropic.claude:0" }] },
    ]
  }

  assert {
    condition     = sort(keys(azapi_resource.llm_backend_pool)) == tolist(["gpt-41-ai-foundry-backend-pool"])
    error_message = "Only gpt-4.1 has 2+ backends of one type: one pool, named after model and type with APIM-illegal characters stripped."
  }
  assert {
    condition     = length(local.direct_backends) == 3
    error_message = "solo and the two Bedrock routes of one model id are direct backends."
  }
  assert {
    condition     = tolist([for p in local.all_pools : "${p.pool_name}:${p.pool_type}"]) == tolist(["gpt-41-ai-foundry-backend-pool:ai-foundry", "f1:ai-foundry", "native:aws-bedrock", "mantle:aws-bedrock-mantle"])
    error_message = "Pools first, then the direct backends, each with its own type."
  }
}

run "stateful_models_get_session_affinity_on_their_pools" {
  command = plan

  variables {
    session_affinity = { cookie_name = "default-cookie" }
    llm_backend_config = [
      { backend_id = "a1", backend_type = "ai-foundry", endpoint = "https://a1.example.com", supported_models = [{ name = "stateful", sessionAwareModel = true }, { name = "stateless" }] },
      { backend_id = "a2", backend_type = "ai-foundry", endpoint = "https://a2.example.com", supported_models = [{ name = "stateful" }, { name = "stateless" }] },
      { backend_id = "b1", backend_type = "azure-openai", endpoint = "https://b1.example.com", session_affinity = { cookie_name = "custom-cookie" }, supported_models = [{ name = "other", sessionAwareModel = true }] },
      { backend_id = "b2", backend_type = "azure-openai", endpoint = "https://b2.example.com", supported_models = [{ name = "other" }] },
    ]
  }

  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend_pool["stateful-ai-foundry-backend-pool"].body)).properties.pool.sessionAffinity == { sessionId = { source = "Cookie", name = "default-cookie" } }
    error_message = "A pool of a session-aware model gets the cookie of the module settings."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend_pool["stateless-ai-foundry-backend-pool"].body)).properties.pool.sessionAffinity == null
    error_message = "A stateless model keeps pure load balancing."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend_pool["other-azure-openai-backend-pool"].body)).properties.pool.sessionAffinity.sessionId.name == "custom-cookie"
    error_message = "A pool member can override the cookie of its pools."
  }
  assert {
    condition     = azapi_resource.llm_backend_pool["stateful-ai-foundry-backend-pool"].type == "Microsoft.ApiManagement/service/backends@2025-03-01-preview"
    error_message = "Pools use the API version that has session affinity."
  }
}

run "session_affinity_can_be_switched_off" {
  command = plan

  variables {
    session_affinity = { enabled = false }
    llm_backend_config = [
      { backend_id = "a1", backend_type = "ai-foundry", endpoint = "https://a1.example.com", supported_models = [{ name = "stateful", sessionAwareModel = true }] },
      { backend_id = "a2", backend_type = "ai-foundry", endpoint = "https://a2.example.com", supported_models = [{ name = "stateful" }] },
    ]
  }

  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend_pool["stateful-ai-foundry-backend-pool"].body)).properties.pool.sessionAffinity == null
    error_message = "The master switch wins over sessionAwareModel."
  }
}

run "aliases_are_virtual_pools_of_the_routing_fragment" {
  command = plan

  variables {
    model_aliases = [{ name = "fast", models = ["m-foundry", "m-gemini"], strategy = "weighted", weights = [80, 20] }]
    llm_backend_config = [
      { backend_id = "f", backend_type = "ai-foundry", endpoint = "https://f.example.com", supported_models = [{ name = "m-foundry" }] },
      { backend_id = "g", backend_type = "gemini-openai", endpoint = "https://g.example.com", auth_config = { named_value_key = "g-key" }, supported_models = [{ name = "m-gemini" }] },
    ]
  }

  assert {
    condition     = strcontains(azurerm_api_management_policy_fragment.set_backend_pools.value, "{ \"poolName\", \"alias:fast\" }") && strcontains(azurerm_api_management_policy_fragment.set_backend_pools.value, "{ \"isAlias\", true }") && strcontains(azurerm_api_management_policy_fragment.set_backend_pools.value, "{ \"strategy\", \"weighted\" }")
    error_message = "The alias is a virtual pool of the backendPools array."
  }
  assert {
    condition     = strcontains(azurerm_api_management_policy_fragment.set_backend_pools.value, "aliasMembers_0.Add(new JObject() { { \"model\", \"m-gemini\" }, { \"weight\", 20 }, { \"pools\", new JArray() { new JObject() { { \"poolName\", \"g\" }, { \"poolType\", \"gemini-openai\" }")
    error_message = "Each member lists the pools that host its model, with its weight."
  }
  assert {
    condition     = !strcontains(azurerm_api_management_policy_fragment.resolve_model_alias.value, "inlineAliasesCode")
    error_message = "The resolve-model-alias fragment has no placeholder left."
  }
}

run "alias_weights_need_one_per_model" {
  command = plan

  variables {
    model_aliases = [{ name = "x", models = ["a", "b"], strategy = "weighted", weights = [100] }]
  }

  expect_failures = [var.model_aliases]
}

run "session_affinity_source_is_cookie_only" {
  command = plan

  variables {
    session_affinity = { source = "Header" }
  }

  expect_failures = [var.session_affinity]
}

run "gemini_and_anthropic_backends_send_their_own_key_header" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "gemini", backend_type = "gemini", endpoint = "https://generativelanguage.googleapis.com", auth_config = { named_value_key = "gemini-key" }, supported_models = [{ name = "g" }] },
      { backend_id = "claude", backend_type = "anthropic", endpoint = "https://api.anthropic.com", auth_config = { named_value_key = "claude-key" }, supported_models = [{ name = "c" }] },
    ]
  }

  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["gemini"].body)).properties.credentials.header == { "x-goog-api-key" = ["{{gemini-key}}"] }
    error_message = "Native Gemini: x-goog-api-key with the bare key."
  }
  assert {
    condition     = jsondecode(jsonencode(azapi_resource.llm_backend["claude"].body)).properties.credentials.header == { "x-api-key" = ["{{claude-key}}"], "anthropic-version" = ["{{anthropic-version}}"] }
    error_message = "Anthropic: x-api-key and the anthropic-version named value."
  }
}

run "a_native_gemini_backend_needs_its_named_value" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "gemini", backend_type = "gemini", endpoint = "https://generativelanguage.googleapis.com", supported_models = [{ name = "g" }] },
    ]
  }

  expect_failures = [var.llm_backend_config]
}

run "model_path_reaches_the_metadata_config" {
  command = plan

  variables {
    llm_backend_config = [
      { backend_id = "flux", backend_type = "azure-flux", endpoint = "https://flux.services.ai.azure.com", supported_models = [{ name = "FLUX.2-pro", modelPath = "flux-2-pro" }, { name = "plain" }] },
    ]
  }

  assert {
    condition     = strcontains(azurerm_api_management_policy_fragment.metadata_config.value, "'modelPath': 'flux-2-pro'") && !strcontains(azurerm_api_management_policy_fragment.metadata_config.value, "'modelPath': ''")
    error_message = "The BFL slug is in the model config of the model that sets it, and only there."
  }
}

# The contract is the live routing configuration as JSON, without any credential.
run "the_backend_contract_describes_the_live_routing" {
  command = plan

  variables {
    release_version = "2.3.4"
    model_aliases   = [{ name = "fast", models = ["m"] }]
    llm_backend_config = [
      { backend_id = "partner", backend_type = "external", endpoint = "https://p.example.com/v1", auth_type = "api-key-bearer", auth_config = { named_value_key = "partner-key" }, supported_models = [{ name = "m" }], circuit_breaker = { trip_duration = "PT5M" } },
    ]
  }

  assert {
    condition     = jsondecode(regex("<set-body>(.*)</set-body>", azurerm_api_management_policy_fragment.backend_contract.value)[0]).masterVersion == "2.3.4"
    error_message = "The contract carries the version of the solution."
  }
  assert {
    condition     = jsondecode(regex("<set-body>(.*)</set-body>", azurerm_api_management_policy_fragment.backend_contract.value)[0]).apim == { subscriptionId = "00000000-0000-0000-0000-000000000002", resourceGroupName = "rg-aigw-dev", name = "apim-aigw-dev" }
    error_message = "The contract names the APIM it describes."
  }
  assert {
    condition     = jsondecode(regex("<set-body>(.*)</set-body>", azurerm_api_management_policy_fragment.backend_contract.value)[0]).backends[0].circuitBreaker.tripDuration == "PT5M" && jsondecode(regex("<set-body>(.*)</set-body>", azurerm_api_management_policy_fragment.backend_contract.value)[0]).backends[0].authConfig.namedValueKey == "partner-key"
    error_message = "Backends are listed with their circuit breaker and the NAME of their key (never a value)."
  }
  assert {
    condition     = !strcontains(azurerm_api_management_policy_fragment.backend_contract.value, "//{backendContractJson}")
    error_message = "The placeholder is replaced."
  }
}
