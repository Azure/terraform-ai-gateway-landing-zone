# identity

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~> 3.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_gateway_app"></a> [gateway\_app](#module\_gateway\_app) | ../../modules/gateway-entra-app | n/a |
| <a name="module_naming"></a> [naming](#module\_naming) | ../../modules/naming | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region (e.g. swedencentral). | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID. | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo. | `bool` | `true` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | Naming inputs shared by all stacks (modules/naming, docs/naming.md).<br/>  unique\_seed     5 lowercase letters/digits; null = derived from subscription\_id, workload and environment.<br/>  name\_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }). | <pre>object({<br/>    unique_seed    = optional(string)<br/>    name_overrides = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.<br/>alz\_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.<br/>byo         no network stack; platform.tfvars carries all IDs. | `string` | `"greenfield"` | no |
| <a name="input_owners"></a> [owners](#input\_owners) | Additional owners (object IDs) of the gateway app registration; the identity running the stack is always an owner. | `set(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource (merged with workload, environment, stack and managed-by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_audience"></a> [audience](#output\_audience) | Token audience, api://<client\_id> (gateway-config entra.audience). |
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | Client ID of the gateway app (gateway-config entra.client\_id). |
| <a name="output_display_name"></a> [display\_name](#output\_display\_name) | Display name of the gateway app (gateway-config looks it up by this name). |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra tenant ID (gateway-config entra.tenant\_id). |
<!-- END_TF_DOCS -->
