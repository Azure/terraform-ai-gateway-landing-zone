# Gateway API

Publishes one API on API Management (HTTP via azurerm, WebSocket/MCP via azapi) with its API policy, operation policies, Application Insights and Azure Monitor diagnostics, and an optional product. The root module calls it once per API with `for_each`.

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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.azure_monitor_diagnostic](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.operation_policy](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.policy](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.this](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource_action.operation_policy_update](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource_action) | resource |
| [azapi_resource_action.policy_update](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource_action) | resource |
| [azapi_update_resource.app_insights_metrics](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_api_management_api.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_diagnostic.app_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_operation_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_product.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_product_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_policy) | resource |
| [terraform_data.operation_policy_hash](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.policy_hash](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api"></a> [api](#input\_api) | The API to publish.<br/>  type = "http": azurerm\_api\_management\_api (OpenAPI import, subscription key names, optional service URL).<br/>  type = "websocket" \| "mcp": azapi Microsoft.ApiManagement/service/apis with `azapi_properties_json`<br/>  (jsonencode of the ARM `properties` object; azurerm doesn't model these API types). | <pre>object({<br/>    name                    = string<br/>    type                    = optional(string, "http")<br/>    display_name            = optional(string)<br/>    description             = optional(string)<br/>    path                    = optional(string)<br/>    protocols               = optional(list(string), ["https"])<br/>    service_url             = optional(string)<br/>    subscription_required   = optional(bool, true)<br/>    subscription_key_names  = optional(object({ header = string, query = string }))<br/>    spec                    = optional(object({ format = string, value = string }))<br/>    policy_xml              = optional(string)<br/>    azapi_properties_json   = optional(string)<br/>    azapi_schema_validation = optional(bool, true)<br/>  })</pre> | n/a | yes |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the API Management service. | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | Name of the API Management service. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group of the API Management service. | `string` | n/a | yes |
| <a name="input_api_depends_on"></a> [api\_depends\_on](#input\_api\_depends\_on) | IDs the API itself waits for (for example an MCP server's backend, or another API it is derived from). | `list(string)` | `[]` | no |
| <a name="input_app_insights_diagnostic"></a> [app\_insights\_diagnostic](#input\_app\_insights\_diagnostic) | API-level Application Insights diagnostic (plus the metrics flag azurerm doesn't expose). null = none. | <pre>object({<br/>    logger_id                 = string<br/>    verbosity                 = string<br/>    body_bytes                = number<br/>    headers                   = list(string)<br/>    http_correlation_protocol = optional(string, "W3C")<br/>  })</pre> | `null` | no |
| <a name="input_azapi_operation_policies"></a> [azapi\_operation\_policies](#input\_azapi\_operation\_policies) | Operation ID => policy XML, managed with azapi (Microsoft.ApiManagement/service/apis/operations/policies). | `map(string)` | `{}` | no |
| <a name="input_azure_monitor_diagnostic"></a> [azure\_monitor\_diagnostic](#input\_azure\_monitor\_diagnostic) | API-level Azure Monitor diagnostic. `properties` is the ARM properties object (includes largeLanguageModel logging). null = none. | <pre>object({<br/>    properties             = any<br/>    response_export_values = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_operation_policies"></a> [operation\_policies](#input\_operation\_policies) | Operation ID => policy XML, managed with azurerm\_api\_management\_api\_operation\_policy (HTTP APIs). | `map(string)` | `{}` | no |
| <a name="input_policy_depends_on"></a> [policy\_depends\_on](#input\_policy\_depends\_on) | IDs the API policies wait for (fragments, named values, loggers). APIM validates references when a policy is saved. | `list(string)` | `[]` | no |
| <a name="input_product"></a> [product](#input\_product) | A product created together with the API (and linked to it). null = none. | <pre>object({<br/>    id                  = string<br/>    display_name        = string<br/>    description         = string<br/>    subscriptions_limit = optional(number)<br/>    policy_xml          = optional(string)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the API. |
| <a name="output_name"></a> [name](#output\_name) | Name of the API. |
| <a name="output_path"></a> [path](#output\_path) | Gateway path of the API (HTTP APIs; null for azapi-managed APIs). |
| <a name="output_product_id"></a> [product\_id](#output\_product\_id) | Product ID created with the API (null when no product). |
<!-- END_TF_DOCS -->
