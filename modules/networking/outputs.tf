output "vnet_id" {
  description = "Resource ID of the virtual network ."
  value       = azurerm_virtual_network.citadel.id
}

output "apim_subnet_id" {
  description = "Resource ID of the APIM subnet."
  value       = azurerm_subnet.apim.id
  # Classic VNet injection needs the NSG and route table on the subnet before APIM is created.
  depends_on = [azurerm_subnet_network_security_group_association.apim, azurerm_subnet_route_table_association.apim]
}

output "pe_subnet_id" {
  description = "Resource ID of the private-endpoint subnet."
  value       = azurerm_subnet.pe.id
}

output "logic_app_subnet_id" {
  description = "Resource ID of the Logic App integration subnet."
  value       = azurerm_subnet.logic_app.id
}

output "agent_subnet_id" {
  description = "Resource ID of the Foundry agent subnet (empty when disabled)."
  value       = var.enable_agent_subnet ? azurerm_subnet.agent[0].id : ""
}
output "agent_subnet_name" {
  description = "Name of the Foundry agent subnet (empty when disabled)."
  value       = var.enable_agent_subnet ? var.agent_subnet_name : ""
}

output "ase_subnet_id" {
  description = "Resource ID of the ASE v3 subnet (empty when disabled)."
  value       = var.enable_ase_subnet ? azurerm_subnet.ase[0].id : ""
}
output "subnet_nsg_names" {
  description = "Names of the NSGs attached to the private-endpoint and Logic App subnets (null when nsg_on_all_subnets = false)."
  value = {
    pe        = one(azurerm_network_security_group.pe[*].name)
    logic_app = one(azurerm_network_security_group.logic_app[*].name)
  }
}
