# =============================================================================
# modules/apim preconditions (WP-1.6): the SKU x network matrix and scale rules.
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

mock_provider "azapi" {
  override_during = plan
}

variables {
  resource_group_name           = "rg-citadel-test"
  location                      = "swedencentral"
  tags                          = {}
  apim_name                     = "apim-test"
  sku_name                      = "StandardV2"
  sku_capacity                  = 1
  publisher_email               = "admin@contoso.com"
  publisher_name                = "Test"
  vnet_mode                     = "integration"
  apim_subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/apim"
  pe_subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
  vnet_id                       = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  apim_v2_use_private_endpoint  = true
  apim_v2_public_network_access = true
  managed_identity_id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-apim"
  dns_zone_id_apim              = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
  subscription_id               = "00000000-0000-0000-0000-000000000002"
}

run "v2_defaults_are_valid" {
  command = plan
}

run "v2_private_access_needs_private_endpoint" {
  command = plan
  variables {
    apim_v2_use_private_endpoint  = false
    apim_v2_public_network_access = false
  }
  expect_failures = [terraform_data.service_rules]
}


run "zones_need_premium_and_enough_units" {
  command = plan
  variables {
    sku_name     = "Premium"
    vnet_mode    = "external"
    sku_capacity = 2
    apim_zones   = ["1", "2", "3"]
  }
  expect_failures = [terraform_data.service_rules]
}

run "premium_zone_redundant_is_valid" {
  command = plan
  variables {
    sku_name     = "Premium"
    vnet_mode    = "internal"
    sku_capacity = 3
    apim_zones   = ["1", "2", "3"]
  }
}

run "premium_v2_injection_gets_private_gateway_dns" {
  command = plan
  variables {
    sku_name            = "PremiumV2"
    vnet_mode           = "injection"
    create_internal_dns = true
  }
  assert {
    condition     = toset(keys(azurerm_private_dns_zone.internal)) == toset(["apim-test.azure-api.net"]) && length(module.service[0].private_endpoints) == 0
    error_message = "Premium v2 injection: private DNS for the gateway hostname only, no inbound private endpoint."
  }
}

run "vnet_mode_must_match_sku" {
  command = plan
  variables {
    sku_name  = "StandardV2"
    vnet_mode = "injection"
  }
  expect_failures = [terraform_data.service_rules]
}

# --- zone redundancy -------------------------------------------------------------

run "v2_zone_redundant_is_created_with_azapi" {
  command = plan
  variables {
    zone_redundant = true
    sku_capacity   = 2
  }
  assert {
    condition     = length(module.service) == 0 && length(azapi_resource.service_zone_redundant) == 1
    error_message = "A zone-redundant v2 service is created by azapi_resource.service_zone_redundant, not by the AVM module."
  }
  assert {
    condition = (
      azapi_resource.service_zone_redundant[0].body.properties.zoneRedundant == true &&
      azapi_resource.service_zone_redundant[0].body.sku.capacity == 2 &&
      azapi_resource.service_zone_redundant[0].body.properties.virtualNetworkType == "External" &&
      azapi_resource.service_zone_redundant[0].body.properties.virtualNetworkConfiguration.subnetResourceId == var.apim_subnet_id &&
      azapi_resource.service_zone_redundant[0].body.properties.customProperties["Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10"] == "false"
    )
    error_message = "The zone-redundant service must carry zoneRedundant, the units, the VNet integration and the hardened protocols."
  }
  assert {
    condition     = length(azurerm_private_endpoint.zone_redundant) == 1 && azurerm_private_endpoint.zone_redundant[0].private_service_connection[0].subresource_names == tolist(["Gateway"])
    error_message = "The zone-redundant service gets its own inbound private endpoint."
  }
}

run "v2_without_zone_redundancy_keeps_the_avm_module" {
  command = plan
  assert {
    condition     = length(module.service) == 1 && length(azapi_resource.service_zone_redundant) == 0 && length(azurerm_private_endpoint.zone_redundant) == 0
    error_message = "Without zone_redundant the AVM module creates the service, as before."
  }
}

run "developer_has_no_zones" {
  command = plan
  variables {
    sku_name       = "Developer"
    vnet_mode      = "none"
    zone_redundant = true
  }
  expect_failures = [terraform_data.service_rules]
}

run "classic_premium_zone_redundant_needs_two_units" {
  command = plan
  variables {
    sku_name       = "Premium"
    vnet_mode      = "external"
    zone_redundant = true
  }
  expect_failures = [terraform_data.service_rules]
}

run "existing_v2_service_keeps_its_zone_setting" {
  command = plan
  variables {
    zone_redundant = true
  }
  override_data {
    target = data.azapi_resource.service_state
    values = {
      exists = true
      output = { zone_redundant = false }
    }
  }
  expect_failures = [terraform_data.service_rules]
}

run "existing_zone_redundant_v2_service_plans_cleanly" {
  command = plan
  variables {
    zone_redundant = true
  }
  override_data {
    target = data.azapi_resource.service_state
    values = {
      exists = true
      output = { zone_redundant = true }
    }
  }
}
