variable "resource_group_name" {
  description = "Name of the resource group the module deploys into."
  type        = string
}
variable "location" {
  description = "Primary Azure region for deployment"
  type        = string
}
variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
}
variable "namespace_name" {
  description = "Name of the Event Hubs namespace."
  type        = string
}
variable "capacity_units" {
  description = "Event Hub capacity units"
  type        = number
}
variable "public_network_access" {
  description = "Event Hub public network access: Enabled or Disabled"
  type        = string
}
variable "subnet_id" {
  description = "Resource ID of the subnet that hosts the private endpoint."
  type        = string
}
variable "dns_zone_id" {
  description = "Resource ID of the privatelink.servicebus.windows.net DNS zone (empty = no DNS zone group)."
  type        = string
}
# Bicep parity:
#  - APIM UAMI needs Data Sender (to publish from loggers).
#  - Logic App / Usage UAMI needs Data Receiver (to consume usage events).
variable "apim_identity_principal_id" {
  description = "Principal ID of the APIM managed identity granted Azure Event Hubs Data Sender."
  type        = string
}
variable "usage_identity_principal_id" {
  description = "Principal ID of the usage-pipeline identity granted Azure Event Hubs Data Receiver."
  type        = string
}
variable "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace that receives diagnostic settings."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# OPTIONAL DISASTER RECOVERY (Bicep parity: disasterRecoveryConfig)
# -----------------------------------------------------------------------------
# When set, creates a Microsoft.EventHub/namespaces/disasterRecoveryConfigs
# resource with alias 'default' pairing this namespace with a partner namespace
# in a secondary region. The partner must already exist.

variable "disaster_recovery_config" {
  description = <<-EOT
    Optional disaster recovery pairing. Set to `null` (default) to skip.
    When provided, must contain:
      - partner_namespace_id: full resource ID of the partner EH namespace
      - alias: optional alias name (defaults to "default")
  EOT
  type = object({
    partner_namespace_id = string
    alias                = optional(string, "default")
  })
  default = null
}
