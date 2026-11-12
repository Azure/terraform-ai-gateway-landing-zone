# API Management service

Creates the API Management **service** and its own network, DNS and cache setup, on the Azure Verified Module `avm-res-apimanagement-service`. Called by [stacks/platform](../../stacks/platform/apim.tf); the caller passes the providers in.

## What it does

| Area | Behavior |
|---|---|
| SKU and scale | `Developer`, `Premium`, `StandardV2` or `PremiumV2`. Developer is fixed at one unit. Availability zones (`apim_zones`) need Premium and at least one unit per zone; the platform stack sets them for Premium with more than one unit. |
| Network model (`vnet_mode`) | `none`, `external` / `internal` (classic injection, Developer and Premium), `integration` (outbound VNet integration, StandardV2 and PremiumV2) or `injection` (PremiumV2, private VIP). Anything the SKU doesn't support fails at plan time. `public_ip_address_id` is for classic `external` / `internal` only. |
| Identity | One user-assigned managed identity (`managed_identity_id`). |
| Inbound private endpoint | For v2 SKUs with `vnet_mode` `none` or `integration` (`apim_v2_use_private_endpoint`). The zone group `apim-dns-group` is created unless Azure Policy owns it (`dns_zone_group_managed_by_policy`). |
| Public access (v2) | Azure rejects creating a v2 service with public access off, so a new service is created public and the next apply applies `apim_v2_public_network_access`. Turning public access off requires the private endpoint (or `injection`). Classic SKUs always keep public access. |
| Private DNS for a private VIP | With `internal` (five hostnames: gateway, portal, developer, management, scm) or `injection` (gateway only) and `create_internal_dns`, one private DNS zone per hostname, an `@` A record to the private IPs, and a link to `vnet_id`. Never an apex `azure-api.net` zone. Set `create_internal_dns = false` when the hub owns the zones. |
| External cache | `enable_redis_cache` links an existing Azure Managed Redis (`redis_cache_connection_string`) as the `Default` cache. |
| Hardening | Legacy protocols and weak ciphers stay off. Classic SKUs set the minimum management API version to 2021-08-01 (v2 SKUs don't take the setting). |

## Not in this module

Everything configured on the service lives elsewhere: loggers and diagnostics in [modules/apim-telemetry](../apim-telemetry/), policy fragments, named values, shared backends and service APIs in [stacks/gateway-config](../../stacks/gateway-config/), LLM backends, pools and APIs in [stacks/llm-backend-onboarding](../../stacks/llm-backend-onboarding/), and products and subscriptions in [stacks/access-contracts](../../stacks/access-contracts/).

Unit tests: [tests/unit.tftest.hcl](tests/unit.tftest.hcl) (mocked providers, `terraform test`).

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
| [azapi_resource.service_zone_redundant](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_named_value.redis_cache_connection_string](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_redis_cache.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_redis_cache) | resource |
| [azurerm_private_dns_a_record.internal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_a_record) | resource |
| [azurerm_private_dns_zone.internal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.internal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_endpoint.zone_redundant](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.zone_redundant_policy_dns](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [terraform_data.service_rules](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [azapi_resource.service_state](https://registry.terraform.io/providers/azure/azapi/latest/docs/data-sources/resource) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_name"></a> [apim\_name](#input\_apim\_name) | Name of the API Management service. | `string` | n/a | yes |
| <a name="input_apim_subnet_id"></a> [apim\_subnet\_id](#input\_apim\_subnet\_id) | Resource ID of the APIM subnet (VNet injection or outbound integration). | `string` | n/a | yes |
| <a name="input_apim_v2_public_network_access"></a> [apim\_v2\_public\_network\_access](#input\_apim\_v2\_public\_network\_access) | Allow public access for APIM V2 SKUs | `bool` | n/a | yes |
| <a name="input_apim_v2_use_private_endpoint"></a> [apim\_v2\_use\_private\_endpoint](#input\_apim\_v2\_use\_private\_endpoint) | Enable private endpoint for APIM V2 SKUs | `bool` | n/a | yes |
| <a name="input_dns_zone_id_apim"></a> [dns\_zone\_id\_apim](#input\_dns\_zone\_id\_apim) | Resource ID of the privatelink.azure-api.net DNS zone for the gateway private endpoint (empty = none). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_managed_identity_id"></a> [managed\_identity\_id](#input\_managed\_identity\_id) | Resource ID of the user-assigned managed identity the service runs as. | `string` | n/a | yes |
| <a name="input_pe_subnet_id"></a> [pe\_subnet\_id](#input\_pe\_subnet\_id) | Resource ID of the subnet that hosts private endpoints. | `string` | n/a | yes |
| <a name="input_publisher_email"></a> [publisher\_email](#input\_publisher\_email) | APIM publisher email | `string` | n/a | yes |
| <a name="input_publisher_name"></a> [publisher\_name](#input\_publisher\_name) | APIM publisher name | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_sku_capacity"></a> [sku\_capacity](#input\_sku\_capacity) | Number of APIM scale units | `number` | n/a | yes |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | APIM SKU: Developer, StandardV2, Premium, PremiumV2. REGION AVAILABILITY (important — v2 SKUs are NOT globally available): - Developer / Premium (classic): Globally available in virtually all Azure public regions. - StandardV2 / PremiumV2 (stv2 platform): Available in a limited subset of regions. Authoritative list (check before deploy): https://learn.microsoft.com/azure/api-management/api-management-region-availability az apim list-skus --location <region> If you hit `SkuNotSupportedInRegion` at apply time, either: (a) pick a supported region for `location`, or (b) fall back to `Premium` (classic) | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Subscription of the APIM service (existence probe for the public-access flip). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | Resource ID of the virtual network. | `string` | n/a | yes |
| <a name="input_vnet_mode"></a> [vnet\_mode](#input\_vnet\_mode) | APIM network mode: none \| external \| internal (Developer/Premium) \| integration (StandardV2/PremiumV2) \| injection (PremiumV2). | `string` | n/a | yes |
| <a name="input_apim_zones"></a> [apim\_zones](#input\_apim\_zones) | Availability zones for APIM (Premium only, skuCount>1). Computed at root; pass explicitly here. | `list(string)` | `[]` | no |
| <a name="input_create_internal_dns"></a> [create\_internal\_dns](#input\_create\_internal\_dns) | For vnet\_mode internal (classic: gateway, portal, developer, management, scm) or injection (Premium v2: gateway), create per-hostname private DNS zones and link them to the VNet. | `bool` | `true` | no |
| <a name="input_dns_zone_group_managed_by_policy"></a> [dns\_zone\_group\_managed\_by\_policy](#input\_dns\_zone\_group\_managed\_by\_policy) | Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone. | `bool` | `false` | no |
| <a name="input_enable_redis_cache"></a> [enable\_redis\_cache](#input\_enable\_redis\_cache) | Attach Azure Managed Redis as the APIM external cache (requires redis\_cache\_connection\_string\_secret\_id). | `bool` | `false` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_managed_identity_client_id"></a> [managed\_identity\_client\_id](#input\_managed\_identity\_client\_id) | Client ID of the user-assigned identity (managed\_identity\_id): reads the Key Vault-backed named values. | `string` | `null` | no |
| <a name="input_public_ip_address_id"></a> [public\_ip\_address\_id](#input\_public\_ip\_address\_id) | Classic external/internal injection only: Standard-SKU public IP resource ID for the service. null = Azure-managed. | `string` | `null` | no |
| <a name="input_redis_cache_connection_string_secret_id"></a> [redis\_cache\_connection\_string\_secret\_id](#input\_redis\_cache\_connection\_string\_secret\_id) | Versionless ID of the Key Vault secret holding the Azure Managed Redis connection string (modules/redis). Used when enable\_redis\_cache. | `string` | `null` | no |
| <a name="input_redis_cache_id"></a> [redis\_cache\_id](#input\_redis\_cache\_id) | Resource ID of the Azure Managed Redis cluster (shown on the APIM external cache). | `string` | `null` | no |
| <a name="input_system_assigned_identity"></a> [system\_assigned\_identity](#input\_system\_assigned\_identity) | Also give the service a system-assigned identity. Needed by the semantic cache: llm-semantic-cache-lookup calls the embeddings backend only as the system-assigned identity. | `bool` | `false` | no |
| <a name="input_zone_redundant"></a> [zone\_redundant](#input\_zone\_redundant) | StandardV2 / PremiumV2: create the service zone redundant (ARM zoneRedundant; set at creation only, Azure can't change it later). Classic Premium uses apim\_zones instead. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apim_id"></a> [apim\_id](#output\_apim\_id) | Resource ID of the API Management service. |
| <a name="output_apim_name"></a> [apim\_name](#output\_apim\_name) | Name of the API Management service. |
| <a name="output_gateway_url"></a> [gateway\_url](#output\_gateway\_url) | Gateway URL of the API Management service. |
| <a name="output_internal_dns_zone_names"></a> [internal\_dns\_zone\_names](#output\_internal\_dns\_zone\_names) | Private DNS zones created for the private VIP hostnames (empty when the hub provides them). |
| <a name="output_management_api_url"></a> [management\_api\_url](#output\_management\_api\_url) | Management API URL of the API Management service. |
| <a name="output_portal_url"></a> [portal\_url](#output\_portal\_url) | Developer portal URL (classic SKUs). |
| <a name="output_private_ip_addresses"></a> [private\_ip\_addresses](#output\_private\_ip\_addresses) | Private IP addresses of the APIM gateway (VNet-injected SKUs). |
| <a name="output_system_assigned_principal_id"></a> [system\_assigned\_principal\_id](#output\_system\_assigned\_principal\_id) | Principal ID of the service's system-assigned identity (null without system\_assigned\_identity). |
<!-- END_TF_DOCS -->
