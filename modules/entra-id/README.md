# Entra ID app registration

Registers the Entra application APIM validates JWTs against (scope, app roles, service principal) and stores a rotating client secret in Key Vault.

This module is called by the root configuration (`main.tf`). It configures no providers; the caller passes them in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | >= 3.0, < 4.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.11, < 1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | >= 3.0, < 4.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.11, < 1.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azuread_application.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_identifier_uri.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_identifier_uri) | resource |
| [azuread_application_password.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_service_principal.gateway](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal) | resource |
| [azurerm_key_vault_secret.client_secret](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [time_rotating.client_secret](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/rotating) | resource |
| [azuread_application_published_app_ids.well_known](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/application_published_app_ids) | data source |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azuread_service_principal.msgraph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name used to suffix the app registration display name (e.g. dev, prod). | `string` | n/a | yes |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | Key Vault ID where the generated client secret will be stored. | `string` | n/a | yes |
| <a name="input_app_display_name_prefix"></a> [app\_display\_name\_prefix](#input\_app\_display\_name\_prefix) | Prefix for the app registration display name. | `string` | `"ai-citadel-gateway"` | no |
| <a name="input_client_secret_name"></a> [client\_secret\_name](#input\_client\_secret\_name) | Key Vault secret name for the client secret. | `string` | `"ENTRA-APP-CLIENT-SECRET"` | no |
| <a name="input_client_secret_rotation_days"></a> [client\_secret\_rotation\_days](#input\_client\_secret\_rotation\_days) | Trigger secret rotation when this many days have passed (default: 2 years). | `number` | `730` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_audience"></a> [audience](#output\_audience) | App ID URI (audience for JWT tokens). |
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | Entra ID app registration client ID (used by APIM JWT-AppRegistrationId named value). |
| <a name="output_client_secret"></a> [client\_secret](#output\_client\_secret) | Generated client secret value. |
| <a name="output_display_name"></a> [display\_name](#output\_display\_name) | App registration display name. |
| <a name="output_key_vault_secret_id"></a> [key\_vault\_secret\_id](#output\_key\_vault\_secret\_id) | Key Vault secret ID of the stored client secret. |
| <a name="output_object_id"></a> [object\_id](#output\_object\_id) | Application object ID. |
| <a name="output_service_principal_id"></a> [service\_principal\_id](#output\_service\_principal\_id) | Service principal object ID. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra ID tenant ID. |
<!-- END_TF_DOCS -->
