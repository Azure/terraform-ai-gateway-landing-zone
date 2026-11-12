address_space          = "10.170.0.0/22"
apim_vnet_mode         = "integration"
subnets_enabled        = { logic_app = true, ase = false, cicd = true }
cicd_subnet_delegation = "github"

# logic_app_zone: privatelink.azurewebsites.net for the Logic App endpoint.
# link_monitor_zone: platform.tfvars monitoring.private_link_scope needs the Azure Monitor zones (monitor, oms, ods, agentsvc).
private_dns = { logic_app_zone = true, link_monitor_zone = true }
