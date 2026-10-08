# Naming

Produces every resource name from one place. `convention = "v1"` reproduces the
names this repository has always generated, so adopting the module renames
nothing. Explicit names (for example `apim_service_name`) and `name_overrides`
always win.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name used in resource names (e.g. citadel-dev). | `string` | n/a | yes |
| <a name="input_legacy_suffix"></a> [legacy\_suffix](#input\_legacy\_suffix) | The 6-character random suffix (random\_string.suffix) that v1 appends to globally unique names. | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Subscription ID; part of the resource\_token seed. | `string` | n/a | yes |
| <a name="input_convention"></a> [convention](#input\_convention) | Naming convention. "v1" reproduces the names this repository has always generated (resource\_token + random suffix), so existing deployments keep their names. | `string` | `"v1"` | no |
| <a name="input_foundry_instance_names"></a> [foundry\_instance\_names](#input\_foundry\_instance\_names) | Explicit Foundry account names, one per instance ("" = generate aif-<env>-<index>-<suffix>). | `list(string)` | `[]` | no |
| <a name="input_name_overrides"></a> [name\_overrides](#input\_name\_overrides) | Logical role => explicit name. Overrides win over generated names (keys: see the names output). | `map(string)` | `{}` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Explicit resource group name, or "" to derive rg-<environment\_name>. Also part of the resource\_token seed. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_convention"></a> [convention](#output\_convention) | Naming convention used to produce the names. |
| <a name="output_foundry_account_names"></a> [foundry\_account\_names](#output\_foundry\_account\_names) | Foundry (AI Services) account names, one per instance. |
| <a name="output_names"></a> [names](#output\_names) | Logical role => resource name (generated, or the override when one is set). |
| <a name="output_resource_token"></a> [resource\_token](#output\_resource\_token) | Deterministic 10-character token used in v1 names. |
<!-- END_TF_DOCS -->
