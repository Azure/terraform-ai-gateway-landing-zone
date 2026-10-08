# =============================================================================
# Typed inputs: defaults, effective configuration and validations.
#   terraform init -backend=false && terraform test -test-directory=tests/unit
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
  # Valid-looking IDs for the byo lookups (network.mode = "byo", BYO workspace).
  mock_data "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-hub"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/snet-x"
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

  mock_data "azurerm_log_analytics_workspace" {
    defaults = {
      workspace_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

mock_provider "azapi" {
  override_during = plan
}
mock_provider "azuread" {
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
run "typed_defaults" {
  command = plan

  assert {
    condition     = local.apim_cfg.sku == "StandardV2" && local.apim_cfg.capacity == 1 && local.apim_cfg.vnet_mode == "integration" && local.apim_cfg.private_endpoint
    error_message = "APIM defaults must be (StandardV2, 1 unit, outbound integration, PE on)."
  }
  assert {
    condition     = !local.network_cfg.byo && local.network_cfg.address_space == "10.170.0.0/24" && local.network_cfg.subnets.apim.name == "snet-citadel-apim" && local.network_cfg.subnets.agent.enabled
    error_message = "Network defaults."
  }
  assert {
    condition     = local.features.api_center && local.features.pii_redaction && !local.features.semantic_cache && !local.features.mcp_sample
    error_message = "Feature defaults."
  }
  assert {
    condition     = local.usage_cfg.logic_app.hosting_model == "WorkflowStandard" && local.usage_cfg.logic_app.ws_sku == "WS1" && local.usage_cfg.logic_app.ase_sku == "I1v2"
    error_message = "Usage pipeline defaults."
  }
  assert {
    condition     = !local.monitoring_cfg.byo_workspace && local.monitoring_cfg.workspace_id == "" && local.monitoring_cfg.app_insights_dashboards
    error_message = "Monitoring defaults."
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

run "typed_inputs_drive_effective_config" {
  command = plan

  variables {
    apim     = { sku = "Premium", capacity = 2, vnet_mode = "internal", name = "apim-custom" }
    network  = { vnet_name = "vnet-custom", address_space = "10.10.0.0/24", subnets = { agent = { enabled = false } } }
    features = { semantic_cache = true, api_center = false }
    usage_pipeline = {
      logic_app = { hosting = "ase_v3", sku = "I2v2", worker_count = 2 }
    }
    monitoring = { log_analytics_workspace_id = "/subscriptions/x/resourceGroups/y/providers/Microsoft.OperationalInsights/workspaces/z" }
  }

  assert {
    condition     = local.apim_cfg.vnet_mode == "internal" && local.apim_cfg.capacity == 2 && local.apim_service_name == "apim-custom"
    error_message = "apim object must drive the APIM settings and name."
  }
  assert {
    condition     = !local.network_cfg.byo && local.vnet_name == "vnet-custom" && local.network_cfg.address_space == "10.10.0.0/24" && !local.network_cfg.subnets.agent.enabled && local.create_dns_zones
    error_message = "network object must drive the VNet name, address space and subnets."
  }
  assert {
    condition     = local.features.semantic_cache && !local.features.api_center
    error_message = "features object must drive the feature flags."
  }
  assert {
    condition     = local.usage_cfg.logic_app.hosting_model == "AppServiceEnvironmentV3" && local.usage_cfg.logic_app.ase_sku == "I2v2" && local.usage_cfg.logic_app.ws_sku == "WS1"
    error_message = "usage_pipeline.logic_app.sku must apply to the selected hosting model only."
  }
  assert {
    condition     = local.monitoring_cfg.byo_workspace
    error_message = "A workspace ID means BYO Log Analytics."
  }
}

run "rejects_vnet_mode_not_supported_by_sku" {
  command = plan

  variables {
    apim = { sku = "StandardV2", vnet_mode = "internal" }
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

run "rejects_unknown_network_mode" {
  command = plan

  variables {
    network = { mode = "hub" }
  }

  expect_failures = [var.network]
}

run "byo_network_is_looked_up_not_created" {
  command = plan

  variables {
    network = {
      mode                = "byo"
      resource_group_name = "rg-net"
      vnet_name           = "vnet-hub"
      subnets             = { agent = { enabled = false } }
      private_dns = {
        resource_group_name = "rg-dns"
        zone_ids = { for k in ["key_vault", "cosmos_db", "event_hub", "cognitive_services", "openai", "storage_blob", "storage_file", "storage_table", "storage_queue", "monitor", "apim_gateway", "ai_services", "redis"] :
        k => "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/${k}.example" }
      }
    }
  }

  assert {
    condition     = length(module.networking) == 0 && length(data.azurerm_virtual_network.byo) == 1
    error_message = "byo must look the VNet up instead of creating one."
  }
  assert {
    condition     = toset(keys(data.azurerm_subnet.byo)) == toset(["apim", "private_endpoint", "logic_app"])
    error_message = "byo must look up exactly the subnets in use."
  }
  assert {
    condition     = endswith(local.network.vnet_id, "/virtualNetworks/vnet-hub") && endswith(local.network.pe_subnet_id, "/subnets/snet-x")
    error_message = "local.network must carry the looked-up IDs."
  }
  assert {
    condition     = !local.create_dns_zones && endswith(module.private_dns.zone_ids["key_vault"], "/key_vault.example")
    error_message = "With BYO zones no zones are created and the supplied IDs are used."
  }
}

run "byo_log_analytics_workspace" {
  command = plan

  variables {
    monitoring = {
      log_analytics_workspace_id    = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-law/providers/Microsoft.OperationalInsights/workspaces/law-central"
      log_analytics_subscription_id = "22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = length(data.azurerm_log_analytics_workspace.byo) == 1 && module.monitoring.log_analytics_workspace_id == "11111111-1111-1111-1111-111111111111"
    error_message = "A BYO workspace must be looked up in the root and passed to modules/monitoring."
  }
  assert {
    condition     = endswith(module.monitoring.log_analytics_id, "/workspaces/law-central")
    error_message = "modules/monitoring must use the BYO workspace ID instead of creating one."
  }
}

# --- Root rules (WP-1.6) ----------------------------------------------------------

run "rejects_unknown_redis_sku" {
  command = plan

  variables {
    redis_sku_name = "Basic_C1"
  }

  expect_failures = [var.redis_sku_name]
}

run "byo_network_needs_resource_group" {
  command = plan

  variables {
    network = { mode = "byo", vnet_name = "vnet-hub" }
  }

  expect_failures = [var.network]
}

run "byo_workspace_id_must_be_a_resource_id" {
  command = plan

  variables {
    monitoring = { log_analytics_workspace_id = "law-central" }
  }

  expect_failures = [var.monitoring]
}

run "alz_spoke_creates_subnets_in_the_vended_vnet" {
  command = plan

  variables {
    network = {
      mode                = "alz_spoke"
      resource_group_name = "rg-spoke-network"
      vnet_name           = "vnet-spoke"
      hub_firewall_ip     = "10.0.0.4"
    }
  }

  assert {
    condition     = length(module.networking) == 1 && endswith(module.networking[0].vnet_id, "/virtualNetworks/vnet-hub") && local.network.vnet_id == module.networking[0].vnet_id
    error_message = "alz_spoke must create the subnets in the vended (looked-up) VNet, not a new VNet."
  }
  assert {
    condition     = module.networking[0].spoke_routes == { apim = "10.0.0.4", pe = "10.0.0.4", logic_app = "10.0.0.4", agent = "10.0.0.4" }
    error_message = "Every alz_spoke subnet must route 0.0.0.0/0 to the hub firewall."
  }
  assert {
    condition     = !local.network_cfg.default_outbound_access && local.network_cfg.zone_groups_managed_by_policy && !local.create_dns_zones
    error_message = "alz_spoke: no default outbound access, DNS zones and zone groups owned by the platform."
  }
}

run "alz_spoke_needs_hub_firewall_ip" {
  command = plan

  variables {
    network = { mode = "alz_spoke", resource_group_name = "rg-spoke-network", vnet_name = "vnet-spoke" }
  }

  expect_failures = [var.network]
}

run "developer_sku_cannot_scale_out" {
  command = plan

  variables {
    apim = { sku = "Developer", capacity = 2 }
  }

  expect_failures = [var.apim]
}

run "premium_v2_injection_is_accepted" {
  command = plan

  variables {
    apim = { sku = "PremiumV2", vnet_mode = "injection" }
  }

  assert {
    condition     = local.apim_cfg.vnet_mode == "injection" && contains(keys(module.networking[0].subnet_nsg_names), "apim")
    error_message = "PremiumV2 injection must get an APIM subnet."
  }
}

run "v2_without_vnet_has_no_apim_subnet" {
  command = plan

  variables {
    apim = { sku = "StandardV2", vnet_mode = "none" }
  }

  assert {
    condition     = module.networking[0].apim_subnet_id == "" && !contains(keys(module.networking[0].subnet_nsg_names), "apim")
    error_message = "vnet_mode none must not create an APIM subnet (or its NSG)."
  }
}

run "injection_is_premium_v2_only" {
  command = plan

  variables {
    apim = { sku = "StandardV2", vnet_mode = "injection" }
  }

  expect_failures = [var.apim]
}

run "private_access_needs_a_private_endpoint" {
  command = plan

  variables {
    apim = { sku = "PremiumV2", vnet_mode = "injection", public_network_access = false }
  }

  expect_failures = [var.apim]
}

run "public_ip_is_classic_only" {
  command = plan

  variables {
    apim = { sku = "StandardV2", public_ip_address_id = "/subscriptions/x/resourceGroups/y/providers/Microsoft.Network/publicIPAddresses/pip" }
  }

  expect_failures = [var.apim]
}

run "alz_policy_owns_every_dns_zone_group" {
  command = plan

  variables {
    network = {
      mode                = "alz_spoke"
      resource_group_name = "rg-spoke-network"
      vnet_name           = "vnet-spoke"
      hub_firewall_ip     = "10.0.0.4"
    }
    features   = { semantic_cache = true }
    monitoring = { private_link_scope = true }
  }

  assert {
    condition     = local.network_cfg.zone_groups_managed_by_policy && length(module.private_dns.zone_ids) == 0
    error_message = "alz_spoke without zone IDs: no zones, zone groups owned by policy."
  }
}
