# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

mock_provider "azapi" {
  override_during = plan
}

mock_provider "azurerm" {
  override_during = plan
}

variables {
  name              = "cs-aigw-dev"
  kind              = "ContentSafety"
  sku_name          = "S0"
  location          = "northeurope"
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev"
  enable_telemetry  = false
  apim_principal_id = "00000000-0000-0000-0000-0000000000a1"
  subnet_id         = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet-aigw-dev/subnets/snet-pe"
  dns_zone_id       = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
}

run "private_endpoint_in_the_vnet_region" {
  command = plan

  variables {
    private_endpoint_location = "swedencentral"
  }

  assert {
    condition     = module.account.private_endpoints["account"].location == "swedencentral"
    error_message = "The private endpoint is created in the VNet's region (private_endpoint_location), not the account's."
  }
}

run "private_endpoint_defaults_to_the_account_region" {
  command = plan

  assert {
    condition     = module.account.private_endpoints["account"].location == "northeurope"
    error_message = "Without private_endpoint_location the private endpoint follows the account's location."
  }
}
