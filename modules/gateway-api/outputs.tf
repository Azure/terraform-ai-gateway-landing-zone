output "id" {
  description = "Resource ID of the API."
  value       = local.api_id
}

output "name" {
  description = "Name of the API."
  value       = local.api_name
}

output "path" {
  description = "Gateway path of the API (HTTP APIs; null for azapi-managed APIs)."
  value       = local.is_http ? azurerm_api_management_api.this[0].path : null
}

output "product_id" {
  description = "Product ID created with the API (null when no product)."
  value       = one(azurerm_api_management_product.this[*].product_id)
}
