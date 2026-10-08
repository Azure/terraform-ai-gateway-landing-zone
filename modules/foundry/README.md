# Microsoft Foundry

Creates the Foundry (AI Services) accounts, projects and model deployments, optional agent network injection, private endpoints, role assignments and the project connection to the APIM gateway.

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
| <a name="module_account"></a> [account](#module\_account) | Azure/avm-res-cognitiveservices-account/azurerm | 0.11.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.apim_connection](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.app_insights_connection](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.project](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_monitor_diagnostic_setting.foundry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_role_assignment.apim_cognitive_services_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.deployer_project_manager](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azapi_resource.account_state](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_names"></a> [account\_names](#input\_account\_names) | Foundry (AI Services) account names, one per entry in foundry\_instances (from modules/naming). | `list(string)` | n/a | yes |
| <a name="input_apim_principal_id"></a> [apim\_principal\_id](#input\_apim\_principal\_id) | Principal ID granted 'Cognitive Services User' on each Foundry (typically APIM UAMI). | `string` | n/a | yes |
| <a name="input_deployer_object_id"></a> [deployer\_object\_id](#input\_deployer\_object\_id) | Principal ID granted 'Azure AI Project Manager' on each Foundry (matches deployer() in Bicep). | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource ID of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subnet ID for private endpoints. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_agent_subnet_id"></a> [agent\_subnet\_id](#input\_agent\_subnet\_id) | Resource ID of the subnet used for Foundry agent network injection. | `string` | `""` | no |
| <a name="input_apim_connections"></a> [apim\_connections](#input\_apim\_connections) | Per-API APIM connection definitions (one connection per Foundry project × api). | <pre>list(object({<br/>    api_name               = string<br/>    api_path               = string<br/>    connection_name        = optional(string, "")<br/>    is_shared_to_all       = optional(bool, false)<br/>    deployment_in_path     = optional(string, "true")<br/>    inference_api_version  = optional(string, "")<br/>    deployment_api_version = optional(string, "")<br/>    list_models_endpoint   = optional(string, "")<br/>    get_model_endpoint     = optional(string, "")<br/>    deployment_provider    = optional(string, "")<br/>    static_models          = optional(list(any), [])<br/>    custom_headers         = optional(map(string), {})<br/>  }))</pre> | `[]` | no |
| <a name="input_apim_gateway_url"></a> [apim\_gateway\_url](#input\_apim\_gateway\_url) | APIM gateway URL (https://...). | `string` | `""` | no |
| <a name="input_apim_primary_key"></a> [apim\_primary\_key](#input\_apim\_primary\_key) | APIM master subscription primary key. | `string` | `""` | no |
| <a name="input_apim_service_name"></a> [apim\_service\_name](#input\_apim\_service\_name) | APIM service name (used to construct default connection names). | `string` | `""` | no |
| <a name="input_app_insights_id"></a> [app\_insights\_id](#input\_app\_insights\_id) | Application Insights resource ID for the Foundry App Insights connection. | `string` | `""` | no |
| <a name="input_app_insights_instrumentation_key"></a> [app\_insights\_instrumentation\_key](#input\_app\_insights\_instrumentation\_key) | Application Insights instrumentation key used by the Foundry App Insights connection. | `string` | `""` | no |
| <a name="input_disable_key_auth"></a> [disable\_key\_auth](#input\_disable\_key\_auth) | If true, only Entra ID auth is allowed (disableLocalAuth=true). | `bool` | `false` | no |
| <a name="input_dns_zone_group_managed_by_policy"></a> [dns\_zone\_group\_managed\_by\_policy](#input\_dns\_zone\_group\_managed\_by\_policy) | Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoints' DNS zone groups; Terraform leaves them alone. | `bool` | `false` | no |
| <a name="input_dns_zone_ids"></a> [dns\_zone\_ids](#input\_dns\_zone\_ids) | Map of DNS zone IDs. Expected keys: cognitive\_services, openai, ai\_services. | `map(string)` | `{}` | no |
| <a name="input_enable_apim_connections"></a> [enable\_apim\_connections](#input\_enable\_apim\_connections) | Create Foundry-project → APIM ApiKey connections. | `bool` | `false` | no |
| <a name="input_enable_app_insights_connection"></a> [enable\_app\_insights\_connection](#input\_enable\_app\_insights\_connection) | Create the App Insights connection on each Foundry account. | `bool` | `true` | no |
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Create diagnostic settings sending AllMetrics to Log Analytics. | `bool` | `true` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_foundry_external_access"></a> [foundry\_external\_access](#input\_foundry\_external\_access) | If true, publicNetworkAccess=Enabled on Foundry accounts. | `bool` | `false` | no |
| <a name="input_foundry_instances"></a> [foundry\_instances](#input\_foundry\_instances) | List of AI Foundry (AIServices) account definitions. | <pre>list(object({<br/>    name                 = optional(string, "")<br/>    location             = string<br/>    custom_subdomain     = optional(string, "")<br/>    default_project_name = optional(string, "")<br/>  }))</pre> | `[]` | no |
| <a name="input_foundry_models"></a> [foundry\_models](#input\_foundry\_models) | Model deployments to create across the Foundry accounts. | <pre>list(object({<br/>    name             = string<br/>    publisher        = optional(string, "OpenAI")<br/>    version          = string<br/>    sku              = optional(string, "GlobalStandard")<br/>    capacity         = optional(number, 100)<br/>    ai_service_index = optional(number, 0)<br/>  }))</pre> | `[]` | no |
| <a name="input_foundry_network_injection_enabled"></a> [foundry\_network\_injection\_enabled](#input\_foundry\_network\_injection\_enabled) | Inject the Foundry Agent Service into the agent subnet (needs enable\_agent\_subnet = true). | `bool` | `true` | no |
| <a name="input_foundry_project_default_name"></a> [foundry\_project\_default\_name](#input\_foundry\_project\_default\_name) | Default AI Foundry project name (used when an instance entry does not override it). | `string` | `"citadel-governance-project"` | no |
| <a name="input_log_analytics_id"></a> [log\_analytics\_id](#input\_log\_analytics\_id) | Log Analytics workspace ID for diagnostic settings. | `string` | `""` | no |
| <a name="input_outbound_allowed_fqdns"></a> [outbound\_allowed\_fqdns](#input\_outbound\_allowed\_fqdns) | Restrict the Foundry accounts' outbound network access to these FQDNs. null = unrestricted. | `list(string)` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_extended_ai_services_config"></a> [extended\_ai\_services\_config](#output\_extended\_ai\_services\_config) | Per-instance Foundry details including the Foundry project endpoint. |
| <a name="output_foundry_endpoints"></a> [foundry\_endpoints](#output\_foundry\_endpoints) | Endpoint for each AI Foundry account. |
| <a name="output_foundry_ids"></a> [foundry\_ids](#output\_foundry\_ids) | Resource IDs for each AI Foundry (AIServices) account. |
| <a name="output_foundry_names"></a> [foundry\_names](#output\_foundry\_names) | Names of each AI Foundry account. |
| <a name="output_foundry_principal_ids"></a> [foundry\_principal\_ids](#output\_foundry\_principal\_ids) | System-assigned managed identity principal IDs for each Foundry account. |
| <a name="output_primary_foundry_endpoint"></a> [primary\_foundry\_endpoint](#output\_primary\_foundry\_endpoint) | Base AI Services endpoint of the primary (index 0) Foundry account; serves content-safety + PII. |
| <a name="output_project_ids"></a> [project\_ids](#output\_project\_ids) | Resource IDs of the default Foundry projects (one per account). |
| <a name="output_project_names"></a> [project\_names](#output\_project\_names) | Names of the default Foundry projects (one per account). |
<!-- END_TF_DOCS -->
