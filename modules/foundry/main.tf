# =============================================================================
# MODULE: Foundry
# Terraform port of ai-hub-gateway-solution-accelerator-citadel-v1/bicep/infra/
#   modules/foundry/foundry.bicep
# Samples referenced:
#   https://github.com/microsoft-foundry/foundry-samples/tree/main/
#     infrastructure/infrastructure-setup-terraform
# =============================================================================



locals {
  instances = var.foundry_instances

  # Built-in role: Azure AI Project Manager
  ai_project_manager_role_id = "eadc314b-1a2d-4efa-be10-5d325db5065e"

  # Names come from modules/naming (explicit name, else aif-<env>-<index>-<suffix>).
  instance_names = var.account_names

  instance_subdomains = [
    for i, c in local.instances :
    lower(
      c.custom_subdomain != "" ? c.custom_subdomain : local.instance_names[i]
    )
  ]

  instance_project_names = [
    for c in local.instances :
    c.default_project_name != "" ? c.default_project_name : var.foundry_project_default_name
  ]

  # Preserve order matching Bicep: cognitiveservices, openai, ai.azure.com
  dns_zone_ids_ordered = compact([
    lookup(var.dns_zone_ids, "cognitive_services", ""),
    lookup(var.dns_zone_ids, "openai", ""),
    lookup(var.dns_zone_ids, "ai_services", ""),
  ])
}

# -----------------------------------------------------------------------------
# AI Foundry (AIServices) accounts
# Bicep: foundryResources (Microsoft.CognitiveServices/accounts@2026-05-01)
# -----------------------------------------------------------------------------
module "account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"
  count   = length(local.instances)

  name             = local.instance_names[count.index]
  location         = local.instances[count.index].location
  parent_id        = var.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  kind                     = "AIServices"
  sku_name                 = "S0"
  allow_project_management = true # required to enable AI Foundry (projects) on the account
  # The project is created below (azapi_resource.project); keep the account's
  # project list and default as Azure sets them, so an update doesn't clear them.
  associated_projects   = [local.instance_project_names[count.index]]
  default_project       = local.instance_project_names[count.index]
  custom_subdomain_name = local.instance_subdomains[count.index]
  local_auth_enabled    = !var.disable_key_auth
  managed_identities    = { system_assigned = true }

  public_network_access_enabled = var.foundry_external_access
  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = []
  }

  # Optional egress lock-down: when set, the account (and the Agent Service)
  # may only reach these FQDNs.
  outbound_network_access_restricted = var.outbound_allowed_fqdns != null
  fqdns                              = var.outbound_allowed_fqdns

  # Model deployments of this account (Bicep: deployments.bicep), created one
  # at a time: the account rejects concurrent deployment PUTs (409).
  deployment_serialization_enabled = true
  cognitive_deployments = {
    for m in var.foundry_models : m.name => {
      name            = m.name
      rai_policy_name = "Microsoft.DefaultV2"
      model = {
        format  = m.publisher
        name    = m.name
        version = m.version
      }
      scale = {
        type     = m.sku
        capacity = m.capacity
      }
      retry = {
        error_message_regex = ["RequestConflict", "Another operation is being performed on the parent resource"]
        interval_seconds    = 15
      }
    } if m.ai_service_index == count.index
  }

  # Per-instance opt-in: config.network_injection_enabled (default true) AND
  # the module-level flag AND an available agent subnet.
  network_injections = (
    var.foundry_network_injection_enabled &&
    try(local.instances[count.index].network_injection_enabled, true) &&
    var.agent_subnet_id != ""
    ) ? {
    scenario                          = "agent"
    subnet_id                         = var.agent_subnet_id
    microsoft_managed_network_enabled = false
  } : null
}

# The principal ID and endpoint never change once an account exists, but an
# in-place update of the account makes the module outputs unknown at plan time,
# which would replace every role assignment on that principal. Read them from
# the live account when it exists; new accounts use the module outputs.
data "azapi_resource" "account_state" {
  count = length(local.instances)

  type                   = "Microsoft.CognitiveServices/accounts@2025-06-01"
  resource_id            = "${var.resource_group_id}/providers/Microsoft.CognitiveServices/accounts/${local.instance_names[count.index]}"
  ignore_not_found       = true
  response_export_values = ["identity.principalId", "properties.endpoint"]
}

locals {
  account_ids   = module.account[*].resource_id
  account_names = module.account[*].name
  account_endpoints = [
    for i, m in module.account : try(data.azapi_resource.account_state[i].output.properties.endpoint, null) != null ? data.azapi_resource.account_state[i].output.properties.endpoint : m.endpoint
  ]
  account_principal_ids = [
    for i, m in module.account : try(data.azapi_resource.account_state[i].output.identity.principalId, null) != null ? data.azapi_resource.account_state[i].output.identity.principalId : m.system_assigned_mi_principal_id
  ]
}

# -----------------------------------------------------------------------------
# AI Foundry Project (one per account)
# Bicep: aiProject (Microsoft.CognitiveServices/accounts/projects@2026-05-01)
# -----------------------------------------------------------------------------
resource "azapi_resource" "project" {
  count     = length(local.instances)
  type      = "Microsoft.CognitiveServices/accounts/projects@2026-05-01"
  name      = local.instance_project_names[count.index]
  location  = local.instances[count.index].location
  parent_id = local.account_ids[count.index]
  tags      = var.tags

  # API version 2026-05-01 is newer than the latest schema validation in azapi.
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = "Citadel Governance Hub default project for AI Evaluation default LLMs"
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC: deployer → Azure AI Project Manager on each Foundry
# Bicep: aiProjectManagerRoleAssignment
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "deployer_project_manager" {
  count              = length(local.instances)
  scope              = local.account_ids[count.index]
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/${local.ai_project_manager_role_id}"
  principal_id       = var.deployer_object_id
}

# -----------------------------------------------------------------------------
# RBAC: APIM MI → Cognitive Services User on each Foundry
# Bicep: roleAssignmentCognitiveServicesUser
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "apim_cognitive_services_user" {
  count                = length(local.instances)
  scope                = local.account_ids[count.index]
  role_definition_name = "Cognitive Services User"
  principal_id         = var.apim_principal_id
  principal_type       = "ServicePrincipal"
}

# -----------------------------------------------------------------------------
# Diagnostic settings → Log Analytics (AllMetrics)
# Bicep: diagnosticSettings
# -----------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "foundry" {
  count                      = var.enable_diagnostics ? length(local.instances) : 0
  name                       = "${local.instance_names[count.index]}-diagnostics"
  target_resource_id         = local.account_ids[count.index]
  log_analytics_workspace_id = var.log_analytics_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Application Insights connection on each Foundry
# Bicep: appInsightsConnection
# -----------------------------------------------------------------------------
resource "azapi_resource" "app_insights_connection" {
  count = var.enable_app_insights_connection ? length(local.instances) : 0

  type      = "Microsoft.CognitiveServices/accounts/connections@2026-05-01"
  name      = "${local.instance_names[count.index]}-appInsights-connection"
  parent_id = local.account_ids[count.index]

  # API version 2026-05-01 is newer than the latest schema validation in azapi.
  schema_validation_enabled = false

  body = {
    properties = {
      authType                    = "ApiKey"
      category                    = "AppInsights"
      target                      = var.app_insights_id
      useWorkspaceManagedIdentity = false
      isSharedToAll               = false
      sharedUserList              = []
      peRequirement               = "NotRequired"
      peStatus                    = "NotApplicable"
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.app_insights_id
      }
      credentials = {
        key = var.app_insights_instrumentation_key
      }
    }
  }
}


# -----------------------------------------------------------------------------
# Private endpoints with all required Foundry DNS zones
# Bicep: privateEndpoints (private-endpoint-multi-dns.bicep)
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "foundry" {
  count               = length(local.instances)
  name                = "pe-${local.instance_names[count.index]}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.instance_names[count.index]}"
    private_connection_resource_id = local.account_ids[count.index]
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(local.dns_zone_ids_ordered) > 0 ? [1] : []
    content {
      name                 = "aif-dns-group"
      private_dns_zone_ids = local.dns_zone_ids_ordered
    }
  }

  depends_on = [module.account]
}
