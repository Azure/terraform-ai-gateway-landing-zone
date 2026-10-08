# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

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

variables {
  workload        = "aigw"
  environment     = "dev"
  location        = "swedencentral"
  subscription_id = "00000000-0000-0000-0000-000000000002"
  github          = { repository = "contoso/ai-gateway" }
}

run "pair_mode_defaults" {
  command = plan

  assert {
    condition     = keys(module.pipeline_identity) == ["apply", "plan"]
    error_message = "pair mode creates a plan and an apply identity."
  }
  assert {
    condition = (
      local.identities["plan"].github_environments == tolist(["dev-plan"]) &&
      local.identities["apply"].github_environments == tolist(["dev"])
    )
    error_message = "The plan identity trusts GitHub environment dev-plan; the apply identity trusts dev."
  }
  assert {
    condition     = length(azurerm_role_definition.plan_reader) == 1 && length(azurerm_role_assignment.plan) == 1
    error_message = "The plan identity gets the custom read-only role."
  }
  assert {
    condition     = keys(azuread_app_role_assignment.graph) == ["apply-Application.Read.All", "apply-Application.ReadWrite.OwnedBy", "plan-Application.Read.All"]
    error_message = "Graph: Application.Read.All for both identities, Application.ReadWrite.OwnedBy for apply only."
  }
  assert {
    condition     = sort(keys(module.state_storage.containers)) == sort(var.stacks)
    error_message = "One state container per stack."
  }
  assert {
    condition     = can(regex("^staigwdev[0-9a-f]{5}tf$", local.names.state_storage_account)) && local.names.resource_group == "rg-aigw-dev"
    error_message = "State and workload names follow the naming contract."
  }
}

run "apply_rbac_never_grants_privileged_roles" {
  command = plan

  assert {
    condition = (
      azurerm_role_assignment.apply["workload-rbac-admin"].condition_version == "2.0" &&
      strcontains(azurerm_role_assignment.apply["workload-rbac-admin"].condition, "8e3af657-a8ff-443c-a75c-2fe8c4bcb635") &&
      strcontains(azurerm_role_assignment.apply["workload-rbac-admin"].condition, "f58310d9-a9f6-439a-9e8d-f62e7b41a168")
    )
    error_message = "The apply identity's RBAC Administrator assignment must exclude Owner, User Access Administrator and RBAC Administrator."
  }
  assert {
    condition     = !contains([for a in azurerm_role_assignment.apply : a.role_definition_name], "Owner")
    error_message = "The apply identity never gets Owner."
  }
}

run "single_mode" {
  command = plan

  variables {
    pipeline_identity_mode = "single"
  }

  assert {
    condition     = keys(module.pipeline_identity) == ["apply"]
    error_message = "single mode creates one identity."
  }
  assert {
    condition     = sort(local.identities["apply"].github_environments) == tolist(["dev", "dev-plan"])
    error_message = "In single mode the one identity trusts both GitHub environments."
  }
  assert {
    condition     = length(azurerm_role_definition.plan_reader) == 0
    error_message = "No separate plan role in single mode."
  }
}

run "existing_identities" {
  command = plan

  variables {
    create_pipeline_identities     = false
    create_workload_resource_group = false
    graph_permissions              = false
    existing_pipeline_identities = {
      apply_principal_id = "00000000-0000-0000-0000-0000000000a1"
      plan_principal_id  = "00000000-0000-0000-0000-0000000000a2"
    }
  }

  assert {
    condition     = length(module.pipeline_identity) == 0 && length(module.workload_resource_group) == 0
    error_message = "Vended identities and resource group are used, not created."
  }
  assert {
    condition     = azurerm_role_assignment.plan[0].principal_id == "00000000-0000-0000-0000-0000000000a2"
    error_message = "The existing plan identity gets the read-only role."
  }
}

run "private_state_needs_a_private_endpoint" {
  command = plan

  variables {
    state_storage = { public_network_access_enabled = false }
  }

  expect_failures = [var.state_storage]
}

run "existing_identities_must_be_supplied" {
  command = plan

  variables {
    create_pipeline_identities = false
  }

  expect_failures = [var.existing_pipeline_identities]
}
