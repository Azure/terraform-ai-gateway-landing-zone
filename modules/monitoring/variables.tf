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

variable "create_foundry_app_insights" {
  description = "Create the Foundry Application Insights component (appi-aif-*), its dashboard and its Private Link Scope entry. false when no Foundry accounts are deployed."
  type        = bool
  default     = true
}

variable "local_authentication_disabled_components" {
  description = "App Insights components (apim, logic_app, foundry) that accept only Microsoft Entra (managed identity) ingestion: local authentication with the instrumentation key is disabled. Their senders need Monitoring Metrics Publisher."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.local_authentication_disabled_components : contains(["apim", "logic_app", "foundry"], c)])
    error_message = "local_authentication_disabled_components accepts apim, logic_app and foundry."
  }
}

variable "subscription_id" {
  description = "Subscription ID used when rendering the App Insights dashboard templates."
  type        = string
}

# -----------------------------------------------------------------------------
# AZURE MONITOR PRIVATE LINK SCOPE
# -----------------------------------------------------------------------------

variable "use_azure_monitor_private_link_scope" {
  description = "Create an Azure Monitor Private Link Scope (AMPLS) with a private endpoint, scoping the workspace (when created here) and the App Insights components. Only one scope per network that shares DNS: in a hub-and-spoke, join the hub's scope (existing_private_link_scope_id) instead."
  type        = bool
  default     = false

  validation {
    condition     = !(var.use_azure_monitor_private_link_scope && var.existing_private_link_scope_id != null)
    error_message = "Set use_azure_monitor_private_link_scope or existing_private_link_scope_id, not both."
  }
}

variable "existing_private_link_scope_id" {
  description = "Resource ID of an existing Azure Monitor Private Link Scope (e.g. the hub's) that the workspace (when created here) and the components join; its private endpoint and DNS belong to its owner. null = none."
  type        = string
  default     = null

  validation {
    condition     = var.existing_private_link_scope_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/microsoft\\.insights/privateLinkScopes/[^/]+$", var.existing_private_link_scope_id))
    error_message = "existing_private_link_scope_id must be an Azure Monitor Private Link Scope resource ID (/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Insights/privateLinkScopes/<name>)."
  }
}

variable "private_link_scope_access_mode" {
  description = "Access modes of the scope created here: Open (the networks can still reach Azure Monitor resources outside the scope that accept public traffic) or PrivateOnly (only resources in the scope)."
  type = object({
    ingestion = optional(string, "Open")
    query     = optional(string, "Open")
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for m in [var.private_link_scope_access_mode.ingestion, var.private_link_scope_access_mode.query] : contains(["Open", "PrivateOnly"], m)])
    error_message = "private_link_scope_access_mode.ingestion and .query must be Open or PrivateOnly."
  }
}

variable "public_ingestion_enabled" {
  description = "Accept ingestion from public networks on the workspace (when created here) and the App Insights components. false needs a private link scope: telemetry then only arrives through it (diagnostic settings aren't affected)."
  type        = bool
  default     = true

  validation {
    condition     = var.public_ingestion_enabled || var.use_azure_monitor_private_link_scope || var.existing_private_link_scope_id != null
    error_message = "public_ingestion_enabled = false needs a private link scope (use_azure_monitor_private_link_scope or existing_private_link_scope_id)."
  }
}

variable "public_query_enabled" {
  description = "Accept queries from public networks on the workspace (when created here) and the App Insights components, except those in public_query_components. false needs a private link scope; portal queries then only work from a network connected to it."
  type        = bool
  default     = true

  validation {
    condition     = var.public_query_enabled || var.use_azure_monitor_private_link_scope || var.existing_private_link_scope_id != null
    error_message = "public_query_enabled = false needs a private link scope (use_azure_monitor_private_link_scope or existing_private_link_scope_id)."
  }
}

variable "public_query_components" {
  description = "Resources that keep accepting public queries when public_query_enabled = false: log_analytics, apim, logic_app, foundry. For resources queried through Resource Manager (e.g. by a Logic App managed connector), which can't use private links. A workspace-based component's data lives in the workspace: a workspace that blocks public query returns that component's public queries empty, so list both."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(setsubtract(var.public_query_components, ["log_analytics", "apim", "logic_app", "foundry"])) == 0
    error_message = "public_query_components accepts log_analytics, apim, logic_app and foundry."
  }
}

variable "ampls_subnet_id" {
  description = "Private endpoint subnet id for the AMPLS scoped PE (when use_azure_monitor_private_link_scope is true)."
  type        = string
  default     = ""
}

variable "ampls_dns_zone_ids" {
  description = "Private DNS zone IDs of the scope's private endpoint (use_azure_monitor_private_link_scope): privatelink.monitor.azure.com, .oms.opinsights.azure.com, .ods.opinsights.azure.com, .agentsvc.azure-automation.net and .blob.core.windows.net. Empty = no zone group."
  type        = list(string)
  default     = []
  nullable    = false
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
