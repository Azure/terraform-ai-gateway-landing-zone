# Unit tests (WP-2b.1): ILB by default, hardening fixed, DNS zone for internal ASEs.
#   terraform init -backend=false && terraform test

mock_provider "azapi" {
  override_during = plan
}

variables {
  name              = "ase-citadel-test"
  location          = "swedencentral"
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-test"
  subnet_id         = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/ase"
  dns_vnet_link_ids = { spoke = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet" }
}

run "internal_and_hardened_by_default" {
  command = plan

  assert {
    condition     = var.internal_load_balancing_mode == "Web, Publishing" && local.internal
    error_message = "The ASE must default to internal (ILB, Web + Publishing)."
  }
  assert {
    condition     = local.hardening == { internal_encryption_enabled = true, tls_1_enabled = false, ftp_enabled = false, remote_debug_enabled = false }
    error_message = "Internal encryption on; TLS 1.0, FTP and remote debugging off."
  }
  assert {
    condition     = length(module.dns) == 1 && output.dns_suffix == "ase-citadel-test.appserviceenvironment.net"
    error_message = "An internal ASE gets the <ase>.appserviceenvironment.net private DNS zone."
  }
}

run "external_ase_has_no_private_dns" {
  command = plan

  variables {
    internal_load_balancing_mode = "None"
  }

  assert {
    condition     = length(module.dns) == 0
    error_message = "An external ASE needs no private DNS zone."
  }
}

run "rejects_unknown_ilb_mode" {
  command = plan

  variables {
    internal_load_balancing_mode = "Web"
  }

  expect_failures = [var.internal_load_balancing_mode]
}
