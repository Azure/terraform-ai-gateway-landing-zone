# Naming

The naming contract shared by every stack (review §7.7). Names follow
`<prefix>-<workload>-<environment>[-<seed>]`. The 5-character seed comes from
`sha256("<subscription>/<workload>/<environment>")` unless `unique_seed` is
set, so every stack computes the same names and finds what other stacks own
with data sources, without reading their state. `name_overrides` always win.

Two resource groups only: `rg-<workload>-<environment>-tfstate` (Terraform
state, owned by `stacks/bootstrap`) and `rg-<workload>-<environment>`
(everything else; created by `stacks/bootstrap`, used by every other stack).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID; seeds the unique suffix when unique\_seed is null. | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_foundry_instance_names"></a> [foundry\_instance\_names](#input\_foundry\_instance\_names) | Explicit Foundry account names, one per instance ("" = generate aif-<workload>-<environment>-<seed>-<index>). | `list(string)` | `[]` | no |
| <a name="input_name_overrides"></a> [name\_overrides](#input\_name\_overrides) | Logical role => explicit name. Non-empty overrides win over generated names (keys: see the names output). | `map(string)` | `{}` | no |
| <a name="input_unique_seed"></a> [unique\_seed](#input\_unique\_seed) | Suffix for globally unique names (5 lowercase letters or digits). null = derived from subscription\_id, workload and environment. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_base"></a> [base](#output\_base) | <workload>-<environment>, used by modules that derive child resource names. |
| <a name="output_foundry_account_names"></a> [foundry\_account\_names](#output\_foundry\_account\_names) | Foundry (AI Services) account names, one per instance. |
| <a name="output_names"></a> [names](#output\_names) | Logical role => resource name (generated, or the override when one is set). |
| <a name="output_private_dns_zones"></a> [private\_dns\_zones](#output\_private\_dns\_zones) | Logical key => private DNS zone name used by the gateway's private endpoints. |
| <a name="output_seed"></a> [seed](#output\_seed) | Deterministic 5-character suffix used in globally unique names. |
<!-- END_TF_DOCS -->
