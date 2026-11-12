output "id" {
  description = "Resource ID of the App Service Environment v3 (available once its private DNS records exist, so apps and their SCM endpoints resolve)."
  value       = module.ase.resource_id
  depends_on  = [module.dns]
}

output "name" {
  description = "Name of the App Service Environment v3."
  value       = module.ase.name
}

output "dns_suffix" {
  description = "DNS suffix of the apps hosted on the ASE (<ase>.appserviceenvironment.net)."
  value       = local.dns_zone_name
}

output "internal_inbound_ip_addresses" {
  description = "Internal inbound IP addresses (ILB) of the ASE."
  value       = module.ase.internal_inbound_ip_addresses
}
