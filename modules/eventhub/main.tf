# =============================================================================
# MODULE: Event Hub
# Usage data streaming pipeline — mirrors Bicep eventhub module
# =============================================================================

# Note on Bicep-parity flags handled implicitly by azurerm v4:
#   - zoneRedundant: managed automatically for Standard/Premium SKUs (no arg).
#   - kafkaEnabled: Kafka is always enabled on Standard+ namespaces; Bicep sets
#     it false but the RP ignores that for Standard. No TF action required.
module "namespace" {
  source  = "Azure/avm-res-eventhub-namespace/azurerm"
  version = "0.1.1"

  name                = var.namespace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry

  sku                           = "Standard"
  capacity                      = var.capacity_units
  auto_inflate_enabled          = true
  maximum_throughput_units      = 20
  local_authentication_enabled  = false # no SAS: APIM and the Logic App use managed identities
  public_network_access_enabled = var.public_network_access == "Enabled"
  # Network rules: azapi_update_resource.network_rule_set below (retried independently).

  # Bicep parity: partition 4 / 2, retention 7 days.
  event_hubs = {
    "ai-usage"  = { namespace_name = var.namespace_name, resource_group_name = var.resource_group_name, partition_count = 4, message_retention = 7 }
    "pii-usage" = { namespace_name = var.namespace_name, resource_group_name = var.resource_group_name, partition_count = 2, message_retention = 7 }
  }

  # Managed identities instead of SAS keys:
  #   APIM loggers send; the Logic App (usage UAMI) receives. Bicep also gives
  #   the Logic App UAMI Data Owner (at RG scope; namespace scope is tighter).
  role_assignments = {
    apim_data_sender = {
      role_definition_id_or_name = "Azure Event Hubs Data Sender"
      principal_id               = var.apim_identity_principal_id
    }
    usage_data_receiver = {
      role_definition_id_or_name = "Azure Event Hubs Data Receiver"
      principal_id               = var.usage_identity_principal_id
    }
    usage_data_owner = {
      role_definition_id_or_name = "Azure Event Hubs Data Owner"
      principal_id               = var.usage_identity_principal_id
    }
  }

  private_endpoints_manage_dns_zone_group = !var.dns_zone_group_managed_by_policy
  private_endpoints = {
    namespace = {
      name                            = "pe-${var.namespace_name}"
      private_service_connection_name = "psc-${var.namespace_name}"
      subnet_resource_id              = var.subnet_id
      private_dns_zone_group_name     = "evhns-dns-group"
      private_dns_zone_resource_ids   = var.dns_zone_id != "" && !var.dns_zone_group_managed_by_policy ? [var.dns_zone_id] : []
      tags                            = var.tags
    }
  }
}

locals {
  namespace_id   = module.namespace.resource_id
  namespace_name = var.namespace_name
}

# -----------------------------------------------------------------------------
# NETWORK RULESET (separate resource so it can be retried independently of the
# namespace create call). azurerm has no standalone resource for this child,
# so we use azapi against the Microsoft.EventHub/namespaces/networkRuleSets
# proxy resource. Name is always "default".
#
# IMPORTANT: Azure auto-creates the `default` networkRuleSet child whenever an
# Event Hub namespace is created, so a CREATE (PUT) via `azapi_resource` will
# always fail with "Resource already exists" on the first apply. Use
# `azapi_update_resource` instead — it issues a PATCH against the always-
# existing child resource, which is idempotent on first and subsequent runs.
# -----------------------------------------------------------------------------

resource "azapi_update_resource" "network_rule_set" {
  type        = "Microsoft.EventHub/namespaces/networkRuleSets@2024-01-01"
  resource_id = "${local.namespace_id}/networkRuleSets/default"

  body = {
    properties = {
      defaultAction               = var.public_network_access == "Enabled" ? "Allow" : "Deny"
      trustedServiceAccessEnabled = true
      publicNetworkAccess         = var.public_network_access == "Enabled" ? "Enabled" : "Disabled"
    }
  }
}

# -----------------------------------------------------------------------------
# EVENT HUB: ai-usage (LLM token/request metrics). Bicep parity: partition=4, retention=7.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# EVENT HUB: pii-usage (PII anonymization audit logs). Bicep parity: partition=2, retention=7.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CONSUMER GROUPS (match Bicep names: aiUsageIngestion / piiUsageIngestion).
# Note: $Default is auto-created by the Event Hub service; Bicep declares it
# explicitly but the Terraform provider rejects '$' in the name. Omitting it
# does not change the deployed state.
# -----------------------------------------------------------------------------

resource "azurerm_eventhub_consumer_group" "ai_usage_ingestion" {
  name                = "aiUsageIngestion"
  namespace_name      = local.namespace_name
  eventhub_name       = "ai-usage"
  resource_group_name = var.resource_group_name

  # The hubs are created inside the AVM namespace module.
  depends_on = [module.namespace]
}

resource "azurerm_eventhub_consumer_group" "pii_usage_ingestion" {
  name                = "piiUsageIngestion"
  namespace_name      = local.namespace_name
  eventhub_name       = "pii-usage"
  resource_group_name = var.resource_group_name

  # The hubs are created inside the AVM namespace module.
  depends_on = [module.namespace]
}

# -----------------------------------------------------------------------------
# PRIVATE ENDPOINT
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
#
# IMPORTANT: Azure Policy (DeployIfNotExists) may auto-create a diagnostic
# setting named `diag-<namespace>` on EventHub namespaces seconds after
# creation. Using azapi_resource_action with method PUT sends a true ARM
# "Create or Update" — it succeeds whether the resource already exists (policy
# present) or not (no policy). This avoids both the "already exists" error
# from azurerm_monitor_diagnostic_setting and the "duplicate sink" error from
# trying to create a second setting with a different name.
# -----------------------------------------------------------------------------

resource "azapi_resource_action" "eventhub_diagnostics" {
  type        = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  resource_id = "${local.namespace_id}/providers/Microsoft.Insights/diagnosticSettings/diag-${var.namespace_name}"
  method      = "PUT"

  body = {
    properties = {
      workspaceId = var.log_analytics_id
      logs = [
        { category = "ArchiveLogs", enabled = true },
        { category = "OperationalLogs", enabled = true }
      ]
      metrics = [
        { category = "AllMetrics", enabled = true }
      ]
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC: Grant UAMI "Azure Event Hubs Data Sender" on namespace
# (used by APIM loggers via managed identity instead of SAS keys)
# -----------------------------------------------------------------------------

# Bicep parity: Logic App UAMI also gets "Azure Event Hubs Data Owner" at
# namespace scope (Bicep grants at RG scope; namespace scope is tighter and
# sufficient for the Logic App workflows).

# -----------------------------------------------------------------------------
# OPTIONAL DISASTER RECOVERY PAIRING (Bicep parity: disasterRecoveryConfig)
# When `var.disaster_recovery_config` is provided, pairs this namespace with a
# partner namespace (typically in a secondary region) under the given alias.
# The partner namespace must already exist and be the same SKU.
# -----------------------------------------------------------------------------

resource "azurerm_eventhub_namespace_disaster_recovery_config" "pairing" {
  count                = var.disaster_recovery_config == null ? 0 : 1
  name                 = var.disaster_recovery_config.alias
  resource_group_name  = var.resource_group_name
  namespace_name       = local.namespace_name
  partner_namespace_id = var.disaster_recovery_config.partner_namespace_id
}
