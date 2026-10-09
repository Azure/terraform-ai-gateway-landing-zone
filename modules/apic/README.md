# API Center

Creates the Azure API Center service (`enable_api_center`, `api_center_sku`, `apic_location`) with a system-assigned identity and the portal enabled, and the catalogue structure the gateway's APIs are registered in:

- the metadata schemas of `apic-metadata.json` (`Visibility`, `Categories`, `Vendor`, `Endpoint`, `Type`, `Icon`, `securitySchemes`);
- four environments in the `default` workspace that Azure creates itself: `api-dev`, `api-prod`, `mcp-dev` and `mcp-prod`;
- for every MCP server listed in `remote-mcp-servers.json`, an API, version `1-0-0`, definition and deployment. That file currently lists none.

The portal's site profile (name, company, support and policy URLs) is fixed in `main.tf` with placeholder values (`yourcompany.com`) and has no input.

The gateway's own APIs are registered by [modules/api-center-registration](../api-center-registration/README.md). Called by [stacks/platform](../../stacks/platform/redis-apic.tf) when `features.api_center` is on; the caller passes the providers in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9, < 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.9, < 3.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.api_center](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_env_api_dev](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_env_api_prod](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_env_mcp_dev](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_env_mcp_prod](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_mcp_api](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_mcp_definition](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_mcp_deployment](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_mcp_version](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.api_center_metadata_schema](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_center_name"></a> [api\_center\_name](#input\_api\_center\_name) | Name of the API Center service. | `string` | n/a | yes |
| <a name="input_api_center_sku"></a> [api\_center\_sku](#input\_api\_center\_sku) | SKU for API Center service. Free tier is 'Free', paid tier is 'Standard'. | `string` | n/a | yes |
| <a name="input_apic_location"></a> [apic\_location](#input\_apic\_location) | Azure region for API Center (API Center isn't available in every region). | `string` | n/a | yes |
| <a name="input_enable_api_center"></a> [enable\_api\_center](#input\_enable\_api\_center) | Deploy API Center as AI Registry | `bool` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource ID of the resource group the module deploys into. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_center_id"></a> [api\_center\_id](#output\_api\_center\_id) | Resource ID of the API Center service (empty when disabled). |
| <a name="output_api_center_name"></a> [api\_center\_name](#output\_api\_center\_name) | Name of the API Center service (empty when disabled). |
<!-- END_TF_DOCS -->
