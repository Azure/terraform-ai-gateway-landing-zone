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
    condition     = toset(keys(azurerm_private_dns_zone.internal)) == toset(["apim-test.azure-api.net"]) && length(module.service.private_endpoints) == 0
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
