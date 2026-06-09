variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }

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
  type    = string
  default = "1.2"
}

variable "use_private_endpoint" {
  type    = bool
  default = true
}

variable "subnet_id" {
  description = "Private endpoint subnet id."
  type        = string
}

variable "dns_zone_id" {
  description = "Redis private DNS zone id (privatelink.redis.azure.net)."
  type        = string
}
