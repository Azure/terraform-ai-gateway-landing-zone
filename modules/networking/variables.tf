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
variable "vnet_name" {
  description = "Name of the virtual network to create."
  type        = string
}
variable "vnet_address_prefix" {
  description = "Address prefix for new VNet"
  type        = string
}
variable "apim_subnet_name" {
  description = "APIM subnet name"
  type        = string
}
variable "apim_subnet_prefix" {
  description = "APIM subnet address prefix (for new VNet)"
  type        = string
}
variable "pe_subnet_name" {
  description = "Private endpoint subnet name"
  type        = string
}
variable "pe_subnet_prefix" {
  description = "Private endpoint subnet address prefix (for new VNet)"
  type        = string
}
variable "logic_app_subnet_name" {
  description = "Logic App / Function App subnet name"
  type        = string
}
variable "logic_app_subnet_prefix" {
  description = "Logic App subnet address prefix (for new VNet)"
  type        = string
}
variable "enable_agent_subnet" {
  description = "Create a dedicated subnet for Foundry Agent Service network injection."
  type        = bool
}
variable "agent_subnet_name" {
  description = "Name of the Foundry agent subnet."
  type        = string
}
variable "agent_subnet_prefix" {
  description = "Address prefix (CIDR) of the Foundry agent subnet."
  type        = string
}
variable "enable_ase_subnet" {
  description = "Create the dedicated /24 subnet for App Service Environment v3 (Logic App ASE hosting)."
  type        = bool
  default     = false
}
variable "ase_subnet_name" {
  description = "Subnet for the App Service Environment v3 (only used when logic_app_hosting_model = \"AppServiceEnvironmentV3\"). Must be empty and delegated to Microsoft.Web/hostingEnvironments when using an existing VNet."
  type        = string
  default     = "snet-citadel-ase"
}
variable "ase_subnet_prefix" {
  description = "Address prefix for the ASE v3 subnet (new VNet only). Minimum /27; Microsoft recommends /24 for production scale. If this range is not inside vnet_address_prefix it is added to the VNet as an extra address space."
  type        = string
  default     = "10.170.1.0/24"
}
variable "apim_network_type" {
  description = "APIM network type: 'External', 'Internal', or 'None'"
  type        = string
}
variable "is_apim_vnet" {
  description = "True when APIM uses classic VNet injection (External/Internal); adds the APIM route table and NSG rules."
  type        = bool
}

# V2 SKUs (StandardV2/PremiumV2) use outbound VNet integration: the APIM subnet
# is delegated to Microsoft.Web/serverFarms (Bicep parity).
variable "is_apim_v2" {
  description = "True when the APIM SKU is a v2 SKU (BasicV2, StandardV2 or PremiumV2)."
  type        = bool
  default     = false
}
variable "nsg_on_all_subnets" {
  description = "Also attach NSGs to the private-endpoint and Logic App subnets (Azure Landing Zone Deny-Subnet-Without-Nsg)."
  type        = bool
  default     = false
}
