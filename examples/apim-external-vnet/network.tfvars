address_space   = "10.170.0.0/22"
apim_vnet_mode  = "external" # = apim.vnet_mode in platform.tfvars
subnets_enabled = { logic_app = true, ase = false, cicd = false }
