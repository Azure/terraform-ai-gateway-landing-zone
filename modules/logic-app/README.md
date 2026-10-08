# Usage ingestion Logic App

Creates the Standard Logic App that moves usage events from Event Hubs into Cosmos DB: runtime storage and private endpoints, the plan (Workflow Standard or App Service Environment v3), the site, the Azure Monitor API connection and the workflow code deployment.

This module is called by the root configuration (`main.tf`). It configures no providers; the caller passes them in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.5, < 3.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9, < 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.2, < 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_archive"></a> [archive](#provider\_archive) | >= 2.5, < 3.0 |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.9, < 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |
| <a name="provider_null"></a> [null](#provider\_null) | >= 3.2, < 4.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_service_plan"></a> [service\_plan](#module\_service\_plan) | Azure/avm-res-web-serverfarm/azurerm | 2.0.8 |
| <a name="module_storage"></a> [storage](#module\_storage) | Azure/avm-res-storage-storageaccount/azurerm | 0.10.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.azuremonitor_connection](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.azuremonitor_connection_access](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.usage_ingestion_ase](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_app_service_environment_v3.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/app_service_environment_v3) | resource |
| [azurerm_cosmosdb_sql_role_assignment.logic_app_system_mi](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_sql_role_assignment) | resource |
| [azurerm_logic_app_standard.usage_ingestion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/logic_app_standard) | resource |
| [azurerm_monitor_diagnostic_setting.logic_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_dns_a_record.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_a_record) | resource |
| [azurerm_private_dns_zone.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.ase](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_endpoint.storage_blob](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.storage_file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.storage_queue](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.storage_table](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.logic_app_system_eh_owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.logic_app_system_monitor_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.storage_account_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.storage_blob_owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.storage_queue_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.storage_table_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [null_resource.publish_workflows](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [archive_file.workflow_code](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_storage_account.logic_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/storage_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_insights_connection_string"></a> [app\_insights\_connection\_string](#input\_app\_insights\_connection\_string) | Application Insights connection string for the Logic App. | `string` | n/a | yes |
| <a name="input_cosmos_db_endpoint"></a> [cosmos\_db\_endpoint](#input\_cosmos\_db\_endpoint) | Cosmos DB account endpoint the workflows write to. | `string` | n/a | yes |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name used for resource naming (e.g., citadel-dev, citadel-prod) | `string` | n/a | yes |
| <a name="input_eventhub_endpoint_host"></a> [eventhub\_endpoint\_host](#input\_eventhub\_endpoint\_host) | EventHub namespace FQDN (e.g. evhns-xxx.servicebus.windows.net) | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_managed_identity_client_id"></a> [managed\_identity\_client\_id](#input\_managed\_identity\_client\_id) | Client ID of the user-assigned managed identity the service runs as. | `string` | n/a | yes |
| <a name="input_managed_identity_id"></a> [managed\_identity\_id](#input\_managed\_identity\_id) | Resource ID of the user-assigned managed identity the service runs as. | `string` | n/a | yes |
| <a name="input_managed_identity_principal_id"></a> [managed\_identity\_principal\_id](#input\_managed\_identity\_principal\_id) | Principal (object) ID of the user-assigned managed identity that is granted data-plane roles. | `string` | n/a | yes |
| <a name="input_names"></a> [names](#input\_names) | Resource names from modules/naming. | <pre>object({<br/>    storage_account         = string<br/>    logic_app               = string<br/>    content_share           = string<br/>    app_service_plan        = string<br/>    app_service_environment = string<br/>    code_artifact           = string<br/>  })</pre> | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource ID of the resource group (scope of the Event Hubs Data Owner and Monitoring Reader assignments). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_sku_size"></a> [sku\_size](#input\_sku\_size) | Logic App (Standard) SKU size. Used only when logic\_app\_hosting\_model = "WorkflowStandard". | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Resource ID of the subnet used for regional VNet integration (Workflow Standard hosting). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_apim_app_insights_name"></a> [apim\_app\_insights\_name](#input\_apim\_app\_insights\_name) | Name of the APIM-side Application Insights (AppSettings AppInsights\_Name). | `string` | `""` | no |
| <a name="input_apim_app_insights_rg"></a> [apim\_app\_insights\_rg](#input\_apim\_app\_insights\_rg) | Resource group of the APIM-side Application Insights. | `string` | `""` | no |
| <a name="input_ase_create_private_dns_zone"></a> [ase\_create\_private\_dns\_zone](#input\_ase\_create\_private\_dns\_zone) | For an internal (ILB) ASE v3, create the <ase>.appserviceenvironment.net private DNS zone (*, *.scm, @ records) and link it to the VNet. Set false when DNS is managed centrally (hub). | `bool` | `true` | no |
| <a name="input_ase_internal_load_balancing_mode"></a> [ase\_internal\_load\_balancing\_mode](#input\_ase\_internal\_load\_balancing\_mode) | ASE v3 ingress: "Web, Publishing" (internal/ILB — app and SCM endpoints reachable only from the VNet) or "None" (external, public VIP). | `string` | `"Web, Publishing"` | no |
| <a name="input_ase_sku_size"></a> [ase\_sku\_size](#input\_ase\_sku\_size) | Isolated v2 App Service plan SKU for the Logic App when logic\_app\_hosting\_model = "AppServiceEnvironmentV3". | `string` | `"I1v2"` | no |
| <a name="input_ase_subnet_id"></a> [ase\_subnet\_id](#input\_ase\_subnet\_id) | Dedicated subnet (delegated to Microsoft.Web/hostingEnvironments) for the ASE v3. | `string` | `""` | no |
| <a name="input_ase_worker_count"></a> [ase\_worker\_count](#input\_ase\_worker\_count) | Number of Isolated v2 instances for the Logic App plan inside the ASE v3. | `number` | `1` | no |
| <a name="input_ase_zone_redundant"></a> [ase\_zone\_redundant](#input\_ase\_zone\_redundant) | Deploy the ASE v3 as zone redundant (region must support availability zones; increases minimum billed instances). | `bool` | `false` | no |
| <a name="input_code_source_path"></a> [code\_source\_path](#input\_code\_source\_path) | Absolute path to the Logic App Standard project folder. Leave blank to skip when enable\_code\_deploy=false. | `string` | `"src/usage-ingestion-logicapp"` | no |
| <a name="input_content_share_name"></a> [content\_share\_name](#input\_content\_share\_name) | Logic App content share (WEBSITE\_CONTENTSHARE). Leave blank to auto-derive. | `string` | `""` | no |
| <a name="input_cosmos_db_account_id"></a> [cosmos\_db\_account\_id](#input\_cosmos\_db\_account\_id) | Cosmos DB account ID for SQL role assignment on Logic App system-assigned principal. | `string` | `""` | no |
| <a name="input_cosmos_db_account_name"></a> [cosmos\_db\_account\_name](#input\_cosmos\_db\_account\_name) | Cosmos DB account name (for AppSettings CosmosDBAccount). | `string` | `""` | no |
| <a name="input_cosmos_db_container_config"></a> [cosmos\_db\_container\_config](#input\_cosmos\_db\_container\_config) | Cosmos DB container holding configuration documents (model pricing, ...). | `string` | `""` | no |
| <a name="input_cosmos_db_container_llm_usage"></a> [cosmos\_db\_container\_llm\_usage](#input\_cosmos\_db\_container\_llm\_usage) | Cosmos DB container for LLM usage records. | `string` | `""` | no |
| <a name="input_cosmos_db_container_pii"></a> [cosmos\_db\_container\_pii](#input\_cosmos\_db\_container\_pii) | Cosmos DB container for PII usage records. | `string` | `""` | no |
| <a name="input_cosmos_db_container_usage"></a> [cosmos\_db\_container\_usage](#input\_cosmos\_db\_container\_usage) | Cosmos DB container for AI usage records. | `string` | `""` | no |
| <a name="input_cosmos_db_database_name"></a> [cosmos\_db\_database\_name](#input\_cosmos\_db\_database\_name) | Cosmos DB database that holds the usage containers. | `string` | `""` | no |
| <a name="input_create_azuremonitor_api_connection"></a> [create\_azuremonitor\_api\_connection](#input\_create\_azuremonitor\_api\_connection) | Create the Logic App 'azuremonitorlogs' API connection and grant access to the system-assigned MI. | `bool` | `true` | no |
| <a name="input_dns_zone_id_blob"></a> [dns\_zone\_id\_blob](#input\_dns\_zone\_id\_blob) | Resource ID of the privatelink.blob.core.windows.net DNS zone for the storage private endpoint. | `string` | `""` | no |
| <a name="input_dns_zone_id_file"></a> [dns\_zone\_id\_file](#input\_dns\_zone\_id\_file) | Resource ID of the privatelink.file.core.windows.net DNS zone for the storage private endpoint. | `string` | `""` | no |
| <a name="input_dns_zone_id_queue"></a> [dns\_zone\_id\_queue](#input\_dns\_zone\_id\_queue) | Resource ID of the privatelink.queue.core.windows.net DNS zone for the storage private endpoint. | `string` | `""` | no |
| <a name="input_dns_zone_id_table"></a> [dns\_zone\_id\_table](#input\_dns\_zone\_id\_table) | Resource ID of the privatelink.table.core.windows.net DNS zone for the storage private endpoint. | `string` | `""` | no |
| <a name="input_enable_code_deploy"></a> [enable\_code\_deploy](#input\_enable\_code\_deploy) | If true, zip and publish the Logic App Standard project folder (src/usage-ingestion-logicapp) as part of apply. | `bool` | `true` | no |
| <a name="input_enable_cosmos_role_assignment"></a> [enable\_cosmos\_role\_assignment](#input\_enable\_cosmos\_role\_assignment) | Whether to create the Cosmos SQL role assignment for the Logic App system MI. Must be known at plan time. | `bool` | `true` | no |
| <a name="input_enable_storage_private_endpoints"></a> [enable\_storage\_private\_endpoints](#input\_enable\_storage\_private\_endpoints) | Whether to create private endpoints for the Logic App storage account (blob/file/table/queue). Must be known at plan time. | `bool` | `true` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_eventhub_ai_usage_hub_name"></a> [eventhub\_ai\_usage\_hub\_name](#input\_eventhub\_ai\_usage\_hub\_name) | Name of the Event Hub carrying AI usage events. | `string` | `""` | no |
| <a name="input_eventhub_pii_usage_hub_name"></a> [eventhub\_pii\_usage\_hub\_name](#input\_eventhub\_pii\_usage\_hub\_name) | Name of the Event Hub carrying PII usage events. | `string` | `""` | no |
| <a name="input_hosting_model"></a> [hosting\_model](#input\_hosting\_model) | WorkflowStandard (WS plan + VNet integration, key-based storage) or AppServiceEnvironmentV3 (Isolated v2 plan in an ASE v3, keyless storage). | `string` | `"WorkflowStandard"` | no |
| <a name="input_log_analytics_id"></a> [log\_analytics\_id](#input\_log\_analytics\_id) | Resource ID of the Log Analytics workspace that receives diagnostic settings. | `string` | `""` | no |
| <a name="input_pe_subnet_id"></a> [pe\_subnet\_id](#input\_pe\_subnet\_id) | Private-endpoint subnet ID for the storage account (blob/file/table/queue PEs). | `string` | `""` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure Subscription ID for the deployment | `string` | `""` | no |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | VNet ID used to link the ASE private DNS zone. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_service_environment_id"></a> [app\_service\_environment\_id](#output\_app\_service\_environment\_id) | Resource ID of the App Service Environment v3 (null when not ASE-hosted). |
| <a name="output_logic_app_id"></a> [logic\_app\_id](#output\_logic\_app\_id) | Resource ID of the usage-ingestion Logic App. |
| <a name="output_logic_app_name"></a> [logic\_app\_name](#output\_logic\_app\_name) | Name of the usage-ingestion Logic App. |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | Name of the Logic App runtime storage account. |
<!-- END_TF_DOCS -->
