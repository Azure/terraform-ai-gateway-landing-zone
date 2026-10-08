# App hosting (App Service Environment v3)

Creates the dedicated App Service Environment v3 that hosts the keyless usage-ingestion Logic App (Isolated v2 plan, see [modules/logic-app](../logic-app/README.md)), plus the private DNS zone that resolves the apps on it.

- **ASE v3** on AVM `avm-res-web-hostingenvironment` 2.0.1, in a dedicated subnet delegated to `Microsoft.Web/hostingEnvironments` (`/24` recommended, `/27` minimum). Internal by default (`internal_load_balancing_mode = "Web, Publishing"`: apps and SCM reachable only from the VNet). Fixed hardening: internal encryption on, TLS 1.0 off, FTP off, remote debugging off. Zone redundancy follows `zone_redundant`.
- **Private DNS zone** `<ase>.appserviceenvironment.net` on AVM `avm-res-network-privatednszone` 0.5.0 (internal ASE and `create_private_dns_zone = true` only), with `*`, `*.scm` and `@` A records pointing at the ASE's internal inbound IP and links to the VNets in `dns_vnet_link_ids`. Set `create_private_dns_zone = false` when DNS is managed centrally in the hub.
- The `id` output depends on the DNS zone, so apps created on the ASE only start once their names resolve.

Creating an ASE takes roughly 1–4 hours; it changes rarely.

This module is called by the root configuration (`module "app_hosting"` in `main.tf`) when `usage_pipeline.logic_app.hosting = "ase_v3"` and `usage_pipeline.ase.app_service_environment_id` is `null`; with a shared / BYO ASE it is skipped and no ASE subnet is created. The root links the DNS zone to the gateway VNet. It configures no providers; the caller passes them in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.12, < 3.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_ase"></a> [ase](#module\_ase) | Azure/avm-res-web-hostingenvironment/azurerm | 2.0.1 |
| <a name="module_dns"></a> [dns](#module\_dns) | Azure/avm-res-network-privatednszone/azurerm | 0.5.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the App Service Environment v3 (also the first label of its DNS suffix). | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource ID of the resource group for the ASE and its private DNS zone. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Dedicated, empty subnet delegated to Microsoft.Web/hostingEnvironments (/24 recommended, /27 minimum). | `string` | n/a | yes |
| <a name="input_create_private_dns_zone"></a> [create\_private\_dns\_zone](#input\_create\_private\_dns\_zone) | Internal ASE: create <ase>.appserviceenvironment.net with *, *.scm and @ records. false = DNS managed centrally (hub). | `bool` | `true` | no |
| <a name="input_dns_vnet_link_ids"></a> [dns\_vnet\_link\_ids](#input\_dns\_vnet\_link\_ids) | VNets to link the ASE private DNS zone to (key => VNet resource ID): the spoke, plus the hub/resolver VNet when DNS is resolved centrally. | `map(string)` | `{}` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Enable Azure Verified Modules usage telemetry. | `bool` | `true` | no |
| <a name="input_internal_load_balancing_mode"></a> [internal\_load\_balancing\_mode](#input\_internal\_load\_balancing\_mode) | "Web, Publishing" = internal (ILB: apps and SCM reachable only from the VNet); "None" = external (public VIP). | `string` | `"Web, Publishing"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for the ASE and its DNS zone. | `map(string)` | `{}` | no |
| <a name="input_zone_redundant"></a> [zone\_redundant](#input\_zone\_redundant) | Zone-redundant ASE (region must support availability zones; increases the minimum billed instances). | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dns_suffix"></a> [dns\_suffix](#output\_dns\_suffix) | DNS suffix of the apps hosted on the ASE (<ase>.appserviceenvironment.net). |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the App Service Environment v3 (available once its private DNS records exist, so apps and their SCM endpoints resolve). |
| <a name="output_internal_inbound_ip_addresses"></a> [internal\_inbound\_ip\_addresses](#output\_internal\_inbound\_ip\_addresses) | Internal inbound IP addresses (ILB) of the ASE. |
| <a name="output_name"></a> [name](#output\_name) | Name of the App Service Environment v3. |
<!-- END_TF_DOCS -->
