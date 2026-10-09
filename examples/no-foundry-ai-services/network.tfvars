# No Foundry accounts, so no agent subnet.
address_space   = "10.170.0.0/22"
apim_vnet_mode  = "integration" # = apim.vnet_mode in platform.tfvars
subnets_enabled = { logic_app = true, agent = false, ase = false, cicd = false }
