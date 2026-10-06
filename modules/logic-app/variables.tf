variable "resource_group_name"         { type = string }
variable "location"                      { type = string }
variable "tags"                          { type = map(string) }
variable "environment_name"              { type = string }
variable "random_suffix"                 { type = string }
variable "sku_tier"                      { type = string }
variable "sku_size"                      { type = string }
variable "subnet_id"                     { type = string }

# -----------------------------------------------------------------------------
# Hosting model (WorkflowStandard | AppServiceEnvironmentV3) — see ase.tf
# -----------------------------------------------------------------------------

variable "hosting_model" {
  description = "WorkflowStandard (WS plan + VNet integration, key-based storage) or AppServiceEnvironmentV3 (Isolated v2 plan in an ASE v3, keyless storage)."
  type        = string
  default     = "WorkflowStandard"

  validation {
    condition     = contains(["WorkflowStandard", "AppServiceEnvironmentV3"], var.hosting_model)
    error_message = "hosting_model must be WorkflowStandard or AppServiceEnvironmentV3."
  }
}

variable "ase_subnet_id" {
  description = "Dedicated subnet (delegated to Microsoft.Web/hostingEnvironments) for the ASE v3."
  type        = string
  default     = ""
}

variable "vnet_id" {
  description = "VNet ID used to link the ASE private DNS zone."
  type        = string
  default     = ""
}

variable "ase_sku_size" {
  type    = string
  default = "I1v2"
}

variable "ase_worker_count" {
  type    = number
  default = 1
}

variable "ase_internal_load_balancing_mode" {
  type    = string
  default = "Web, Publishing"
}

variable "ase_zone_redundant" {
  type    = bool
  default = false
}

variable "ase_create_private_dns_zone" {
  type    = bool
  default = true
}
variable "eventhub_endpoint_host"        { 
    type = string
    description = "EventHub namespace FQDN (e.g. evhns-xxx.servicebus.windows.net)"
}
variable "cosmos_db_endpoint"            { type = string }
variable "app_insights_connection_string" { 
    type = string
    sensitive = true
}
variable "managed_identity_id"           { type = string }
variable "managed_identity_client_id"     { type = string }
variable "managed_identity_principal_id"  { type = string }
variable "log_analytics_id"              { 
    type = string
    default = "" 
}

# -----------------------------------------------------------------------------
# Extended Logic App configuration
# -----------------------------------------------------------------------------

variable "eventhub_namespace_name" {
  type        = string
  description = "EventHub namespace name (not FQDN)."
  default     = ""
}

variable "eventhub_ai_usage_hub_name" {
  type    = string
  default = ""
}

variable "eventhub_pii_usage_hub_name" {
  type    = string
  default = ""
}

variable "cosmos_db_account_name" {
  type        = string
  description = "Cosmos DB account name (for AppSettings CosmosDBAccount)."
  default     = ""
}

variable "cosmos_db_database_name" {
  type    = string
  default = ""
}

variable "cosmos_db_container_config" {
  type    = string
  default = ""
}

variable "cosmos_db_container_usage" {
  type    = string
  default = ""
}

variable "cosmos_db_container_pii" {
  type    = string
  default = ""
}

variable "cosmos_db_container_llm_usage" {
  type    = string
  default = ""
}

variable "cosmos_db_account_id" {
  description = "Cosmos DB account ID for SQL role assignment on Logic App system-assigned principal."
  type        = string
  default     = ""
}

variable "apim_app_insights_name" {
  description = "Name of the APIM-side Application Insights (AppSettings AppInsights_Name)."
  type        = string
  default     = ""
}

variable "apim_app_insights_rg" {
  description = "Resource group of the APIM-side Application Insights."
  type        = string
  default     = ""
}

variable "subscription_id" {
  type    = string
  default = ""
}

variable "content_share_name" {
  description = "Logic App content share (WEBSITE_CONTENTSHARE). Leave blank to auto-derive."
  type        = string
  default     = ""
}

variable "pe_subnet_id" {
  description = "Private-endpoint subnet ID for the storage account (blob/file/table/queue PEs)."
  type        = string
  default     = ""
}

variable "enable_storage_private_endpoints" {
  description = "Whether to create private endpoints for the Logic App storage account (blob/file/table/queue). Must be known at plan time."
  type        = bool
  default     = true
}

variable "enable_cosmos_role_assignment" {
  description = "Whether to create the Cosmos SQL role assignment for the Logic App system MI. Must be known at plan time."
  type        = bool
  default     = true
}

variable "dns_zone_id_blob" {
  type    = string
  default = ""
}

variable "dns_zone_id_file" {
  type    = string
  default = ""
}

variable "dns_zone_id_table" {
  type    = string
  default = ""
}

variable "dns_zone_id_queue" {
  type    = string
  default = ""
}

variable "create_azuremonitor_api_connection" {
  description = "Create the Logic App 'azuremonitorlogs' API connection and grant access to the system-assigned MI."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Workflow-code publish (see LOGIC_APP_CODE_PORT.md)
# Mirrors `azd deploy usageProcessingLogicApp` — zips the Logic App Standard
# project folder and pushes via `az logicapp deployment source config-zip`.
# -----------------------------------------------------------------------------

variable "enable_code_deploy" {
  description = "If true, zip and publish the Logic App Standard project folder (src/usage-ingestion-logicapp) as part of apply."
  type        = bool
  default     = true
}

variable "code_source_path" {
  description = "Absolute path to the Logic App Standard project folder. Leave blank to skip when enable_code_deploy=false."
  type        = string
  default     = "src/usage-ingestion-logicapp"
}
