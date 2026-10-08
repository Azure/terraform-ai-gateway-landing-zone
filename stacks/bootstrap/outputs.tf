output "apply_client_id" {
  description = "Client ID of the apply identity: set it as AZURE_CLIENT_ID on the GitHub environment <environment>."
  value       = try(module.pipeline_identity["apply"].client_id, null)
}

output "plan_client_id" {
  description = "Client ID of the plan identity: set it as AZURE_CLIENT_ID on the GitHub environment <environment>-plan (pair mode)."
  value       = try(module.pipeline_identity["plan"].client_id, try(module.pipeline_identity["apply"].client_id, null))
}

output "apply_principal_id" {
  description = "Object ID of the apply identity (platform.tfvars secret_writer_principal_ids)."
  value       = local.apply_principal_id
}

output "plan_principal_id" {
  description = "Object ID of the plan identity (platform.tfvars secret_reader_principal_ids)."
  value       = local.plan_principal_id
}

output "state_resource_group_name" {
  description = "Resource group of the Terraform state account."
  value       = module.state_resource_group.name
}

output "state_storage_account_name" {
  description = "Terraform state account."
  value       = module.state_storage.name
}

output "workload_resource_group_name" {
  description = "Resource group every other stack deploys into."
  value       = local.names.resource_group
}

output "backend_hcl" {
  description = "Content for environments/<env>/backend.hcl."
  value       = <<-EOT
    resource_group_name  = "${module.state_resource_group.name}"
    storage_account_name = "${module.state_storage.name}"
    subscription_id      = "${var.subscription_id}"
    tenant_id            = "${data.azurerm_client_config.current.tenant_id}"
  EOT
}
