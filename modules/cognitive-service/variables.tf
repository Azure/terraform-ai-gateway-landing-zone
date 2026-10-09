variable "name" {
  description = "Account name (2-64 characters; also the custom subdomain unless custom_subdomain is set)."
  type        = string
}

variable "kind" {
  description = "Account kind: TextAnalytics (Language service) or ContentSafety."
  type        = string

  validation {
    condition     = contains(["TextAnalytics", "ContentSafety"], var.kind)
    error_message = "kind must be TextAnalytics or ContentSafety."
  }
}

variable "sku_name" {
  description = "SKU: S for TextAnalytics (Language, standard), S0 for ContentSafety."
  type        = string
}

variable "location" {
  description = "Azure region (the service must be available there)."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the workload resource group."
  type        = string
}

variable "tags" {
  description = "Tags applied to the account and its private endpoint."
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Enable Azure Verified Modules usage telemetry."
  type        = bool
  default     = true
}

variable "custom_subdomain" {
  description = "Custom subdomain (the endpoint host); \"\" = the account name."
  type        = string
  default     = ""
}

variable "disable_key_auth" {
  description = "true (default): only Entra ID auth is allowed; the gateway uses its managed identity and no key is issued."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Public network access to the account. false = private endpoint only."
  type        = bool
  default     = false
}

variable "allowed_ip_rules" {
  description = "Public IPs / CIDRs allowed through the firewall when public access is enabled."
  type        = set(string)
  default     = []
}

variable "apim_principal_id" {
  description = "Principal ID of the APIM user-assigned identity (gets Cognitive Services User)."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the private endpoint."
  type        = string
}

variable "dns_zone_id" {
  description = "Resource ID of privatelink.cognitiveservices.azure.com (\"\" = no zone group, e.g. policy-managed)."
  type        = string
  default     = ""
}

variable "dns_zone_group_managed_by_policy" {
  description = "Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone."
  type        = bool
  default     = false
}

variable "enable_diagnostics" {
  description = "Create the AllMetrics diagnostic setting (false when Azure Policy owns it)."
  type        = bool
  default     = true
}

variable "log_analytics_id" {
  description = "Log Analytics workspace for the diagnostic setting."
  type        = string
  default     = ""
}
