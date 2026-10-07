# Unified AI API

Publishes the wildcard Unified AI API on API Management, plus its product, product policy and diagnostics.

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
| [azapi_resource.deployment_by_name_policy](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.deployments_policy](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_api.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_product.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_product_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_name"></a> [apim\_name](#input\_apim\_name) | Name of the parent API Management service. | `string` | n/a | yes |
| <a name="input_deployment_by_name_op_policy_xml_path"></a> [deployment\_by\_name\_op\_policy\_xml\_path](#input\_deployment\_by\_name\_op\_policy\_xml\_path) | Absolute path to the operation-policy XML for GET /deployments/{deployment-id}. | `string` | n/a | yes |
| <a name="input_deployments_op_policy_xml_path"></a> [deployments\_op\_policy\_xml\_path](#input\_deployments\_op\_policy\_xml\_path) | Absolute path to the operation-policy XML for GET /deployments. | `string` | n/a | yes |
| <a name="input_openapi_spec_path"></a> [openapi\_spec\_path](#input\_openapi\_spec\_path) | Absolute path to the OpenAPI spec JSON file imported into APIM (UnifiedAIWildcard.json). | `string` | n/a | yes |
| <a name="input_policy_xml_path"></a> [policy\_xml\_path](#input\_policy\_xml\_path) | Absolute path to the API-level inbound policy XML (unified-ai-api-policy.xml). | `string` | n/a | yes |
| <a name="input_product_policy_xml_path"></a> [product\_policy\_xml\_path](#input\_product\_policy\_xml\_path) | Absolute path to the product policy XML (unified-ai-product-subscription.xml). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name. Leave empty for auto-generated. | `string` | n/a | yes |
| <a name="input_api_description"></a> [api\_description](#input\_api\_description) | Description of the API in API Management. | `string` | `"Unified AI Gateway API - Routes requests to multiple AI model providers (Azure OpenAI, AI Foundry, Gemini) using dynamic path-based routing with support for multiple API types."` | no |
| <a name="input_api_display_name"></a> [api\_display\_name](#input\_api\_display\_name) | Display name of the API in API Management. | `string` | `"Unified AI API"` | no |
| <a name="input_api_name"></a> [api\_name](#input\_api\_name) | Name (ID) of the API in API Management. | `string` | `"unified-ai-api"` | no |
| <a name="input_api_path"></a> [api\_path](#input\_api\_path) | URL path suffix of the API on the APIM gateway. | `string` | `"unified-ai"` | no |
| <a name="input_azure_monitor_log_settings"></a> [azure\_monitor\_log\_settings](#input\_azure\_monitor\_log\_settings) | Bicep parity: `azureMonitorLogSettings` — frontend/backend headers+body and largeLanguageModel logs. | <pre>object({<br/>    frontend = object({<br/>      request  = object({ headers = list(string), body = object({ bytes = number }) })<br/>      response = object({ headers = list(string), body = object({ bytes = number }) })<br/>    })<br/>    backend = object({<br/>      request  = object({ headers = list(string), body = object({ bytes = number }) })<br/>      response = object({ headers = list(string), body = object({ bytes = number }) })<br/>    })<br/>    largeLanguageModel = object({<br/>      logs      = string<br/>      requests  = object({ messages = string, maxSizeInBytes = number })<br/>      responses = object({ messages = string, maxSizeInBytes = number })<br/>    })<br/>  })</pre> | <pre>{<br/>  "backend": {<br/>    "request": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    },<br/>    "response": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    }<br/>  },<br/>  "frontend": {<br/>    "request": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    },<br/>    "response": {<br/>      "body": {<br/>        "bytes": 0<br/>      },<br/>      "headers": []<br/>    }<br/>  },<br/>  "largeLanguageModel": {<br/>    "logs": "enabled",<br/>    "requests": {<br/>      "maxSizeInBytes": 262144,<br/>      "messages": "all"<br/>    },<br/>    "responses": {<br/>      "maxSizeInBytes": 262144,<br/>      "messages": "all"<br/>    }<br/>  }<br/>}</pre> | no |
| <a name="input_azure_monitor_logger_id"></a> [azure\_monitor\_logger\_id](#input\_azure\_monitor\_logger\_id) | APIM Azure Monitor logger resource ID. When empty, the azuremonitor diagnostic is skipped. | `string` | `""` | no |
| <a name="input_policy_dependencies"></a> [policy\_dependencies](#input\_policy\_dependencies) | Resources the API-level policy depends on (named values, fragments). | `any` | `[]` | no |
| <a name="input_product_description"></a> [product\_description](#input\_product\_description) | Description of the Unified AI API product. | `string` | `"Unified AI Gateway product - provides access to all AI model providers through a single wildcard endpoint."` | no |
| <a name="input_product_display_name"></a> [product\_display\_name](#input\_product\_display\_name) | Display name of the Unified AI API product. | `string` | `"Unified AI Gateway"` | no |
| <a name="input_product_id"></a> [product\_id](#input\_product\_id) | ID of the APIM product created for the Unified AI API. | `string` | `"unified-ai-product"` | no |
| <a name="input_product_subscriptions_limit"></a> [product\_subscriptions\_limit](#input\_product\_subscriptions\_limit) | Maximum number of subscriptions allowed on the product. | `number` | `10` | no |
| <a name="input_subscription_required"></a> [subscription\_required](#input\_subscription\_required) | Bicep parity: subscriptionRequired (always true for unified-ai-api). | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | Resource ID of the Unified AI API. |
| <a name="output_api_name"></a> [api\_name](#output\_api\_name) | Name of the Unified AI API. |
| <a name="output_api_path"></a> [api\_path](#output\_api\_path) | Gateway path of the Unified AI API. |
| <a name="output_product_id"></a> [product\_id](#output\_product\_id) | Resource ID of the Unified AI API product. |
| <a name="output_product_name"></a> [product\_name](#output\_product\_name) | Product ID (name) of the Unified AI API product. |
<!-- END_TF_DOCS -->
