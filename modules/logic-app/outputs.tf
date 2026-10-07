output "logic_app_name" { value = local.logic_app_name }
output "logic_app_id"   { value = local.logic_app_id }
output "storage_account_name" { value = azurerm_storage_account.logic_app.name }
output "app_service_environment_id" { value = one(azurerm_app_service_environment_v3.ase[*].id) }
