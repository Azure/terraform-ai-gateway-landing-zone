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
variable "account_name" {
  description = "Name of the Cosmos DB account."
  type        = string
}
variable "public_network_access" {
  description = "Cosmos DB public network access: Enabled or Disabled"
  type        = string
}
variable "subnet_id" {
  description = "Resource ID of the subnet that hosts the private endpoint."
  type        = string
}
variable "dns_zone_id" {
  description = "Resource ID of the privatelink.documents.azure.com DNS zone (empty = no DNS zone group)."
  type        = string
}
variable "managed_identity_principal_id" {
  description = "Principal ID of the usage-pipeline identity granted the Cosmos DB Built-in Data Contributor role."
  type        = string
}
variable "local_authentication_enabled" {
  description = "Allow key/connection-string auth on the Cosmos DB data plane. When false, only Entra ID (RBAC) is accepted."
  type        = bool
  default     = false
}
variable "enable_diagnostics" {
  description = "Create the workload diagnostic setting. false = Azure Policy owns diagnostics; do not adopt its settings."
  type        = bool
  default     = true
}

variable "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace that receives diagnostic settings."
  type        = string
  default     = ""
}

variable "dns_zone_group_managed_by_policy" {
  description = "Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone."
  type        = bool
  default     = false
}

variable "enable_telemetry" {
  description = "Enable Azure Verified Modules usage telemetry."
  type        = bool
  default     = true
}
