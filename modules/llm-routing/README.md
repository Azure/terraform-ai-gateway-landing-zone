# LLM routing

Turns the LLM backend catalogue (`llm_backend_config`) into:

- one APIM backend per entry (managed-identity credential for `managed-identity` backends, a circuit-breaker rule built from the entry's own `circuit_breaker`, on by default), with TLS validation on;
- a load-balancing backend pool for every model that more than one backend serves;
- the four generated routing fragments `set-backend-pools`, `get-available-models`, `metadata-config` and `resolve-model-alias` (the last from `model_aliases`, `priority` or `weighted`). The fragment templates live in `templates/`.

Called by [stacks/llm-backend-onboarding](../../stacks/llm-backend-onboarding/backends.tf), which builds the catalogue from the Foundry deployments and `llm_backends`.

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
| <a name="input_llm_backend_config"></a> [llm\_backend\_config](#input\_llm\_backend\_config) | llmBackendConfig: one entry per LLM endpoint, each becoming one APIM backend.<br/>  auth\_type        managed-identity \| aws-sigv4 \| api-key-bearer \| api-key-header \| none.<br/>                   Default by backend\_type: aws-bedrock = aws-sigv4, external = none,<br/>                   aws-bedrock-mantle and gemini-openai = api-key-bearer, otherwise<br/>                   managed-identity. auth\_scheme is legacy and ignored.<br/>  auth\_config      named\_value\_key: the APIM named value holding the key. APIM adds it as the<br/>                   header of the backend (Authorization for api-key-bearer, api-key for<br/>                   api-key-header), so the secret holds the COMPLETE header value<br/>                   ("Bearer <key>" for api-key-bearer, the bare key for api-key-header).<br/>  circuit\_breaker  Per-backend circuit breaker rule (APIM allows one rule per backend):<br/>    enabled             false = no circuit breaker on this backend.<br/>    failure\_count       Failures within failure\_interval that trip the breaker.<br/>    failure\_interval    ISO 8601 window in which failures are counted (PT5M = 5 minutes).<br/>    trip\_duration       ISO 8601 time the backend stays out of rotation once tripped.<br/>    status\_code\_ranges  HTTP status ranges counted as failures (200-599, at most 10).<br/>    error\_reasons       APIM error reasons counted as failures (at most 10).<br/>    accept\_retry\_after  Honour a Retry-After header of the backend as the trip duration. | <pre>list(object({<br/>    backend_id   = string<br/>    backend_type = string<br/>    endpoint     = string<br/>    auth_scheme  = optional(string) # legacy, ignored (auth_type decides)<br/>    auth_type    = optional(string) # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'<br/>    auth_config = optional(object({<br/>      named_value_key = optional(string)<br/>    }))<br/>    supported_models = list(object({<br/>      name                = string<br/>      sku                 = optional(string, "Standard")<br/>      capacity            = optional(number, 100)<br/>      modelFormat         = optional(string, "OpenAI")<br/>      modelVersion        = optional(string, "1")<br/>      apiVersion          = optional(string, "2024-02-15-preview")<br/>      timeout             = optional(number, 120)<br/>      inferenceApiVersion = optional(string, "")<br/>      retirementDate      = optional(string, "")<br/>    }))<br/>    priority = optional(number, 1)<br/>    weight   = optional(number, 100)<br/>    circuit_breaker = optional(object({<br/>      enabled            = optional(bool, true)<br/>      failure_count      = optional(number, 3)<br/>      failure_interval   = optional(string, "PT5M")<br/>      trip_duration      = optional(string, "PT1M")<br/>      status_code_ranges = optional(list(object({ min = number, max = number })), [{ min = 429, max = 429 }, { min = 500, max = 503 }])<br/>      error_reasons      = optional(list(string), ["Server errors"])<br/>      accept_retry_after = optional(bool, true)<br/>    }), {})<br/>  }))</pre> | `[]` | no |
| <a name="input_model_aliases"></a> [model\_aliases](#input\_model\_aliases) | Model alias definitions. Each: { name, models[], strategy?, weights?[] } | <pre>list(object({<br/>    name     = string<br/>    models   = list(string)<br/>    strategy = optional(string, "priority")<br/>    weights  = optional(list(number), [])<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_ids"></a> [backend\_ids](#output\_backend\_ids) | LLM backend ID => APIM backend resource ID. |
| <a name="output_fragment_ids"></a> [fragment\_ids](#output\_fragment\_ids) | Routing fragment name => policy fragment resource ID. APIs whose policies include these fragments must depend on them. |
| <a name="output_pool_ids"></a> [pool\_ids](#output\_pool\_ids) | Backend pool name => APIM backend resource ID (only models served by 2+ backends get a pool). |
| <a name="output_pools"></a> [pools](#output\_pools) | Pool catalogue consumed by the routing fragments (pool name, type, models, auth). |
<!-- END_TF_DOCS -->
