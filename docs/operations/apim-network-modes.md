# APIM network modes: choosing and changing them

`apim.vnet_mode` (with `apim.private_endpoint` and `apim.public_network_access`)
in `environments/<env>/platform.tfvars` decides how the gateway is reached and
how it reaches its backends. The validations of the `apim` variable in
[stacks/platform/variables.tf](../../stacks/platform/variables.tf) reject
combinations that Azure doesn't support.

The APIM subnet comes from the network stack (`greenfield` / `alz_spoke`): set
`apim_vnet_mode` in `network.tfvars` to the same value as `apim.vnet_mode`. In
`byo` (and optionally `alz_spoke`) the platform team owns the subnet and passes
it in the `network` object of `platform.tfvars`.

| SKU | `vnet_mode` | Inbound | Outbound to backends | APIM subnet |
|---|---|---|---|---|
| Developer / Premium | `none` | Public | Public | none |
| Developer / Premium | `external` (default) | Public VIP | VNet | no delegation, NSG with management rules, route table |
| Developer / Premium | `internal` | Private VIP (5 private DNS zones created) | VNet | as above |
| StandardV2 / PremiumV2 | `none` | Public and/or private endpoint | Public | none |
| StandardV2 / PremiumV2 | `integration` (default) | Public and/or private endpoint | VNet | delegated to `Microsoft.Web/serverFarms` |
| PremiumV2 | `injection` | Private VIP (gateway private DNS zone created) | VNet | delegated to `Microsoft.Web/hostingEnvironments`, at least /27 (/24 recommended) |

Rules enforced at plan time:

* A private endpoint applies to v2 SKUs with `none` or `integration` only.
* `public_network_access = false` needs that private endpoint.
* `public_ip_address_id` applies to classic `external` / `internal` only.

## Changing the mode of a running environment

| Change | How |
|---|---|
| v2 `none` → `integration` | In place. Set `apim.vnet_mode = "integration"` in `platform.tfvars` and `apim_vnet_mode = "integration"` in `network.tfvars`, then run `task up ENV=<env>`. The network stack creates the delegated APIM subnet and the service (platform stack) attaches to it. |
| v2 `integration` → `none` | In place. Set both values to `none`, apply the platform stack first (`task apply STACK=platform ENV=<env>`) so the service detaches, then the network stack, which removes the subnet and its NSG. |
| Public access off (v2) | Set `apim.public_network_access = false` (with `private_endpoint = true`). A new service is always created public, because Azure rejects private-only activation. The setting is applied on the next apply, once the service and its private endpoint exist. Run `task apply STACK=platform ENV=<env>` twice for a new environment. |
| Classic `external` ↔ `internal` | Check the plan first. If it updates in place, the service redeploys and is unavailable for up to ~45 minutes, so plan a maintenance window. If it plans a **replacement**, use the new-instance route below. Internal creates private DNS zones for the five default hostnames in `greenfield` only; in `alz_spoke` / `byo` the hub owns them. |
| → PremiumV2 `injection`, or classic → v2 SKU | **New instance alongside the old one.** These can't be changed in place. |

### New instance alongside the old one

1. Add a second environment folder (`environments/<new-env>/`, with its own
   state from `task bootstrap ENV=<new-env>`) whose stacks resolve to a new APIM name: a different `environment` in
   `common.tfvars`, or `naming.name_overrides = { apim = "<new-name>" }`. Set
   `apim = { sku = "PremiumV2", vnet_mode = "injection", ... }` in
   `platform.tfvars` and the matching `apim_vnet_mode` in `network.tfvars`. For
   injection, also give it a dedicated APIM subnet prefix of at least /27.
2. Copy the `gateway-config.tfvars`, `llm-backend-onboarding.tfvars` and
   `access-contracts/<use-case>.tfvars` files of the old environment.
3. Run `task up ENV=<new-env>`. It applies the platform, then
   `gateway-config` (named values, shared fragments, service APIs),
   `llm-backend-onboarding` (backends, LLM fragments and APIs) and every access
   contract. Each stack finds the APIM by its deterministic name.
4. Run the smoke tests (`task validate ENV=<new-env>`) against the new gateway.
5. Switch clients: update DNS (custom domain / private DNS records) and the
   endpoints held in Key Vault or Foundry connections.
6. Retire the old environment: `task down ENV=<old-env>`.

## Azure Landing Zone notes

* In `network_mode = "alz_spoke"` (`common.tfvars`), every subnet, including the APIM subnet,
  routes `0.0.0.0/0` to the hub firewall. Classic `external`/`internal` keeps a
  route for the `ApiManagement` service tag to the internet, which the management
  plane needs.
* Allow the APIM dependencies on the hub firewall: Azure Key Vault (all modes),
  Azure Monitor, and for classic SKUs Storage and SQL. See
  [Virtual network resource requirements](https://learn.microsoft.com/azure/api-management/virtual-network-injection-resources)
  and [Premium v2 injection](https://learn.microsoft.com/azure/api-management/inject-vnet-v2).
