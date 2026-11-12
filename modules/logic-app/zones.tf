# =============================================================================
# Availability zones of the Logic App plan and its storage account.
#   plan     zone_balancing_enabled = var.zone_redundant. Azure sets a plan's zone
#            redundancy at creation only, so a change on an existing plan stops at plan time.
#   storage  ZRS for a new account when zone redundant. An existing account keeps its SKU:
#            ARM rejects a SKU change from LRS to ZRS (InvalidValuesForRequestParameters);
#            the conversion is `az storage account migration start` (days, can't be stopped),
#            after which this module reads the new SKU and keeps it.
# =============================================================================

data "azapi_resource" "storage_state" {
  type                   = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id            = "${local.resource_group_id}/providers/Microsoft.Storage/storageAccounts/${var.names.storage_account}"
  ignore_not_found       = true
  response_export_values = { sku = "sku.name" }
}

data "azapi_resource" "plan_state" {
  type                   = "Microsoft.Web/serverfarms@2024-04-01"
  resource_id            = "${local.resource_group_id}/providers/Microsoft.Web/serverfarms/${var.names.app_service_plan}"
  ignore_not_found       = true
  response_export_values = { zone_redundant = "properties.zoneRedundant" }
}

locals {
  existing_storage_sku = data.azapi_resource.storage_state.exists ? try(data.azapi_resource.storage_state.output.sku, null) : null
  storage_sku          = coalesce(local.existing_storage_sku, var.zone_redundant ? "Standard_ZRS" : "Standard_LRS")

  plan_exists                  = data.azapi_resource.plan_state.exists
  existing_plan_zone_redundant = local.plan_exists && try(data.azapi_resource.plan_state.output.zone_redundant == true, false)
}

resource "terraform_data" "zone_rules" {
  input = var.zone_redundant

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || var.worker_count >= 2
      error_message = "A zone-redundant Logic App plan needs at least 2 instances (worker_count >= 2) to span availability zones."
    }
    precondition {
      condition     = !local.plan_exists || local.existing_plan_zone_redundant == var.zone_redundant
      error_message = "zone_redundant = ${var.zone_redundant} but the existing plan ${var.names.app_service_plan} was created ${local.existing_plan_zone_redundant ? "zone redundant" : "without zone redundancy"}, and Azure can't change that. Recreate the plan and the Logic App on it (usage ingestion pauses in between): 1) task apply STACK=platform ENV=<env> PLAN_ARGS=\"-destroy -target=module.logic_app.module.service_plan.azapi_resource.this\" (destroys the plan, the Logic App and its role assignments), 2) task apply STACK=platform ENV=<env>."
    }
  }
}

check "storage_zone_redundancy" {
  assert {
    condition     = !var.zone_redundant || can(regex("ZRS$", local.storage_sku))
    error_message = "The Logic App plan is zone redundant but its storage account ${var.names.storage_account} is ${local.storage_sku}: workflow state isn't zone redundant. Convert it (takes days, can't be stopped): az storage account migration start --account-name ${var.names.storage_account} -g ${var.resource_group_name} --sku Standard_ZRS --yes"
  }
}
