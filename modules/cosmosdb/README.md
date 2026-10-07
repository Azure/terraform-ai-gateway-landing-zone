# Cosmos DB (usage store)

Creates the serverless Cosmos DB account, the usage database and its containers (usage, LLM usage, PII, configuration, model pricing), the private endpoint, diagnostics and the data-plane role assignment for the usage-pipeline identity.

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
| [azurerm_cosmosdb_account.citadel](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_account) | resource |
| [azurerm_cosmosdb_sql_container.config](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_container) | resource |
| [azurerm_cosmosdb_sql_container.llm_usage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_container) | resource |
| [azurerm_cosmosdb_sql_container.model_pricing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_container) | resource |
| [azurerm_cosmosdb_sql_container.pii](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_container) | resource |
| [azurerm_cosmosdb_sql_container.usage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_container) | resource |
| [azurerm_cosmosdb_sql_database.usage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_database) | resource |
| [azurerm_cosmosdb_sql_role_assignment.uami_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_role_assignment) | resource |
| [azurerm_monitor_diagnostic_setting.cosmos](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_endpoint.cosmos](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_name"></a> [account\_name](#input\_account\_name) | Name of the Cosmos DB account. | `string` | n/a | yes |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Resource ID of the privatelink.documents.azure.com DNS zone (empty = no DNS zone group). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_managed_identity_principal_id"></a> [managed\_identity\_principal\_id](#input\_managed\_identity\_principal\_id) | Principal ID of the usage-pipeline identity granted the Cosmos DB Built-in Data Contributor role. | `string` | n/a | yes |
| <a name="input_public_network_access"></a> [public\_network\_access](#input\_public\_network\_access) | Cosmos DB public network access: Enabled or Disabled | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Resource ID of the subnet that hosts the private endpoint. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_local_authentication_enabled"></a> [local\_authentication\_enabled](#input\_local\_authentication\_enabled) | Allow key/connection-string auth on the Cosmos DB data plane. When false, only Entra ID (RBAC) is accepted. | `bool` | `false` | no |
| <a name="input_log_analytics_id"></a> [log\_analytics\_id](#input\_log\_analytics\_id) | Resource ID of the Log Analytics workspace that receives diagnostic settings. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Resource ID of the Cosmos DB account. |
| <a name="output_account_name"></a> [account\_name](#output\_account\_name) | Name of the Cosmos DB account. |
| <a name="output_config_container_name"></a> [config\_container\_name](#output\_config\_container\_name) | Name of the configuration container. |
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | Name of the usage database. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Cosmos DB account endpoint. |
| <a name="output_llm_usage_container_name"></a> [llm\_usage\_container\_name](#output\_llm\_usage\_container\_name) | Name of the LLM usage container. |
| <a name="output_model_pricing_container_name"></a> [model\_pricing\_container\_name](#output\_model\_pricing\_container\_name) | Name of the model pricing container. |
| <a name="output_pii_container_name"></a> [pii\_container\_name](#output\_pii\_container\_name) | Name of the PII usage container. |
| <a name="output_usage_container_name"></a> [usage\_container\_name](#output\_usage\_container\_name) | Name of the AI usage container. |
<!-- END_TF_DOCS -->
