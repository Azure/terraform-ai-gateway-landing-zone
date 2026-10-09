output "diagnostic_setting_names" {
  description = "Workload diagnostic setting names (empty when policy owns diagnostics)."
  value       = [for setting in azapi_resource_action.logic_app_diagnostics : "diag-logic-${var.environment_name}"]
}

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

output "hosting" {
  description = "Hosting summary: model, whether the runtime storage is keyless, how workflows are deployed and the app setting names of the keyless (ASE) site."
  value = {
    model             = var.hosting_model
    keyless_storage   = local.use_ase
    deployment_method = local.use_ase ? var.deployment_method : "zip_deploy"
    package_url       = local.package_url
    app_setting_names = local.use_ase ? sort(keys(local.ase_app_settings)) : []
  }
}
