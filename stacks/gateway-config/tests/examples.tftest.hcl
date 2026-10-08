# Plans the stack with an example's tfvars (scripts/ci/check-examples.sh):
#   terraform test -filter=tests/examples.tftest.hcl -var-file=<common> -var-file=<stack>
# Mocked providers: it checks types and validations, not Azure.

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_api_management" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.ApiManagement/service/apim-aigw-dev"
      name                = "apim-aigw-dev"
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
      endpoint = "https://aif-aigw-dev.cognitiveservices.azure.com/"
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
mock_provider "azuread" {
  override_during = plan

  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "azuread_application" {
    defaults = {
      client_id       = "00000000-0000-0000-0000-0000000000e1"
      identifier_uris = ["api://00000000-0000-0000-0000-0000000000e1"]
    }
  }
}

run "example" {
  command = plan
}
