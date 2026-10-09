# =============================================================================
# MODULE: cognitive-service
# A single-purpose Azure AI account that is not a Foundry account: Language
# (kind TextAnalytics, used for PII redaction) or Content Safety (kind
# ContentSafety). Same AVM module and resource provider as modules/foundry,
# different kind. Reached by APIM with its managed identity (no keys), over a
# private endpoint unless public access is asked for.
# =============================================================================

locals {
  subdomain = lower(var.custom_subdomain != "" ? var.custom_subdomain : var.name)
}

module "account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  name             = var.name
  location         = var.location
  parent_id        = var.resource_group_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  # Deleting can race the asynchronous delete of child resources (409 until terminal).
  retry = {
    error_message_regex = ["RequestConflict", "provisioning state is not terminal"]
    interval_seconds    = 30
  }

  kind                  = var.kind
  sku_name              = var.sku_name
  custom_subdomain_name = local.subdomain # required for Entra tokens and private endpoints
  local_auth_enabled    = !var.disable_key_auth
  managed_identities    = { system_assigned = true }

  public_network_access_enabled = var.public_network_access_enabled
  network_acls = {
    default_action = "Deny"
    # The ContentSafety kind rejects the bypass property altogether (NetworkAclsBypassNotSupported).
    bypass   = var.kind == "ContentSafety" ? null : "AzureServices"
    ip_rules = var.allowed_ip_rules
  }

  # One zone (privatelink.cognitiveservices.azure.com). With Azure Policy
  # (ALZ Deploy-Private-DNS-Zones) owning the zone group, or no zone given, Terraform
  # creates no zone group.
  private_endpoints_manage_dns_zone_group = !var.dns_zone_group_managed_by_policy && var.dns_zone_id != ""
  private_endpoints = {
    account = {
      name                            = "pe-${var.name}"
      private_service_connection_name = "psc-${var.name}"
      subnet_resource_id              = var.subnet_id
      private_dns_zone_resource_ids   = var.dns_zone_group_managed_by_policy || var.dns_zone_id == "" ? [] : [var.dns_zone_id]
      tags                            = var.tags
    }
  }
}

# APIM calls the service with its managed identity.
resource "azurerm_role_assignment" "apim_cognitive_services_user" {
  scope                = module.account.resource_id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.apim_principal_id
  principal_type       = "ServicePrincipal"
}

# An ARM PUT is a create-or-update: it succeeds even when Azure Policy already
# created a setting with this name. Azure deletes it with the account.
resource "azapi_resource_action" "diagnostics" {
  count = var.enable_diagnostics ? 1 : 0

  type        = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  resource_id = "${module.account.resource_id}/providers/Microsoft.Insights/diagnosticSettings/${var.name}-diagnostics"
  method      = "PUT"

  body = {
    properties = {
      workspaceId = var.log_analytics_id
      metrics     = [{ category = "AllMetrics", enabled = true }]
    }
  }
}
