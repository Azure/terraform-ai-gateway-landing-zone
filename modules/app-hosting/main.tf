# =============================================================================
# MODULE: App hosting — App Service Environment v3 (review 7.5.3a)
# Dedicated, internal (ILB) ASE v3 for the keyless usage-ingestion Logic App,
# plus the private DNS zone <ase>.appserviceenvironment.net that resolves the
# apps and their SCM endpoints to the ASE's internal inbound IP.
# Creating an ASE takes 1–4 hours; it changes rarely (Phase 3 moves this module
# to its own stack, stacks/app-hosting).
# =============================================================================

locals {
  internal = var.internal_load_balancing_mode != "None"
  # Known at plan time (the module's dns_suffix output is not).
  dns_zone_name = "${var.name}.appserviceenvironment.net"

  # Fixed hardening (review 7.5.3a): encrypted internal traffic, no TLS 1.0,
  # no FTP, no remote debugging.
  hardening = {
    internal_encryption_enabled = true
    tls_1_enabled               = false
    ftp_enabled                 = false
    remote_debug_enabled        = false
  }
}

module "ase" {
  source  = "Azure/avm-res-web-hostingenvironment/azurerm"
  version = "2.0.1"

  name             = var.name
  location         = var.location
  parent_id        = var.resource_group_id
  subnet_id        = var.subnet_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  internal_load_balancing_mode = var.internal_load_balancing_mode
  zone_redundancy_enabled      = var.zone_redundant
  internal_encryption_enabled  = local.hardening.internal_encryption_enabled
  tls_1_enabled                = local.hardening.tls_1_enabled
  ftp_enabled                  = local.hardening.ftp_enabled
  remote_debug_enabled         = local.hardening.remote_debug_enabled
}

module "dns" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"
  count   = local.internal && var.create_private_dns_zone ? 1 : 0

  domain_name      = local.dns_zone_name
  parent_id        = var.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  a_records = {
    for name in ["*", "*.scm", "@"] : name => {
      name    = name
      ttl     = 300
      records = module.ase.internal_inbound_ip_addresses
    }
  }

  virtual_network_links = {
    for k, id in var.dns_vnet_link_ids : k => {
      name                 = "link-${k}"
      virtual_network_id   = id
      registration_enabled = false
    }
  }
}
