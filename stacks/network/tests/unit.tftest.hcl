# Unit tests (mocked providers, plan only):
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_resource_group" {
    defaults = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev"
      name = "rg-aigw-dev"
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

run "greenfield_default_carve" {
  command = plan

  assert {
    condition = local.prefixes == {
      agent     = "10.170.0.0/24"
      ase       = "10.170.1.0/24"
      apim      = "10.170.2.0/24"
      pe        = "10.170.3.0/26"
      logic_app = "10.170.3.64/26"
      cicd      = "10.170.3.128/27"
    }
    error_message = "The default carve of a /22 must not overlap and must give the ASE a /24."
  }
  assert {
    condition     = sort(keys(module.networking.subnet_nsg_names)) == tolist(["agent", "ase", "cicd", "pe"])
    error_message = "Defaults: pe, agent, ase and cicd subnets (no APIM subnet for vnet_mode none, no Logic App subnet), each with an NSG."
  }
  assert {
    condition     = length(module.private_dns) == 1 && length(module.private_dns[0].zone_ids) == 13
    error_message = "Greenfield creates all 13 private DNS zones."
  }
}

run "greenfield_apim_internal_and_ws_logic_app" {
  command = plan

  variables {
    apim_vnet_mode  = "internal"
    subnets_enabled = { logic_app = true, ase = false, cicd = false }
  }

  assert {
    condition     = sort(keys(module.networking.subnet_nsg_names)) == tolist(["agent", "apim", "logic_app", "pe"])
    error_message = "vnet_mode internal adds the APIM subnet; Workflow Standard adds the Logic App subnet."
  }
}

run "alz_spoke_creates_no_dns_and_routes_to_hub" {
  command = plan

  variables {
    network_mode = "alz_spoke"
    alz_spoke = {
      vended_vnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-vended/providers/Microsoft.Network/virtualNetworks/vnet-spoke"
      hub_firewall_ip = "10.0.0.4"
    }
  }

  assert {
    condition     = length(module.private_dns) == 0 && output.private_dns_zone_ids == {}
    error_message = "alz_spoke: the hub owns the private DNS zones."
  }
  assert {
    condition     = alltrue([for k, ip in module.networking.spoke_routes : ip == "10.0.0.4"])
    error_message = "alz_spoke: every subnet routes 0.0.0.0/0 to the hub firewall."
  }
  assert {
    condition     = output.platform_network.dns_zone_groups_managed_by_policy
    error_message = "alz_spoke: platform leaves PE DNS zone groups to Azure Policy by default."
  }
}

run "byo_does_not_run" {
  command = plan

  variables {
    network_mode = "byo"
  }

  expect_failures = [data.azurerm_resource_group.workload]
}

run "alz_spoke_needs_vended_vnet" {
  command = plan

  variables {
    network_mode = "alz_spoke"
  }

  expect_failures = [data.azurerm_resource_group.workload]
}

run "address_space_too_small" {
  command = plan

  variables {
    address_space = "10.170.0.0/24"
  }

  expect_failures = [var.address_space]
}
