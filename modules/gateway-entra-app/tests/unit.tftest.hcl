# Unit tests (mocked provider, plan only):
#   terraform init -backend=false && terraform test

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

variables {
  display_name = "app-aigw-dev-27cbb-gateway"
}

# Upstream's setup.ps1 (1.0.3): one role per capability and no umbrella role. The roles keep the IDs of the
# Models.Read, MCP.Read and Agent.Read roles they replace (scripts/entra_id_setup.py uses the same IDs), so
# an existing app is updated in place and its role assignments survive.
run "the_gateway_app_defines_the_invoke_roles" {
  command = plan

  assert {
    condition = { for r in azuread_application.gateway.app_role : r.value => r.id } == {
      "Model.Invoke" = "00000000-0000-0000-0000-000000000003"
      "MCP.Invoke"   = "00000000-0000-0000-0000-000000000004"
      "Agent.Invoke" = "00000000-0000-0000-0000-000000000005"
    }
    error_message = "Model.Invoke, MCP.Invoke and Agent.Invoke on the IDs of the roles they replace; no Task.ReadWrite."
  }
  assert {
    condition = alltrue([for r in azuread_application.gateway.app_role :
    r.enabled && r.display_name == r.value && toset(r.allowed_member_types) == toset(["User", "Application"])])
    error_message = "Every role is enabled, named like its value, and can be assigned to users and applications."
  }
  assert {
    condition     = length(azuread_application.gateway.api[0].oauth2_permission_scope) == 1 && one(azuread_application.gateway.api[0].oauth2_permission_scope).value == "access_as_user"
    error_message = "The delegated scope access_as_user stays."
  }
}
