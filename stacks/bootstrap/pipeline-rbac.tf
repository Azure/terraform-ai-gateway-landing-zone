# Pipeline RBAC (review 7.13). Everything is scoped to the two resource groups
# of this environment, plus explicit extras (vended VNet, platform workspace).
locals {
  # Owner, User Access Administrator, Role Based Access Control Administrator.
  privileged_role_ids = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168"

  # The apply identity may create role assignments in the workload group (the
  # stacks grant managed identities data-plane roles), but never privileged
  # roles, so it can't escalate its own rights.
  rbac_admin_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
     )
    )
  EOT

  apply_assignments = merge(
    {
      workload-contributor = { scope = local.workload_resource_group_id, role = "Contributor", condition = null }
      workload-rbac-admin  = { scope = local.workload_resource_group_id, role = "Role Based Access Control Administrator", condition = local.rbac_admin_condition }
    },
    var.policy_assignments ? {
      workload-policy = { scope = local.workload_resource_group_id, role = "Resource Policy Contributor", condition = null }
    } : {},
    { for k, a in var.additional_apply_role_assignments : "extra-${k}" => { scope = a.scope, role = a.role_definition_id_or_name, condition = null } },
  )
}

resource "azurerm_role_assignment" "apply" {
  for_each = local.apply_assignments

  scope                = each.value.scope
  role_definition_name = startswith(each.value.role, "/") ? null : each.value.role
  role_definition_id   = startswith(each.value.role, "/") ? each.value.role : null
  principal_id         = local.apply_principal_id
  principal_type       = "ServicePrincipal"
  condition            = each.value.condition
  condition_version    = each.value.condition == null ? null : "2.0"
  description          = "Terraform apply identity (${var.workload}-${var.environment})"
}

# Read-only plan identity: Reader cannot call the list* actions that some
# resources read during refresh (keys, secrets, app settings), so it gets a
# custom role that adds exactly those, plus blob read for the workflow package.
resource "azurerm_role_definition" "plan_reader" {
  count = local.separate_plan_identity ? 1 : 0

  # Custom role names are unique per tenant: the seed keeps environments apart.
  name        = "Terraform Plan Reader (${module.naming.base}-${module.naming.seed})"
  scope       = local.workload_resource_group_id
  description = "Read-only access for Terraform plans and drift checks of ${var.workload}-${var.environment}."

  permissions {
    actions = [
      "*/read",
      "Microsoft.ApiManagement/service/*/listSecrets/action",
      "Microsoft.ApiManagement/service/*/listValue/action",
      "Microsoft.Cache/redisEnterprise/databases/listKeys/action",
      "Microsoft.CognitiveServices/accounts/listKeys/action",
      # azurerm_cosmosdb_account always lists keys on refresh, even with local auth off.
      "Microsoft.DocumentDB/databaseAccounts/listKeys/action",
      "Microsoft.DocumentDB/databaseAccounts/readonlykeys/action",
      "Microsoft.DocumentDB/databaseAccounts/listConnectionStrings/action",
      "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
      "Microsoft.Storage/storageAccounts/listKeys/action",
      "Microsoft.Web/sites/config/list/action",
    ]
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
    ]
  }

  assignable_scopes = [local.workload_resource_group_id]
}

resource "azurerm_role_assignment" "plan" {
  count = local.separate_plan_identity ? 1 : 0

  scope              = local.workload_resource_group_id
  role_definition_id = azurerm_role_definition.plan_reader[0].role_definition_resource_id
  principal_id       = local.plan_principal_id
  principal_type     = "ServicePrincipal"
  description        = "Terraform plan identity (${var.workload}-${var.environment})"
}

# --- Microsoft Graph application permissions ----------------------------------
# Application.Read.All lets gateway-config find the gateway app by name;
# Application.ReadWrite.OwnedBy lets the apply identity manage the app it creates.

data "azuread_application_published_app_ids" "well_known" {
  count = var.graph_permissions ? 1 : 0
}

data "azuread_service_principal" "msgraph" {
  count     = var.graph_permissions ? 1 : 0
  client_id = data.azuread_application_published_app_ids.well_known[0].result["MicrosoftGraph"]
}

locals {
  graph_grants = var.graph_permissions ? merge(
    { "apply-Application.ReadWrite.OwnedBy" = { principal = local.apply_principal_id, role = "Application.ReadWrite.OwnedBy" } },
    { "apply-Application.Read.All" = { principal = local.apply_principal_id, role = "Application.Read.All" } },
    local.separate_plan_identity ? { "plan-Application.Read.All" = { principal = local.plan_principal_id, role = "Application.Read.All" } } : {},
  ) : {}
}

resource "azuread_app_role_assignment" "graph" {
  for_each = local.graph_grants

  app_role_id         = data.azuread_service_principal.msgraph[0].app_role_ids[each.value.role]
  principal_object_id = each.value.principal
  resource_object_id  = data.azuread_service_principal.msgraph[0].object_id
}
