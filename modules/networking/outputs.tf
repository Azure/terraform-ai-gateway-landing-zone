output "vnet_id" {
  description = "Resource ID of the virtual network (created or existing)."
  value       = var.use_existing_vnet ? data.azurerm_virtual_network.existing[0].id : azurerm_virtual_network.citadel[0].id
}

output "apim_subnet_id" {
  description = "Resource ID of the APIM subnet."
  value       = var.use_existing_vnet ? data.azurerm_subnet.existing_apim[0].id : azurerm_subnet.apim[0].id
}

output "pe_subnet_id" {
  description = "Resource ID of the private-endpoint subnet."
  value       = var.use_existing_vnet ? data.azurerm_subnet.existing_pe[0].id : azurerm_subnet.pe[0].id
}

output "logic_app_subnet_id" {
  description = "Resource ID of the Logic App integration subnet."
  value       = var.use_existing_vnet ? data.azurerm_subnet.existing_logic_app[0].id : azurerm_subnet.logic_app[0].id
}

output "dns_zone_ids" {
  description = <<-EOT
    Map of DNS zone keys (snake_case) to their resource IDs. Child modules consume
    this via `module.networking.dns_zone_ids["<key>"]`.

    Resolution order:
      1. BYO zones from `var.existing_private_dns_zones` (accepts both Bicep
         camelCase — e.g. `keyVault`, `cosmosDb`, `storageBlob` — and TF
         snake_case keys).
      2. Newly-created zones (when `var.create_dns_zones = true`).

    BYO entries override created zones for the same logical key, which allows
    partial BYO (some zones created, some referenced from another subscription).
  EOT
  value = merge(
    var.create_dns_zones ? {
      for k, v in azurerm_private_dns_zone.zones : k => v.id
    } : {},
    # Normalize Bicep camelCase → TF snake_case keys. Unknown keys pass through.
    {
      for k, v in var.existing_private_dns_zones : lookup(local.byo_key_map, k, k) => v
      if v != ""
    },
  )
}

output "agent_subnet_id" {
  description = "Resource ID of the Foundry agent subnet (empty when disabled)."
  value = var.enable_agent_subnet ? (
    var.use_existing_vnet
    ? try(data.azurerm_subnet.existing_agent[0].id, "")
    : try(azurerm_subnet.agent[0].id, "")
  ) : ""
}
output "agent_subnet_name" {
  description = "Name of the Foundry agent subnet (empty when disabled)."
  value       = var.enable_agent_subnet ? var.agent_subnet_name : ""
}

output "ase_subnet_id" {
  description = "Resource ID of the ASE v3 subnet (empty when disabled)."
  value = var.enable_ase_subnet ? (
    var.use_existing_vnet
    ? data.azurerm_subnet.existing_ase[0].id
    : azurerm_subnet.ase[0].id
  ) : ""
}
output "subnet_nsg_names" {
  description = "Names of the NSGs attached to the private-endpoint and Logic App subnets (null when nsg_on_all_subnets = false)."
  value = {
    pe        = one(azurerm_network_security_group.pe[*].name)
    logic_app = one(azurerm_network_security_group.logic_app[*].name)
  }
}
