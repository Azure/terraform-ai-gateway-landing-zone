# Azure Managed Redis

Creates the Azure Managed Redis cluster (`Microsoft.Cache/redisEnterprise`, API 2025-07-01, through `azapi` because azurerm doesn't model the `Balanced_*` SKUs) and its `default` database, the APIM external cache:

- the database uses access-key authentication, `NoEviction`, the `EnterpriseCluster` clustering policy, encrypted clients, the RediSearch module and port 10000; `sku_capacity` only applies to the `Enterprise_*` and `EnterpriseFlash_*` SKUs;
- an optional `redisEnterprise` private endpoint (`use_private_endpoint`) with the zone group `redis-dns-group`, or without one when Azure Policy owns it;
- the connection string (`host:port,password=<key>,ssl=true`) for the APIM external cache, written to a Key Vault secret (`key_vault_id`, `connection_string_secret_name`). The primary key is read with an ephemeral `listKeys` and goes only to the secret's write-only value, so it's never in Terraform state. APIM can't use Entra authentication for Azure Managed Redis, hence the key. The secret is rewritten (and its 90-day expiry pushed forward) every 60 days; after regenerating the Redis keys, re-apply with `-replace` on `azurerm_key_vault_secret.connection_string`.

Called by [stacks/platform](../../stacks/platform/redis-apic.tf) when `features.semantic_cache` is on; the APIM module links the cache to the service through a Key Vault-backed named value (`connection_string_secret_id`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9, < 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.11, < 1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.9, < 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.11, < 1.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.redis](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.redis_db](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_key_vault_secret.connection_string](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_private_endpoint.redis](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.redis_policy_dns](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [time_rotating.connection_string](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/rotating) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Redis private DNS zone id (privatelink.redis.azure.net). | `string` | n/a | yes |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | Key Vault for the connection-string secret the APIM external cache reads (writer needs Key Vault Secrets Officer, and the data plane reachable). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the Azure Managed Redis (Redis Enterprise) cluster. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Private endpoint subnet id. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_connection_string_secret_name"></a> [connection\_string\_secret\_name](#input\_connection\_string\_secret\_name) | Name of the Key Vault secret with the connection string. | `string` | `"apim-redis-cache-connection-string"` | no |
| <a name="input_dns_zone_group_managed_by_policy"></a> [dns\_zone\_group\_managed\_by\_policy](#input\_dns\_zone\_group\_managed\_by\_policy) | Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone. | `bool` | `false` | no |
| <a name="input_minimum_tls_version"></a> [minimum\_tls\_version](#input\_minimum\_tls\_version) | Minimum TLS version accepted by Azure Managed Redis. | `string` | `"1.2"` | no |
| <a name="input_public_network_access"></a> [public\_network\_access](#input\_public\_network\_access) | Enabled or Disabled for the Redis Enterprise cluster. | `string` | `"Disabled"` | no |
| <a name="input_sku_capacity"></a> [sku\_capacity](#input\_sku\_capacity) | Cluster capacity (only used for Enterprise\_* and EnterpriseFlash\_* SKUs). | `number` | `2` | no |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | Azure Managed Redis SKU (Microsoft.Cache/redisEnterprise). | `string` | `"Balanced_B10"` | no |
| <a name="input_use_private_endpoint"></a> [use\_private\_endpoint](#input\_use\_private\_endpoint) | Create a private endpoint for Azure Managed Redis. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_connection_string_secret_id"></a> [connection\_string\_secret\_id](#output\_connection\_string\_secret\_id) | Versionless ID of the Key Vault secret with the connection string (host:port,password=<key>,ssl=true) for the APIM external cache. |
| <a name="output_host_name"></a> [host\_name](#output\_host\_name) | Host name of the Azure Managed Redis cluster. |
| <a name="output_port"></a> [port](#output\_port) | Port of the Redis database. |
| <a name="output_redis_id"></a> [redis\_id](#output\_redis\_id) | Resource ID of the Azure Managed Redis cluster. |
<!-- END_TF_DOCS -->
