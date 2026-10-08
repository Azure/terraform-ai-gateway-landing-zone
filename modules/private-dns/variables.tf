variable "resource_group_name" {
  description = "Resource group for the private DNS zones and VNet links."
  type        = string
}

variable "tags" {
  description = "Tags applied to the private DNS zones."
  type        = map(string)
  default     = {}
}

variable "vnet_id" {
  description = "Resource ID of the VNet the created zones are linked to."
  type        = string
}

variable "create_zones" {
  description = "Create the private DNS zones and link them to the VNet. false = use existing_zone_ids only."
  type        = bool
  default     = true
}

variable "link_monitor_zone" {
  description = "Link privatelink.monitor.azure.com to the VNet. Only true when AMPLS is deployed: an empty linked monitor zone blackholes App Insights ingestion DNS."
  type        = bool
  default     = false
}

variable "existing_zone_ids" {
  description = "Existing zone key => private DNS zone resource ID. Accepts snake_case keys and the Bicep camelCase keys (keyVault, cosmosDb, ...). Overrides a created zone with the same key."
  type        = map(string)
  default     = {}
}

variable "required_zone_keys" {
  description = "Zone keys the caller dereferences (e.g. key_vault, cosmos_db). Planning fails with a clear message when one is neither created nor supplied in existing_zone_ids."
  type        = list(string)
  default     = []
}
