# API Center registration

Registers APIs in an existing API Center workspace. For each entry of `apis` it creates an API (`kind`: `rest`, `websocket`, `mcp`, `graphql`, `grpc`, `soap` or `webhook`), a version `1-0-0` in the `development` lifecycle stage, a definition, and an active deployment in the named environment whose runtime URI is `<gateway_url>/<path>`. `enabled = false` creates nothing.

Called by [stacks/gateway-config](../../stacks/gateway-config/api-center.tf) (AI Search, Document Intelligence and the MCP sample APIs) and [stacks/llm-backend-onboarding](../../stacks/llm-backend-onboarding/api-center.tf) (the LLM APIs), each registering the APIs it publishes when its `features.api_center_onboarding` is on. The API Center itself comes from [modules/apic](../apic/README.md). The `apis` map must be known at plan time.

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
