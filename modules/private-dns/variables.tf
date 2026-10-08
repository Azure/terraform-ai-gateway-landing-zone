variable "resource_group_id" {
  description = "Resource group for the private DNS zones."
  type        = string
}

variable "zone_names" {
  description = "Logical key => private DNS zone name (modules/naming private_dns_zones)."
  type        = map(string)
}

variable "vnet_id" {
  description = "Resource ID of the VNet the zones are linked to."
  type        = string
}

variable "extra_vnet_link_ids" {
  description = "Additional VNets to link every zone to (name => VNet resource ID), e.g. a runner or jump-box VNet."
  type        = map(string)
  default     = {}
}

variable "link_monitor_zone" {
  description = "Link privatelink.monitor.azure.com to the VNets. Only true when AMPLS is deployed: an empty linked monitor zone blackholes App Insights ingestion DNS."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the private DNS zones."
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Enable Azure Verified Modules usage telemetry."
  type        = bool
  default     = true
}
