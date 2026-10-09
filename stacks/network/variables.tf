variable "address_space" {
  description = "Greenfield: the VNet address space. alz_spoke: the range allocated to this workload in the vended VNet (only used to carve default subnet prefixes). At least /22 so the ASE /24 fits."
  type        = string
  default     = "10.170.0.0/22"

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && tonumber(split("/", var.address_space)[1]) <= 22
    error_message = "address_space must be a CIDR of /22 or larger (ASE v3 needs a dedicated /24)."
  }
}

variable "subnet_prefixes" {
  description = "Subnet CIDRs; a null attribute falls back to the default carve of address_space (locals.tf)."
  type = object({
    apim      = optional(string) # classic: >= /29 (/27 recommended); v2 injection/integration: >= /27 (/24 recommended)
    pe        = optional(string) # /26
    logic_app = optional(string) # /26, Workflow Standard hosting only
    agent     = optional(string) # /24 recommended for Foundry agent injection
    ase       = optional(string) # /24, delegated to Microsoft.Web/hostingEnvironments
    cicd      = optional(string) # /27, private CI runners
  })
  default  = {}
  nullable = false
}

variable "subnets_enabled" {
  description = "Optional subnets. The APIM subnet follows apim_vnet_mode; the private endpoint subnet is always created."
  type = object({
    logic_app = optional(bool, false) # usage_pipeline.logic_app.hosting = workflow_standard
    agent     = optional(bool, true)  # Foundry agent network injection
    ase       = optional(bool, true)  # app-hosting (ASE v3) in this VNet
    cicd      = optional(bool, true)  # private runners
  })
  default  = {}
  nullable = false
}

variable "apim_vnet_mode" {
  description = "Must equal apim.vnet_mode in platform.tfvars: drives the APIM subnet (none = no subnet), its delegation, NSG rules and route table."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "external", "internal", "injection", "integration"], var.apim_vnet_mode)
    error_message = "apim_vnet_mode must be none, external, internal, injection or integration."
  }
}

variable "cicd_subnet_delegation" {
  description = "github = delegate snet-cicd to GitHub.Network/networkSettings (GitHub-hosted runners with Azure private networking); none = self-hosted runner VM."
  type        = string
  default     = "github"
}

variable "alz_spoke" {
  description = "alz_spoke only: the VNet created by subscription vending and the hub firewall's private IP (UDR next hop for 0.0.0.0/0)."
  type = object({
    vended_vnet_id  = string
    hub_firewall_ip = string
  })
  default = null
}

variable "default_outbound_access" {
  description = "Default outbound internet access on the subnets. null = true for greenfield (no other egress path), false for alz_spoke (egress through the hub firewall)."
  type        = bool
  default     = null
}

variable "private_dns" {
  description = <<-EOT
    Greenfield private DNS zones (alz_spoke: the hub owns them, nothing is created).
      link_monitor_zone    Link privatelink.monitor.azure.com: only when platform deploys AMPLS.
      logic_app_zone       Also create privatelink.azurewebsites.net: only when platform gives the
                           Workflow Standard Logic App a private endpoint
                           (usage_pipeline.logic_app.private_endpoint = true).
      extra_vnet_link_ids  name => VNet ID to link every zone to as well (e.g. a runner or jump-box VNet).
  EOT
  type = object({
    link_monitor_zone   = optional(bool, false)
    logic_app_zone      = optional(bool, false)
    extra_vnet_link_ids = optional(map(string), {})
  })
  default  = {}
  nullable = false
}
