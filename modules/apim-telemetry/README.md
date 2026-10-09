# APIM telemetry

Attaches loggers and service-level diagnostics to an API Management service: Application Insights, Azure Monitor and Event Hub (usage + PII) loggers, the service-level `applicationinsights` diagnostic with metrics enabled, and the diagnostic setting to Log Analytics.

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

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource_action.apim_diagnostics](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource_action) | resource |
| [azapi_resource_action.azure_monitor_logger](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource_action) | resource |
| [azapi_update_resource.global_appinsights_metrics](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_api_management_diagnostic.global](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_diagnostic) | resource |
| [azurerm_api_management_logger.app_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_logger) | resource |
| [azurerm_api_management_logger.eventhub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_logger) | resource |
| [azurerm_api_management_logger.pii_eventhub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_logger) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the API Management service. | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | Name of the API Management service. | `string` | n/a | yes |
| <a name="input_app_insights_id"></a> [app\_insights\_id](#input\_app\_insights\_id) | Resource ID of the Application Insights component used by the APIM logger. | `string` | n/a | yes |
| <a name="input_app_insights_instrumentation_key"></a> [app\_insights\_instrumentation\_key](#input\_app\_insights\_instrumentation\_key) | Instrumentation key of the APIM Application Insights component (legacy logger credential). | `string` | n/a | yes |
| <a name="input_enable_pii_redaction"></a> [enable\_pii\_redaction](#input\_enable\_pii\_redaction) | Create the PII usage Event Hub logger (pii-usage-eventhub-logger). | `bool` | n/a | yes |
| <a name="input_eventhub_endpoint_uri"></a> [eventhub\_endpoint\_uri](#input\_eventhub\_endpoint\_uri) | EventHub namespace endpoint URI (https://<ns>.servicebus.windows.net) | `string` | n/a | yes |
| <a name="input_log_analytics_id"></a> [log\_analytics\_id](#input\_log\_analytics\_id) | Resource ID of the Log Analytics workspace that receives diagnostic settings. | `string` | n/a | yes |
| <a name="input_log_body_bytes"></a> [log\_body\_bytes](#input\_log\_body\_bytes) | Max bytes to log from request/response body | `number` | n/a | yes |
| <a name="input_log_verbosity"></a> [log\_verbosity](#input\_log\_verbosity) | APIM diagnostic log verbosity: verbose, information, error | `string` | n/a | yes |
| <a name="input_managed_identity_client_id"></a> [managed\_identity\_client\_id](#input\_managed\_identity\_client\_id) | Client ID of the user-assigned managed identity the service runs as. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_app_insights_connection_string"></a> [app\_insights\_connection\_string](#input\_app\_insights\_connection\_string) | Application Insights connection string — used in the AppInsights logger (Bicep parity). | `string` | `""` | no |
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Configure the workload Azure Monitor diagnostic setting by ARM PUT. false = Azure Policy owns it. APIM loggers and API diagnostics are unaffected. | `bool` | `true` | no |
| <a name="input_eventhub_pii_hub_name"></a> [eventhub\_pii\_hub\_name](#input\_eventhub\_pii\_hub\_name) | Name of the PII usage event hub (matches Bicep output eventHubPIIName). | `string` | `"pii-usage"` | no |
| <a name="input_eventhub_usage_hub_name"></a> [eventhub\_usage\_hub\_name](#input\_eventhub\_usage\_hub\_name) | Name of the APIM usage event hub inside the namespace (matches Bicep output eventHub.name). | `string` | `"ai-usage"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_insights_logger_id"></a> [app\_insights\_logger\_id](#output\_app\_insights\_logger\_id) | Resource ID of the Application Insights logger (appinsights-logger). |
| <a name="output_azure_monitor_logger_id"></a> [azure\_monitor\_logger\_id](#output\_azure\_monitor\_logger\_id) | Resource ID of the Azure Monitor logger (azuremonitor). |
| <a name="output_dependency_ids"></a> [dependency\_ids](#output\_dependency\_ids) | IDs to depend on before creating API diagnostics that use the Azure Monitor logger. |
| <a name="output_diagnostic_setting_names"></a> [diagnostic\_setting\_names](#output\_diagnostic\_setting\_names) | Workload Azure Monitor diagnostic setting names (empty when policy owns diagnostics). |
| <a name="output_logger_names"></a> [logger\_names](#output\_logger\_names) | Names of the loggers this module creates (contract for API-level diagnostics). |
<!-- END_TF_DOCS -->
