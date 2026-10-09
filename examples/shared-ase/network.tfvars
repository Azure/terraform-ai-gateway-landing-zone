address_space          = "10.170.0.0/22"
apim_vnet_mode         = "integration"
subnets_enabled        = { logic_app = false, ase = false, cicd = true } # no ASE subnet: the ASE is shared
cicd_subnet_delegation = "github"

# Resolve the private endpoints from the shared ASE's VNet too (peering is not created here).
private_dns = {
  extra_vnet_link_ids = {
    shared-ase = "/subscriptions/<sub>/resourceGroups/<rg-ase>/providers/Microsoft.Network/virtualNetworks/<vnet-ase>"
  }
}
