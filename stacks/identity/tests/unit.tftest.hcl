# Unit tests (mocked providers, plan only):
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
  workload        = "aigw"
  environment     = "dev"
  location        = "swedencentral"
  subscription_id = "00000000-0000-0000-0000-000000000002"
}

run "app_follows_naming_contract_and_has_no_secret" {
  command = plan

  assert {
    condition     = module.gateway_app.display_name == "app-aigw-dev-gateway"
    error_message = "gateway-config finds the app by its deterministic display name."
  }
  assert {
    condition     = contains(module.gateway_app.owners, "00000000-0000-0000-0000-0000000000a1")
    error_message = "The identity running the stack must own the app (Application.ReadWrite.OwnedBy)."
  }
}
