# gateway-config

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.12 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~> 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.81 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | ~> 2.12 |
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | ~> 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.81 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_api"></a> [api](#module\_api) | ../../modules/gateway-api | n/a |
| <a name="module_api_center_registration"></a> [api\_center\_registration](#module\_api\_center\_registration) | ../../modules/api-center-registration | n/a |
| <a name="module_api_dependent"></a> [api\_dependent](#module\_api\_dependent) | ../../modules/gateway-api | n/a |
| <a name="module_naming"></a> [naming](#module\_naming) | ../../modules/naming | n/a |
| <a name="module_shared_fragments"></a> [shared\_fragments](#module\_shared\_fragments) | ../../modules/apim-policy-fragments | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.content_safety_backend](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.embeddings_backend](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.ms_learn_mcp_backend](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_backend.ai_search](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_backend) | resource |
| [azurerm_api_management_named_value.plain](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azapi_resource.api_center](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource) | data source |
| [azuread_application.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/application) | data source |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azurerm_api_management.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/api_management) | data source |
| [azurerm_cognitive_account.content_safety](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/cognitive_account) | data source |
| [azurerm_cognitive_account.language](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/cognitive_account) | data source |
| [azurerm_cognitive_account.primary](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/cognitive_account) | data source |
| [azurerm_user_assigned_identity.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region (e.g. swedencentral). | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID. | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_ai_search_instances"></a> [ai\_search\_instances](#input\_ai\_search\_instances) | Existing AI Search endpoints registered as APIM backends (features.azure\_ai\_search). | <pre>list(object({<br/>    name     = string<br/>    endpoint = string<br/>  }))</pre> | `[]` | no |
| <a name="input_api_diagnostics"></a> [api\_diagnostics](#input\_api\_diagnostics) | Application Insights and Azure Monitor diagnostics on the service APIs (AI Search, Document Intelligence): enabled, headers and body bytes logged. | <pre>object({<br/>    enabled    = optional(bool, false)<br/>    headers    = optional(list(string), ["Content-type", "User-agent", "x-ms-region", "x-ratelimit-remaining-tokens", "x-ratelimit-remaining-requests"])<br/>    body_bytes = optional(number, 0)<br/>  })</pre> | `{}` | no |
| <a name="input_content_safety_service"></a> [content\_safety\_service](#input\_content\_safety\_service) | Where the content-safety backend and named value (features.content\_safety) point.<br/>  source  foundry    the primary Foundry account of stacks/platform (an AIServices account<br/>                     serves Content Safety too); the default.<br/>          dedicated  the standalone Content Safety account of stacks/platform<br/>                     (content\_safety\_service.enabled), found by name.<br/>          url        an existing Content Safety / AIServices endpoint you give in url.<br/>  url     Endpoint when source = url. | <pre>object({<br/>    source = optional(string, "foundry")<br/>    url    = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_embeddings_backend_url"></a> [embeddings\_backend\_url](#input\_embeddings\_backend\_url) | Foundry embeddings deployment endpoint for the semantic cache (features.embeddings\_backend). | `string` | `""` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo. | `bool` | `true` | no |
| <a name="input_entra_auth"></a> [entra\_auth](#input\_entra\_auth) | Entra ID JWT validation on the gateway (security-handler fragment; APIs then<br/>don't require a subscription key).<br/>  enabled         Validate Entra tokens.<br/>  tenant\_id / client\_id / audience<br/>                  null = taken from the gateway app of stacks/identity, found by<br/>                  its deterministic name (needs Graph Application.Read.All).<br/>  login\_endpoint  Entra authority (sovereign clouds differ). | <pre>object({<br/>    enabled        = optional(bool, false)<br/>    tenant_id      = optional(string)<br/>    client_id      = optional(string)<br/>    audience       = optional(string)<br/>    login_endpoint = optional(string, "https://login.microsoftonline.com/")<br/>  })</pre> | `{}` | no |
| <a name="input_features"></a> [features](#input\_features) | Model-agnostic gateway capabilities owned by this stack. | <pre>object({<br/>    pii_redaction         = optional(bool, true)<br/>    pii_anonymization     = optional(bool, true)<br/>    content_safety        = optional(bool, true)<br/>    azure_ai_search       = optional(bool, false)<br/>    document_intelligence = optional(bool, false)<br/>    embeddings_backend    = optional(bool, false)<br/>    mcp_sample            = optional(bool, false)<br/>    api_center_onboarding = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_foundry_primary_account_name"></a> [foundry\_primary\_account\_name](#input\_foundry\_primary\_account\_name) | Name of the primary Foundry account (PII and Content Safety endpoint). "" = the generated name of platform's first instance. | `string` | `""` | no |
| <a name="input_ms_learn_mcp_backend_url"></a> [ms\_learn\_mcp\_backend\_url](#input\_ms\_learn\_mcp\_backend\_url) | Backend URL of the Microsoft Learn MCP server (features.mcp\_sample). | `string` | `"https://learn.microsoft.com/api/mcp"` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | Naming inputs shared by all stacks (modules/naming, docs/naming.md).<br/>  unique\_seed     5 lowercase letters/digits; null = derived from subscription\_id, workload and environment.<br/>  name\_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }). | <pre>object({<br/>    unique_seed    = optional(string)<br/>    name_overrides = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.<br/>alz\_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.<br/>byo         no network stack; platform.tfvars carries all IDs. | `string` | `"greenfield"` | no |
| <a name="input_pii_service"></a> [pii\_service](#input\_pii\_service) | Where PII redaction and anonymization (features.pii\_redaction) call the Language API.<br/>  source  foundry    the primary Foundry account of stacks/platform (an AIServices account<br/>                     serves Language too); the default.<br/>          dedicated  the standalone Language account of stacks/platform<br/>                     (language\_service.enabled), found by name.<br/>          url        an existing Language / AIServices endpoint you give in url<br/>                     (the APIM identity needs Cognitive Services User on it).<br/>  url     Endpoint when source = url, e.g. https://<name>.cognitiveservices.azure.com/. | <pre>object({<br/>    source = optional(string, "foundry")<br/>    url    = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource (merged with workload, environment, stack and managed-by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_names"></a> [api\_names](#output\_api\_names) | Service APIs published by this stack. |
| <a name="output_fragment_names"></a> [fragment\_names](#output\_fragment\_names) | Shared policy fragments owned by this stack (llm-backend-onboarding policies reference them). |
| <a name="output_named_value_names"></a> [named\_value\_names](#output\_named\_value\_names) | Named values owned by this stack. |
<!-- END_TF_DOCS -->
