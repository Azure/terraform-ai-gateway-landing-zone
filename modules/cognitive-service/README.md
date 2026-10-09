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
| <a name="module_account"></a> [account](#module\_account) | Azure/avm-res-cognitiveservices-account/azurerm | 0.11.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource_action.diagnostics](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource_action) | resource |
| [azurerm_role_assignment.apim_cognitive_services_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_principal_id"></a> [apim\_principal\_id](#input\_apim\_principal\_id) | Principal ID of the APIM user-assigned identity (gets Cognitive Services User). | `string` | n/a | yes |
| <a name="input_kind"></a> [kind](#input\_kind) | Account kind: TextAnalytics (Language service) or ContentSafety. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region (the service must be available there). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Account name (2-64 characters; also the custom subdomain unless custom\_subdomain is set). | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource ID of the workload resource group. | `string` | n/a | yes |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | SKU: S for TextAnalytics (Language, standard), S0 for ContentSafety. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subnet for the private endpoint. | `string` | n/a | yes |
| <a name="input_allowed_ip_rules"></a> [allowed\_ip\_rules](#input\_allowed\_ip\_rules) | Public IPs / CIDRs allowed through the firewall when public access is enabled. | `set(string)` | `[]` | no |
| <a name="input_custom_subdomain"></a> [custom\_subdomain](#input\_custom\_subdomain) | Custom subdomain (the endpoint host); "" = the account name. | `string` | `""` | no |
| <a name="input_disable_key_auth"></a> [disable\_key\_auth](#input\_disable\_key\_auth) | true (default): only Entra ID auth is allowed; the gateway uses its managed identity and no key is issued. | `bool` | `true` | no |
| <a name="input_dns_zone_group_managed_by_policy"></a> [dns\_zone\_group\_managed\_by\_policy](#input\_dns\_zone\_group\_managed\_by\_policy) | Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone. | `bool` | `false` | no |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Resource ID of privatelink.cognitiveservices.azure.com ("" = no zone group, e.g. policy-managed). | `string` | `""` | no |
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Create the AllMetrics diagnostic setting (false when Azure Policy owns it). | `bool` | `true` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_log_analytics_id"></a> [log\_analytics\_id](#input\_log\_analytics\_id) | Log Analytics workspace for the diagnostic setting. | `string` | `""` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Public network access to the account. false = private endpoint only. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the account and its private endpoint. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_diagnostic_setting_name"></a> [diagnostic\_setting\_name](#output\_diagnostic\_setting\_name) | Workload diagnostic setting name (null when policy owns diagnostics). |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Base endpoint (https://<custom subdomain>.cognitiveservices.azure.com/), the same shape APIM already uses for Foundry accounts. |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the account. |
| <a name="output_name"></a> [name](#output\_name) | Account name. |
<!-- END_TF_DOCS -->