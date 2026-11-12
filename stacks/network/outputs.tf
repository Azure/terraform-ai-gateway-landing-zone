output "vnet_id" {
  description = "Resource ID of the gateway VNet (greenfield) or the vended VNet (alz_spoke)."
  value       = module.networking.vnet_id
}

output "subnet_ids" {
  description = "Subnet key (apim, pe, logic_app, agent, ase, cicd) => resource ID."
  value       = module.networking.subnet_ids
}

output "private_dns_zone_ids" {
  description = "Greenfield: logical zone key => private DNS zone ID ({} in alz_spoke: the hub owns the zones)."
  value       = try(module.private_dns[0].zone_ids, {})
}

output "platform_network" {
  description = "alz_spoke: paste into platform.tfvars as `network` (add the hub's private_dns_zone_ids when Terraform binds them). Greenfield doesn't need it: platform looks everything up."
  value = {
    vnet_id = module.networking.vnet_id
    subnet_ids = {
      apim      = try(module.networking.subnet_ids["apim"], null)
      pe        = module.networking.pe_subnet_id
      logic_app = try(module.networking.subnet_ids["logic_app"], null)
      agent     = try(module.networking.subnet_ids["agent"], null)
    }
    private_dns_zone_ids              = try(module.private_dns[0].zone_ids, {})
    dns_zone_groups_managed_by_policy = !local.greenfield
  }
}

output "ase_subnet_id" {
  description = "app-hosting ase.subnet_id for alz_spoke (greenfield looks it up). null when no ASE subnet is created."
  value       = try(module.networking.subnet_ids["ase"], null)
}
