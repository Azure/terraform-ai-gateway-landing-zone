# Access contract

Onboards one use case to the gateway: per service code a product with its
policy, the mapped APIs, a subscription, optional Key Vault secrets (endpoint
and key) and an optional Foundry connection that calls the gateway.

Subscription keys never reach Terraform state. The subscription is an azapi
resource (APIM doesn't return keys on GET), the key is read with an ephemeral
`listSecrets` action, and it's only written to write-only arguments: the Key
Vault secret's `value_wo` and the Foundry connection's `sensitive_body`. Both
are rewritten when the `time_rotating` clock ticks (`secret_rotation_days`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.5, < 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.11, < 1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.5, < 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.11, < 1.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.foundry_connection](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.subscription](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_product.service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_product_policy.service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_policy) | resource |
| [azurerm_key_vault_secret.endpoint](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [time_rotating.secrets](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/rotating) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_management"></a> [api\_management](#input\_api\_management) | Target API Management service: id, name, resource group and gateway URL. | <pre>object({<br/>    id                  = string<br/>    name                = string<br/>    resource_group_name = string<br/>    gateway_url         = string<br/>  })</pre> | n/a | yes |
| <a name="input_api_name_mapping"></a> [api\_name\_mapping](#input\_api\_name\_mapping) | Service code => names of APIs already published in APIM, e.g. { LLM = ["universal-llm-api", "azure-openai-api"] }. | `map(list(string))` | n/a | yes |
| <a name="input_api_paths"></a> [api\_paths](#input\_api\_paths) | Service code => path of the first API in api\_name\_mapping (the endpoint written to Key Vault / used by Foundry). | `map(string)` | n/a | yes |
| <a name="input_services"></a> [services](#input\_services) | Services to onboard; each gets a product (policy) and a subscription.<br/>  code                  key in api\_name\_mapping, e.g. LLM<br/>  endpoint\_secret\_name  Key Vault secret for the endpoint URL<br/>  api\_key\_secret\_name   Key Vault secret for the subscription key<br/>  policy\_xml            product policy; "" = policies/default-ai-product-policy.xml | <pre>list(object({<br/>    code                 = string<br/>    endpoint_secret_name = string<br/>    api_key_secret_name  = string<br/>    policy_xml           = optional(string, "")<br/>  }))</pre> | n/a | yes |
| <a name="input_use_case"></a> [use\_case](#input\_use\_case) | Use case descriptor; products and subscriptions are named <code>-<business\_unit>-<use\_case\_name>-<environment>. | <pre>object({<br/>    business_unit = string<br/>    use_case_name = string<br/>    environment   = string<br/>  })</pre> | n/a | yes |
| <a name="input_foundry_config"></a> [foundry\_config](#input\_foundry\_config) | Foundry connection settings (Bicep foundryConfig).<br/>  connection\_name\_prefix  "" = Hub-<bu>-<usecase>-<env><br/>  connection\_category     ApiManagement \| ModelGateway<br/>  deployment\_in\_path      "true" (model in path) \| "false" (model in body)<br/>  is\_shared\_to\_all, inference\_api\_version, deployment\_api\_version, static\_models,<br/>  list\_models\_endpoint, get\_model\_endpoint, deployment\_provider ("" \| AzureOpenAI \| OpenAI),<br/>  custom\_headers, auth\_config | <pre>object({<br/>    connection_name_prefix = optional(string, "")<br/>    connection_category    = optional(string, "ApiManagement")<br/>    deployment_in_path     = optional(string, "false")<br/>    is_shared_to_all       = optional(bool, false)<br/>    inference_api_version  = optional(string, "")<br/>    deployment_api_version = optional(string, "")<br/>    static_models          = optional(list(any), [])<br/>    list_models_endpoint   = optional(string, "")<br/>    get_model_endpoint     = optional(string, "")<br/>    deployment_provider    = optional(string, "")<br/>    custom_headers         = optional(map(string), {})<br/>    auth_config            = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_foundry_project_id"></a> [foundry\_project\_id](#input\_foundry\_project\_id) | Foundry project that gets one connection per service, pointing at the gateway (key passed write-only). null = no connection. | `string` | `null` | no |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | Key Vault that receives the endpoint and key secrets (write-only: the key never enters state). null = no secrets. | `string` | `null` | no |
| <a name="input_product_terms"></a> [product\_terms](#input\_product\_terms) | Product terms of service shown to subscribers. | `string` | `""` | no |
| <a name="input_secret_rotation_days"></a> [secret\_rotation\_days](#input\_secret\_rotation\_days) | Days after which the key secrets are rewritten and their expiry pushed forward on the next apply. | `number` | `60` | no |
| <a name="input_secret_validity_days"></a> [secret\_validity\_days](#input\_secret\_validity\_days) | Key Vault secret validity (expiration\_date) in days; ALZ Enforce-GR-KeyVault allows at most 90. | `number` | `90` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoints"></a> [endpoints](#output\_endpoints) | Service code => gateway endpoint URL. |
| <a name="output_foundry_connections"></a> [foundry\_connections](#output\_foundry\_connections) | Service code => Foundry connection name (empty without a Foundry project). |
| <a name="output_key_vault_secret_names"></a> [key\_vault\_secret\_names](#output\_key\_vault\_secret\_names) | Service code => { endpoint, key } Key Vault secret names (empty without a Key Vault). |
| <a name="output_products"></a> [products](#output\_products) | Service code => product ID. |
| <a name="output_subscriptions"></a> [subscriptions](#output\_subscriptions) | Service code => subscription resource ID. |
<!-- END_TF_DOCS -->
