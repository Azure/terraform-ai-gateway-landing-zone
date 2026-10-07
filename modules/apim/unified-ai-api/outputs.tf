output "api_id" {
  description = "Resource ID of the Unified AI API."
  value       = azurerm_api_management_api.this.id
}

output "api_name" {
  description = "Name of the Unified AI API."
  value       = azurerm_api_management_api.this.name
}

output "api_path" {
  description = "Gateway path of the Unified AI API."
  value       = azurerm_api_management_api.this.path
}

output "product_id" {
  description = "Resource ID of the Unified AI API product."
  value       = azurerm_api_management_product.this.product_id
}

output "product_name" {
  description = "Product ID (name) of the Unified AI API product."
  value       = azurerm_api_management_product.this.product_id
}
