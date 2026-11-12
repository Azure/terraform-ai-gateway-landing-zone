# APIM policy fragments

Deploys a map of policy fragments (`rawxml`) to an API Management service, in two ways:

- `fragments`: `azurerm_api_management_policy_fragment`, with 45-minute timeouts because APIM's create LRO can answer 404 on the status endpoint before the fragment is queryable.
- `azapi_fragments`: for fragments that hit the azurerm LRO polling bug (`PolicyFragment not found`). A direct `azapi` PUT creates them; APIM reformats the stored XML, so the body is ignored on read-back and content changes go through an idempotent PUT (`azapi_resource_action`) that re-runs when the XML or description changes (a fragment in use can't be deleted and recreated).

`depends_on_ids` orders the fragments after the named values and loggers they reference, because APIM validates references when a fragment is saved.

**Usage event markers.** APIM doesn't let a fragment include another fragment. A fragment that answers a request itself records its usage event with a marker comment right before the `<return-response>`, e.g. `<!-- usage-event status="403" reason="validate-model-access" -->`. The module replaces each marker with the `usageEventStatus` / `usageEventReason` variables and the body of [templates/usage-event.xml.tftpl](templates/usage-event.xml.tftpl), the same body as the `usage-event` fragment that gateway-config deploys. The `xml` output shows the expanded XML.

Called by [stacks/gateway-config](../../stacks/gateway-config/fragments.tf) (shared, event and PII fragments) and [stacks/llm-backend-onboarding](../../stacks/llm-backend-onboarding/fragments.tf) (Unified AI fragments).

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
| <a name="input_usage_event"></a> [usage\_event](#input\_usage\_event) | Usage events inside fragments. A fragment can't include another fragment, so the module expands<br/>every marker comment `<!-- usage-event status="403" reason="validate-model-access" -->` (written<br/>right before a `<return-response>`) into the usage event body (templates/usage-event.xml.tftpl, the<br/>same body as the usage-event fragment). It's a no-op unless the request belongs to an access contract with<br/>usage\_events, or record\_key\_rejections is on and the request has no subscription.<br/>  record\_key\_rejections  also record rejections without a subscription key (security-handler) | <pre>object({<br/>    record_key_rejections = optional(bool, false)<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ids"></a> [ids](#output\_ids) | Fragment ID => policy fragment resource ID (both azurerm- and azapi-managed fragments). |
| <a name="output_names"></a> [names](#output\_names) | IDs (names) of all fragments deployed by this module. |
| <a name="output_xml"></a> [xml](#output\_xml) | Fragment ID => the XML deployed (after the usage event markers are expanded). |
<!-- END_TF_DOCS -->
