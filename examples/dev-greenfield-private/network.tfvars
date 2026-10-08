address_space          = "10.170.0.0/22"
apim_vnet_mode         = "integration"
subnets_enabled        = { logic_app = false, ase = true, cicd = true }
cicd_subnet_delegation = "github" # GitHub-hosted runners with Azure private networking
