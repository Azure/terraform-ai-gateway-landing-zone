# =============================================================================
# modules/monitoring: Azure Monitor private link and public network access.
#   terraform init -backend=false && terraform test
# =============================================================================

mock_provider "azurerm" {
  override_during = plan
}
mock_provider "azapi" {
  override_during = plan
}
mock_provider "random" {
  override_during = plan
}

variables {
  resource_group_name = "rg-aigw-dev"
  location            = "swedencentral"
  tags                = {}
  log_analytics_name  = "log-aigw-dev"
  environment_name    = "aigw-dev"
  create_dashboards   = false
  subscription_id     = "00000000-0000-0000-0000-000000000002"
  enable_telemetry    = false
}

run "public_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_private_link_scope.ampls) == 0 && length(azapi_resource.scoped) == 0 && length(azurerm_private_endpoint.ampls) == 0
    error_message = "No private link scope, scoped resources or private endpoint by default."
  }
  assert {
    condition     = output.private_link_scope_id == null && alltrue([for r in output.public_network_access : r.ingestion && r.query])
    error_message = "Every resource accepts public ingestion and queries by default."
  }
}

run "created_scope_with_public_access_off" {
  command = plan

  variables {
    use_azure_monitor_private_link_scope = true
    private_link_scope_access_mode       = { ingestion = "PrivateOnly" }
    ampls_subnet_id                      = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
    ampls_dns_zone_ids = [
      for z in ["monitor.azure.com", "oms.opinsights.azure.com", "ods.opinsights.azure.com", "agentsvc.azure-automation.net", "blob.core.windows.net"] :
      "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/privateDnsZones/privatelink.${z}"
    ]
    public_ingestion_enabled = false
    public_query_enabled     = false
    public_query_components  = ["log_analytics", "apim"]
  }

  assert {
    condition     = azurerm_monitor_private_link_scope.ampls[0].ingestion_access_mode == "PrivateOnly" && azurerm_monitor_private_link_scope.ampls[0].query_access_mode == "Open"
    error_message = "The scope takes the access modes (Open unless set)."
  }
  assert {
    condition     = sort(keys(azapi_resource.scoped)) == tolist(["apim", "foundry", "log_analytics", "logic_app"])
    error_message = "The workspace created here and the three components are scoped resources."
  }
  assert {
    condition     = length(azurerm_private_endpoint.ampls) == 1 && length(azurerm_private_endpoint.ampls[0].private_dns_zone_group[0].private_dns_zone_ids) == 5
    error_message = "The scope's private endpoint binds the five Azure Monitor zones."
  }
  assert {
    condition     = alltrue([for k, r in output.public_network_access : !r.ingestion && r.query == contains(["log_analytics", "apim"], k)])
    error_message = "Public ingestion is off everywhere, public query everywhere except the listed workspace and APIM component."
  }
}

run "dns_zone_group_left_to_policy" {
  command = plan

  variables {
    use_azure_monitor_private_link_scope = true
    dns_zone_group_managed_by_policy     = true
    ampls_subnet_id                      = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
  }

  assert {
    condition     = length(azurerm_private_endpoint.ampls) == 0 && length(azurerm_private_endpoint.ampls_policy_dns) == 1
    error_message = "Azure Policy binds the zone group: the private endpoint without one."
  }
}

run "joins_an_existing_scope_with_a_byo_workspace" {
  command = plan

  variables {
    existing_private_link_scope_id = "/subscriptions/00000000-0000-0000-0000-0000000000aa/resourceGroups/rg-hub-monitor/providers/Microsoft.Insights/privateLinkScopes/ampls-hub"
    existing_log_analytics_workspace = {
      id           = "/subscriptions/00000000-0000-0000-0000-0000000000bb/resourceGroups/rg-mgmt/providers/Microsoft.OperationalInsights/workspaces/law-central"
      workspace_id = "00000000-0000-0000-0000-0000000000cc"
    }
    public_ingestion_enabled = false
    public_query_enabled     = false
    public_query_components  = ["apim"]
  }

  # Mixed-case component IDs, as Azure Resource Manager reports them.
  override_module {
    target = module.app_insights
    outputs = {
      name        = "appi-aigw-dev"
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Insights/components/appi-aigw-dev"
    }
  }

  assert {
    condition     = length(azurerm_monitor_private_link_scope.ampls) == 0 && length(azurerm_private_endpoint.ampls) == 0 && length(azurerm_private_endpoint.ampls_policy_dns) == 0
    error_message = "Joining a scope creates no scope and no private endpoint (its owner's)."
  }
  assert {
    condition = (
      sort(keys(azapi_resource.scoped)) == tolist(["apim", "foundry", "logic_app"])
      && alltrue([for s in azapi_resource.scoped : s.parent_id == var.existing_private_link_scope_id])
    )
    error_message = "Only the components join the existing scope; a BYO workspace belongs to its owner."
  }
  assert {
    condition     = alltrue([for s in azapi_resource.scoped : s.body.properties.linkedResourceId == "/subscriptions/00000000-0000-0000-0000-000000000002/resourcegroups/rg-aigw-dev/providers/microsoft.insights/components/appi-aigw-dev"])
    error_message = "Linked resource IDs are sent lowercased (Azure returns them lowercased; any other casing drifts)."
  }
  assert {
    condition     = output.private_link_scope_id == var.existing_private_link_scope_id && !contains(keys(output.public_network_access), "log_analytics")
    error_message = "The joined scope is reported, and the BYO workspace's settings aren't."
  }
}

run "public_access_off_needs_a_scope" {
  command = plan

  variables {
    public_query_enabled = false
  }

  expect_failures = [var.public_query_enabled]
}

run "create_and_join_are_exclusive" {
  command = plan

  variables {
    use_azure_monitor_private_link_scope = true
    existing_private_link_scope_id       = "/subscriptions/00000000-0000-0000-0000-0000000000aa/resourceGroups/rg-hub-monitor/providers/Microsoft.Insights/privateLinkScopes/ampls-hub"
  }

  expect_failures = [var.use_azure_monitor_private_link_scope]
}

run "existing_scope_must_be_a_scope_id" {
  command = plan

  variables {
    existing_private_link_scope_id = "ampls-hub"
  }

  expect_failures = [var.existing_private_link_scope_id]
}

run "access_mode_is_validated" {
  command = plan

  variables {
    use_azure_monitor_private_link_scope = true
    private_link_scope_access_mode       = { query = "Private" }
  }

  expect_failures = [var.private_link_scope_access_mode]
}

run "public_query_components_are_validated" {
  command = plan

  variables {
    public_query_components = ["gateway"]
  }

  expect_failures = [var.public_query_components]
}
