# API Center registration

Registers APIs (REST, WebSocket, MCP) in an existing API Center: one API, version, definition and deployment each, pointing at the APIM gateway.

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
| [azapi_resource.apic_api](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.apic_api_definition](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.apic_api_deployment](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.apic_api_version](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_center_id"></a> [api\_center\_id](#input\_api\_center\_id) | Resource ID of the API Center service the APIs are registered in. | `string` | n/a | yes |
| <a name="input_apis"></a> [apis](#input\_apis) | API name => registration details. kind: rest \| websocket \| mcp. environment: API Center environment name. | <pre>map(object({<br/>    display_name = string<br/>    description  = string<br/>    kind         = string<br/>    path         = string<br/>    environment  = string<br/>  }))</pre> | n/a | yes |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Register the APIs. Must be known at plan time (don't derive it from computed values). | `bool` | n/a | yes |
| <a name="input_gateway_url"></a> [gateway\_url](#input\_gateway\_url) | APIM gateway base URL; each deployment's runtime URI is <gateway\_url>/<path>. | `string` | n/a | yes |
| <a name="input_workspace_name"></a> [workspace\_name](#input\_workspace\_name) | API Center workspace that receives the registrations. | `string` | `"default"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_ids"></a> [api\_ids](#output\_api\_ids) | API name => API Center API resource ID. |
<!-- END_TF_DOCS -->
