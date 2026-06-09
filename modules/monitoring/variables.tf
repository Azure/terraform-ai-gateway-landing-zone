variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "log_analytics_name" { type = string }
variable "use_existing_log_analytics" { type = bool }
variable "existing_log_analytics_id" { type = string }
variable "environment_name" { type = string }
variable "create_dashboards" { type = bool }

variable "subscription_id" {
  description = "Subscription ID used when rendering the App Insights dashboard templates."
  type        = string
}

# -----------------------------------------------------------------------------
# AZURE MONITOR PRIVATE LINK SCOPE (Bicep parity: useAzureMonitorPrivateLinkScope)
# -----------------------------------------------------------------------------

variable "use_azure_monitor_private_link_scope" {
  description = "Create an Azure Monitor Private Link Scope (AMPLS) scoping the LAW and App Insights components."
  type        = bool
  default     = false
}

variable "ampls_subnet_id" {
  description = "Private endpoint subnet id for the AMPLS scoped PE (when use_azure_monitor_private_link_scope is true)."
  type        = string
  default     = ""
}

variable "ampls_dns_zone_id_monitor" {
  description = "Private DNS zone id for privatelink.monitor.azure.com."
  type        = string
  default     = ""
}
