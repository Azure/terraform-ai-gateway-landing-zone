# Plans the stack with an example's tfvars (scripts/ci/check-examples.sh):
#   terraform test -filter=tests/examples.tftest.hcl -var-file=<common> -var-file=<stack>
# Mocked providers: it checks types and validations, not Azure.

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-000000000003"
    }
  }
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev"
    }
  }
}
mock_provider "azapi" {
  override_during = plan
}
mock_provider "modtm" {
  override_during = plan
}
mock_provider "random" {
  override_during = plan
}
mock_provider "azuread" {
  override_during = plan

  mock_data "azuread_application_published_app_ids" {
    defaults = {
      result = { MicrosoftGraph = "00000003-0000-0000-c000-000000000000" }
    }
  }
  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "00000000-0000-0000-0000-0000000000aa"
      app_role_ids = {
        "Application.Read.All"          = "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"
        "Application.ReadWrite.OwnedBy" = "18a4783c-866b-4cc7-a460-3d5e5662c884"
      }
    }
  }
}

run "example" {
  command = plan
}
