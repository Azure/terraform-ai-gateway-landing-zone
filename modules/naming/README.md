# Naming

Produces every resource name from one place. Names are deterministic: a
10-character `resource_token` derived from the resource group, environment and
subscription, plus a 6-character suffix derived from that token for globally
unique names — so every name is known at plan time. Explicit names
(`name_overrides`, `foundry_instance_names` and the root `*_name` variables)
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
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Subscription ID; part of the resource\_token seed. | `string` | n/a | yes |
| <a name="input_foundry_instance_names"></a> [foundry\_instance\_names](#input\_foundry\_instance\_names) | Explicit Foundry account names, one per instance ("" = generate aif-<env>-<index>-<suffix>). | `list(string)` | `[]` | no |
| <a name="input_name_overrides"></a> [name\_overrides](#input\_name\_overrides) | Logical role => explicit name. Overrides win over generated names (keys: see the names output). | `map(string)` | `{}` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Explicit resource group name, or "" to derive rg-<environment\_name>. Also part of the resource\_token seed. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_foundry_account_names"></a> [foundry\_account\_names](#output\_foundry\_account\_names) | Foundry (AI Services) account names, one per instance. |
| <a name="output_names"></a> [names](#output\_names) | Logical role => resource name (generated, or the override when one is set). |
| <a name="output_resource_token"></a> [resource\_token](#output\_resource\_token) | Deterministic 10-character token used in globally unique names. |
<!-- END_TF_DOCS -->
