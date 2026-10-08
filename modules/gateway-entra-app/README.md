# Gateway Entra app

The Entra application APIM validates JWTs against. It creates the app
registration (the `access_as_user` scope plus the `Task.ReadWrite`,
`Models.Read`, `MCP.Read` and `Agent.Read` app roles), the `api://<client_id>`
identifier URI and the service principal.

No client secret is created: `validate-jwt` / `validate-azure-ad-token` only
need the tenant ID, client ID and audience. If a confidential client is ever
needed, use a federated credential or a certificate.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | >= 3.0, < 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | >= 3.0, < 4.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azuread_application.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_identifier_uri.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_identifier_uri) | resource |
| [azuread_service_principal.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal) | resource |
| [azuread_application_published_app_ids.well_known](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/application_published_app_ids) | data source |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azuread_service_principal.msgraph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_display_name"></a> [display\_name](#input\_display\_name) | Display name of the app registration (the naming contract's gateway\_app: other stacks look the app up by this name). | `string` | n/a | yes |
| <a name="input_owners"></a> [owners](#input\_owners) | Additional owner object IDs (the identity running Terraform is always an owner). | `set(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_audience"></a> [audience](#output\_audience) | App ID URI (audience for JWT tokens). |
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | Entra ID app registration client ID (APIM named values entra-client-id / JWT-AppRegistrationId). |
| <a name="output_display_name"></a> [display\_name](#output\_display\_name) | App registration display name. |
| <a name="output_object_id"></a> [object\_id](#output\_object\_id) | Application object ID. |
| <a name="output_owners"></a> [owners](#output\_owners) | Owner object IDs of the app registration. |
| <a name="output_service_principal_id"></a> [service\_principal\_id](#output\_service\_principal\_id) | Service principal object ID. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra ID tenant ID. |
<!-- END_TF_DOCS -->
