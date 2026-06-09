# =============================================================================
# MODULE: Event Hub
# Usage data streaming pipeline — mirrors Bicep eventhub module
# =============================================================================

# Note on Bicep-parity flags handled implicitly by azurerm v4:
#   - zoneRedundant: managed automatically for Standard/Premium SKUs (no arg).
#   - kafkaEnabled: Kafka is always enabled on Standard+ namespaces; Bicep sets
#     it false but the RP ignores that for Standard. No TF action required.
resource "azurerm_eventhub_namespace" "citadel" {
  name                = var.namespace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  capacity            = var.capacity_units
  tags                = var.tags

  auto_inflate_enabled          = true
  maximum_throughput_units      = 20
  local_authentication_enabled  = false
  public_network_access_enabled = var.public_network_access == "Enabled" ? true : false

  # Network rules are managed by `azurerm_eventhub_namespace_network_rule_set`
  # below. Splitting them out avoids a known RP flake where the namespace
  # create succeeds but the inline networkRuleSets PUT drops its connection
  # ("HTTP response was nil"), which leaves Terraform unable to retry cleanly.
  lifecycle {
    ignore_changes = [network_rulesets]
  }
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
  resource_id = "${azurerm_eventhub_namespace.citadel.id}/networkRuleSets/default"

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

resource "azurerm_eventhub" "ai_usage" {
  name              = "ai-usage"
  namespace_id      = azurerm_eventhub_namespace.citadel.id
  partition_count   = 4
  message_retention = 7
}

# -----------------------------------------------------------------------------
# EVENT HUB: pii-usage (PII anonymization audit logs). Bicep parity: partition=2, retention=7.
# -----------------------------------------------------------------------------

resource "azurerm_eventhub" "pii_usage" {
  name              = "pii-usage"
  namespace_id      = azurerm_eventhub_namespace.citadel.id
  partition_count   = 2
  message_retention = 7
}

# -----------------------------------------------------------------------------
# CONSUMER GROUPS (match Bicep names: aiUsageIngestion / piiUsageIngestion).
# Note: $Default is auto-created by the Event Hub service; Bicep declares it
# explicitly but the Terraform provider rejects '$' in the name. Omitting it
# does not change the deployed state.
# -----------------------------------------------------------------------------

resource "azurerm_eventhub_consumer_group" "ai_usage_ingestion" {
  name                = "aiUsageIngestion"
  namespace_name      = azurerm_eventhub_namespace.citadel.name
  eventhub_name       = azurerm_eventhub.ai_usage.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_eventhub_consumer_group" "pii_usage_ingestion" {
  name                = "piiUsageIngestion"
  namespace_name      = azurerm_eventhub_namespace.citadel.name
  eventhub_name       = azurerm_eventhub.pii_usage.name
  resource_group_name = var.resource_group_name
}

# -----------------------------------------------------------------------------
# PRIVATE ENDPOINT
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "eventhub" {
  name                = "pe-${var.namespace_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.namespace_name}"
    private_connection_resource_id = azurerm_eventhub_namespace.citadel.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.dns_zone_id != "" ? [1] : []
    content {
      name                 = "evhns-dns-group"
      private_dns_zone_ids = [var.dns_zone_id]
    }
  }
}

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
  resource_id = "${azurerm_eventhub_namespace.citadel.id}/providers/Microsoft.Insights/diagnosticSettings/diag-${var.namespace_name}"
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

resource "azurerm_role_assignment" "eventhub_data_sender" {
  scope                = azurerm_eventhub_namespace.citadel.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = var.apim_identity_principal_id
}

resource "azurerm_role_assignment" "eventhub_data_receiver" {
  scope                = azurerm_eventhub_namespace.citadel.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = var.usage_identity_principal_id
}

# Bicep parity: Logic App UAMI also gets "Azure Event Hubs Data Owner" at
# namespace scope (Bicep grants at RG scope; namespace scope is tighter and
# sufficient for the Logic App workflows).
resource "azurerm_role_assignment" "eventhub_data_owner_usage" {
  scope                = azurerm_eventhub_namespace.citadel.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = var.usage_identity_principal_id
}

# -----------------------------------------------------------------------------
# OPTIONAL DISASTER RECOVERY PAIRING (Bicep parity: disasterRecoveryConfig)
# When `var.disaster_recovery_config` is provided, pairs this namespace with a
# partner namespace (typically in a secondary region) under the given alias.
# The partner namespace must already exist and be the same SKU.
# -----------------------------------------------------------------------------

resource "azurerm_eventhub_namespace_disaster_recovery_config" "pairing" {
  count                 = var.disaster_recovery_config == null ? 0 : 1
  name                  = var.disaster_recovery_config.alias
  resource_group_name   = var.resource_group_name
  namespace_name        = azurerm_eventhub_namespace.citadel.name
  partner_namespace_id  = var.disaster_recovery_config.partner_namespace_id
}
