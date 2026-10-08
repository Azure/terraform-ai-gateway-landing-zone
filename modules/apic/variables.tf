variable "resource_group_id" {
  description = "Resource ID of the resource group the module deploys into."
  type        = string
}
variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
}
variable "enable_api_center" {
  description = "Deploy API Center as AI Registry"
  type        = bool
}
variable "api_center_sku" {
  description = "SKU for API Center service. Free tier is 'Free', paid tier is 'Standard'."
  type        = string
}
variable "apic_location" {
  description = "Azure region for API Center (API Center isn't available in every region)."
  type        = string
}

variable "api_center_name" {
  description = "Name of the API Center service."
  type        = string
}
