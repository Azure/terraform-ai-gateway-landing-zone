# API Center

Creates the Azure API Center service (`enable_api_center`, `api_center_sku`, `apic_location`) with a system-assigned identity and the portal enabled, and the catalogue structure the gateway's APIs are registered in:

- the metadata schemas of `apic-metadata.json` (`Visibility`, `Categories`, `Vendor`, `Endpoint`, `Type`, `Icon`, `securitySchemes`);
- four environments in the `default` workspace that Azure creates itself: `api-dev`, `api-prod`, `mcp-dev` and `mcp-prod`;
- for every remote (third-party) MCP server in `remote_mcp_servers`, an API of kind `mcp`, version `1-0-0`, definition and deployment whose runtime URI is the server's `url`, plus a VS Code install link and an optional documentation link. These servers aren't served by the gateway, and the list is empty by default; the platform stack takes it from `api_center.remote_mcp_servers` ([examples/all-features](../../examples/all-features/platform.tfvars)).

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
| <a name="input_remote_mcp_servers"></a> [remote\_mcp\_servers](#input\_remote\_mcp\_servers) | Remote (third-party) MCP servers to catalogue in API Center: an API of kind MCP, a version, a<br/>definition and a deployment each. They are not served by the gateway.<br/>  name               API Center API name (letters, digits and hyphens), unique<br/>  description        summary shown in the catalogue<br/>  url                the server's MCP (SSE) endpoint: the deployment's runtime URI and the VS Code install link<br/>  documentation\_url  optional documentation link | <pre>list(object({<br/>    name              = string<br/>    description       = string<br/>    url               = string<br/>    documentation_url = optional(string, "")<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_center_id"></a> [api\_center\_id](#output\_api\_center\_id) | Resource ID of the API Center service (empty when disabled). |
| <a name="output_api_center_name"></a> [api\_center\_name](#output\_api\_center\_name) | Name of the API Center service (empty when disabled). |
| <a name="output_remote_mcp_server_apis"></a> [remote\_mcp\_server\_apis](#output\_remote\_mcp\_server\_apis) | Remote MCP server name => resource ID of its API Center API. |
<!-- END_TF_DOCS -->
