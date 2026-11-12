variable "ase" {
  description = <<-EOT
    App Service Environment v3 for the keyless usage pipeline (Logic App on Isolated v2).
      subnet_id                     alz_spoke/byo: the dedicated /24 subnet (delegated to Microsoft.Web/hostingEnvironments).
                                    greenfield: null = snet-ase in the greenfield VNet.
      internal_load_balancing_mode  "Web, Publishing" (ILB; required in Corp by AseDenyPublicIP) or "None".
      zone_redundant                Spread the ASE across availability zones (prod).
  EOT
  type = object({
    subnet_id                    = optional(string)
    internal_load_balancing_mode = optional(string, "Web, Publishing")
    zone_redundant               = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "dns" {
  description = <<-EOT
    Private DNS zone <ase>.appserviceenvironment.net (ILB only).
      create         false = the zone is managed elsewhere (e.g. the hub).
      vnet_link_ids  name => VNet ID to link the zone to. greenfield: null = the greenfield VNet.
                     alz_spoke: the spoke VNet (+ the hub / DNS resolver VNet).
  EOT
  type = object({
    create        = optional(bool, true)
    vnet_link_ids = optional(map(string))
  })
  default  = {}
  nullable = false
}
