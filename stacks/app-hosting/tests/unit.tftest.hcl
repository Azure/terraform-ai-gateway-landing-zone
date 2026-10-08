# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet-aigw-dev/subnets/snet-ase"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet-aigw-dev"
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

variables {
  workload        = "aigw"
  environment     = "dev"
  location        = "swedencentral"
  subscription_id = "00000000-0000-0000-0000-000000000002"
}

run "greenfield_looks_up_subnet_and_vnet" {
  command = plan

  assert {
    condition     = endswith(local.ase_subnet_id, "/subnets/snet-ase") && endswith(local.dns_vnet_link_ids["spoke"], "/virtualNetworks/vnet-aigw-dev")
    error_message = "Greenfield finds snet-ase and the VNet by name."
  }
  assert {
    condition     = module.app_hosting.name == "ase-aigw-dev-${module.naming.seed}"
    error_message = "The ASE follows the naming contract (platform finds it by name)."
  }
}

run "alz_spoke_uses_explicit_ids" {
  command = plan

  variables {
    network_mode = "alz_spoke"
    ase          = { subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/snet-ase", zone_redundant = true }
    dns          = { vnet_link_ids = { spoke = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke" } }
  }

  assert {
    condition     = length(data.azurerm_subnet.ase) == 0 && length(data.azurerm_virtual_network.greenfield) == 0
    error_message = "alz_spoke doesn't look anything up."
  }
}
