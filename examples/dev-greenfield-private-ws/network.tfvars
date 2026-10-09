address_space          = "10.170.0.0/22"
apim_vnet_mode         = "integration"
subnets_enabled        = { logic_app = true, ase = false, cicd = true }
cicd_subnet_delegation = "github"
private_dns            = { logic_app_zone = true } # privatelink.azurewebsites.net for the Logic App endpoint
