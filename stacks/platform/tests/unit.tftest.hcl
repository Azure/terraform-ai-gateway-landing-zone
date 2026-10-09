# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

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
  mock_data "azurerm_resource_group" {
    defaults = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev"
      name = "rg-aigw-dev"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet-aigw-dev"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet-aigw-dev/subnets/snet"
    }
  }
  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/privateDnsZones/zone"
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
mock_provider "modtm" {
  override_during = plan
}

variables {
  workload        = "aigw"
  environment     = "dev"
  location        = "swedencentral"
  subscription_id = "00000000-0000-0000-0000-000000000002"
  foundry = {
    instances = [{ location = "swedencentral" }]
    models    = [{ name = "gpt-4o-mini", version = "2024-07-18" }]
  }
}

# --- defaults and greenfield lookups -----------------------------------------

run "policy_managed_diagnostics_create_no_workload_settings" {
  command = plan
  variables {
    monitoring = {
      policy_managed_diagnostics = ["apim", "cosmosdb", "eventhub", "foundry", "logic_app"]
    }
  }
  assert {
    condition     = alltrue([for names in output.diagnostic_setting_names : length(names) == 0])
    error_message = "Policy-owned diagnostics must not be created or overwritten by any service module."
  }
}

run "unknown_policy_managed_service_is_rejected" {
  command = plan
  variables {
    monitoring = { policy_managed_diagnostics = ["unknown"] }
  }
  expect_failures = [var.monitoring]
}

run "defaults_and_greenfield_lookups" {
  command = plan

  assert {
    condition     = alltrue([for names in output.diagnostic_setting_names : length(names) == 1])
    error_message = "Every service retains its workload diagnostics by default."
  }
  assert {
    condition     = local.apim_cfg.sku == "StandardV2" && local.apim_cfg.vnet_mode == "integration" && local.apim_cfg.private_endpoint
    error_message = "APIM defaults: StandardV2, outbound integration, inbound private endpoint."
  }
  assert {
    condition     = sort(keys(data.azurerm_subnet.greenfield)) == tolist(["agent", "apim", "logic_app", "pe"])
    error_message = "Greenfield looks up pe, apim (integration), logic_app (Workflow Standard) and agent (injection) by name."
  }
  assert {
    condition     = length(local.zone_ids) == 13 && !local.network.dns_zone_groups_managed_by_policy
    error_message = "Greenfield looks up all 13 private DNS zones and binds every zone group itself."
  }
  assert {
    condition     = module.apim.apim_name == local.names.apim && local.names.apim == "apim-aigw-dev-${module.naming.seed}"
    error_message = "APIM follows the naming contract (downstream stacks find it by name)."
  }
}

run "classic_sku_defaults_to_external_injection" {
  command = plan

  variables {
    apim = { sku = "Developer" }
  }

  assert {
    condition     = local.apim_cfg.vnet_mode == "external"
    error_message = "Classic SKUs default to external VNet injection."
  }
}

run "apim_none_skips_the_apim_subnet" {
  command = plan

  variables {
    apim = { vnet_mode = "none" }
  }

  assert {
    condition     = !contains(keys(data.azurerm_subnet.greenfield), "apim")
    error_message = "vnet_mode none: no APIM subnet to look up."
  }
}

# --- alz_spoke / byo -----------------------------------------------------------

run "alz_spoke_takes_explicit_ids_and_leaves_zone_groups_to_policy" {
  command = plan

  variables {
    network_mode = "alz_spoke"
    network = {
      vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke"
      subnet_ids = {
        pe        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/snet-pe"
        apim      = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/snet-apim"
        logic_app = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/snet-logic"
      }
      private_dns_zone_ids              = {}
      dns_zone_groups_managed_by_policy = true
    }
    features = { semantic_cache = true }
  }

  assert {
    condition     = length(data.azurerm_subnet.greenfield) == 0 && length(data.azurerm_private_dns_zone.greenfield) == 0
    error_message = "alz_spoke doesn't look anything up."
  }
  assert {
    condition     = local.network.dns_zone_groups_managed_by_policy && length(module.apim.internal_dns_zone_names) == 0
    error_message = "alz_spoke: policy owns the PE zone groups and the hub owns APIM DNS."
  }
}

run "alz_spoke_workflow_standard_needs_logic_app_subnet" {
  command = plan

  variables {
    network_mode = "alz_spoke"
    network = {
      vnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke"
      subnet_ids = { pe = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/snet-pe" }
    }
    apim = { vnet_mode = "none" }
  }

  expect_failures = [var.network]
}

run "alz_spoke_needs_network" {
  command = plan

  variables {
    network_mode = "alz_spoke"
  }

  expect_failures = [var.network]
}

# --- input rules -----------------------------------------------------------------

run "rejects_vnet_mode_not_supported_by_sku" {
  command = plan
  variables {
    apim = { sku = "StandardV2", vnet_mode = "internal" }
  }
  expect_failures = [var.apim]
}

run "private_access_needs_a_private_endpoint" {
  command = plan
  variables {
    apim = { public_network_access = false, private_endpoint = false }
  }
  expect_failures = [var.apim]
}

run "rejects_wrong_logic_app_sku_for_hosting" {
  command = plan
  variables {
    usage_pipeline = { logic_app = { hosting = "ase_v3", sku = "WS1" } }
  }
  expect_failures = [var.usage_pipeline]
}

run "rejects_unknown_redis_sku" {
  command = plan
  variables {
    redis = { sku_name = "Premium_P1" }
  }
  expect_failures = [var.redis]
}

run "byo_workspace_id_must_be_a_resource_id" {
  command = plan
  variables {
    monitoring = { log_analytics_workspace_id = "law-name" }
  }
  expect_failures = [var.monitoring]
}

run "dev_access_is_not_for_prod" {
  command = plan
  variables {
    environment = "prod"
    dev_access  = { allowed_cidrs = ["203.0.113.10"] }
  }
  expect_failures = [check.dev_access_scope]
}

# --- keyless usage pipeline on ASE v3 -------------------------------------------

run "ase_v3_is_keyless_and_runs_from_package" {
  command = plan

  variables {
    usage_pipeline = {
      logic_app = { hosting = "ase_v3", code_deploy = true }
    }
  }

  override_data {
    target = data.azapi_resource.ase[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Web/hostingEnvironments/ase-aigw-dev"
    }
  }

  assert {
    condition     = endswith(local.app_service_environment_id, "/hostingEnvironments/ase-aigw-dev") && !contains(keys(data.azurerm_subnet.greenfield), "logic_app")
    error_message = "ase_v3: the ASE of stacks/app-hosting is found by name; no Logic App subnet."
  }
  assert {
    condition     = module.logic_app.hosting.keyless_storage && module.logic_app.hosting.deployment_method == "run_from_package"
    error_message = "ase_v3 must use keyless storage and run-from-package by default."
  }
  assert {
    condition     = length(setintersection(module.logic_app.hosting.app_setting_names, ["AzureWebJobsStorage", "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING", "WEBSITE_CONTENTSHARE", "AzureCosmosDB_connectionString"])) == 0
    error_message = "No key-based app settings on the keyless site."
  }
}

run "shared_ase_is_not_looked_up" {
  command = plan

  variables {
    usage_pipeline = {
      logic_app = { hosting = "ase_v3" }
      ase       = { app_service_environment_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-shared/providers/Microsoft.Web/hostingEnvironments/ase-shared" }
    }
  }

  assert {
    condition     = length(data.azapi_resource.ase) == 0 && endswith(local.app_service_environment_id, "/ase-shared")
    error_message = "A shared ASE is used by ID."
  }
}

run "shared_key_deny_needs_ase" {
  command = plan
  variables {
    deny_storage_shared_key = true
  }
  expect_failures = [azurerm_resource_group_policy_assignment.deny_storage_shared_key]
}
