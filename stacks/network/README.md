# network

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.12 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.81 |
| <a name="requirement_modtm"></a> [modtm](#requirement\_modtm) | ~> 0.3 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.5 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.81 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_naming"></a> [naming](#module\_naming) | ../../modules/naming | n/a |
| <a name="module_networking"></a> [networking](#module\_networking) | ../../modules/networking | n/a |
| <a name="module_private_dns"></a> [private\_dns](#module\_private\_dns) | ../../modules/private-dns | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_resource_group.workload](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region (e.g. swedencentral). | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID. | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | Greenfield: the VNet address space. alz\_spoke: the range allocated to this workload in the vended VNet (only used to carve default subnet prefixes). At least /22 so the ASE /24 fits. | `string` | `"10.170.0.0/22"` | no |
| <a name="input_alz_spoke"></a> [alz\_spoke](#input\_alz\_spoke) | alz\_spoke only: the VNet created by subscription vending and the hub firewall's private IP (UDR next hop for 0.0.0.0/0). | <pre>object({<br/>    vended_vnet_id  = string<br/>    hub_firewall_ip = string<br/>  })</pre> | `null` | no |
| <a name="input_apim_vnet_mode"></a> [apim\_vnet\_mode](#input\_apim\_vnet\_mode) | Must equal apim.vnet\_mode in platform.tfvars: drives the APIM subnet (none = no subnet), its delegation, NSG rules and route table. | `string` | `"none"` | no |
| <a name="input_cicd_subnet_delegation"></a> [cicd\_subnet\_delegation](#input\_cicd\_subnet\_delegation) | github = delegate snet-cicd to GitHub.Network/networkSettings (GitHub-hosted runners with Azure private networking); none = self-hosted runner VM. | `string` | `"github"` | no |
| <a name="input_default_outbound_access"></a> [default\_outbound\_access](#input\_default\_outbound\_access) | Default outbound internet access on the subnets. null = true for greenfield (no other egress path), false for alz\_spoke (egress through the hub firewall). | `bool` | `null` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo. | `bool` | `true` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | Naming inputs shared by all stacks (modules/naming, docs/naming.md).<br/>  unique\_seed     5 lowercase letters/digits; null = derived from subscription\_id, workload and environment.<br/>  name\_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }). | <pre>object({<br/>    unique_seed    = optional(string)<br/>    name_overrides = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.<br/>alz\_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.<br/>byo         no network stack; platform.tfvars carries all IDs. | `string` | `"greenfield"` | no |
| <a name="input_private_dns"></a> [private\_dns](#input\_private\_dns) | Greenfield private DNS zones (alz\_spoke: the hub owns them, nothing is created).<br/>  link\_monitor\_zone    Link privatelink.monitor.azure.com: only when platform deploys AMPLS.<br/>  extra\_vnet\_link\_ids  name => VNet ID to link every zone to as well (e.g. a runner or jump-box VNet). | <pre>object({<br/>    link_monitor_zone   = optional(bool, false)<br/>    extra_vnet_link_ids = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_subnet_prefixes"></a> [subnet\_prefixes](#input\_subnet\_prefixes) | Subnet CIDRs; a null attribute falls back to the default carve of address\_space (locals.tf). | <pre>object({<br/>    apim      = optional(string) # classic: >= /29 (/27 recommended); v2 injection/integration: >= /27 (/24 recommended)<br/>    pe        = optional(string) # /26<br/>    logic_app = optional(string) # /26, Workflow Standard hosting only<br/>    agent     = optional(string) # /24 recommended for Foundry agent injection<br/>    ase       = optional(string) # /24, delegated to Microsoft.Web/hostingEnvironments<br/>    cicd      = optional(string) # /27, private CI runners<br/>  })</pre> | `{}` | no |
| <a name="input_subnets_enabled"></a> [subnets\_enabled](#input\_subnets\_enabled) | Optional subnets. The APIM subnet follows apim\_vnet\_mode; the private endpoint subnet is always created. | <pre>object({<br/>    logic_app = optional(bool, false) # usage_pipeline.logic_app.hosting = workflow_standard<br/>    agent     = optional(bool, true)  # Foundry agent network injection<br/>    ase       = optional(bool, true)  # app-hosting (ASE v3) in this VNet<br/>    cicd      = optional(bool, true)  # private runners<br/>  })</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource (merged with workload, environment, stack and managed-by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ase_subnet_id"></a> [ase\_subnet\_id](#output\_ase\_subnet\_id) | app-hosting ase.subnet\_id for alz\_spoke (greenfield looks it up). null when no ASE subnet is created. |
| <a name="output_platform_network"></a> [platform\_network](#output\_platform\_network) | alz\_spoke: paste into platform.tfvars as `network` (add the hub's private\_dns\_zone\_ids when Terraform binds them). Greenfield doesn't need it: platform looks everything up. |
| <a name="output_private_dns_zone_ids"></a> [private\_dns\_zone\_ids](#output\_private\_dns\_zone\_ids) | Greenfield: logical zone key => private DNS zone ID ({} in alz\_spoke: the hub owns the zones). |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Subnet key (apim, pe, logic\_app, agent, ase, cicd) => resource ID. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | Resource ID of the gateway VNet (greenfield) or the vended VNet (alz\_spoke). |
<!-- END_TF_DOCS -->
