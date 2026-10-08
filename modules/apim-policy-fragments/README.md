# APIM policy fragments

Deploys a map of policy fragments to an API Management service. Fragments that hit the azurerm LRO polling bug can be passed in `azapi_fragments` instead. `depends_on_ids` orders the fragments after the named values they reference.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9, < 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.79, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.9, < 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79, < 5.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.this](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource_action.update](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource_action) | resource |
| [azurerm_api_management_policy_fragment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_policy_fragment) | resource |
| [terraform_data.hash](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the API Management service. | `string` | n/a | yes |
| <a name="input_azapi_fragments"></a> [azapi\_fragments](#input\_azapi\_fragments) | Fragment ID => { xml, description }, managed with azapi\_resource (direct PUT). Use for fragments that hit the azurerm LRO polling bug (404 PolicyFragment not found). | <pre>map(object({<br/>    xml         = string<br/>    description = optional(string, "")<br/>  }))</pre> | `{}` | no |
| <a name="input_depends_on_ids"></a> [depends\_on\_ids](#input\_depends\_on\_ids) | IDs of objects the fragments reference by name (named values). APIM validates those references when a fragment is saved, so the fragments wait for them. | `list(string)` | `[]` | no |
| <a name="input_fragments"></a> [fragments](#input\_fragments) | Fragment ID => { xml, description }. Managed with azurerm\_api\_management\_policy\_fragment. | <pre>map(object({<br/>    xml         = string<br/>    description = optional(string, "")<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ids"></a> [ids](#output\_ids) | Fragment ID => policy fragment resource ID (both azurerm- and azapi-managed fragments). |
| <a name="output_names"></a> [names](#output\_names) | IDs (names) of all fragments deployed by this module. |
<!-- END_TF_DOCS -->
