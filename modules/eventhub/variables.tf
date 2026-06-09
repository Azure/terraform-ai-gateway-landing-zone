variable "resource_group_name"    { type = string }
variable "location"                { type = string }
variable "tags"                    { type = map(string) }
variable "namespace_name"          { type = string }
variable "capacity_units"          { type = number }
variable "partition_count"         { type = number }
variable "public_network_access"   { type = string }
variable "subnet_id"               { type = string }
variable "vnet_id"                 { type = string }
variable "dns_zone_id"             { type = string }
# Bicep parity:
#  - APIM UAMI needs Data Sender (to publish from loggers).
#  - Logic App / Usage UAMI needs Data Receiver (to consume usage events).
variable "apim_identity_principal_id"  { type = string }
variable "usage_identity_principal_id" { type = string }
variable "log_analytics_id"        { 
    type = string
    default = "" 
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
