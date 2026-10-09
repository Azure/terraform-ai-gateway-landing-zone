# Access contract

Onboards one use case to the gateway. For each service code in `services` it creates an APIM product named `<code>-<business unit>-<use case>-<environment>` with its policy, links the APIs mapped to that code (`api_name_mapping`, `api_paths`) and creates a subscription. Optionally it writes the endpoint and key as Key Vault secrets (`key_vault_id`) and creates a Foundry project connection to the gateway (`foundry_project_id`).

## Product policy

The policy is generated from the service's properties with [policies/product-policy.xml.tftpl](policies/product-policy.xml.tftpl), so a contract's tfvars holds no XML:

| Property | Default | Generates |
|---|---|---|
| `allowed_models` | `[]` (every model) | `allowedModels` and the `validate-model-access` fragment |
| `token_limit` (`tokens_per_minute`, `token_quota`, `token_quota_period`) | `null` (no limit) | an `llm-token-limit` per subscription |
| `enable_response_headers` | `true` | `enableResponseHeaders` (the `UAIG-*` debug headers) |
| `jwt_required` | `false` | the JWT validation variables (see Foundry connection below); needs `tenant_id` |

Every policy also calls `set-llm-requested-model` and carries the commented throttling-event hint in `on-error`.

**Mixed asset types.** A product can grant LLM APIs together with tools (MCP) and agents (A2A). List the granted tool and agent APIs by APIM API name and the policy classifies each request with the `set-asset-kind` fragment (stacks/gateway-config), then applies the right controls per type, as upstream's `default-multi-product-policy.xml` does:

| Property | Default | Generates |
|---|---|---|
| `tool_apis`, `agent_apis` | `[]` | `contractToolApis` / `contractAgentApis`, the `set-asset-kind` include and a `<choose>`; the LLM rules above move into the LLM branch. They must be in `api_name_mapping` for the service. |
| `tool_limit`, `agent_limit` (`calls_per_minute`, `call_quota`, `call_quota_period`) | `null` (no limit) | a `rate-limit-by-key` (per minute) and a `quota-by-key` (per period) in that asset kind's branch. They need the matching `*_apis`. |

With no tool or agent APIs the policy has no classification. The first API of `api_name_mapping[code]` is the product's endpoint, so list the LLM API first. `policy_xml` is the advanced escape hatch: a complete policy that replaces the generated one, ignoring the properties above.

Subscription keys never reach Terraform state. The subscription is an azapi
resource (APIM doesn't return keys on GET), the key is read with an ephemeral
`listSecrets` action, and it's only written to write-only arguments: the Key
Vault secret's `value_wo` and the Foundry connection's `sensitive_body`. Both
are rewritten when the `time_rotating` clock ticks (`secret_rotation_days`);
the secrets expire after `secret_validity_days`.

## Foundry connection

The connection (`foundry_config.connection_category`: `ApiManagement` or `ModelGateway`) authenticates in one of two ways (`foundry_config.auth_type`):

- `ProjectManagedIdentity` (default): the Foundry project's managed identity sends an Entra token for `managed_identity_audience`, and the subscription key travels as the `api-key` custom header. The product policy has to validate that token: set `jwt_required = true` and the generated policy sets `jwtRequired`, `jwtAudience` (= `managed_identity_audience`), `jwtIssuer` and `jwtOpenIdConfigUrl` for `tenant_id`. A `check` warns when a service has neither `jwt_required` nor a custom `policy_xml` that sets `jwtRequired`. The `foundry_connection_auth` output reports the audience to validate.
- `ApiKey`: the subscription key is the connection's credential and no token is involved.

Called by [stacks/access-contracts](../../stacks/access-contracts/main.tf), once per use case (one state per `environments/<env>/access-contracts/<use-case>.tfvars`).

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
| <a name="input_services"></a> [services](#input\_services) | Services to onboard; each gets a product, its policy and a subscription.<br/>  code                     key in api\_name\_mapping, e.g. LLM<br/>  endpoint\_secret\_name     Key Vault secret for the endpoint URL<br/>  api\_key\_secret\_name      Key Vault secret for the subscription key<br/>The product policy is generated from these properties:<br/>  allowed\_models           models (and aliases) the contract may call; [] = every model<br/>  token\_limit              per-subscription limit (llm-token-limit): tokens\_per\_minute and / or<br/>                           token\_quota, with token\_quota\_period (Hourly \| Daily \| Weekly \| Monthly \| Yearly);<br/>                           null = no limit<br/>  enable\_response\_headers  the UAIG-* debug response headers (set-response-headers fragment)<br/>  jwt\_required             also validate the Entra token the Foundry connection sends<br/>                           (audience = foundry\_config.managed\_identity\_audience, tenant = tenant\_id)<br/>One product can grant a mix of asset types (LLM + tools (MCP) + agents (A2A)). List the granted<br/>tool and agent APIs by APIM API name (they must be in api\_name\_mapping[code]); every other API of the<br/>service is an LLM API, and allowed\_models, token\_limit and enable\_response\_headers apply to those only:<br/>  tool\_apis / agent\_apis   API names granted as tools / agents ([] = none)<br/>  tool\_limit / agent\_limit per-subscription request limits (rate-limit-by-key + quota-by-key):<br/>                           calls\_per\_minute and / or call\_quota, with call\_quota\_period<br/>                           (Hourly \| Daily \| Weekly \| Monthly \| Yearly); null = no limit.<br/>                           Needs the matching *\_apis.<br/>policy\_xml                 advanced: a complete product policy that replaces the generated one<br/>                           (the properties above are then ignored) | <pre>list(object({<br/>    code                 = string<br/>    endpoint_secret_name = string<br/>    api_key_secret_name  = string<br/><br/>    allowed_models = optional(list(string), [])<br/>    token_limit = optional(object({<br/>      tokens_per_minute  = optional(number)<br/>      token_quota        = optional(number)<br/>      token_quota_period = optional(string, "Monthly")<br/>    }))<br/>    enable_response_headers = optional(bool, true)<br/>    jwt_required            = optional(bool, false)<br/><br/>    tool_apis = optional(list(string), [])<br/>    tool_limit = optional(object({<br/>      calls_per_minute  = optional(number)<br/>      call_quota        = optional(number)<br/>      call_quota_period = optional(string, "Monthly")<br/>    }))<br/>    agent_apis = optional(list(string), [])<br/>    agent_limit = optional(object({<br/>      calls_per_minute  = optional(number)<br/>      call_quota        = optional(number)<br/>      call_quota_period = optional(string, "Monthly")<br/>    }))<br/><br/>    policy_xml = optional(string, "")<br/>  }))</pre> | n/a | yes |
| <a name="input_use_case"></a> [use\_case](#input\_use\_case) | Use case descriptor; products and subscriptions are named <code>-<business\_unit>-<use\_case\_name>-<environment>. | <pre>object({<br/>    business_unit = string<br/>    use_case_name = string<br/>    environment   = string<br/>  })</pre> | n/a | yes |
| <a name="input_foundry_config"></a> [foundry\_config](#input\_foundry\_config) | Foundry connection settings.<br/>  connection\_name\_prefix  "" = Hub-<bu>-<usecase>-<env><br/>  connection\_category     ApiManagement \| ModelGateway<br/>  auth\_type               ProjectManagedIdentity (default) \| ApiKey.<br/>                          ProjectManagedIdentity: the Foundry project's managed identity sends an<br/>                          Entra JWT for managed\_identity\_audience AND the subscription key travels<br/>                          as the `api-key` custom header (no stored credential). The product policy<br/>                          must validate that JWT (jwtRequired + jwtAudience/jwtIssuer/jwtOpenIdConfigUrl,<br/>                          see DEPLOYMENT\_GUIDE "Foundry connection authentication"); a check warns when<br/>                          it doesn't. ApiKey: the subscription key is the stored credential.<br/>  managed\_identity\_audience<br/>                          Audience the project identity requests a token for; must equal the audience<br/>                          the product policy validates. Only for ProjectManagedIdentity.<br/>  deployment\_in\_path      "true" (model in path) \| "false" (model in body)<br/>  is\_shared\_to\_all, inference\_api\_version, deployment\_api\_version, static\_models,<br/>  list\_models\_endpoint, get\_model\_endpoint, deployment\_provider ("" \| AzureOpenAI \| OpenAI),<br/>  custom\_headers (the api-key header is added automatically for ProjectManagedIdentity), auth\_config | <pre>object({<br/>    connection_name_prefix = optional(string, "")<br/>    connection_category    = optional(string, "ApiManagement")<br/>    auth_type              = optional(string, "ProjectManagedIdentity")<br/>    deployment_in_path     = optional(string, "false")<br/>    is_shared_to_all       = optional(bool, false)<br/>    inference_api_version  = optional(string, "")<br/>    deployment_api_version = optional(string, "")<br/>    static_models          = optional(list(any), [])<br/>    list_models_endpoint   = optional(string, "")<br/>    get_model_endpoint     = optional(string, "")<br/>    deployment_provider    = optional(string, "")<br/>    custom_headers         = optional(map(string), {})<br/>    auth_config            = optional(map(string), {})<br/><br/>    managed_identity_audience = optional(string, "https://cognitiveservices.azure.com")<br/>  })</pre> | `{}` | no |
| <a name="input_foundry_project_id"></a> [foundry\_project\_id](#input\_foundry\_project\_id) | Foundry project that gets one connection per service, pointing at the gateway (key passed write-only). null = no connection. | `string` | `null` | no |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | Key Vault that receives the endpoint and key secrets (write-only: the key never enters state). null = no secrets. | `string` | `null` | no |
| <a name="input_product_terms"></a> [product\_terms](#input\_product\_terms) | Product terms of service shown to subscribers. | `string` | `""` | no |
| <a name="input_secret_rotation_days"></a> [secret\_rotation\_days](#input\_secret\_rotation\_days) | Days after which the key secrets are rewritten and their expiry pushed forward on the next apply. | `number` | `60` | no |
| <a name="input_secret_validity_days"></a> [secret\_validity\_days](#input\_secret\_validity\_days) | Key Vault secret validity (expiration\_date) in days; ALZ Enforce-GR-KeyVault allows at most 90. | `number` | `90` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Entra tenant ID of the Foundry project identity's tokens; the issuer of the generated JWT policy (services[*].jwt\_required). | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoints"></a> [endpoints](#output\_endpoints) | Service code => gateway endpoint URL. |
| <a name="output_foundry_connection_auth"></a> [foundry\_connection\_auth](#output\_foundry\_connection\_auth) | Foundry connection authentication: auth\_type, and the token audience the product policy must validate (empty for ApiKey). |
| <a name="output_foundry_connections"></a> [foundry\_connections](#output\_foundry\_connections) | Service code => Foundry connection name (empty without a Foundry project). |
| <a name="output_key_vault_secret_names"></a> [key\_vault\_secret\_names](#output\_key\_vault\_secret\_names) | Service code => { endpoint, key } Key Vault secret names (empty without a Key Vault). |
| <a name="output_products"></a> [products](#output\_products) | Service code => product ID. |
| <a name="output_subscriptions"></a> [subscriptions](#output\_subscriptions) | Service code => subscription resource ID. |
<!-- END_TF_DOCS -->
