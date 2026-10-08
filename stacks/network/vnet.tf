# The workload resource group is created by stacks/bootstrap.
data "azurerm_resource_group" "workload" {
  name = local.names.resource_group

  lifecycle {
    postcondition {
      condition     = var.network_mode != "byo"
      error_message = "network_mode = \"byo\": the network stack doesn't run (delete network.tfvars); platform.tfvars carries the network IDs."
    }
    postcondition {
      condition     = var.network_mode != "alz_spoke" || var.alz_spoke != null
      error_message = "network_mode = \"alz_spoke\" needs alz_spoke = { vended_vnet_id, hub_firewall_ip }."
    }
  }
}

# greenfield: VNet + subnets + NSGs (+ APIM route table for classic injection).
# alz_spoke:  subnets + NSGs + UDR (0.0.0.0/0 -> hub firewall) in the vended VNet.
# Subnet names and NSG rules are the same in both modes.
module "networking" {
  source = "../../modules/networking"

  resource_group_name = data.azurerm_resource_group.workload.name
  subscription_id     = var.subscription_id
  location            = var.location
  tags                = local.tags
  enable_telemetry    = var.enable_telemetry

  default_outbound_access_enabled = coalesce(var.default_outbound_access, local.greenfield)
  existing_vnet_id                = local.greenfield ? null : try(var.alz_spoke.vended_vnet_id, null)
  hub_firewall_ip                 = local.greenfield ? null : try(var.alz_spoke.hub_firewall_ip, null)

  vnet_name           = local.names.virtual_network
  vnet_address_prefix = var.address_space
  apim_vnet_mode      = var.apim_vnet_mode

  apim_subnet_name        = local.names.subnet_apim
  apim_subnet_prefix      = local.prefixes.apim
  pe_subnet_name          = local.names.subnet_pe
  pe_subnet_prefix        = local.prefixes.pe
  enable_logic_app_subnet = var.subnets_enabled.logic_app
  logic_app_subnet_name   = local.names.subnet_logic_app
  logic_app_subnet_prefix = local.prefixes.logic_app
  enable_agent_subnet     = var.subnets_enabled.agent
  agent_subnet_name       = local.names.subnet_agent
  agent_subnet_prefix     = local.prefixes.agent
  enable_ase_subnet       = var.subnets_enabled.ase
  ase_subnet_name         = local.names.subnet_ase
  ase_subnet_prefix       = local.prefixes.ase
  enable_cicd_subnet      = var.subnets_enabled.cicd
  cicd_subnet_name        = local.names.subnet_cicd
  cicd_subnet_prefix      = local.prefixes.cicd
  cicd_subnet_delegation  = var.cicd_subnet_delegation
}

check "ase_subnet_is_24" {
  assert {
    condition     = !var.subnets_enabled.ase || endswith(local.prefixes.ase, "/24")
    error_message = "The ASE v3 subnet should be a /24 (it can't be resized later)."
  }
}
