# Private DNS

Creates the `privatelink.*` zones the gateway's private endpoints use (`zone_names`, from the naming module) and links each one to the gateway VNet and to any extra VNets (`extra_vnet_link_ids`, for example a runner or jump-box VNet). Zones are created in greenfield only; in an Azure Landing Zone the connectivity hub owns them.

`privatelink.monitor.azure.com` is linked only with `link_monitor_zone`, which is for environments that deploy the Azure Monitor Private Link Scope: an empty linked monitor zone would resolve Application Insights ingestion to nothing from inside the VNet.

Called by [stacks/network](../../stacks/network/private-dns.tf); the caller passes the providers in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_zone"></a> [zone](#module\_zone) | Azure/avm-res-network-privatednszone/azurerm | 0.5.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource group for the private DNS zones. | `string` | n/a | yes |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | Resource ID of the VNet the zones are linked to. | `string` | n/a | yes |
| <a name="input_zone_names"></a> [zone\_names](#input\_zone\_names) | Logical key => private DNS zone name (modules/naming private\_dns\_zones). | `map(string)` | n/a | yes |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_extra_vnet_link_ids"></a> [extra\_vnet\_link\_ids](#input\_extra\_vnet\_link\_ids) | Additional VNets to link every zone to (name => VNet resource ID), e.g. a runner or jump-box VNet. | `map(string)` | `{}` | no |
| <a name="input_link_monitor_zone"></a> [link\_monitor\_zone](#input\_link\_monitor\_zone) | Link the Azure Monitor zones (privatelink.monitor.azure.com, and the oms / ods / agentsvc zones when passed) to the VNets. Only true when AMPLS is deployed: an empty linked monitor zone blackholes App Insights ingestion DNS. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the private DNS zones. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_zone_ids"></a> [zone\_ids](#output\_zone\_ids) | Logical key => private DNS zone resource ID. |
<!-- END_TF_DOCS -->