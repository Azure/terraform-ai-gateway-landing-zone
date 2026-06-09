# =============================================================================
# MODULE: Foundry - Input Variables
# Mirrors parameters of bicep/infra/modules/foundry/foundry.bicep
# =============================================================================

variable "resource_group_name" { type = string }
variable "resource_group_id"   { type = string }
variable "location"            { type = string }
variable "tags"                { type = map(string) }
variable "environment_name"    { type = string }
variable "random_suffix"       { type = string }

variable "foundry_external_access" {
  description = "If true, publicNetworkAccess=Enabled on Foundry accounts."
  type        = bool
  default     = false
}

variable "disable_key_auth" {
  description = "If true, only Entra ID auth is allowed (disableLocalAuth=true)."
  type        = bool
  default     = false
}

variable "foundry_project_default_name" {
  description = "Default AI Foundry project name (used when an instance entry does not override it)."
  type        = string
  default     = "citadel-governance-project"
}

# Mirrors aiServicesConfig in foundry.bicep
variable "foundry_instances" {
  description = "List of AI Foundry (AIServices) account definitions."
  type = list(object({
    name                 = optional(string, "")
    location             = string
    custom_subdomain     = optional(string, "")
    default_project_name = optional(string, "")
  }))
  default = []
}

# Mirrors modelsConfig in foundry.bicep
variable "foundry_models" {
  description = "Model deployments to create across the Foundry accounts."
  type = list(object({
    name             = string
    publisher        = optional(string, "OpenAI")
    version          = string
    sku              = optional(string, "GlobalStandard")
    capacity         = optional(number, 100)
    ai_service_index = optional(number, 0)
  }))
  default = []
}

variable "apim_principal_id" {
  description = "Principal ID granted 'Cognitive Services User' on each Foundry (typically APIM UAMI)."
  type        = string
}

variable "deployer_object_id" {
  description = "Principal ID granted 'Azure AI Project Manager' on each Foundry (matches deployer() in Bicep)."
  type        = string
}

variable "enable_diagnostics" {
  description = "Create diagnostic settings sending AllMetrics to Log Analytics."
  type        = bool
  default     = true
}

variable "log_analytics_id" {
  description = "Log Analytics workspace ID for diagnostic settings."
  type        = string
  default     = ""
}

variable "enable_app_insights_connection" {
  description = "Create the App Insights connection on each Foundry account."
  type        = bool
  default     = true
}

variable "app_insights_id" {
  description = "Application Insights resource ID for the Foundry App Insights connection."
  type        = string
  default     = ""
}

variable "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key used by the Foundry App Insights connection."
  type        = string
  default     = ""
  sensitive   = true
}

variable "subnet_id" {
  description = "Subnet ID for private endpoints."
  type        = string
}

variable "dns_zone_ids" {
  description = "Map of DNS zone IDs. Expected keys: cognitive_services, openai, ai_services."
  type        = map(string)
  default     = {}
}

variable "agent_subnet_id" {
  type    = string
  default = ""
}

variable "foundry_network_injection_enabled" {
  type    = bool
  default = true
}

# ------------------------------------------------------------------------------
# APIM → Foundry connection parameters (connection-apim.bicep parity)
# ------------------------------------------------------------------------------

variable "enable_apim_connections" {
  description = "Create Foundry-project → APIM ApiKey connections."
  type        = bool
  default     = false
}

variable "apim_service_name" {
  description = "APIM service name (used to construct default connection names)."
  type        = string
  default     = ""
}

variable "apim_gateway_url" {
  description = "APIM gateway URL (https://...)."
  type        = string
  default     = ""
}

variable "apim_primary_key" {
  description = "APIM master subscription primary key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "apim_connections" {
  description = "Per-API APIM connection definitions (one connection per Foundry project × api)."
  type = list(object({
    api_name               = string
    api_path               = string
    connection_name        = optional(string, "")
    is_shared_to_all       = optional(bool, false)
    deployment_in_path     = optional(string, "true")
    inference_api_version  = optional(string, "")
    deployment_api_version = optional(string, "")
    list_models_endpoint   = optional(string, "")
    get_model_endpoint     = optional(string, "")
    deployment_provider    = optional(string, "")
    static_models          = optional(list(any), [])
    custom_headers         = optional(map(string), {})
  }))
  default = []
}
