# LLM routing

Turns the LLM backend catalogue (`llm_backend_config`) into APIM backends, load-balancing backend pools with circuit breakers, and the four generated routing fragments (`set-backend-pools`, `get-available-models`, `metadata-config`, `resolve-model-alias`). The fragment templates live in `templates/`.

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
| [azapi_resource.llm_backend](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.llm_backend_pool](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_policy_fragment.get_available_models](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [azurerm_api_management_policy_fragment.metadata_config](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [azurerm_api_management_policy_fragment.resolve_model_alias](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [azurerm_api_management_policy_fragment.set_backend_pools](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the API Management service. | `string` | n/a | yes |
| <a name="input_managed_identity_client_id"></a> [managed\_identity\_client\_id](#input\_managed\_identity\_client\_id) | Client ID of the APIM user-assigned managed identity that authenticates to managed-identity backends. | `string` | n/a | yes |
| <a name="input_configure_circuit_breaker"></a> [configure\_circuit\_breaker](#input\_configure\_circuit\_breaker) | Enable per-backend circuit breaker rules. | `bool` | `true` | no |
| <a name="input_llm_backend_config"></a> [llm\_backend\_config](#input\_llm\_backend\_config) | Bicep llmBackendConfig — one entry per LLM endpoint. | <pre>list(object({<br/>    backend_id   = string<br/>    backend_type = string<br/>    endpoint     = string<br/>    auth_scheme  = optional(string) # legacy, retained<br/>    auth_type    = optional(string) # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'<br/>    auth_config = optional(object({<br/>      named_value_key = optional(string)<br/>    }))<br/>    supported_models = list(object({<br/>      name                = string<br/>      sku                 = optional(string, "Standard")<br/>      capacity            = optional(number, 100)<br/>      modelFormat         = optional(string, "OpenAI")<br/>      modelVersion        = optional(string, "1")<br/>      apiVersion          = optional(string, "2024-02-15-preview")<br/>      timeout             = optional(number, 120)<br/>      inferenceApiVersion = optional(string, "")<br/>      retirementDate      = optional(string, "")<br/>    }))<br/>    priority = optional(number, 1)<br/>    weight   = optional(number, 100)<br/>  }))</pre> | `[]` | no |
| <a name="input_model_aliases"></a> [model\_aliases](#input\_model\_aliases) | Model alias definitions. Each: { name, models[], strategy?, weights?[] } | <pre>list(object({<br/>    name     = string<br/>    models   = list(string)<br/>    strategy = optional(string, "priority")<br/>    weights  = optional(list(number), [])<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_ids"></a> [backend\_ids](#output\_backend\_ids) | LLM backend ID => APIM backend resource ID. |
| <a name="output_fragment_ids"></a> [fragment\_ids](#output\_fragment\_ids) | Routing fragment name => policy fragment resource ID. APIs whose policies include these fragments must depend on them. |
| <a name="output_pool_ids"></a> [pool\_ids](#output\_pool\_ids) | Backend pool name => APIM backend resource ID (only models served by 2+ backends get a pool). |
| <a name="output_pools"></a> [pools](#output\_pools) | Pool catalogue consumed by the routing fragments (pool name, type, models, auth). |
<!-- END_TF_DOCS -->
