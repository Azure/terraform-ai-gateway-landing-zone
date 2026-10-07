output "api_id" {
  description = "Resource ID of the Azure OpenAI API."
  value       = azurerm_api_management_api.this.id
}

output "api_name" {
  description = "Name of the Azure OpenAI API."
  value       = azurerm_api_management_api.this.name
}

output "api_path" {
  description = "Gateway path of the Azure OpenAI API."
  value       = azurerm_api_management_api.this.path
}
