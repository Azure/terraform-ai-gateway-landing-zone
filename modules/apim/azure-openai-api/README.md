# Azure OpenAI API

Publishes the Azure OpenAI-compatible API (`/openai/deployments/...`) on API Management with its policy, operation policies and diagnostics.

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

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.azure_monitor_diagnostic](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_update_resource.app_insights_metrics](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_api_management_api.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_diagnostic.app_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_operation_policy.deployment_by_name](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_operation_policy.deployments](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_name"></a> [apim\_name](#input\_apim\_name) | Name of the parent API Management service. | `string` | n/a | yes |
| <a name="input_openapi_spec_path"></a> [openapi\_spec\_path](#input\_openapi\_spec\_path) | Absolute path to the OpenAPI spec JSON file imported into APIM (AIFoundryOpenAI.json). | `string` | n/a | yes |
| <a name="input_policy_xml_path"></a> [policy\_xml\_path](#input\_policy\_xml\_path) | Absolute path to the API-level inbound policy XML (azure-open-ai-api-policy.xml). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name. Leave empty for auto-generated. | `string` | n/a | yes |
| <a name="input_api_description"></a> [api\_description](#input\_api\_description) | Description of the API in API Management. | `string` | `"Azure OpenAI API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models."` | no |
| <a name="input_api_display_name"></a> [api\_display\_name](#input\_api\_display\_name) | Display name of the API in API Management. | `string` | `"Azure OpenAI API"` | no |
| <a name="input_api_name"></a> [api\_name](#input\_api\_name) | Name (ID) of the API in API Management. | `string` | `"azure-openai-api"` | no |
| <a name="input_api_path"></a> [api\_path](#input\_api\_path) | URL path suffix of the API on the APIM gateway. | `string` | `"openai"` | no |
| <a name="input_app_insights_log_settings"></a> [app\_insights\_log\_settings](#input\_app\_insights\_log\_settings) | Bicep parity: `appInsightsLogSettings`. | <pre>object({<br/>    headers = list(string)<br/>    body    = object({ bytes = number })<br/>  })</pre> | <pre>{<br/>  "body": {<br/>    "bytes": 0<br/>  },<br/>  "headers": [<br/>    "Content-type",<br/>    "User-agent",<br/>    "x-ms-region",<br/>    "x-ratelimit-remaining-tokens",<br/>    "x-ratelimit-remaining-requests"<br/>  ]<br/>}</pre> | no |
| <a name="input_app_insights_logger_id"></a> [app\_insights\_logger\_id](#input\_app\_insights\_logger\_id) | APIM Application Insights logger resource ID. | `string` | `""` | no |
| <a name="input_azure_monitor_log_settings"></a> [azure\_monitor\_log\_settings](#input\_azure\_monitor\_log\_settings) | Bicep parity: `azureMonitorLogSettings` — frontend/backend headers+body and largeLanguageModel logs. | <pre>object({<br/>    frontend = object({<br/>      request  = object({ headers = list(string), body = object({ bytes = number }) })<br/>      response = object({ headers = list(string), body = object({ bytes = number }) })<br/>    })<br/>    backend = object({<br/>      request  = object({ headers = list(string), body = object({ bytes = number }) })<br/>      response = object({ headers = list(string), body = object({ bytes = number }) })<br/>    })<br/>    largeLanguageModel = object({<br/>      logs      = string<br/>      requests  = object({ messages = string, maxSizeInBytes = number })<br/>      responses = object({ messages = string, maxSizeInBytes = number })<br/>    })<br/>  })</pre> | <pre>{<br/>  "backend": {<br/>    "request": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    },<br/>    "response": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    }<br/>  },<br/>  "frontend": {<br/>    "request": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    },<br/>    "response": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    }<br/>  },<br/>  "largeLanguageModel": {<br/>    "logs": "enabled",<br/>    "requests": {<br/>      "maxSizeInBytes": 262144,<br/>      "messages": "all"<br/>    },<br/>    "responses": {<br/>      "maxSizeInBytes": 262144,<br/>      "messages": "all"<br/>    }<br/>  }<br/>}</pre> | no |
| <a name="input_azure_monitor_logger_id"></a> [azure\_monitor\_logger\_id](#input\_azure\_monitor\_logger\_id) | APIM Azure Monitor logger resource ID. | `string` | `""` | no |
| <a name="input_deployment_by_name_op_policy_xml_path"></a> [deployment\_by\_name\_op\_policy\_xml\_path](#input\_deployment\_by\_name\_op\_policy\_xml\_path) | Absolute path to the operation-policy XML for GET /deployments/{deployment-id}. | `string` | `""` | no |
| <a name="input_deployments_op_policy_xml_path"></a> [deployments\_op\_policy\_xml\_path](#input\_deployments\_op\_policy\_xml\_path) | Absolute path to the operation-policy XML for GET /deployments. | `string` | `""` | no |
| <a name="input_has_llm_backends"></a> [has\_llm\_backends](#input\_has\_llm\_backends) | When false, skip operation policies that reference the dynamic get-available-models fragment. | `bool` | `false` | no |
| <a name="input_policy_dependencies"></a> [policy\_dependencies](#input\_policy\_dependencies) | Resources the API-level policy depends on (named values, fragments). | `any` | `[]` | no |
| <a name="input_subscription_required"></a> [subscription\_required](#input\_subscription\_required) | Bicep parity: `allowSubscriptionKey` (true unless Entra-only). | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | Resource ID of the Azure OpenAI API. |
| <a name="output_api_name"></a> [api\_name](#output\_api\_name) | Name of the Azure OpenAI API. |
| <a name="output_api_path"></a> [api\_path](#output\_api\_path) | Gateway path of the Azure OpenAI API. |
<!-- END_TF_DOCS -->
