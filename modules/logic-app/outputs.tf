output "logic_app_name" { value = azurerm_logic_app_standard.usage_ingestion.name }
output "logic_app_id"   { value = azurerm_logic_app_standard.usage_ingestion.id }
output "storage_account_name" { value = azurerm_storage_account.logic_app.name }
