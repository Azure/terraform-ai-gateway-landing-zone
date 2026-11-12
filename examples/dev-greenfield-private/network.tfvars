address_space          = "10.170.0.0/22"
apim_vnet_mode         = "integration"
subnets_enabled        = { logic_app = false, ase = true, cicd = true }
cicd_subnet_delegation = "github" # GitHub-hosted runners with Azure private networking

# platform.tfvars monitoring.private_link_scope: the Azure Monitor zones (monitor, oms, ods, agentsvc).
private_dns = { link_monitor_zone = true }
