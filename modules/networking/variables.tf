variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "use_existing_vnet" { type = bool }
variable "existing_vnet_rg" { type = string }
variable "vnet_name" { type = string }
variable "vnet_address_prefix" { type = string }
variable "apim_subnet_name" { type = string }
variable "apim_subnet_prefix" { type = string }
variable "pe_subnet_name" { type = string }
variable "pe_subnet_prefix" { type = string }
variable "logic_app_subnet_name" { type = string }
variable "logic_app_subnet_prefix" { type = string }
variable "enable_agent_subnet" { type = bool }
variable "agent_subnet_name" { type = string }
variable "agent_subnet_prefix" { type = string }
variable "enable_ase_subnet" {
  type    = bool
  default = false
}
variable "ase_subnet_name" {
  type    = string
  default = "snet-citadel-ase"
}
variable "ase_subnet_prefix" {
  type    = string
  default = "10.170.1.0/24"
}
variable "apim_network_type" { type = string }
variable "is_apim_vnet" { type = bool }

# V2 SKUs (StandardV2/PremiumV2) use outbound VNet integration: the APIM subnet
# is delegated to Microsoft.Web/serverFarms (Bicep parity).
variable "is_apim_v2" {
  type    = bool
  default = false
}
variable "create_dns_zones" { type = bool }

# When AMPLS (Azure Monitor Private Link Scope) is NOT enabled, the
# privatelink.monitor.azure.com zone must NOT be linked to the VNet: an empty
# linked zone hijacks and blackholes App Insights / Azure Monitor ingestion DNS
# for every resource in the VNet (APIM gateway, Logic App, etc.), silently
# breaking all Application Insights telemetry while Log Analytics keeps working.
variable "use_azure_monitor_private_link_scope" {
  type    = bool
  default = false
}
variable "dns_zone_rg" { type = string }
variable "dns_subscription_id" { type = string }
variable "existing_private_dns_zones" { type = map(string) }
