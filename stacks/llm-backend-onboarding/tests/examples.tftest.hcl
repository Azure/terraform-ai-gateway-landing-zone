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

run "example" {
  command = plan
}
