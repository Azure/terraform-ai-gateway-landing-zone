output "logic_app_name" {
  description = "Name of the usage-ingestion Logic App."
  value       = local.logic_app_name
}
output "logic_app_id" {
  description = "Resource ID of the usage-ingestion Logic App."
  value       = local.logic_app_id
}
output "storage_account_name" {
  description = "Name of the Logic App runtime storage account."
  value       = module.storage.name
}
output "app_service_environment_id" {
  description = "Resource ID of the App Service Environment v3 (null when not ASE-hosted)."
  value       = one(azurerm_app_service_environment_v3.ase[*].id)
}
