# =============================================================================
# modules/private-dns (WP-1.4/1.6): created vs supplied zones, required keys.
#   terraform init -backend=false && terraform test -test-directory=tests/unit
# =============================================================================

mock_provider "azurerm" {
  override_during = plan
}

variables {
  resource_group_name = "rg-dns"
  vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  required_zone_keys  = ["key_vault", "cosmos_db"]
}

run "created_zones_cover_required_keys" {
  command = plan
  module {
    source = "./modules/private-dns"
  }
  assert {
    condition     = length(azurerm_private_dns_zone.zones) == 13 && length(azurerm_private_dns_zone_virtual_network_link.links) == 12
    error_message = "All 13 zones are created; the monitor zone is not linked without AMPLS."
  }
}

run "supplied_zone_ids_accept_bicep_keys" {
  command = plan
  module {
    source = "./modules/private-dns"
  }
  variables {
    create_zones      = false
    existing_zone_ids = { keyVault = "/zones/kv", cosmos_db = "/zones/cosmos" }
  }
  assert {
    condition     = output.zone_ids == { key_vault = "/zones/kv", cosmos_db = "/zones/cosmos" } && length(azurerm_private_dns_zone.zones) == 0
    error_message = "Supplied IDs must be used (camelCase keys normalised) and nothing created."
  }
}

run "missing_required_zone_is_reported" {
  command = plan
  module {
    source = "./modules/private-dns"
  }
  variables {
    create_zones      = false
    existing_zone_ids = { key_vault = "/zones/kv" }
  }
  expect_failures = [output.zone_ids]
}
