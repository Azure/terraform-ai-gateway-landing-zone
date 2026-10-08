# Key Vault

Creates the Key Vault (RBAC mode, purge protection), its private endpoint and network rules, the role assignments for the deployer and APIM identity, and optional placeholder secrets.

This module is called by the root configuration (`main.tf`). It configures no providers; the caller passes them in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.11, < 1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.11, < 1.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | Azure/avm-res-keyvault-vault/azurerm | 0.11.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_key_vault_secret.apim_subscription_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [time_rotating.apim_gateway_key_secret](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/rotating) | resource |
| [time_sleep.wait_for_kv_acl](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_for_kv_rbac](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_deployer_object_id"></a> [deployer\_object\_id](#input\_deployer\_object\_id) | Object ID of the identity running Terraform; granted Key Vault data-plane access so it can write secrets. | `string` | n/a | yes |
| <a name="input_dns_zone_id_key_vault"></a> [dns\_zone\_id\_key\_vault](#input\_dns\_zone\_id\_key\_vault) | Resource ID of the privatelink.vaultcore.azure.net DNS zone (empty = no DNS zone group). | `string` | n/a | yes |
| <a name="input_key_vault_name"></a> [key\_vault\_name](#input\_key\_vault\_name) | Name of the Key Vault. | `string` | n/a | yes |
| <a name="input_key_vault_sku"></a> [key\_vault\_sku](#input\_key\_vault\_sku) | Key Vault SKU | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region for deployment | `string` | n/a | yes |
| <a name="input_managed_identity_principal_id"></a> [managed\_identity\_principal\_id](#input\_managed\_identity\_principal\_id) | Principal ID of the APIM managed identity granted Key Vault Secrets User. | `string` | n/a | yes |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Allow public network access to the Key Vault. | `bool` | n/a | yes |
| <a name="input_purge_protection_enabled"></a> [purge\_protection\_enabled](#input\_purge\_protection\_enabled) | Enable purge protection on Key Vault (prevents permanent deletion) | `bool` | n/a | yes |
| <a name="input_rbac_authorization_enabled"></a> [rbac\_authorization\_enabled](#input\_rbac\_authorization\_enabled) | Enable RBAC authorization on Key Vault | `bool` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Resource ID of the subnet that hosts the private endpoint. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Entra tenant ID for the Key Vault. | `string` | n/a | yes |
| <a name="input_create_apim_gateway_key_secret"></a> [create\_apim\_gateway\_key\_secret](#input\_create\_apim\_gateway\_key\_secret) | Create a placeholder `apim-gateway-key` secret in Key Vault. Disabled by<br/>default — nothing in the Terraform stack consumes it programmatically<br/>(only notebook samples reference it, and they fetch the key out-of-band<br/>via `az apim`). Creating it requires KV data-plane write access from the<br/>deployer IP and commonly trips the KV firewall on locked-down<br/>environments. Set to `true` only if you have downstream tooling that<br/>reads `apim-gateway-key` from KV directly. | `bool` | `false` | no |
| <a name="input_dns_zone_group_managed_by_policy"></a> [dns\_zone\_group\_managed\_by\_policy](#input\_dns\_zone\_group\_managed\_by\_policy) | Azure Policy (e.g. ALZ Deploy-Private-DNS-Zones) creates the private endpoint's DNS zone group; Terraform leaves it alone. | `bool` | `false` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_foundry_principal_count"></a> [foundry\_principal\_count](#input\_foundry\_principal\_count) | Number of Foundry principals — must be known at plan time so `count` works. Caller should pass `length(var.ai_foundry_instances)` (or 0 when Foundry disabled). | `number` | `0` | no |
| <a name="input_foundry_principal_ids"></a> [foundry\_principal\_ids](#input\_foundry\_principal\_ids) | System-assigned principal IDs of AI Foundry accounts for KV Secrets User grant (Bicep: keyvault-rbac.bicep). | `list(string)` | `[]` | no |
| <a name="input_ip_rules"></a> [ip\_rules](#input\_ip\_rules) | Optional list of public IPs / CIDRs to add to Key Vault network\_acls.ip\_rules (for bootstrap/data-plane writes from the deployer). | `list(string)` | `[]` | no |
| <a name="input_network_acl_default_action"></a> [network\_acl\_default\_action](#input\_network\_acl\_default\_action) | Default network access action for Key Vault (Allow or Deny) | `string` | `"Deny"` | no |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | Number of days to retain soft-deleted Key Vaults (1-90, default 7) | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_key_vault_id"></a> [key\_vault\_id](#output\_key\_vault\_id) | Resource ID of the Key Vault. |
| <a name="output_key_vault_id_for_secrets"></a> [key\_vault\_id\_for\_secrets](#output\_key\_vault\_id\_for\_secrets) | Resource ID of the Key Vault, available once the deployer's RBAC and the network ACLs have propagated. Use it for data-plane writes (secrets). |
| <a name="output_key_vault_name"></a> [key\_vault\_name](#output\_key\_vault\_name) | Name of the Key Vault. |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | URI of the Key Vault. |
<!-- END_TF_DOCS -->
