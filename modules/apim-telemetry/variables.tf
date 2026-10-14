variable "api_management_id" {
  description = "Resource ID of the API Management service."
  type        = string
}

variable "api_management_name" {
  description = "Name of the API Management service."
  type        = string
}

variable "app_insights_connection_string" {
  description = "Application Insights connection string — used in the AppInsights logger."
  type        = string
  sensitive   = true
  default     = ""
}

variable "app_insights_id" {
  description = "Resource ID of the Application Insights component used by the APIM logger."
  type        = string
}

variable "app_insights_managed_identity" {
  description = "The App Insights logger authenticates with the APIM managed identity (managed_identity_client_id, which needs Monitoring Metrics Publisher on the component) instead of the instrumentation key. Requires app_insights_connection_string. Needed when the component disables local authentication."
  type        = bool
  default     = false
  nullable    = false
}

variable "credentials_in_key_vault" {
  description = "Logger credentials (identity client ID, App Insights connection string) in Key Vault (credentials_key_vault_id): written as secrets apim-logger-*, read by APIM through Key Vault-backed named values (managed_identity_client_id needs Key Vault Secrets User, and APIM must reach the vault). false = APIM stores them in the secret named values it generates (Logger-Credentials--*)."
  type        = bool
  default     = false
  nullable    = false
}

variable "credentials_key_vault_id" {
  description = "Key Vault for the logger credentials (credentials_in_key_vault = true)."
  type        = string
  default     = null
}

variable "app_insights_instrumentation_key" {
  description = "Instrumentation key of the APIM Application Insights component (legacy logger credential)."
  type        = string
  sensitive   = true
}

variable "enable_pii_redaction" {
  description = "Create the PII usage Event Hub logger (pii-usage-eventhub-logger)."
  type        = bool
}

variable "eventhub_pii_hub_name" {
  type        = string
  description = "Name of the PII usage event hub."
  default     = "pii-usage"
}

variable "eventhub_usage_hub_name" {
  type        = string
  description = "Name of the APIM usage event hub inside the namespace."
  default     = "ai-usage"
}

variable "eventhub_endpoint_uri" {
  type        = string
  description = "EventHub namespace endpoint URI (https://<ns>.servicebus.windows.net)"
}

variable "enable_diagnostics" {
  description = "Configure the workload Azure Monitor diagnostic setting by ARM PUT. false = Azure Policy owns it. APIM loggers and API diagnostics are unaffected."
  type        = bool
  default     = true
}

variable "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace that receives diagnostic settings."
  type        = string
}

variable "log_body_bytes" {
  description = "Max bytes to log from request/response body"
  type        = number
}

variable "log_verbosity" {
  description = "APIM diagnostic log verbosity: verbose, information, error"
  type        = string
}

variable "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity the service runs as."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group the module deploys into."
  type        = string
}
