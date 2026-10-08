# Monitoring

Creates (or reuses) the Log Analytics workspace, the Application Insights components for APIM, the Logic App and Foundry, the optional Azure Monitor Private Link Scope and the dashboards.

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

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_app_insights"></a> [app\_insights](#module\_app\_insights) | Azure/avm-res-insights-component/azurerm | 0.4.0 |
| <a name="module_log_analytics"></a> [log\_analytics](#module\_log\_analytics) | Azure/avm-res-operationalinsights-workspace/azurerm | 0.5.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_monitor_private_link_scope.ampls](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_private_link_scope) | resource |
| [azurerm_monitor_private_link_scoped_service.appi_apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_private_link_scoped_service) | resource |
| [azurerm_monitor_private_link_scoped_service.appi_foundry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_private_link_scoped_service) | resource |
| [azurerm_monitor_private_link_scoped_service.appi_logic](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_private_link_scoped_service) | resource |
| [azurerm_monitor_private_link_scoped_service.law](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_private_link_scoped_service) | resource |
| [azurerm_portal_dashboard.app_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/portal_dashboard) | resource |
| [azurerm_private_endpoint.ampls](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create_dashboards"></a> [create\_dashboards](#input\_create\_dashboards) | Create Application Insights dashboards | `bool` | n/a | yes |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name used for resource naming (e.g., citadel-dev, citadel-prod) | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_log_analytics_name"></a> [log\_analytics\_name](#input\_log\_analytics\_name) | Name of the Log Analytics workspace to create (ignored when existing\_log\_analytics\_workspace is set). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Subscription ID used when rendering the App Insights dashboard templates. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_ampls_dns_zone_id_monitor"></a> [ampls\_dns\_zone\_id\_monitor](#input\_ampls\_dns\_zone\_id\_monitor) | Private DNS zone id for privatelink.monitor.azure.com. | `string` | `""` | no |
| <a name="input_ampls_subnet_id"></a> [ampls\_subnet\_id](#input\_ampls\_subnet\_id) | Private endpoint subnet id for the AMPLS scoped PE (when use\_azure\_monitor\_private\_link\_scope is true). | `string` | `""` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_existing_log_analytics_workspace"></a> [existing\_log\_analytics\_workspace](#input\_existing\_log\_analytics\_workspace) | Existing (BYO) Log Analytics workspace: resource id and workspace (customer) id. null = create one named log\_analytics\_name. The caller looks the workspace up. | <pre>object({<br/>    id           = string<br/>    workspace_id = string<br/>  })</pre> | `null` | no |
| <a name="input_use_azure_monitor_private_link_scope"></a> [use\_azure\_monitor\_private\_link\_scope](#input\_use\_azure\_monitor\_private\_link\_scope) | Create an Azure Monitor Private Link Scope (AMPLS) scoping the LAW and App Insights components. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_insights_connection_string"></a> [app\_insights\_connection\_string](#output\_app\_insights\_connection\_string) | Connection string of the APIM Application Insights component. |
| <a name="output_app_insights_id"></a> [app\_insights\_id](#output\_app\_insights\_id) | Resource ID of the APIM Application Insights component. |
| <a name="output_app_insights_instrumentation_key"></a> [app\_insights\_instrumentation\_key](#output\_app\_insights\_instrumentation\_key) | Instrumentation key of the APIM Application Insights component. |
| <a name="output_app_insights_name"></a> [app\_insights\_name](#output\_app\_insights\_name) | Name of the APIM Application Insights component. |
| <a name="output_foundry_app_insights_connection_string"></a> [foundry\_app\_insights\_connection\_string](#output\_foundry\_app\_insights\_connection\_string) | Connection string of the Foundry Application Insights component. |
| <a name="output_foundry_app_insights_id"></a> [foundry\_app\_insights\_id](#output\_foundry\_app\_insights\_id) | Resource ID of the Foundry Application Insights component. |
| <a name="output_foundry_app_insights_instrumentation_key"></a> [foundry\_app\_insights\_instrumentation\_key](#output\_foundry\_app\_insights\_instrumentation\_key) | Instrumentation key of the Foundry Application Insights component. |
| <a name="output_foundry_app_insights_name"></a> [foundry\_app\_insights\_name](#output\_foundry\_app\_insights\_name) | Name of the Foundry Application Insights component. |
| <a name="output_log_analytics_id"></a> [log\_analytics\_id](#output\_log\_analytics\_id) | Resource ID of the Log Analytics workspace (created or existing). |
| <a name="output_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#output\_log\_analytics\_workspace\_id) | Workspace (customer) ID of the Log Analytics workspace. |
| <a name="output_logic_app_insights_connection_string"></a> [logic\_app\_insights\_connection\_string](#output\_logic\_app\_insights\_connection\_string) | Connection string of the Logic App Application Insights component. |
<!-- END_TF_DOCS -->
