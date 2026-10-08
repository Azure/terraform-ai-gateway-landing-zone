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
variable "apim_name" {
  description = "Name of the API Management service."
  type        = string
}
variable "sku_name" {
  description = "APIM SKU: Developer, StandardV2, Premium, PremiumV2. REGION AVAILABILITY (important — v2 SKUs are NOT globally available): - Developer / Premium (classic): Globally available in virtually all Azure public regions. - StandardV2 / PremiumV2 (stv2 platform): Available in a limited subset of regions. Authoritative list (check before deploy): https://learn.microsoft.com/azure/api-management/api-management-region-availability az apim list-skus --location <region> If you hit `SkuNotSupportedInRegion` at apply time, either: (a) pick a supported region for `location`, or (b) fall back to `Premium` (classic)"
  type        = string
}
variable "sku_capacity" {
  description = "Number of APIM scale units"
  type        = number
}
variable "publisher_email" {
  description = "APIM publisher email"
  type        = string
}
variable "publisher_name" {
  description = "APIM publisher name"
  type        = string
}
variable "apim_subnet_id" {
  description = "Resource ID of the APIM subnet (VNet injection or outbound integration)."
  type        = string
}
variable "pe_subnet_id" {
  description = "Resource ID of the subnet that hosts private endpoints."
  type        = string
}
variable "vnet_id" {
  description = "Resource ID of the virtual network."
  type        = string
}
variable "apim_v2_use_private_endpoint" {
  description = "Enable private endpoint for APIM V2 SKUs"
  type        = bool
}
variable "apim_v2_public_network_access" {
  description = "Allow public access for APIM V2 SKUs"
  type        = bool
}
variable "managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity the service runs as."
  type        = string
}
variable "dns_zone_id_apim" {
  description = "Resource ID of the privatelink.azure-api.net DNS zone for the gateway private endpoint (empty = none)."
  type        = string
}

variable "create_internal_dns" {
  description = "For vnet_mode internal (classic: gateway, portal, developer, management, scm) or injection (Premium v2: gateway), create per-hostname private DNS zones and link them to the VNet."
  type        = bool
  default     = true
}

variable "redis_cache_connection_string" {
  description = "Optional Azure Managed Redis connection string. When set, creates an APIM service/caches resource."
  type        = string
  sensitive   = true
  default     = ""
}

variable "apim_zones" {
  description = "Availability zones for APIM (Premium only, skuCount>1). Computed at root; pass explicitly here."
  type        = list(string)
  default     = []
}

variable "enable_redis_cache" {
  description = "Attach Azure Managed Redis as the APIM external cache (requires redis_cache_connection_string)."
  type        = bool
  default     = false
}

variable "subscription_id" {
  description = "Subscription of the APIM service (existence probe for the public-access flip)."
  type        = string
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

variable "vnet_mode" {
  description = "APIM network mode: none | external | internal (Developer/Premium) | integration (StandardV2/PremiumV2) | injection (PremiumV2)."
  type        = string
}

variable "public_ip_address_id" {
  description = "Classic external/internal injection only: Standard-SKU public IP resource ID for the service. null = Azure-managed."
  type        = string
  default     = null
}
