# app-hosting

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
| <a name="module_app_hosting"></a> [app\_hosting](#module\_app\_hosting) | ../../modules/app-hosting | n/a |
| <a name="module_naming"></a> [naming](#module\_naming) | ../../modules/naming | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_subnet.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subnet) | data source |
| [azurerm_virtual_network.greenfield](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/virtual_network) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region (e.g. swedencentral). | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID. | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_ase"></a> [ase](#input\_ase) | App Service Environment v3 for the keyless usage pipeline (Logic App on Isolated v2).<br/>  subnet\_id                     alz\_spoke/byo: the dedicated /24 subnet (delegated to Microsoft.Web/hostingEnvironments).<br/>                                greenfield: null = snet-ase in the greenfield VNet.<br/>  internal\_load\_balancing\_mode  "Web, Publishing" (ILB; required in Corp by AseDenyPublicIP) or "None".<br/>  zone\_redundant                Spread the ASE across availability zones (prod). | <pre>object({<br/>    subnet_id                    = optional(string)<br/>    internal_load_balancing_mode = optional(string, "Web, Publishing")<br/>    zone_redundant               = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_dns"></a> [dns](#input\_dns) | Private DNS zone <ase>.appserviceenvironment.net (ILB only).<br/>  create         false = the zone is managed elsewhere (e.g. the hub).<br/>  vnet\_link\_ids  name => VNet ID to link the zone to. greenfield: null = the greenfield VNet.<br/>                 alz\_spoke: the spoke VNet (+ the hub / DNS resolver VNet). | <pre>object({<br/>    create        = optional(bool, true)<br/>    vnet_link_ids = optional(map(string))<br/>  })</pre> | `{}` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo. | `bool` | `true` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | Naming inputs shared by all stacks (modules/naming, docs/naming.md).<br/>  unique\_seed     5 lowercase letters/digits; null = derived from subscription\_id, workload and environment.<br/>  name\_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }). | <pre>object({<br/>    unique_seed    = optional(string)<br/>    name_overrides = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.<br/>alz\_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.<br/>byo         no network stack; platform.tfvars carries all IDs. | `string` | `"greenfield"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource (merged with workload, environment, stack and managed-by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_service_environment_id"></a> [app\_service\_environment\_id](#output\_app\_service\_environment\_id) | Resource ID of the ASE v3 (platform finds it by name; a shared ASE is passed as usage\_pipeline.ase.app\_service\_environment\_id). |
| <a name="output_app_service_environment_name"></a> [app\_service\_environment\_name](#output\_app\_service\_environment\_name) | Name of the ASE v3. |
| <a name="output_dns_suffix"></a> [dns\_suffix](#output\_dns\_suffix) | Default domain of the ASE (<name>.appserviceenvironment.net). |
| <a name="output_internal_inbound_ip_addresses"></a> [internal\_inbound\_ip\_addresses](#output\_internal\_inbound\_ip\_addresses) | Internal inbound IPs of the ILB ASE (the private DNS records point here). |
<!-- END_TF_DOCS -->
