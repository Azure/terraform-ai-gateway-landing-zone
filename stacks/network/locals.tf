locals {
  stack                  = "network"
  foundry_instance_names = []

  greenfield = var.network_mode == "greenfield"

  # Default carve of a /22 (e.g. 10.170.0.0/22):
  #   agent .0.0/24 · ase .1.0/24 · apim .2.0/24 · pe .3.0/26 · logic .3.64/26 · cicd .3.128/27
  default_prefixes = {
    agent     = cidrsubnet(var.address_space, 2, 0)
    ase       = cidrsubnet(var.address_space, 2, 1)
    apim      = cidrsubnet(var.address_space, 2, 2)
    pe        = cidrsubnet(var.address_space, 4, 12)
    logic_app = cidrsubnet(var.address_space, 4, 13)
    cicd      = cidrsubnet(var.address_space, 5, 28)
  }
  prefixes = { for k, v in local.default_prefixes : k => coalesce(lookup(var.subnet_prefixes, k, null), v) }
}
