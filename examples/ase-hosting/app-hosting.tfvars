# The App Service Environment v3 that hosts the keyless usage-ingestion Logic App.
# Creating it takes 2 to 4 hours and it changes rarely: this stack runs on its own, before platform.
ase = {
  # Greenfield: the ASE goes into snet-ase of the VNet that stacks/network created (found by name).
  # alz_spoke / byo: the dedicated subnet's ID.
  # subnet_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<snet-ase>"

  # "Web, Publishing" = internal load balancer: apps and SCM are reachable only from the VNet.
  # Required in Corp (the AseDenyPublicIP policy). "None" = an external ASE with a public inbound
  # address, which also means no private DNS zone below.
  internal_load_balancing_mode = "Web, Publishing"

  # Spread the ASE over availability zones. The region needs zones. Keep it in step with
  # usage_pipeline.ase.zone_redundant in platform.tfvars, which zone-balances the plan.
  zone_redundant = true
}

# Private DNS zone <ase>.appserviceenvironment.net (internal ASE only): `*`, `*.scm` and `@`
# records that point at the ASE's inbound IP, so the apps and their SCM endpoints resolve.
dns = {
  create = true # false = the zone is managed elsewhere (for example in a hub)

  # Greenfield: unset links the zone to the gateway VNet. Set this to link more VNets (a runner or
  # jump-box VNet, a hub / DNS resolver VNet); it replaces the default, so list the gateway VNet too:
  # vnet_link_ids = {
  #   gateway = "/subscriptions/<workload-subscription-id>/resourceGroups/rg-aigw-dev/providers/Microsoft.Network/virtualNetworks/vnet-aigw-dev"
  #   runner  = "/subscriptions/<sub>/resourceGroups/<rg-runner>/providers/Microsoft.Network/virtualNetworks/<vnet-runner>"
  # }
}
