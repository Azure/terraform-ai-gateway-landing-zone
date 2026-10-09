# Plans the stack with an example's tfvars (scripts/ci/check-examples.sh):
#   terraform test -filter=tests/examples.tftest.hcl -var-file=<common> -var-file=<stack>
# Mocked providers: it checks types and validations, not Azure.

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

run "example" {
  command = plan

  override_module {
    target  = module.contract
    outputs = { products = {}, subscriptions = {}, endpoints = {}, key_vault_secret_names = {}, foundry_connections = {}, foundry_connection_auth = { auth_type = "ProjectManagedIdentity", managed_identity_audience = "https://cognitiveservices.azure.com" } }
  }
}
