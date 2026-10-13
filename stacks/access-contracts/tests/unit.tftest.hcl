# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "azurerm_api_management" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiManagement/service/apim-aigw-dev"
      resource_group_name = "rg-aigw-dev"
      gateway_url         = "https://apim-aigw-dev.azure-api.net"
    }
  }
  mock_data "azurerm_api_management_api" {
    defaults = {
      path = "models"
    }
  }
  mock_data "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.KeyVault/vaults/kv-aigw-dev"
    }
  }
}
# azapi is NOT mocked: mock providers don't support ephemeral resources
# (modules/access-contract reads the subscription key with one). Every run
# overrides the module, so the real provider is configured but never called.
mock_provider "time" {
  override_during = plan
}

variables {
  workload         = "aigw"
  environment      = "dev"
  location         = "swedencentral"
  subscription_id  = "00000000-0000-0000-0000-000000000002"
  use_case         = { business_unit = "HR", use_case_name = "ChatAgent", environment = "DEV" }
  api_name_mapping = { LLM = ["universal-llm-api", "azure-openai-api"] }
  services         = [{ code = "LLM", endpoint_secret_name = "HR_LLM_ENDPOINT", api_key_secret_name = "HR_LLM_KEY" }]
}

run "contract_without_secrets" {
  command = plan

  variables {
    key_vault = { enabled = false }
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  assert {
    condition     = local.key_vault_id == null && length(data.azurerm_key_vault.platform) == 0 && local.foundry_project_id == null
    error_message = "key_vault.enabled = false and no Foundry: no Key Vault lookup, no project."
  }
  assert {
    condition     = data.azurerm_api_management.this.name == local.names.apim && keys(data.azurerm_api_management_api.first) == ["LLM"]
    error_message = "APIM found by name; the first mapped API per service gives the endpoint path."
  }
}

run "secrets_go_to_the_platform_key_vault" {
  command = plan

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  assert {
    condition     = endswith(local.key_vault_id, "/vaults/kv-aigw-dev") && local.foundry_project_id == null
    error_message = "Secrets go to the platform Key Vault (found by name); no Foundry project by default."
  }
}

run "team_key_vault_and_foundry_project" {
  command = plan

  variables {
    key_vault = { id = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-team/providers/Microsoft.KeyVault/vaults/kv-team" }
    foundry   = { enabled = true }
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  assert {
    condition     = local.key_vault_id == var.key_vault.id && length(data.azurerm_key_vault.platform) == 0
    error_message = "A team-owned Key Vault is used by ID."
  }
  assert {
    condition     = endswith(local.foundry_project_id, "/accounts/aif-aigw-dev-${module.naming.seed}-0/projects/citadel-governance-project")
    error_message = "The connection goes to the default project of platform's primary Foundry account."
  }
}

run "foundry_auth_type_is_validated" {
  command = plan

  variables {
    foundry_config = { auth_type = "Basic" }
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ApiKey", managed_identity_audience = "" } }
  }

  expect_failures = [var.foundry_config]
}

# --- generated product policy properties ---------------------------------------

run "policy_properties_are_accepted" {
  command = plan

  variables {
    services = [{
      code                    = "LLM"
      endpoint_secret_name    = "HR_LLM_ENDPOINT"
      api_key_secret_name     = "HR_LLM_KEY"
      allowed_models          = ["gpt-5.4-mini", "fast"]
      token_limit             = { tokens_per_minute = 2000, token_quota = 50000, token_quota_period = "Daily" }
      enable_response_headers = true
      jwt_required            = true
    }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  assert {
    condition     = var.services[0].token_limit.token_quota_period == "Daily" && var.services[0].jwt_required
    error_message = "The structured policy properties are part of the service."
  }
}

run "jwt_properties_are_accepted" {
  command = plan

  variables {
    services = [{
      code                  = "LLM"
      endpoint_secret_name  = "A"
      api_key_secret_name   = "B"
      jwt_required          = true
      required_roles        = ["Models.Read", "Task.ReadWrite"]
      jwt_audience          = "https://my-api.example.com"
      jwt_issuer            = "https://my-company.auth0.com/"
      jwt_openid_config_url = "https://my-company.auth0.com/.well-known/openid-configuration"
    }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" }, jwt = {} }
  }

  assert {
    condition     = length(var.services[0].required_roles) == 2 && var.services[0].jwt_issuer == "https://my-company.auth0.com/"
    error_message = "App roles and another identity provider (Auth0) are part of the service."
  }
}

run "jwt_roles_need_jwt_required" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", required_roles = ["Models.Read"] }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" }, jwt = {} }
  }

  expect_failures = [var.services]
}

run "model_names_are_validated" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", allowed_models = ["gpt-4o,deepseek"] }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  expect_failures = [var.services]
}

run "token_limit_is_validated" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", token_limit = { token_quota = 10, token_quota_period = "Sometimes" } }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  expect_failures = [var.services]
}

# --- multi-asset policy properties ----------------------------------------------

run "multi_asset_properties_are_accepted" {
  command = plan

  variables {
    api_name_mapping = { MULTI = ["universal-llm-api", "weather-mcp", "hr-agent"] }
    services = [{
      code                 = "MULTI"
      endpoint_secret_name = "HR_MULTI_ENDPOINT"
      api_key_secret_name  = "HR_MULTI_KEY"
      allowed_models       = ["fast"]
      tool_apis            = ["weather-mcp"]
      tool_limit           = { calls_per_minute = 60, call_quota = 10000, call_quota_period = "Monthly" }
      agent_apis           = ["hr-agent"]
      agent_limit          = { calls_per_minute = 30 }
    }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  assert {
    condition     = contains(var.services[0].tool_apis, "weather-mcp") && var.services[0].agent_limit.call_quota_period == "Monthly"
    error_message = "Tool and agent APIs and limits are part of the service."
  }
}

run "tool_apis_must_be_in_the_api_mapping" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["weather-mcp"] }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  expect_failures = [var.services]
}

run "tool_limit_needs_tool_apis" {
  command = plan

  variables {
    services = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_limit = { calls_per_minute = 5 } }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  expect_failures = [var.services]
}

run "asset_limit_period_is_validated" {
  command = plan

  variables {
    api_name_mapping = { LLM = ["universal-llm-api", "weather-mcp"] }
    services         = [{ code = "LLM", endpoint_secret_name = "A", api_key_secret_name = "B", tool_apis = ["weather-mcp"], tool_limit = { call_quota = 5, call_quota_period = "Sometimes" } }]
  }

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }

  expect_failures = [var.services]
}
