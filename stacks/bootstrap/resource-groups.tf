# Two resource groups per environment: Terraform state (+ pipeline identities)
# and the workload. Every other stack deploys into the workload group, so the
# apply identity's rights stop at that group.
data "azurerm_client_config" "current" {}

module "state_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.names.state_resource_group
  location         = var.location
  tags             = local.tags
  enable_telemetry = var.enable_telemetry
}

module "workload_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"
  count   = var.create_workload_resource_group ? 1 : 0

  name             = local.names.resource_group
  location         = var.location
  tags             = local.tags
  enable_telemetry = var.enable_telemetry
}

data "azurerm_resource_group" "workload" {
  count = var.create_workload_resource_group ? 0 : 1
  name  = local.names.resource_group
}

locals {
  workload_resource_group_id = var.create_workload_resource_group ? module.workload_resource_group[0].resource_id : data.azurerm_resource_group.workload[0].id
}
