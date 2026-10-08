output "ids" {
  description = "Fragment ID => policy fragment resource ID (both azurerm- and azapi-managed fragments)."
  value = merge(
    { for k, f in azurerm_api_management_policy_fragment.this : k => f.id },
    { for k, f in azapi_resource.this : k => f.id },
  )
}

output "names" {
  description = "IDs (names) of all fragments deployed by this module."
  value       = concat(keys(azurerm_api_management_policy_fragment.this), keys(azapi_resource.this))
}
