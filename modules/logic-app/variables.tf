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
variable "environment_name" {
  description = "Environment name used for resource naming (e.g., citadel-dev, citadel-prod)"
  type        = string
}
variable "random_suffix" {
  description = "Random suffix appended to globally unique resource names."
  type        = string
}
variable "sku_size" {
  description = "Logic App (Standard) SKU size. Used only when logic_app_hosting_model = \"WorkflowStandard\"."
  type        = string
}
variable "subnet_id" {
  description = "Resource ID of the subnet used for regional VNet integration (Workflow Standard hosting)."
  type        = string
}

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
  description = "Isolated v2 App Service plan SKU for the Logic App when logic_app_hosting_model = \"AppServiceEnvironmentV3\"."
  type        = string
  default     = "I1v2"
}

variable "ase_worker_count" {
  description = "Number of Isolated v2 instances for the Logic App plan inside the ASE v3."
  type        = number
  default     = 1
}

variable "ase_internal_load_balancing_mode" {
  description = "ASE v3 ingress: \"Web, Publishing\" (internal/ILB — app and SCM endpoints reachable only from the VNet) or \"None\" (external, public VIP)."
  type        = string
  default     = "Web, Publishing"
}

variable "ase_zone_redundant" {
  description = "Deploy the ASE v3 as zone redundant (region must support availability zones; increases minimum billed instances)."
  type        = bool
  default     = false
}

variable "ase_create_private_dns_zone" {
  description = "For an internal (ILB) ASE v3, create the <ase>.appserviceenvironment.net private DNS zone (*, *.scm, @ records) and link it to the VNet. Set false when DNS is managed centrally (hub)."
  type        = bool
  default     = true
}
variable "eventhub_endpoint_host" {
  type        = string
  description = "EventHub namespace FQDN (e.g. evhns-xxx.servicebus.windows.net)"
}
variable "cosmos_db_endpoint" {
  description = "Cosmos DB account endpoint the workflows write to."
  type        = string
}
variable "app_insights_connection_string" {
  description = "Application Insights connection string for the Logic App."
  type        = string
  sensitive   = true
}
variable "managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity the service runs as."
  type        = string
}
variable "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity the service runs as."
  type        = string
}
variable "managed_identity_principal_id" {
  description = "Principal (object) ID of the user-assigned managed identity that is granted data-plane roles."
  type        = string
}
variable "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace that receives diagnostic settings."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Extended Logic App configuration
# -----------------------------------------------------------------------------

variable "eventhub_ai_usage_hub_name" {
  description = "Name of the Event Hub carrying AI usage events."
  type        = string
  default     = ""
}

variable "eventhub_pii_usage_hub_name" {
  description = "Name of the Event Hub carrying PII usage events."
  type        = string
  default     = ""
}

variable "cosmos_db_account_name" {
  type        = string
  description = "Cosmos DB account name (for AppSettings CosmosDBAccount)."
  default     = ""
}

variable "cosmos_db_database_name" {
  description = "Cosmos DB database that holds the usage containers."
  type        = string
  default     = ""
}

variable "cosmos_db_container_config" {
  description = "Cosmos DB container holding configuration documents (model pricing, ...)."
  type        = string
  default     = ""
}

variable "cosmos_db_container_usage" {
  description = "Cosmos DB container for AI usage records."
  type        = string
  default     = ""
}

variable "cosmos_db_container_pii" {
  description = "Cosmos DB container for PII usage records."
  type        = string
  default     = ""
}

variable "cosmos_db_container_llm_usage" {
  description = "Cosmos DB container for LLM usage records."
  type        = string
  default     = ""
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
  description = "Azure Subscription ID for the deployment"
  type        = string
  default     = ""
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
  description = "Resource ID of the privatelink.blob.core.windows.net DNS zone for the storage private endpoint."
  type        = string
  default     = ""
}

variable "dns_zone_id_file" {
  description = "Resource ID of the privatelink.file.core.windows.net DNS zone for the storage private endpoint."
  type        = string
  default     = ""
}

variable "dns_zone_id_table" {
  description = "Resource ID of the privatelink.table.core.windows.net DNS zone for the storage private endpoint."
  type        = string
  default     = ""
}

variable "dns_zone_id_queue" {
  description = "Resource ID of the privatelink.queue.core.windows.net DNS zone for the storage private endpoint."
  type        = string
  default     = ""
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
