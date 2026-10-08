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
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {} }
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
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {} }
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
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {} }
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
