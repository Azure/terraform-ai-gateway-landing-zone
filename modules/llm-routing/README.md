# LLM routing

Turns the LLM backend catalogue (`llm_backend_config`) into:

- one APIM backend per entry (managed-identity credential for `managed-identity` backends, a circuit-breaker rule built from the entry's own `circuit_breaker`, on by default), with TLS validation on;
- a load-balancing backend pool for every model that more than one backend of the same type serves (named `<model>-<type>-backend-pool`, with session affinity for stateful models);
- the generated routing fragments `set-backend-pools` (with one virtual pool per model alias), `get-available-models`, `metadata-config`, `resolve-model-alias` and `backend-contract` (the live routing contract as JSON). The fragment templates live in `templates/`.

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
| [azurerm_api_management_policy_fragment.backend_contract](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [azurerm_api_management_policy_fragment.get_available_models](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [azurerm_api_management_policy_fragment.metadata_config](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [azurerm_api_management_policy_fragment.resolve_model_alias](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [azurerm_api_management_policy_fragment.set_backend_pools](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the API Management service. | `string` | n/a | yes |
| <a name="input_managed_identity_client_id"></a> [managed\_identity\_client\_id](#input\_managed\_identity\_client\_id) | Client ID of the APIM user-assigned managed identity that authenticates to managed-identity backends. | `string` | n/a | yes |
| <a name="input_llm_backend_config"></a> [llm\_backend\_config](#input\_llm\_backend\_config) | llmBackendConfig: one entry per LLM endpoint, each becoming one APIM backend.<br/>  backend\_type     ai-foundry \| azure-openai \| aws-bedrock \| aws-bedrock-mantle \| gemini \|<br/>                   gemini-openai \| anthropic \| azure-flux \| azure-mai \| external.<br/>  auth\_type        managed-identity \| aws-sigv4 \| api-key-bearer \| api-key-header \|<br/>                   api-key-gemini (x-goog-api-key) \| api-key-anthropic (x-api-key and<br/>                   anthropic-version) \| none.<br/>                   Default by backend\_type: aws-bedrock = aws-sigv4, external = none,<br/>                   aws-bedrock-mantle and gemini-openai = api-key-bearer, gemini =<br/>                   api-key-gemini, anthropic = api-key-anthropic, otherwise<br/>                   managed-identity. auth\_scheme is legacy and ignored.<br/>  auth\_config      named\_value\_key: the APIM named value holding the key. APIM adds it as the<br/>                   header of the backend (Authorization for api-key-bearer, api-key for<br/>                   api-key-header), so the secret holds the COMPLETE header value<br/>                   ("Bearer <key>" for api-key-bearer, the bare key for api-key-header).<br/>  circuit\_breaker  Per-backend circuit breaker rule (APIM allows one rule per backend):<br/>    enabled             false = no circuit breaker on this backend.<br/>    failure\_count       Failures within failure\_interval that trip the breaker.<br/>    failure\_interval    ISO 8601 window in which failures are counted (PT5M = 5 minutes).<br/>    trip\_duration       ISO 8601 time the backend stays out of rotation once tripped.<br/>    status\_code\_ranges  HTTP status ranges counted as failures (200-599, at most 10).<br/>    error\_reasons       APIM error reasons counted as failures (at most 10).<br/>    accept\_retry\_after  Honour a Retry-After header of the backend as the trip duration.<br/>  session\_affinity cookie\_name / source of the affinity cookie of the pools this backend joins<br/>                   (overrides the module's session\_affinity); only pools of models flagged<br/>                   sessionAwareModel get one. | <pre>list(object({<br/>    backend_id   = string<br/>    backend_type = string<br/>    endpoint     = string<br/>    auth_scheme  = optional(string) # legacy, ignored (auth_type decides)<br/>    auth_type    = optional(string) # 'managed-identity'|'aws-sigv4'|'api-key-bearer'|'api-key-header'|'none'<br/>    auth_config = optional(object({<br/>      named_value_key = optional(string)<br/>    }))<br/>    supported_models = list(object({<br/>      name                = string<br/>      sku                 = optional(string, "Standard")<br/>      capacity            = optional(number, 100)<br/>      modelFormat         = optional(string, "OpenAI")<br/>      modelVersion        = optional(string, "1")<br/>      apiVersion          = optional(string, "2024-02-15-preview")<br/>      timeout             = optional(number, 120)<br/>      inferenceApiVersion = optional(string, "")<br/>      retirementDate      = optional(string, "")<br/>      # Provider slug in the URL path of the backend: required for azure-flux models (the<br/>      # Black Forest Labs slug differs from the model name, e.g. FLUX.2-pro = flux-2-pro).<br/>      modelPath = optional(string, "")<br/>      # A stateful model (OpenAI Responses, Assistants): the pools that serve it get session affinity.<br/>      sessionAwareModel = optional(bool, false)<br/>    }))<br/>    priority = optional(number, 1)<br/>    weight   = optional(number, 100)<br/>    # Per-backend override of the session cookie of the pools this backend joins.<br/>    session_affinity = optional(object({<br/>      cookie_name = optional(string)<br/>      source      = optional(string)<br/>    }))<br/>    circuit_breaker = optional(object({<br/>      enabled            = optional(bool, true)<br/>      failure_count      = optional(number, 3)<br/>      failure_interval   = optional(string, "PT5M")<br/>      trip_duration      = optional(string, "PT1M")<br/>      status_code_ranges = optional(list(object({ min = number, max = number })), [{ min = 429, max = 429 }, { min = 500, max = 503 }])<br/>      error_reasons      = optional(list(string), ["Server errors"])<br/>      accept_retry_after = optional(bool, true)<br/>    }), {})<br/>  }))</pre> | `[]` | no |
| <a name="input_model_aliases"></a> [model\_aliases](#input\_model\_aliases) | Model alias definitions. Each: { name, models[], strategy?, weights?[] } | <pre>list(object({<br/>    name     = string<br/>    models   = list(string)<br/>    strategy = optional(string, "priority")<br/>    weights  = optional(list(number), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_release_version"></a> [release\_version](#input\_release\_version) | Version of this solution reported as masterVersion in the backend contract (the stack reads version.txt of release-please). | `string` | `"0.0.0"` | no |
| <a name="input_session_affinity"></a> [session\_affinity](#input\_session\_affinity) | Session affinity (sticky routing) of the backend pools of stateful models (those flagged<br/>sessionAwareModel): APIM sets an affinity cookie and routes a client that replays it back to the<br/>same backend, as the OpenAI Responses and Assistants APIs require.<br/>  enabled      master switch; false = no pool gets session affinity.<br/>  cookie\_name  name of the affinity cookie.<br/>  source       where the session id lives; APIM supports Cookie only. | <pre>object({<br/>    enabled     = optional(bool, true)<br/>    cookie_name = optional(string, "ai-gateway-affinity")<br/>    source      = optional(string, "Cookie")<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_contract_version"></a> [backend\_contract\_version](#output\_backend\_contract\_version) | Version of the backend contract document served at /version/backend-contract. |
| <a name="output_backend_ids"></a> [backend\_ids](#output\_backend\_ids) | LLM backend ID => APIM backend resource ID. |
| <a name="output_fragment_ids"></a> [fragment\_ids](#output\_fragment\_ids) | Routing fragment name => policy fragment resource ID. APIs whose policies include these fragments must depend on them. |
| <a name="output_pool_ids"></a> [pool\_ids](#output\_pool\_ids) | Backend pool name => APIM backend resource ID (only models served by 2+ backends get a pool). |
| <a name="output_pools"></a> [pools](#output\_pools) | Pool catalogue consumed by the routing fragments (pool name, type, models, auth). |
<!-- END_TF_DOCS -->
