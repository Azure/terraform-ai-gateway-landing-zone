# APIM network modes: choosing and changing them

`apim.vnet_mode` (with `apim.private_endpoint` and `apim.public_network_access`)
decides how the gateway is reached and how it reaches its backends. The
Terraform validations reject combinations that Azure doesn't support.

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
| v2 `none` → `integration` | In place. Set `apim.vnet_mode = "integration"` and apply. The network creates the delegated APIM subnet and the service attaches to it. |
| v2 `integration` → `none` | In place. Apply. The subnet and its NSG are removed after the service detaches. |
| Public access off (v2) | Set `apim.public_network_access = false` (with `private_endpoint = true`). A new service is always created public, because Azure rejects private-only activation. The setting is applied on the next apply, once the service and its private endpoint exist. Run apply twice for a new environment. |
| Classic `external` ↔ `internal` | Check the plan first. If it updates in place, the service redeploys and is unavailable for up to ~45 minutes, so plan a maintenance window. If it plans a **replacement**, use the new-instance route below. Internal creates private DNS zones for the five default hostnames (unless the DNS zones are BYO or owned by the platform). |
| → PremiumV2 `injection`, or classic → v2 SKU | **New instance alongside the old one.** These can't be changed in place. |

### New instance alongside the old one

1. Add a second environment folder or tfvars that differs only in
   `apim = { name = "<new-name>", sku = "PremiumV2", vnet_mode = "injection", ... }`.
   For injection, also give it a dedicated subnet prefix of at least /27.
2. Apply it. The gateway configuration (APIs, fragments, products, named values)
   is part of the deployment.
3. Replay the stacks that target the gateway by APIM name:
   `llm-backend-onboarding` and every `citadel-access-contracts` use case.
   Point `apim_name` / `apim.name` at the new instance.
4. Run the smoke tests (`scripts/validate.sh <env>`) against the new gateway.
5. Switch clients: update DNS (custom domain / private DNS records) and the
   endpoints held in Key Vault or Foundry connections.
6. Retire the old instance: remove its configuration and apply.

## Azure Landing Zone notes

* In `network.mode = "alz_spoke"`, every subnet, including the APIM subnet,
  routes `0.0.0.0/0` to the hub firewall. Classic `external`/`internal` keeps a
  route for the `ApiManagement` service tag to the internet, which the management
  plane needs.
* Allow the APIM dependencies on the hub firewall: Azure Key Vault (all modes),
  Azure Monitor, and for classic SKUs Storage and SQL. See
  [Virtual network resource requirements](https://learn.microsoft.com/azure/api-management/virtual-network-injection-resources)
  and [Premium v2 injection](https://learn.microsoft.com/azure/api-management/inject-vnet-v2).
