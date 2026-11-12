output "app_service_environment_id" {
  description = "Resource ID of the ASE v3 (platform finds it by name; a shared ASE is passed as usage_pipeline.ase.app_service_environment_id)."
  value       = module.app_hosting.id
}

output "app_service_environment_name" {
  description = "Name of the ASE v3."
  value       = module.app_hosting.name
}

output "dns_suffix" {
  description = "Default domain of the ASE (<name>.appserviceenvironment.net)."
  value       = module.app_hosting.dns_suffix
}

output "internal_inbound_ip_addresses" {
  description = "Internal inbound IPs of the ILB ASE (the private DNS records point here)."
  value       = module.app_hosting.internal_inbound_ip_addresses
}
