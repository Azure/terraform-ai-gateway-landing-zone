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

output "private_endpoint_name" {
  description = "Name of the Logic App private endpoint (null when none is created)."
  value       = one(concat(azurerm_private_endpoint.logic_app[*].name, azurerm_private_endpoint.logic_app_policy_dns[*].name))
}

output "hosting" {
  description = "Hosting summary: model, whether the runtime storage is keyless, how workflows are deployed, the app setting names of the keyless (ASE) site, whether the site accepts public traffic and whether it has a private endpoint."
  value = {
    model             = var.hosting_model
    keyless_storage   = local.use_ase
    deployment_method = local.use_ase ? var.deployment_method : "zip_deploy"
    package_url       = local.package_url
    app_setting_names = local.use_ase ? sort(keys(local.ase_app_settings)) : []
    public_access     = local.use_ase ? false : var.public_network_access_enabled
    private_endpoint  = local.private_endpoint_enabled
  }
}
