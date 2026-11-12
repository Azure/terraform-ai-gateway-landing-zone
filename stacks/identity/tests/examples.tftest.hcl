# Plans the stack with an example's tfvars (scripts/ci/check-examples.sh):
#   terraform test -filter=tests/examples.tftest.hcl -var-file=<common> -var-file=<stack>
# Mocked providers: it checks types and validations, not Azure.

mock_provider "azuread" {
  override_during = plan

  mock_data "azuread_client_config" {
    defaults = {
      object_id = "00000000-0000-0000-0000-0000000000a1"
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "azuread_application_published_app_ids" {
    defaults = {
      result = { MicrosoftGraph = "00000003-0000-0000-c000-000000000000" }
    }
  }
  mock_data "azuread_service_principal" {
    defaults = {
      oauth2_permission_scope_ids = { "User.Read" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" }
    }
  }
}

run "example" {
  command = plan
}
