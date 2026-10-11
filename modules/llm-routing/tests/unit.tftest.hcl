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
