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
# V2 SKUs (StandardV2/PremiumV2) use outbound VNet integration: the APIM subnet
# is delegated to Microsoft.Web/serverFarms (Bicep parity).
variable "subscription_id" {
  description = "Subscription of the resource group (AVM modules take the resource group ID)."
  type        = string
}

variable "default_outbound_access_enabled" {
  description = "Default outbound internet access on the subnets. false (private subnets) needs another egress path: a NAT gateway or a UDR to a hub firewall."
  type        = bool
  default     = true
}

variable "enable_telemetry" {
  description = "Enable Azure Verified Modules usage telemetry."
  type        = bool
  default     = true
}

variable "existing_vnet_id" {
  description = "alz_spoke: resource ID of the platform-vended spoke VNet the subnets are created in. null = create the VNet (greenfield)."
  type        = string
  default     = null
}

variable "hub_firewall_ip" {
  description = "alz_spoke: private IP of the hub firewall; every subnet routes 0.0.0.0/0 to it."
  type        = string
  default     = null
}

variable "apim_vnet_mode" {
  description = "APIM network mode (none | external | internal | integration | injection). Drives the APIM subnet: none = no subnet; external/internal = classic injection (management NSG rules + route table); integration = delegated to Microsoft.Web/serverFarms; injection = delegated to Microsoft.Web/hostingEnvironments (Premium v2)."
  type        = string

  validation {
    condition     = contains(["none", "external", "internal", "integration", "injection"], var.apim_vnet_mode)
    error_message = "apim_vnet_mode must be none, external, internal, integration or injection."
  }
}
