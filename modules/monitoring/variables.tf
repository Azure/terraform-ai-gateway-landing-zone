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
variable "log_analytics_name" {
  description = "Name of the Log Analytics workspace to create (ignored when existing_log_analytics_workspace is set)."
  type        = string
}
variable "existing_log_analytics_workspace" {
  description = "Existing (BYO) Log Analytics workspace: resource id and workspace (customer) id. null = create one named log_analytics_name. The caller looks the workspace up."
  type = object({
    id           = string
    workspace_id = string
  })
  default = null
}
variable "environment_name" {
  description = "Environment name used for resource naming (e.g., citadel-dev, citadel-prod)"
  type        = string
}
variable "create_dashboards" {
  description = "Create Application Insights dashboards"
  type        = bool
}

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

variable "enable_telemetry" {
  description = "Enable Azure Verified Modules usage telemetry."
  type        = bool
  default     = true
}

variable "dns_zone_group_managed_by_policy" {
  description = "Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone."
  type        = bool
  default     = false
}
