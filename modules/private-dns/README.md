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
| [azurerm_private_dns_zone.zones](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.links](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group for the private DNS zones and VNet links. | `string` | n/a | yes |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | Resource ID of the VNet the created zones are linked to. | `string` | n/a | yes |
| <a name="input_create_zones"></a> [create\_zones](#input\_create\_zones) | Create the private DNS zones and link them to the VNet. false = use existing\_zone\_ids only. | `bool` | `true` | no |
| <a name="input_existing_zone_ids"></a> [existing\_zone\_ids](#input\_existing\_zone\_ids) | Existing zone key => private DNS zone resource ID. Accepts snake\_case keys and the Bicep camelCase keys (keyVault, cosmosDb, ...). Overrides a created zone with the same key. | `map(string)` | `{}` | no |
| <a name="input_link_monitor_zone"></a> [link\_monitor\_zone](#input\_link\_monitor\_zone) | Link privatelink.monitor.azure.com to the VNet. Only true when AMPLS is deployed: an empty linked monitor zone blackholes App Insights ingestion DNS. | `bool` | `false` | no |
| <a name="input_required_zone_keys"></a> [required\_zone\_keys](#input\_required\_zone\_keys) | Zone keys the caller dereferences (e.g. key\_vault, cosmos\_db). Planning fails with a clear message when one is neither created nor supplied in existing\_zone\_ids. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the private DNS zones. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_zone_ids"></a> [zone\_ids](#output\_zone\_ids) | Zone key (snake\_case) => private DNS zone resource ID.<br/>Created zones first, then existing\_zone\_ids (camelCase keys normalised to<br/>snake\_case) on top, so a partial BYO set overrides individual created zones. |
<!-- END_TF_DOCS -->