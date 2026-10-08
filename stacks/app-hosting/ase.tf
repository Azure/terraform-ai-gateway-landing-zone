# ASE v3 (ILB, internal encryption, TLS 1.0 / FTP / remote debug off) and its
# private DNS zone. platform finds the ASE by its deterministic name. Creating
# an ASE takes 2-4 hours: run this stack on its own (long CI timeout).
module "app_hosting" {
  source = "../../modules/app-hosting"

  name                         = local.names.app_service_environment
  location                     = var.location
  resource_group_id            = "/subscriptions/${var.subscription_id}/resourceGroups/${local.names.resource_group}"
  subnet_id                    = local.ase_subnet_id
  internal_load_balancing_mode = var.ase.internal_load_balancing_mode
  zone_redundant               = var.ase.zone_redundant
  create_private_dns_zone      = var.dns.create
  dns_vnet_link_ids            = local.dns_vnet_link_ids
  tags                         = local.tags
  enable_telemetry             = var.enable_telemetry
}

check "ase_subnet_known" {
  assert {
    condition     = local.ase_subnet_id != "-"
    error_message = "No ASE subnet: set ase.subnet_id (alz_spoke / byo), or apply stacks/network with subnets_enabled.ase = true (greenfield)."
  }
}
