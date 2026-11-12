# bootstrap

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.12 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~> 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.81 |
| <a name="requirement_modtm"></a> [modtm](#requirement\_modtm) | ~> 0.3 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.5 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | ~> 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.81 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_naming"></a> [naming](#module\_naming) | ../../modules/naming | n/a |
| <a name="module_pipeline_identity"></a> [pipeline\_identity](#module\_pipeline\_identity) | Azure/avm-res-managedidentity-userassignedidentity/azurerm | 0.5.3 |
| <a name="module_state_resource_group"></a> [state\_resource\_group](#module\_state\_resource\_group) | Azure/avm-res-resources-resourcegroup/azurerm | 0.4.0 |
| <a name="module_state_storage"></a> [state\_storage](#module\_state\_storage) | Azure/avm-res-storage-storageaccount/azurerm | 0.10.0 |
| <a name="module_workload_resource_group"></a> [workload\_resource\_group](#module\_workload\_resource\_group) | Azure/avm-res-resources-resourcegroup/azurerm | 0.4.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azuread_app_role_assignment.graph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/app_role_assignment) | resource |
| [azurerm_role_assignment.apply](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.plan](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.plan_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_definition) | resource |
| [azuread_application_published_app_ids.well_known](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/application_published_app_ids) | data source |
| [azuread_service_principal.msgraph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_resource_group.workload](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment code used in every resource name (2-10 lowercase letters or digits, e.g. dev, test, prod). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Primary Azure region (e.g. swedencentral). | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Workload subscription ID. | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Short workload code used in every resource name (2-8 lowercase letters or digits). | `string` | n/a | yes |
| <a name="input_additional_apply_role_assignments"></a> [additional\_apply\_role\_assignments](#input\_additional\_apply\_role\_assignments) | Extra role assignments for the apply identity outside the workload resource group, e.g. Network Contributor on a vended VNet (alz\_spoke) or Log Analytics Contributor on a platform workspace. | <pre>map(object({<br/>    scope                      = string<br/>    role_definition_id_or_name = string<br/>  }))</pre> | `{}` | no |
| <a name="input_create_pipeline_identities"></a> [create\_pipeline\_identities](#input\_create\_pipeline\_identities) | false = the identities already exist (e.g. created by ALZ subscription vending); pass their principal IDs in existing\_pipeline\_identities. | `bool` | `true` | no |
| <a name="input_create_workload_resource_group"></a> [create\_workload\_resource\_group](#input\_create\_workload\_resource\_group) | Create the workload resource group (rg-<workload>-<environment>). false = it already exists (e.g. vended). | `bool` | `true` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable AVM module telemetry (azure/modtm). See https://aka.ms/avm/telemetryinfo. | `bool` | `true` | no |
| <a name="input_existing_pipeline_identities"></a> [existing\_pipeline\_identities](#input\_existing\_pipeline\_identities) | Principal IDs of existing pipeline identities (create\_pipeline\_identities = false). plan\_principal\_id null = the apply identity also plans. | <pre>object({<br/>    apply_principal_id = string<br/>    plan_principal_id  = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_github"></a> [github](#input\_github) | GitHub repository whose workflows deploy this environment (OIDC federated credentials).<br/>  repository         owner/name.<br/>  plan\_environment   GitHub environment used by PR plans and drift checks (null = "<environment>-plan").<br/>  apply\_environment  GitHub environment used by applies on main (null = "<environment>").<br/>null = no federated credentials (local runs only). | <pre>object({<br/>    repository        = string<br/>    plan_environment  = optional(string)<br/>    apply_environment = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_graph_permissions"></a> [graph\_permissions](#input\_graph\_permissions) | Grant Microsoft Graph application permissions to the pipeline identities: Application.Read.All (both) and Application.ReadWrite.OwnedBy (apply, for stacks/identity). Needs a Privileged Role Administrator. false = run stacks/identity as a human and set entra in gateway-config.tfvars. | `bool` | `true` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | Naming inputs shared by all stacks (modules/naming, docs/naming.md).<br/>  unique\_seed     5 lowercase letters/digits; null = derived from subscription\_id, workload and environment.<br/>  name\_overrides  logical role => explicit name (e.g. { apim = "apim-contoso-prod" }). | <pre>object({<br/>    unique_seed    = optional(string)<br/>    name_overrides = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | greenfield  stacks/network creates the VNet, subnets, NSGs and private DNS zones; downstream stacks look them up by name.<br/>alz\_spoke   stacks/network adds subnets + NSGs (+ UDR) to a vended VNet; platform.tfvars carries the subnet and hub DNS zone IDs.<br/>byo         no network stack; platform.tfvars carries all IDs. | `string` | `"greenfield"` | no |
| <a name="input_pipeline_identity_mode"></a> [pipeline\_identity\_mode](#input\_pipeline\_identity\_mode) | pair = a read-only plan identity + an apply identity (recommended); single = one identity for both (sandbox/dev only: PR plans then run with write rights). | `string` | `"pair"` | no |
| <a name="input_policy_assignments"></a> [policy\_assignments](#input\_policy\_assignments) | Grant the apply identity Resource Policy Contributor on the workload resource group (platform's deny\_storage\_shared\_key assignment). | `bool` | `true` | no |
| <a name="input_resource_providers"></a> [resource\_providers](#input\_resource\_providers) | Resource providers registered on the subscription (the pipeline identities can't register them). | `set(string)` | <pre>[<br/>  "GitHub.Network",<br/>  "Microsoft.ApiCenter",<br/>  "Microsoft.ApiManagement",<br/>  "Microsoft.App",<br/>  "Microsoft.Cache",<br/>  "Microsoft.CognitiveServices",<br/>  "Microsoft.DocumentDB",<br/>  "Microsoft.EventHub",<br/>  "Microsoft.Insights",<br/>  "Microsoft.KeyVault",<br/>  "Microsoft.ManagedIdentity",<br/>  "Microsoft.Network",<br/>  "Microsoft.OperationalInsights",<br/>  "Microsoft.Storage",<br/>  "Microsoft.Web"<br/>]</pre> | no |
| <a name="input_stacks"></a> [stacks](#input\_stacks) | Stacks that get a state container (one container per stack: separate locks and blast radius). | `list(string)` | <pre>[<br/>  "bootstrap",<br/>  "identity",<br/>  "network",<br/>  "app-hosting",<br/>  "platform",<br/>  "gateway-config",<br/>  "llm-backend-onboarding",<br/>  "access-contracts"<br/>]</pre> | no |
| <a name="input_state_admin_principal_ids"></a> [state\_admin\_principal\_ids](#input\_state\_admin\_principal\_ids) | Principals (besides the person running bootstrap) that get Storage Blob Data Contributor on the state account, e.g. a break-glass group. | `map(string)` | `{}` | no |
| <a name="input_state_storage"></a> [state\_storage](#input\_state\_storage) | Terraform state account (keyless: Entra ID only).<br/>  replication                    ZRS (default) or another Standard SKU replication.<br/>  public\_network\_access\_enabled  false = private endpoint only (Corp): runners need a private path.<br/>  allowed\_ip\_ranges              Public CIDRs allowed through the firewall (default action Deny when set).<br/>  private\_endpoint               subnet\_id (+ private\_dns\_zone\_id unless policy creates the zone group).<br/>  retention\_days                 Blob and container soft-delete retention. | <pre>object({<br/>    replication                   = optional(string, "ZRS")<br/>    public_network_access_enabled = optional(bool, true)<br/>    allowed_ip_ranges             = optional(list(string), [])<br/>    retention_days                = optional(number, 30)<br/>    private_endpoint = optional(object({<br/>      subnet_id           = string<br/>      private_dns_zone_id = optional(string)<br/>    }))<br/>  })</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource (merged with workload, environment, stack and managed-by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apply_client_id"></a> [apply\_client\_id](#output\_apply\_client\_id) | Client ID of the apply identity: set it as AZURE\_CLIENT\_ID on the GitHub environment <environment>. |
| <a name="output_apply_principal_id"></a> [apply\_principal\_id](#output\_apply\_principal\_id) | Object ID of the apply identity (platform.tfvars secret\_writer\_principal\_ids). |
| <a name="output_backend_hcl"></a> [backend\_hcl](#output\_backend\_hcl) | Content for environments/<env>/backend.hcl. |
| <a name="output_plan_client_id"></a> [plan\_client\_id](#output\_plan\_client\_id) | Client ID of the plan identity: set it as AZURE\_CLIENT\_ID on the GitHub environment <environment>-plan (pair mode). |
| <a name="output_plan_principal_id"></a> [plan\_principal\_id](#output\_plan\_principal\_id) | Object ID of the plan identity (platform.tfvars secret\_reader\_principal\_ids). |
| <a name="output_state_resource_group_name"></a> [state\_resource\_group\_name](#output\_state\_resource\_group\_name) | Resource group of the Terraform state account. |
| <a name="output_state_storage_account_name"></a> [state\_storage\_account\_name](#output\_state\_storage\_account\_name) | Terraform state account. |
| <a name="output_workload_resource_group_name"></a> [workload\_resource\_group\_name](#output\_workload\_resource\_group\_name) | Resource group every other stack deploys into. |
<!-- END_TF_DOCS -->
