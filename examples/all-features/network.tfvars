# Explicit carve of the /22 instead of the default one.
address_space = "10.170.0.0/22"
subnet_prefixes = {
  apim      = "10.170.0.0/24"
  pe        = "10.170.1.0/26"
  logic_app = "10.170.1.64/26"
  agent     = "10.170.2.0/24"
}
apim_vnet_mode          = "integration" # = apim.vnet_mode in platform.tfvars
subnets_enabled         = { logic_app = true, agent = true, ase = false, cicd = true }
cicd_subnet_delegation  = "github"
default_outbound_access = false # no implicit internet egress from the subnets

private_dns = {
  link_monitor_zone = true # platform deploys the Azure Monitor Private Link Scope
  # Also link every zone to a runner / jump-box VNet owned by another team.
  extra_vnet_link_ids = {
    jumpbox = "/subscriptions/<sub>/resourceGroups/<rg-jumpbox>/providers/Microsoft.Network/virtualNetworks/<vnet-jumpbox>"
  }
}
