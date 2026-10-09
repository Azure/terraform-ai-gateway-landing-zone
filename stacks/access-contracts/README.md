# access-contracts

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.12 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.81 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.11 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.81 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_contract"></a> [contract](#module\_contract) | ../../modules/access-contract | n/a |
| <a name="module_naming"></a> [naming](#module\_naming) | ../../modules/naming | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_api_management.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/api_management) | data source |
| [azurerm_api_management_api.first](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/api_management_api) | data source |
| [azurerm_key_vault.platform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_name_mapping"></a> [api\_name\_mapping](#input\_api\_name\_mapping) | Service code => names of published APIs, e.g. { LLM = ["universal-llm-api", "azure-openai-api"] }. | `map(list(string))` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region (e.g. swedencentral). | `string` | n/a | yes |
| <a name="input_services"></a> [services](#input\_services) | Services to onboard (code, endpoint\_secret\_name, api\_key\_secret\_name, policy\_xml); see modules/access-contract. | <pre>list(object({<br/>    code                 = string<br/>    endpoint_secret_name = string<br/>    api_key_secret_name  = string<br/>    policy_xml           = optional(string, "")<br/>  }))</pre> | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID. | `string` | n/a | yes |
| <a name="input_use_case"></a> [use\_case](#input\_use\_case) | Use case descriptor; products and subscriptions are named <code>-<business\_unit>-<use\_case\_name>-<environment>. | <pre>object({<br/>    business_unit = string<br/>    use_case_name = string<br/>    environment   = string<br/>  })</pre> | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo. | `bool` | `true` | no |
| <a name="input_foundry"></a> [foundry](#input\_foundry) | Foundry project that gets a connection per service. account\_name "" = platform's primary account; project\_id overrides both names (e.g. a team-owned project). | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    account_name = optional(string, "")<br/>    project_name = optional(string, "citadel-governance-project")<br/>    project_id   = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_foundry_config"></a> [foundry\_config](#input\_foundry\_config) | Foundry connection settings (Bicep foundryConfig).<br/>  connection\_name\_prefix  "" = Hub-<bu>-<usecase>-<env><br/>  connection\_category     ApiManagement \| ModelGateway<br/>  auth\_type               ProjectManagedIdentity (default) \| ApiKey. With ProjectManagedIdentity the<br/>                          Foundry project's managed identity sends an Entra JWT for<br/>                          managed\_identity\_audience and the subscription key travels as the api-key<br/>                          custom header; the product policy must validate that JWT (see modules/access-contract).<br/>  managed\_identity\_audience  token audience; must equal the jwtAudience the product policy validates<br/>  deployment\_in\_path      "true" (model in path) \| "false" (model in body)<br/>  is\_shared\_to\_all, inference\_api\_version, deployment\_api\_version, static\_models,<br/>  list\_models\_endpoint, get\_model\_endpoint, deployment\_provider ("" \| AzureOpenAI \| OpenAI),<br/>  custom\_headers, auth\_config | <pre>object({<br/>    connection_name_prefix = optional(string, "")<br/>    connection_category    = optional(string, "ApiManagement")<br/>    auth_type              = optional(string, "ProjectManagedIdentity")<br/>    deployment_in_path     = optional(string, "false")<br/>    is_shared_to_all       = optional(bool, false)<br/>    inference_api_version  = optional(string, "")<br/>    deployment_api_version = optional(string, "")<br/>    static_models          = optional(list(any), [])<br/>    list_models_endpoint   = optional(string, "")<br/>    get_model_endpoint     = optional(string, "")<br/>    deployment_provider    = optional(string, "")<br/>    custom_headers         = optional(map(string), {})<br/>    auth_config            = optional(map(string), {})<br/><br/>    managed_identity_audience = optional(string, "https://cognitiveservices.azure.com")<br/>  })</pre> | `{}` | no |
| <a name="input_key_vault"></a> [key\_vault](#input\_key\_vault) | Where the endpoint and key secrets go. enabled = false: no secrets (endpoints in outputs, keys from APIM on demand). id null = the platform Key Vault; set it for a team-owned vault. | <pre>object({<br/>    enabled = optional(bool, true)<br/>    id      = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | Naming inputs shared by all stacks (modules/naming, docs/naming.md).<br/>  unique\_seed     5 lowercase letters/digits; null = derived from subscription\_id, workload and environment.<br/>  name\_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }). | <pre>object({<br/>    unique_seed    = optional(string)<br/>    name_overrides = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.<br/>alz\_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.<br/>byo         no network stack; platform.tfvars carries all IDs. | `string` | `"greenfield"` | no |
| <a name="input_product_terms"></a> [product\_terms](#input\_product\_terms) | Product terms of service shown to subscribers. | `string` | `""` | no |
| <a name="input_secret_rotation_days"></a> [secret\_rotation\_days](#input\_secret\_rotation\_days) | Days after which the key secrets are rewritten on the next apply. | `number` | `60` | no |
| <a name="input_secret_validity_days"></a> [secret\_validity\_days](#input\_secret\_validity\_days) | Key Vault secret validity in days (ALZ Enforce-GR-KeyVault allows at most 90). | `number` | `90` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource (merged with workload, environment, stack and managed-by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoints"></a> [endpoints](#output\_endpoints) | Service code => gateway endpoint URL. |
| <a name="output_foundry_connection_auth"></a> [foundry\_connection\_auth](#output\_foundry\_connection\_auth) | Foundry connection authentication: auth\_type and the token audience the product policy must validate (empty for ApiKey). |
| <a name="output_foundry_connections"></a> [foundry\_connections](#output\_foundry\_connections) | Service code => Foundry connection name. |
| <a name="output_key_vault_secret_names"></a> [key\_vault\_secret\_names](#output\_key\_vault\_secret\_names) | Service code => { endpoint, key } Key Vault secret names. |
| <a name="output_products"></a> [products](#output\_products) | Service code => product ID. |
| <a name="output_subscriptions"></a> [subscriptions](#output\_subscriptions) | Service code => subscription resource ID (keys are never in state: read them from Key Vault or APIM). |
<!-- END_TF_DOCS -->
