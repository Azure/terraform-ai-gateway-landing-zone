# =============================================================================
# Adopt existing v1 resources into Azure Verified Modules (Phase 2)
# =============================================================================
# Some AVM modules manage their resource with azapi, where v1 used azurerm. A
# moved {} block can't cross resource types, so the v1 resource is dropped from
# state with removed { destroy = false } (in the owning module) and imported
# here.
#
# Upgrading an environment deployed before Phase 2: set
# adopt_existing_resources = true for the upgrade run. Each import then runs
# only when the Azure resource exists (probed at plan time); once it is in
# state the import is a no-op. Greenfield deployments leave it false: their
# names contain a random suffix that isn't known until the first apply, so a
# probe can't be planned.
# =============================================================================

locals {
  adopt_rg_id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}"

  adopt_targets = {
    usage_storage = {
      type = "Microsoft.Storage/storageAccounts@2025-01-01"
      id   = "${local.adopt_rg_id}/providers/Microsoft.Storage/storageAccounts/${local.names.storage_logic}"
    }
    usage_service_plan = {
      type = "Microsoft.Web/serverfarms@2024-11-01"
      id   = "${local.adopt_rg_id}/providers/Microsoft.Web/serverfarms/${local.names.app_service_plan}"
    }
  }
  # Content share name exactly as modules/logic-app computes it.
  adopt_content_share = local.usage_cfg.logic_app.content_share_name != "" ? local.usage_cfg.logic_app.content_share_name : local.names.logic_content_share
}

data "azapi_resource" "adopt" {
  for_each = var.adopt_existing_resources ? local.adopt_targets : {}

  type             = each.value.type
  resource_id      = each.value.id
  ignore_not_found = true
}

data "azapi_resource" "adopt_content_share" {
  count = var.adopt_existing_resources && local.usage_cfg.logic_app.hosting == "workflow_standard" ? 1 : 0

  type             = "Microsoft.Storage/storageAccounts/fileServices/shares@2025-01-01"
  resource_id      = "${local.adopt_targets.usage_storage.id}/fileServices/default/shares/${local.adopt_content_share}"
  ignore_not_found = true
}

import {
  for_each = try(data.azapi_resource.adopt["usage_storage"].exists, false) ? toset(["x"]) : toset([])
  to       = module.logic_app.module.storage.azapi_resource.this
  id       = local.adopt_targets.usage_storage.id
}

import {
  for_each = try(data.azapi_resource.adopt_content_share[0].exists, false) ? toset(["x"]) : toset([])
  to       = module.logic_app.module.storage.module.shares["content"].azapi_resource.this
  id       = "${local.adopt_targets.usage_storage.id}/fileServices/default/shares/${local.adopt_content_share}"
}

import {
  for_each = try(data.azapi_resource.adopt["usage_service_plan"].exists, false) ? toset(["x"]) : toset([])
  to       = module.logic_app.module.service_plan.azapi_resource.this
  id       = local.adopt_targets.usage_service_plan.id
}
