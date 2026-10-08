# Networking

Creates (or looks up) the virtual network, the APIM, private-endpoint, Logic App, agent and ASE subnets, their NSGs and route table, and the private DNS zones with VNet links.

This module is called by the root configuration (`main.tf`). It configures no providers; the caller passes them in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_network_security_group.agent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_group.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_group.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_group.logic_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_group.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_route_table.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table) | resource |
| [azurerm_subnet.agent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.logic_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.agent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.logic_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_route_table_association.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_virtual_network.citadel](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_agent_subnet_name"></a> [agent\_subnet\_name](#input\_agent\_subnet\_name) | Name of the Foundry agent subnet. | `string` | n/a | yes |
| <a name="input_agent_subnet_prefix"></a> [agent\_subnet\_prefix](#input\_agent\_subnet\_prefix) | Address prefix (CIDR) of the Foundry agent subnet. | `string` | n/a | yes |
| <a name="input_apim_network_type"></a> [apim\_network\_type](#input\_apim\_network\_type) | APIM network type: 'External', 'Internal', or 'None' | `string` | n/a | yes |
| <a name="input_apim_subnet_name"></a> [apim\_subnet\_name](#input\_apim\_subnet\_name) | APIM subnet name | `string` | n/a | yes |
| <a name="input_apim_subnet_prefix"></a> [apim\_subnet\_prefix](#input\_apim\_subnet\_prefix) | APIM subnet address prefix (for new VNet) | `string` | n/a | yes |
| <a name="input_enable_agent_subnet"></a> [enable\_agent\_subnet](#input\_enable\_agent\_subnet) | Create a dedicated subnet for Foundry Agent Service network injection. | `bool` | n/a | yes |
| <a name="input_is_apim_vnet"></a> [is\_apim\_vnet](#input\_is\_apim\_vnet) | True when APIM uses classic VNet injection (External/Internal); adds the APIM route table and NSG rules. | `bool` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_logic_app_subnet_name"></a> [logic\_app\_subnet\_name](#input\_logic\_app\_subnet\_name) | Logic App / Function App subnet name | `string` | n/a | yes |
| <a name="input_logic_app_subnet_prefix"></a> [logic\_app\_subnet\_prefix](#input\_logic\_app\_subnet\_prefix) | Logic App subnet address prefix (for new VNet) | `string` | n/a | yes |
| <a name="input_pe_subnet_name"></a> [pe\_subnet\_name](#input\_pe\_subnet\_name) | Private endpoint subnet name | `string` | n/a | yes |
| <a name="input_pe_subnet_prefix"></a> [pe\_subnet\_prefix](#input\_pe\_subnet\_prefix) | Private endpoint subnet address prefix (for new VNet) | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_vnet_address_prefix"></a> [vnet\_address\_prefix](#input\_vnet\_address\_prefix) | Address prefix for new VNet | `string` | n/a | yes |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | Name of the virtual network to create. | `string` | n/a | yes |
| <a name="input_ase_subnet_name"></a> [ase\_subnet\_name](#input\_ase\_subnet\_name) | Subnet for the App Service Environment v3 (only used when logic\_app\_hosting\_model = "AppServiceEnvironmentV3"). Must be empty and delegated to Microsoft.Web/hostingEnvironments when using an existing VNet. | `string` | `"snet-citadel-ase"` | no |
| <a name="input_ase_subnet_prefix"></a> [ase\_subnet\_prefix](#input\_ase\_subnet\_prefix) | Address prefix for the ASE v3 subnet (new VNet only). Minimum /27; Microsoft recommends /24 for production scale. If this range is not inside vnet\_address\_prefix it is added to the VNet as an extra address space. | `string` | `"10.170.1.0/24"` | no |
| <a name="input_enable_ase_subnet"></a> [enable\_ase\_subnet](#input\_enable\_ase\_subnet) | Create the dedicated /24 subnet for App Service Environment v3 (Logic App ASE hosting). | `bool` | `false` | no |
| <a name="input_is_apim_v2"></a> [is\_apim\_v2](#input\_is\_apim\_v2) | True when the APIM SKU is a v2 SKU (BasicV2, StandardV2 or PremiumV2). | `bool` | `false` | no |
| <a name="input_nsg_on_all_subnets"></a> [nsg\_on\_all\_subnets](#input\_nsg\_on\_all\_subnets) | Also attach NSGs to the private-endpoint and Logic App subnets (Azure Landing Zone Deny-Subnet-Without-Nsg). | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_agent_subnet_id"></a> [agent\_subnet\_id](#output\_agent\_subnet\_id) | Resource ID of the Foundry agent subnet (empty when disabled). |
| <a name="output_agent_subnet_name"></a> [agent\_subnet\_name](#output\_agent\_subnet\_name) | Name of the Foundry agent subnet (empty when disabled). |
| <a name="output_apim_subnet_id"></a> [apim\_subnet\_id](#output\_apim\_subnet\_id) | Resource ID of the APIM subnet. |
| <a name="output_ase_subnet_id"></a> [ase\_subnet\_id](#output\_ase\_subnet\_id) | Resource ID of the ASE v3 subnet (empty when disabled). |
| <a name="output_logic_app_subnet_id"></a> [logic\_app\_subnet\_id](#output\_logic\_app\_subnet\_id) | Resource ID of the Logic App integration subnet. |
| <a name="output_pe_subnet_id"></a> [pe\_subnet\_id](#output\_pe\_subnet\_id) | Resource ID of the private-endpoint subnet. |
| <a name="output_subnet_nsg_names"></a> [subnet\_nsg\_names](#output\_subnet\_nsg\_names) | Names of the NSGs attached to the private-endpoint and Logic App subnets (null when nsg\_on\_all\_subnets = false). |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | Resource ID of the virtual network . |
<!-- END_TF_DOCS -->
