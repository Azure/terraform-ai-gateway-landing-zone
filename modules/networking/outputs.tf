output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = local.alz_spoke ? var.existing_vnet_id : one(module.vnet[*].resource_id)
}

output "apim_subnet_id" {
  description = "Resource ID of the APIM subnet (empty when apim_vnet_mode = none)."
  value       = lookup(local.subnet_ids, "apim", "")
}

output "pe_subnet_id" {
  description = "Resource ID of the private-endpoint subnet."
  value       = local.subnet_ids["pe"]
}

output "logic_app_subnet_id" {
  description = "Resource ID of the Logic App integration subnet."
  value       = local.subnet_ids["logic_app"]
}

output "agent_subnet_id" {
  description = "Resource ID of the Foundry agent subnet (empty when disabled)."
  value       = var.enable_agent_subnet ? local.subnet_ids["agent"] : ""
}

output "agent_subnet_name" {
  description = "Name of the Foundry agent subnet (empty when disabled)."
  value       = var.enable_agent_subnet ? var.agent_subnet_name : ""
}

output "ase_subnet_id" {
  description = "Resource ID of the ASE v3 subnet (empty when disabled)."
  value       = var.enable_ase_subnet ? local.subnet_ids["ase"] : ""
}

output "subnet_nsg_names" {
  description = "Subnet key => name of its network security group (every subnet has one)."
  value       = { for k, m in module.nsg : k => m.name }
}

locals {
  subnet_ids = merge(
    { for k, m in module.spoke_subnet : k => m.resource_id },
    merge([for v in module.vnet : { for k, sn in v.subnets : k => sn.resource_id }]...),
  )
}

output "spoke_routes" {
  description = "alz_spoke: subnet key => next hop of its 0.0.0.0/0 route (empty for greenfield)."
  value       = { for k, rt in azurerm_route_table.spoke : k => one([for r in rt.route : r.next_hop_in_ip_address if r.address_prefix == "0.0.0.0/0"]) }
}
