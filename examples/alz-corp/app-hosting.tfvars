ase = {
  subnet_id      = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>/subnets/snet-ase"
  zone_redundant = true
}
dns = {
  vnet_link_ids = {
    spoke = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>"
    hub   = "/subscriptions/<hub-sub>/resourceGroups/<rg-hub>/providers/Microsoft.Network/virtualNetworks/<vnet-hub-or-resolver>"
  }
}
