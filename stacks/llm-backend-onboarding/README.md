# llm-backend-onboarding

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.12 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.81 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | ~> 2.12 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.81 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_api_center_registration"></a> [api\_center\_registration](#module\_api\_center\_registration) | ../../modules/api-center-registration | n/a |
| <a name="module_llm_api"></a> [llm\_api](#module\_llm\_api) | ../../modules/gateway-api | n/a |
| <a name="module_llm_fragments"></a> [llm\_fragments](#module\_llm\_fragments) | ../../modules/apim-policy-fragments | n/a |
| <a name="module_llm_routing"></a> [llm\_routing](#module\_llm\_routing) | ../../modules/llm-routing | n/a |
| <a name="module_naming"></a> [naming](#module\_naming) | ../../modules/naming | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_api_management_named_value.aws](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.aws_region](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.backend_api_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azapi_resource.api_center](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource) | data source |
| [azapi_resource.entra_auth](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource) | data source |
| [azapi_resource_list.deployments](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource_list) | data source |
| [azapi_resource_list.foundry_accounts](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource_list) | data source |
| [azapi_resource_list.fragments](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource_list) | data source |
| [azurerm_api_management.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/api_management) | data source |
| [azurerm_cognitive_account.foundry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/cognitive_account) | data source |
| [azurerm_user_assigned_identity.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region (e.g. swedencentral). | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID. | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_aws"></a> [aws](#input\_aws) | AWS Bedrock credentials (Key Vault references, versionless secret URIs) and region; "" = NOT\_CONFIGURED placeholders. | <pre>object({<br/>    region                = optional(string, "")<br/>    access_key_secret_uri = optional(string, "")<br/>    secret_key_secret_uri = optional(string, "")<br/>  })</pre> | `{}` | no |
| <a name="input_configure_circuit_breaker"></a> [configure\_circuit\_breaker](#input\_configure\_circuit\_breaker) | Per-backend circuit breaker rules (recommended for production). | `bool` | `true` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo. | `bool` | `true` | no |
| <a name="input_extra_llm_backends"></a> [extra\_llm\_backends](#input\_extra\_llm\_backends) | Backends APPENDED to the Foundry-derived ones (e.g. Azure OpenAI outside Foundry, third-party endpoints, AWS Bedrock). Same shape as llm\_backend\_config; ignored when llm\_backend\_config is set. | <pre>list(object({<br/>    backend_id   = string<br/>    backend_type = string<br/>    endpoint     = string<br/>    auth_scheme  = optional(string)<br/>    auth_type    = optional(string)<br/>    auth_config = optional(object({<br/>      named_value_key      = optional(string)<br/>      key_vault_secret_uri = optional(string)<br/>      secret_value         = optional(string)<br/>    }))<br/>    supported_models = list(object({<br/>      name                = string<br/>      sku                 = optional(string, "Standard")<br/>      capacity            = optional(number, 100)<br/>      modelFormat         = optional(string, "OpenAI")<br/>      modelVersion        = optional(string, "1")<br/>      apiVersion          = optional(string, "2024-02-15-preview")<br/>      timeout             = optional(number, 120)<br/>      inferenceApiVersion = optional(string, "")<br/>      retirementDate      = optional(string, "")<br/>    }))<br/>    priority = optional(number, 1)<br/>    weight   = optional(number, 100)<br/>  }))</pre> | `[]` | no |
| <a name="input_features"></a> [features](#input\_features) | Optional LLM APIs: unified\_ai\_api (+ product), ai\_model\_inference, openai\_realtime; api\_center\_onboarding registers the LLM APIs in API Center. | <pre>object({<br/>    unified_ai_api        = optional(bool, false)<br/>    ai_model_inference    = optional(bool, false)<br/>    openai_realtime       = optional(bool, false)<br/>    api_center_onboarding = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_foundry_backends"></a> [foundry\_backends](#input\_foundry\_backends) | LLM backends derived from the Foundry accounts of stacks/platform: one backend per<br/>account, serving every model deployed on it (read from Azure, so this file doesn't<br/>repeat the platform configuration).<br/>  enabled        false = only llm\_backend\_config / extra\_llm\_backends.<br/>  account\_names  null = every account in the workload resource group whose name<br/>                 starts with aif-<workload>-<environment>- (the naming contract).<br/>  api\_version    Inference API version for the derived models. | <pre>object({<br/>    enabled       = optional(bool, true)<br/>    account_names = optional(list(string))<br/>    api_version   = optional(string, "2024-02-15-preview")<br/>  })</pre> | `{}` | no |
| <a name="input_inference_api_type"></a> [inference\_api\_type](#input\_inference\_api\_type) | Universal LLM API contract (Bicep inferenceAPIType): AzureOpenAI, AzureAI, OpenAI or OpenAIV1. | `string` | `"OpenAIV1"` | no |
| <a name="input_llm_backend_config"></a> [llm\_backend\_config](#input\_llm\_backend\_config) | FULL override of the LLM backends (replaces the Foundry-derived list). One entry per endpoint:<br/>  backend\_id        unique id (APIM backend name)<br/>  backend\_type      ai-foundry \| azure-openai \| external \| aws-bedrock<br/>  endpoint          base URL<br/>  auth\_type         managed-identity \| aws-sigv4 \| api-key-bearer \| api-key-header \| none<br/>  auth\_config       named\_value\_key + key\_vault\_secret\_uri (versionless; secret\_value is for tests only)<br/>  supported\_models  models served (name, apiVersion, timeout, inferenceApiVersion, ...)<br/>  priority / weight load-balancing within a pool | <pre>list(object({<br/>    backend_id   = string<br/>    backend_type = string<br/>    endpoint     = string<br/>    auth_scheme  = optional(string)<br/>    auth_type    = optional(string)<br/>    auth_config = optional(object({<br/>      named_value_key      = optional(string)<br/>      key_vault_secret_uri = optional(string)<br/>      secret_value         = optional(string)<br/>    }))<br/>    supported_models = list(object({<br/>      name                = string<br/>      sku                 = optional(string, "Standard")<br/>      capacity            = optional(number, 100)<br/>      modelFormat         = optional(string, "OpenAI")<br/>      modelVersion        = optional(string, "1")<br/>      apiVersion          = optional(string, "2024-02-15-preview")<br/>      timeout             = optional(number, 120)<br/>      inferenceApiVersion = optional(string, "")<br/>      retirementDate      = optional(string, "")<br/>    }))<br/>    priority = optional(number, 1)<br/>    weight   = optional(number, 100)<br/>  }))</pre> | `[]` | no |
| <a name="input_model_aliases"></a> [model\_aliases](#input\_model\_aliases) | Model aliases: { name, models[], strategy (priority \| weighted), weights[] }. | <pre>list(object({<br/>    name     = string<br/>    models   = list(string)<br/>    strategy = optional(string, "priority")<br/>    weights  = optional(list(number), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | Naming inputs shared by all stacks (modules/naming, docs/naming.md).<br/>  unique\_seed     5 lowercase letters/digits; null = derived from subscription\_id, workload and environment.<br/>  name\_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }). | <pre>object({<br/>    unique_seed    = optional(string)<br/>    name_overrides = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.<br/>alz\_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.<br/>byo         no network stack; platform.tfvars carries all IDs. | `string` | `"greenfield"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource (merged with workload, environment, stack and managed-by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_names"></a> [api\_names](#output\_api\_names) | LLM APIs published by this stack (access contracts attach them to products). |
| <a name="output_backend_ids"></a> [backend\_ids](#output\_backend\_ids) | LLM backends. |
| <a name="output_models"></a> [models](#output\_models) | Model name => backend or pool that serves it. |
| <a name="output_pool_ids"></a> [pool\_ids](#output\_pool\_ids) | LLM backend pools (models served by more than one backend). |
| <a name="output_universal_llm_api_url"></a> [universal\_llm\_api\_url](#output\_universal\_llm\_api\_url) | Universal LLM API endpoint. |
<!-- END_TF_DOCS -->
