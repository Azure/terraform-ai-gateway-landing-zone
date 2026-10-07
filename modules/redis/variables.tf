variable "name" {
  description = "Name of the Azure Managed Redis (Redis Enterprise) cluster."
  type        = string
}
variable "location" {
  description = "Primary Azure region for deployment"
  type        = string
}
variable "resource_group_name" {
  description = "Name of the resource group the module deploys into."
  type        = string
}
variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
}

variable "sku_name" {
  description = "Azure Managed Redis SKU (Microsoft.Cache/redisEnterprise)."
  type        = string
  default     = "Balanced_B10"
}

variable "sku_capacity" {
  description = "Cluster capacity (only used for Enterprise_* and EnterpriseFlash_* SKUs)."
  type        = number
  default     = 2
}

variable "public_network_access" {
  description = "Enabled or Disabled for the Redis Enterprise cluster."
  type        = string
  default     = "Disabled"
}

variable "minimum_tls_version" {
  description = "Minimum TLS version accepted by Azure Managed Redis."
  type        = string
  default     = "1.2"
}

variable "use_private_endpoint" {
  description = "Create a private endpoint for Azure Managed Redis."
  type        = bool
  default     = true
}

variable "subnet_id" {
  description = "Private endpoint subnet id."
  type        = string
}

variable "dns_zone_id" {
  description = "Redis private DNS zone id (privatelink.redis.azure.net)."
  type        = string
}
