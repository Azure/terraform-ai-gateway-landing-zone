# =============================================================================
# MODULE: Foundry
# Terraform port of ai-hub-gateway-solution-accelerator-citadel-v1/bicep/infra/
#   modules/foundry/foundry.bicep
# Samples referenced:
#   https://github.com/microsoft-foundry/foundry-samples/tree/main/
#     infrastructure/infrastructure-setup-terraform
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}

locals {
  instances = var.foundry_instances

  # Built-in role: Azure AI Project Manager
  ai_project_manager_role_id = "eadc314b-1a2d-4efa-be10-5d325db5065e"

  instance_names = [
    for i, c in local.instances :
    c.name != "" ? c.name : "aif-${var.environment_name}-${i}-${var.random_suffix}"
  ]

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
# Bicep: foundryResources (Microsoft.CognitiveServices/accounts@2026-01-15-preview)
# -----------------------------------------------------------------------------
resource "azapi_resource" "foundry" {
  count     = length(local.instances)
  type      = "Microsoft.CognitiveServices/accounts@2026-01-15-preview"
  name      = local.instance_names[count.index]
  location  = local.instances[count.index].location
  parent_id = var.resource_group_id
  tags      = var.tags

  # 2026-01-15-preview (networkInjections) is newer than the azapi provider's
  # embedded schema; skip client-side schema validation.
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      # Required to enable AI Foundry (project management) on the account
      allowProjectManagement = true
      customSubDomainName = local.instance_subdomains[count.index]
      disableLocalAuth = var.disable_key_auth
      publicNetworkAccess = var.foundry_external_access ? "Enabled" : "Disabled"
      networkAcls = {
        defaultAction       = "Deny"
        bypass               = "AzureServices"
        ipRules             = []
        virtualNetworkRules = []
      }
      # Per-instance opt-in: config.network_injection_enabled (default true) AND
      # the module-level flag AND an available agent subnet.
      networkInjections = (
        var.foundry_network_injection_enabled &&
        try(local.instances[count.index].network_injection_enabled, true) &&
        var.agent_subnet_id != ""
      ) ? [
        {
          scenario                 = "agent"
          subnetArmId              = var.agent_subnet_id
          useMicrosoftManagedNetwork = false
        }
      ] : null

    }
  }

  response_export_values = ["identity.principalId", "properties.endpoint"]
}

# -----------------------------------------------------------------------------
# AI Foundry Project (one per account)
# Bicep: aiProject (Microsoft.CognitiveServices/accounts/projects@2025-06-01)
# -----------------------------------------------------------------------------
resource "azapi_resource" "project" {
  count     = length(local.instances)
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.instance_project_names[count.index]
  location  = local.instances[count.index].location
  parent_id = azapi_resource.foundry[count.index].id
  tags      = var.tags

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
  scope              = azapi_resource.foundry[count.index].id
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/${local.ai_project_manager_role_id}"
  principal_id       = var.deployer_object_id
}

# -----------------------------------------------------------------------------
# RBAC: APIM MI → Cognitive Services User on each Foundry
# Bicep: roleAssignmentCognitiveServicesUser
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "apim_cognitive_services_user" {
  count                = length(local.instances)
  scope                = azapi_resource.foundry[count.index].id
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
  target_resource_id         = azapi_resource.foundry[count.index].id
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

  type      = "Microsoft.CognitiveServices/accounts/connections@2025-06-01"
  name      = "${local.instance_names[count.index]}-appInsights-connection"
  parent_id = azapi_resource.foundry[count.index].id

  # The schema validator rejects names longer than 32 chars, but the RP accepts
  # the full connection name as generated by the Bicep reference implementation.
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
# Model deployments
# Bicep: modelDeployments (deployments.bicep)
# -----------------------------------------------------------------------------
resource "azapi_resource" "model_deployment" {
  count = length(var.foundry_models)

  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = var.foundry_models[count.index].name
  parent_id = azapi_resource.foundry[var.foundry_models[count.index].ai_service_index].id

  body = {
    sku = {
      name     = var.foundry_models[count.index].sku
      capacity = var.foundry_models[count.index].capacity
    }
    properties = {
      model = {
        format  = var.foundry_models[count.index].publisher
        name    = var.foundry_models[count.index].name
        version = var.foundry_models[count.index].version
      }
      raiPolicyName = "Microsoft.DefaultV2"
    }
  }

  # Serialize deployments to the same Cognitive Services account: each deployment
  # waits for the previous one to finish. The parent does not allow concurrent
  # PUT /deployments/<name> operations (409 RequestConflict).
  depends_on = [
    azapi_resource.app_insights_connection,
  ]

  # Retry on the well-known transient 409 returned while another deployment is
  # still being created on the same account.
  retry = {
    error_message_regex = [
      "RequestConflict",
      "Another operation is being performed on the parent resource",
    ]
    interval_seconds = 15
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
    private_connection_resource_id = azapi_resource.foundry[count.index].id
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

  depends_on = [azapi_resource.model_deployment]
}
