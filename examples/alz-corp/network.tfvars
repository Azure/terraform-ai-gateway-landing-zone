alz_spoke = {
  vended_vnet_id  = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>"
  hub_firewall_ip = "<hub-firewall-private-ip>"
}
# The range allocated to this workload by vending (default carve), or explicit prefixes.
address_space          = "10.20.4.0/22"
apim_vnet_mode         = "internal"
subnets_enabled        = { logic_app = false, ase = true, cicd = true }
cicd_subnet_delegation = "none" # self-hosted runner VM
