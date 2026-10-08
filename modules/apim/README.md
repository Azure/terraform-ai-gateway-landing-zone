# API Management (AI gateway)

Creates the API Management service and everything that runs on it today: loggers and diagnostics, policy fragments, LLM backends and pools, the Universal LLM / Azure OpenAI / Unified AI APIs, the extra service APIs, named values and API Center onboarding. It's split into smaller modules in Phase 1 of the implementation plan.

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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_service"></a> [service](#module\_service) | Azure/avm-res-apimanagement-service/azurerm | 0.9.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.content_safety_backend](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.embeddings_backend](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.ms_learn_mcp_backend](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_backend.ai_search](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_backend) | resource |
| [azurerm_api_management_named_value.aws_access_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.aws_region](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.aws_secret_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.content_safety_url](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.entra_audience](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.entra_auth_flag](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.entra_client_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.entra_tenant_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.jwt_app_registration_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.jwt_issuer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.jwt_openid_config_url](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.jwt_tenant_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.pii_service_url](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.uami_client_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_product.default_contract](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.openai_default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_product_api.universal_llm_default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_redis_cache.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_redis_cache) | resource |
| [azurerm_api_management_subscription.foundry_connection](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_subscription) | resource |
| [azurerm_private_dns_a_record.internal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_a_record) | resource |
| [azurerm_private_dns_zone.internal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.internal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [terraform_data.service_rules](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [azapi_resource.service_state](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_name"></a> [apim\_name](#input\_apim\_name) | Name of the API Management service. | `string` | n/a | yes |
| <a name="input_apim_network_type"></a> [apim\_network\_type](#input\_apim\_network\_type) | APIM network type: 'External', 'Internal', or 'None' | `string` | n/a | yes |
| <a name="input_apim_subnet_id"></a> [apim\_subnet\_id](#input\_apim\_subnet\_id) | Resource ID of the APIM subnet (VNet injection or outbound integration). | `string` | n/a | yes |
| <a name="input_apim_v2_public_network_access"></a> [apim\_v2\_public\_network\_access](#input\_apim\_v2\_public\_network\_access) | Allow public access for APIM V2 SKUs | `bool` | n/a | yes |
| <a name="input_apim_v2_use_private_endpoint"></a> [apim\_v2\_use\_private\_endpoint](#input\_apim\_v2\_use\_private\_endpoint) | Enable private endpoint for APIM V2 SKUs | `bool` | n/a | yes |
| <a name="input_content_safety_endpoint"></a> [content\_safety\_endpoint](#input\_content\_safety\_endpoint) | Endpoint of the content-safety service (Foundry); empty when content safety is off. | `string` | n/a | yes |
| <a name="input_default_product_api_names"></a> [default\_product\_api\_names](#input\_default\_product\_api\_names) | Names of the APIs linked to the default-ai-access product (root apis.tf). | <pre>object({<br/>    universal_llm = string<br/>    azure_openai  = string<br/>  })</pre> | n/a | yes |
| <a name="input_dns_zone_id_apim"></a> [dns\_zone\_id\_apim](#input\_dns\_zone\_id\_apim) | Resource ID of the privatelink.azure-api.net DNS zone for the gateway private endpoint (empty = none). | `string` | n/a | yes |
| <a name="input_enable_content_safety"></a> [enable\_content\_safety](#input\_enable\_content\_safety) | Enable Azure AI Content Safety | `bool` | n/a | yes |
| <a name="input_enable_pii_redaction"></a> [enable\_pii\_redaction](#input\_enable\_pii\_redaction) | Enable PII detection and masking via Language Service | `bool` | n/a | yes |
| <a name="input_entra_audience"></a> [entra\_audience](#input\_entra\_audience) | Entra ID audience (resource identifier) | `string` | n/a | yes |
| <a name="input_entra_auth_enabled"></a> [entra\_auth\_enabled](#input\_entra\_auth\_enabled) | Enable Entra ID JWT validation on APIM | `bool` | n/a | yes |
| <a name="input_entra_client_id"></a> [entra\_client\_id](#input\_entra\_client\_id) | Entra ID client ID (application ID) | `string` | n/a | yes |
| <a name="input_entra_tenant_id"></a> [entra\_tenant\_id](#input\_entra\_tenant\_id) | Entra ID tenant ID for JWT validation | `string` | n/a | yes |
| <a name="input_is_apim_v2"></a> [is\_apim\_v2](#input\_is\_apim\_v2) | True when the APIM SKU is a v2 SKU (BasicV2, StandardV2 or PremiumV2). | `bool` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_managed_identity_client_id"></a> [managed\_identity\_client\_id](#input\_managed\_identity\_client\_id) | Client ID of the user-assigned managed identity the service runs as. | `string` | n/a | yes |
| <a name="input_managed_identity_id"></a> [managed\_identity\_id](#input\_managed\_identity\_id) | Resource ID of the user-assigned managed identity the service runs as. | `string` | n/a | yes |
| <a name="input_pe_subnet_id"></a> [pe\_subnet\_id](#input\_pe\_subnet\_id) | Resource ID of the subnet that hosts private endpoints. | `string` | n/a | yes |
| <a name="input_pii_service_endpoint"></a> [pii\_service\_endpoint](#input\_pii\_service\_endpoint) | Endpoint of the PII detection service (Foundry Language); empty when PII redaction is off. | `string` | n/a | yes |
| <a name="input_publisher_email"></a> [publisher\_email](#input\_publisher\_email) | APIM publisher email | `string` | n/a | yes |
| <a name="input_publisher_name"></a> [publisher\_name](#input\_publisher\_name) | APIM publisher name | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_sku_capacity"></a> [sku\_capacity](#input\_sku\_capacity) | Number of APIM scale units | `number` | n/a | yes |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | APIM SKU: Developer, StandardV2, Premium, PremiumV2. REGION AVAILABILITY (important — v2 SKUs are NOT globally available): - Developer / Premium (classic): Globally available in virtually all Azure public regions. - StandardV2 / PremiumV2 (stv2 platform): Available in a limited subset of regions. Authoritative list (check before deploy): https://learn.microsoft.com/azure/api-management/api-management-region-availability az apim list-skus --location <region> If you hit `SkuNotSupportedInRegion` at apply time, either: (a) pick a supported region for `location`, or (b) fall back to `Premium` (classic) | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Subscription of the APIM service (existence probe for the public-access flip). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | Resource ID of the virtual network. | `string` | n/a | yes |
| <a name="input_ai_search_instances"></a> [ai\_search\_instances](#input\_ai\_search\_instances) | Existing AI Search endpoints to register as APIM backends. | <pre>list(object({<br/>    name        = string<br/>    description = optional(string, "AI Search backend")<br/>    url         = string<br/>  }))</pre> | `[]` | no |
| <a name="input_apim_zones"></a> [apim\_zones](#input\_apim\_zones) | Availability zones for APIM (Premium only, skuCount>1). Computed at root; pass explicitly here. | `list(string)` | `[]` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for AWS Bedrock backends (APIM named value). | `string` | `""` | no |
| <a name="input_azure_login_endpoint"></a> [azure\_login\_endpoint](#input\_azure\_login\_endpoint) | Entra login endpoint (e.g. https://login.microsoftonline.com/). | `string` | `"https://login.microsoftonline.com/"` | no |
| <a name="input_create_internal_dns"></a> [create\_internal\_dns](#input\_create\_internal\_dns) | For apim\_network\_type = Internal (Developer/Premium), create per-hostname private DNS zones for the gateway/portal/developer/management/scm endpoints and link them to the VNet. | `bool` | `true` | no |
| <a name="input_dns_zone_group_managed_by_policy"></a> [dns\_zone\_group\_managed\_by\_policy](#input\_dns\_zone\_group\_managed\_by\_policy) | Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone. | `bool` | `false` | no |
| <a name="input_embeddings_backend_id"></a> [embeddings\_backend\_id](#input\_embeddings\_backend\_id) | APIM backend ID of the embeddings backend used by semantic caching. | `string` | `"foundry-embeddings"` | no |
| <a name="input_embeddings_backend_url"></a> [embeddings\_backend\_url](#input\_embeddings\_backend\_url) | Foundry embeddings deployment endpoint (consumed only when enable\_embeddings\_backend = true). | `string` | `""` | no |
| <a name="input_enable_azure_ai_search"></a> [enable\_azure\_ai\_search](#input\_enable\_azure\_ai\_search) | Enable Azure AI Search Index API in APIM. | `bool` | `false` | no |
| <a name="input_enable_embeddings_backend"></a> [enable\_embeddings\_backend](#input\_enable\_embeddings\_backend) | Register a Foundry embeddings backend for semantic caching. | `bool` | `false` | no |
| <a name="input_enable_foundry_apim_connection"></a> [enable\_foundry\_apim\_connection](#input\_enable\_foundry\_apim\_connection) | Create a dedicated APIM subscription for Foundry connections. | `bool` | `false` | no |
| <a name="input_enable_jwt_auth"></a> [enable\_jwt\_auth](#input\_enable\_jwt\_auth) | When true, JWT-* named values are populated from jwt\_tenant\_id / jwt\_app\_registration\_id. | `bool` | `false` | no |
| <a name="input_enable_redis_cache"></a> [enable\_redis\_cache](#input\_enable\_redis\_cache) | Attach Azure Managed Redis as the APIM external cache (requires redis\_cache\_connection\_string). | `bool` | `false` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_is_mcp_sample_deployed"></a> [is\_mcp\_sample\_deployed](#input\_is\_mcp\_sample\_deployed) | Deploy the sample MCP server (weather-api / weather-mcp / ms-learn-mcp). | `bool` | `false` | no |
| <a name="input_jwt_app_registration_id"></a> [jwt\_app\_registration\_id](#input\_jwt\_app\_registration\_id) | Entra application (client) ID used as the JWT audience. | `string` | `""` | no |
| <a name="input_jwt_tenant_id"></a> [jwt\_tenant\_id](#input\_jwt\_tenant\_id) | Entra tenant ID used by the JWT-validation policies. | `string` | `""` | no |
| <a name="input_ms_learn_mcp_backend_url"></a> [ms\_learn\_mcp\_backend\_url](#input\_ms\_learn\_mcp\_backend\_url) | Backend URL for the MS Learn MCP server. | `string` | `"https://learn.microsoft.com/api/mcp"` | no |
| <a name="input_redis_cache_connection_string"></a> [redis\_cache\_connection\_string](#input\_redis\_cache\_connection\_string) | Optional Azure Managed Redis connection string. When set, creates an APIM service/caches resource. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apim_id"></a> [apim\_id](#output\_apim\_id) | Resource ID of the API Management service. |
| <a name="output_apim_name"></a> [apim\_name](#output\_apim\_name) | Name of the API Management service. |
| <a name="output_foundry_connection_primary_key"></a> [foundry\_connection\_primary\_key](#output\_foundry\_connection\_primary\_key) | Primary key of the APIM subscription used by the Foundry connection (sensitive; internal wiring only). |
| <a name="output_gateway_url"></a> [gateway\_url](#output\_gateway\_url) | Gateway URL of the API Management service. |
| <a name="output_management_api_url"></a> [management\_api\_url](#output\_management\_api\_url) | Management API URL of the API Management service. |
| <a name="output_ms_learn_mcp_backend_id"></a> [ms\_learn\_mcp\_backend\_id](#output\_ms\_learn\_mcp\_backend\_id) | Resource ID of the MS Learn MCP backend (null when the MCP samples are off). |
| <a name="output_named_value_ids"></a> [named\_value\_ids](#output\_named\_value\_ids) | IDs of the named values that policy fragments reference (fragments must be created after them). |
| <a name="output_portal_url"></a> [portal\_url](#output\_portal\_url) | Developer portal URL (classic SKUs). |
| <a name="output_private_ip_addresses"></a> [private\_ip\_addresses](#output\_private\_ip\_addresses) | Private IP addresses of the APIM gateway (VNet-injected SKUs). |
<!-- END_TF_DOCS -->
