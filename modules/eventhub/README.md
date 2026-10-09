# Event Hubs (usage events)

Creates the Event Hubs namespace (local auth disabled), the AI-usage and PII-usage hubs and their consumer groups, the private endpoint, diagnostics and the sender/receiver role assignments.

This module is called by the root configuration (`main.tf`). It configures no providers; the caller passes them in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9, < 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.9, < 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_namespace"></a> [namespace](#module\_namespace) | Azure/avm-res-eventhub-namespace/azurerm | 0.1.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource_action.eventhub_diagnostics](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource_action) | resource |
| [azapi_update_resource.network_rule_set](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_eventhub_consumer_group.ai_usage_ingestion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_consumer_group) | resource |
| [azurerm_eventhub_consumer_group.pii_usage_ingestion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_consumer_group) | resource |
| [azurerm_eventhub_namespace_disaster_recovery_config.pairing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_namespace_disaster_recovery_config) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_identity_principal_id"></a> [apim\_identity\_principal\_id](#input\_apim\_identity\_principal\_id) | Principal ID of the APIM managed identity granted Azure Event Hubs Data Sender. | `string` | n/a | yes |
| <a name="input_capacity_units"></a> [capacity\_units](#input\_capacity\_units) | Event Hub capacity units | `number` | n/a | yes |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Resource ID of the privatelink.servicebus.windows.net DNS zone (empty = no DNS zone group). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_namespace_name"></a> [namespace\_name](#input\_namespace\_name) | Name of the Event Hubs namespace. | `string` | n/a | yes |
| <a name="input_public_network_access"></a> [public\_network\_access](#input\_public\_network\_access) | Event Hub public network access: Enabled or Disabled | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Resource ID of the subnet that hosts the private endpoint. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_usage_identity_principal_id"></a> [usage\_identity\_principal\_id](#input\_usage\_identity\_principal\_id) | Principal ID of the usage-pipeline identity granted Azure Event Hubs Data Receiver. | `string` | n/a | yes |
| <a name="input_disaster_recovery_config"></a> [disaster\_recovery\_config](#input\_disaster\_recovery\_config) | Optional disaster recovery pairing. Set to `null` (default) to skip.<br/>When provided, must contain:<br/>  - partner\_namespace\_id: full resource ID of the partner EH namespace<br/>  - alias: optional alias name (defaults to "default") | <pre>object({<br/>    partner_namespace_id = string<br/>    alias                = optional(string, "default")<br/>  })</pre> | `null` | no |
| <a name="input_dns_zone_group_managed_by_policy"></a> [dns\_zone\_group\_managed\_by\_policy](#input\_dns\_zone\_group\_managed\_by\_policy) | Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone. | `bool` | `false` | no |
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Configure the workload diagnostic setting by ARM PUT. false = Azure Policy owns diagnostics; leave its settings untouched. | `bool` | `true` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_log_analytics_id"></a> [log\_analytics\_id](#input\_log\_analytics\_id) | Resource ID of the Log Analytics workspace that receives diagnostic settings. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ai_usage_ingestion_cg"></a> [ai\_usage\_ingestion\_cg](#output\_ai\_usage\_ingestion\_cg) | Consumer group used by the AI usage ingestion workflow. |
| <a name="output_apim_usage_hub_name"></a> [apim\_usage\_hub\_name](#output\_apim\_usage\_hub\_name) | Name of the Event Hub that receives AI usage events from APIM. |
| <a name="output_diagnostic_setting_names"></a> [diagnostic\_setting\_names](#output\_diagnostic\_setting\_names) | Workload diagnostic setting names (empty when policy owns diagnostics). |
| <a name="output_endpoint_uri"></a> [endpoint\_uri](#output\_endpoint\_uri) | HTTPS endpoint of the Event Hubs namespace. |
| <a name="output_namespace_id"></a> [namespace\_id](#output\_namespace\_id) | Resource ID of the Event Hubs namespace. |
| <a name="output_namespace_name"></a> [namespace\_name](#output\_namespace\_name) | Name of the Event Hubs namespace. |
| <a name="output_pii_usage_hub_name"></a> [pii\_usage\_hub\_name](#output\_pii\_usage\_hub\_name) | Name of the Event Hub that receives PII usage events from APIM. |
| <a name="output_pii_usage_ingestion_cg"></a> [pii\_usage\_ingestion\_cg](#output\_pii\_usage\_ingestion\_cg) | Consumer group used by the PII usage ingestion workflow. |
<!-- END_TF_DOCS -->
