# Baseline unit tests (Phase 0, WP-0.7) — mocked providers, plan only.
#   terraform init -backend=false && terraform test -test-directory=tests/unit

mock_provider "azurerm" {
  mock_data "azurerm_api_management" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-test/providers/Microsoft.ApiManagement/service/apim-test"
      name                = "apim-test"
      resource_group_name = "rg-test"
    }
  }
}

mock_provider "azapi" {}

variables {
  subscription_id            = "00000000-0000-0000-0000-000000000002"
  resource_group_name        = "rg-test"
  apim_name                  = "apim-test"
  managed_identity_client_id = "00000000-0000-0000-0000-000000000005"
  llm_backend_config = [
    {
      backend_id       = "east"
      backend_type     = "azure-openai"
      endpoint         = "https://east.openai.azure.com/openai"
      auth_scheme      = "managedIdentity"
      priority         = 1
      supported_models = [{ name = "gpt-4.1" }, { name = "gpt-4.1-mini" }]
    },
    {
      backend_id       = "west"
      backend_type     = "azure-openai"
      endpoint         = "https://west.openai.azure.com/openai"
      auth_scheme      = "managedIdentity"
      priority         = 2
      supported_models = [{ name = "gpt-4.1" }]
    },
  ]
}

run "backends_and_pools" {
  command = plan

  assert {
    condition     = toset(keys(azapi_resource.llm_backend)) == toset(["east", "west"])
    error_message = "One backend per llm_backend_config entry."
  }
  assert {
    condition     = toset(keys(azapi_resource.llm_backend_pool)) == toset(["gpt-41-backend-pool"])
    error_message = "Only models served by 2+ backends get a pool."
  }
}

run "fragments_come_from_the_single_shared_copy" {
  command = plan

  assert {
    condition     = azurerm_api_management_policy_fragment.static["validate-model-access"].value == file("${path.module}/../policies/fragments/frag-validate-model-access.xml")
    error_message = "Static fragments must be read from policies/fragments (no duplicated copies)."
  }
}

run "plaintext_backend_secret_is_reported" {
  command = plan

  variables {
    llm_backend_config = [
      {
        backend_id       = "ext"
        backend_type     = "external"
        endpoint         = "https://llm.example.com"
        auth_scheme      = "apiKey"
        auth_type        = "api-key-header"
        auth_config      = { named_value_key = "ext-key", secret_value = "not-a-real-key" }
        supported_models = [{ name = "ext-model" }]
      },
    ]
  }

  expect_failures = [check.no_plaintext_backend_secrets]
}

# imports.tf: only objects that exist under the APIM service are adopted.
run "existing_objects_are_adopted" {
  command = plan

  override_data {
    target = data.azapi_resource_list.backends
    values = { output = { names = ["east", "gpt-41-backend-pool", "unrelated"] } }
  }
  override_data {
    target = data.azapi_resource_list.policy_fragments
    values = { output = { names = ["set-backend-pools", "set-llm-usage"] } }
  }
  override_data {
    target = data.azapi_resource_list.named_values
    values = { output = { names = ["aws-region"] } }
  }
  # Mock providers can't import; stand in for the adopted objects.
  override_resource {
    target = azapi_resource.llm_backend
  }
  override_resource {
    target = azapi_resource.llm_backend_pool
  }
  override_resource {
    target = azurerm_api_management_policy_fragment.set_backend_pools
  }
  override_resource {
    target = azurerm_api_management_policy_fragment.static
  }
  override_resource {
    target = azurerm_api_management_named_value.aws_region
  }

  assert {
    condition     = local.importable_backend_keys == ["east"]
    error_message = "Only configured backends that exist must be imported."
  }
  assert {
    condition     = contains(local.existing_backends, "gpt-41-backend-pool") && contains(keys(local.pool_configs), "gpt-41-backend-pool")
    error_message = "An existing pool that is configured must be importable."
  }
  assert {
    condition     = contains(local.existing_fragments, "set-backend-pools") && !contains(local.existing_fragments, "metadata-config")
    error_message = "Fragment existence must come from the APIM listing."
  }
}
