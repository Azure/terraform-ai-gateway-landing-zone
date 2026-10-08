variable "name" {
  description = "Name of the App Service Environment v3 (also the first label of its DNS suffix)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the resource group for the ASE and its private DNS zone."
  type        = string
}

variable "subnet_id" {
  description = "Dedicated, empty subnet delegated to Microsoft.Web/hostingEnvironments (/24 recommended, /27 minimum)."
  type        = string
}

variable "internal_load_balancing_mode" {
  description = "\"Web, Publishing\" = internal (ILB: apps and SCM reachable only from the VNet); \"None\" = external (public VIP)."
  type        = string
  default     = "Web, Publishing"

  validation {
    condition     = contains(["None", "Web, Publishing"], var.internal_load_balancing_mode)
    error_message = "internal_load_balancing_mode must be \"None\" or \"Web, Publishing\"."
  }
}

variable "zone_redundant" {
  description = "Zone-redundant ASE (region must support availability zones; increases the minimum billed instances)."
  type        = bool
  default     = false
}

variable "create_private_dns_zone" {
  description = "Internal ASE: create <ase>.appserviceenvironment.net with *, *.scm and @ records. false = DNS managed centrally (hub)."
  type        = bool
  default     = true
}

variable "dns_vnet_link_ids" {
  description = "VNets to link the ASE private DNS zone to (key => VNet resource ID): the spoke, plus the hub/resolver VNet when DNS is resolved centrally."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags for the ASE and its DNS zone."
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Enable Azure Verified Modules usage telemetry."
  type        = bool
  default     = true
}
