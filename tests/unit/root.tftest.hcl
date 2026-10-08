# =============================================================================
# Baseline unit tests for the root configuration (Phase 0, WP-0.7).
#
# They capture CURRENT behaviour so the Phase 1 refactor (moving code between
# modules) can prove it changed nothing. Every run uses `command = plan` with
# mocked providers, so no Azure credentials or network access are needed.
#
#   terraform init -backend=false && terraform test
# =============================================================================

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
      client_id       = "00000000-0000-0000-0000-000000000004"
    }
  }
  mock_data "azurerm_subscription" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000002"
      tenant_id       = "00000000-0000-0000-0000-000000000001"
    }
  }
}

mock_provider "azurerm" {
  alias           = "loganalytics"
  override_during = plan
}

mock_provider "azapi" {
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
      oauth2_permission_scope_ids = { "User.Read" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" }
      app_role_ids                = {}
    }
  }
}
mock_provider "random" {
  override_during = plan
}
mock_provider "time" {
  override_during = plan
}
mock_provider "archive" {
  override_during = plan
}
mock_provider "null" {
  override_during = plan
}
mock_provider "http" {
  override_during = plan
}

variables {
  subscription_id     = "00000000-0000-0000-0000-000000000002"
  environment_name    = "citadel-test"
  location            = "swedencentral"
  resource_group_name = "rg-citadel-test"
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------
run "naming_is_deterministic" {
  command = plan

  assert {
    condition     = module.naming.resource_token == substr(sha256("rg-citadel-test-citadel-test-00000000-0000-0000-0000-000000000002"), 0, 10)
    error_message = "resource_token must be sha256(<rg>-<env>-<subscription>)[0:10]."
  }
  assert {
    condition     = local.apim_service_name == "apim-${module.naming.resource_token}"
    error_message = "Default APIM name must be apim-<resource_token>."
  }
  assert {
    condition     = local.key_vault_name == "kv-${module.naming.resource_token}" && local.cosmos_db_name == "cosmos-${module.naming.resource_token}" && local.eventhub_ns_name == "evhns-${module.naming.resource_token}"
    error_message = "Default Key Vault / Cosmos / Event Hubs names changed."
  }
  assert {
    condition     = local.vnet_name == "vnet-citadel-test" && local.resource_group_name == "rg-citadel-test"
    error_message = "Default VNet / resource group names changed."
  }
}

run "explicit_names_win" {
  command = plan

  variables {
    apim                   = { name = "apim-custom" }
    key_vault_name         = "kv-custom"
    cosmos_db_account_name = "cosmos-custom"
  }

  assert {
    condition     = local.apim_service_name == "apim-custom" && local.key_vault_name == "kv-custom" && local.cosmos_db_name == "cosmos-custom"
    error_message = "Explicit names must override generated ones."
  }
}

run "default_resource_group_name_from_environment" {
  command = plan

  variables {
    resource_group_name = ""
  }

  assert {
    condition     = local.resource_group_name == "rg-citadel-test"
    error_message = "With no resource_group_name the RG must be rg-<environment_name>."
  }
}

# -----------------------------------------------------------------------------
# Feature flags (defaults and toggles)
# -----------------------------------------------------------------------------
run "optional_features_default_state" {
  command = plan

  assert {
    condition     = length(module.redis) == 0
    error_message = "Redis must be opt-in (features.semantic_cache defaults to false)."
  }
  assert {
    condition     = length(module.entra_id) == 0
    error_message = "Entra ID setup must be opt-in (enable_entra_id_setup defaults to false)."
  }
  assert {
    condition     = toset(keys(module.networking[0].subnet_nsg_names)) == toset(["apim", "pe", "logic_app", "agent"])
    error_message = "Every greenfield subnet must have an NSG (ALZ Deny-Subnet-Without-Nsg)."
  }
}

run "redis_and_entra_toggle_on" {
  command = plan

  variables {
    features                          = { semantic_cache = true }
    enable_entra_id_setup             = true
    entra_client_secret_rotation_days = 60 # <= 90 keeps the ALZ check quiet
  }

  assert {
    condition     = length(module.redis) == 1 && length(module.entra_id) == 1
    error_message = "features.semantic_cache / enable_entra_id_setup must create their modules."
  }
  # Regression test: this plan used to fail with "Invalid count argument"
  # because the APIM cache count depended on the Redis connection string.
}

run "apim_sku_family" {
  command = plan

  variables {
    apim = { sku = "StandardV2" }
  }

  assert {
    condition     = local.is_apim_v2 && !local.is_apim_vnet
    error_message = "StandardV2 must be treated as a v2 SKU without classic VNet injection."
  }
}

run "apim_sku_family_classic" {
  command = plan

  variables {
    apim = { sku = "Developer" }
  }

  assert {
    condition     = !local.is_apim_v2 && local.is_apim_vnet
    error_message = "Developer must be treated as a classic SKU with VNet injection."
  }
}

# -----------------------------------------------------------------------------
# LLM backend synthesis (modules/apim/backends.tf)
# -----------------------------------------------------------------------------
run "llm_backends_pools_for_shared_models" {
  command = plan

  variables {
    llm_backend_config = [
      {
        backend_id   = "east"
        backend_type = "azure-openai"
        endpoint     = "https://east.openai.azure.com/openai"
        auth_scheme  = "managedIdentity"
        priority     = 1
        weight       = 100
        supported_models = [
          { name = "gpt-4.1" },
          { name = "gpt-4.1-mini" },
        ]
      },
      {
        backend_id   = "west"
        backend_type = "azure-openai"
        endpoint     = "https://west.openai.azure.com/openai"
        auth_scheme  = "managedIdentity"
        priority     = 2
        weight       = 100
        supported_models = [
          { name = "gpt-4.1" },
        ]
      },
    ]
  }

  assert {
    condition     = toset(keys(module.llm_routing.backend_ids)) == toset(["east", "west"])
    error_message = "One APIM backend must be created per llm_backend_config entry."
  }
  assert {
    condition     = toset(keys(module.llm_routing.pool_ids)) == toset(["gpt-41-backend-pool"])
    error_message = "Only models served by 2+ backends get a pool, named <model without dots>-backend-pool."
  }
}

run "llm_backends_auto_derived_from_foundry" {
  command = plan

  variables {
    ai_foundry_instances = [
      { name = "", location = "swedencentral" },
      { name = "", location = "westeurope" },
    ]
    ai_foundry_models = [
      { name = "gpt-4.1", version = "2025-04-14", ai_service_index = 0 },
      { name = "gpt-4.1", version = "2025-04-14", ai_service_index = 1 },
    ]
  }

  assert {
    condition     = toset(keys(module.llm_routing.backend_ids)) == toset(["foundry-swedencentral-0", "foundry-westeurope-1"])
    error_message = "With llm_backend_config = [] one backend per Foundry instance must be derived (foundry-<location>-<index>)."
  }
  assert {
    condition     = toset(keys(module.llm_routing.pool_ids)) == toset(["gpt-41-backend-pool"])
    error_message = "A model deployed on both Foundry instances must get a backend pool."
  }
}

run "name_overrides_apply_when_dedicated_inputs_unset" {
  command = plan

  variables {
    name_overrides = { key_vault = "kv-override", apim = "apim-override" }
  }

  assert {
    condition     = local.key_vault_name == "kv-override" && local.apim_service_name == "apim-override"
    error_message = "name_overrides must apply when the dedicated *_name input is unset."
  }
}
