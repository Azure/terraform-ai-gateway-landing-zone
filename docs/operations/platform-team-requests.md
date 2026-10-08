# Platform-team requests (Phase 0, WP-0.8)

These requests go to the platform / landing-zone team in **week 1** of the
implementation plan, because their lead time is usually longer than the
engineering work. Each line says which phase needs it.

**Greenfield dev/test environments don't need P2–P4.** In `network_mode =
"greenfield"`, the network stack creates its own VNet, subnets and private DNS
zones. Only `alz_spoke` (Corp landing zone) environments depend on the hub.

## Status

Track each request here. Update the status when the ticket is acknowledged or done.

| # | Ticket | Status | Owner | Notes |
|---|---|---|---|---|
| P1 | | not submitted | | |
| P2 | | not submitted | | `alz_spoke` only |
| P3 | | not submitted | | `alz_spoke` only |
| P4 | | not submitted | | `alz_spoke` only |
| P5 | | not submitted | | |
| P6 | | not submitted | | only for V2 APIM SKUs / WS Logic App in dev |
| P7 | | not submitted | | or created by `stacks/bootstrap` (Phase 3) |
| P8 | | not submitted | | |
| P9 | | not submitted | | |
| P10 | | not submitted | | |

## What to ask for

| # | Request (to) | Detail | Needed by |
|---|---|---|---|
| P1 | Subscription vending (platform) | One application landing zone subscription per environment under **Corp** (D1), with a budget and tags | Phase 3 |
| P2 | Spoke VNet (platform) — **`alz_spoke` environments only**; greenfield dev/test needs no request | ≥ `/22` per environment and region; CAF's Foundry LZ baseline suggests `/21` if agents and MCP hosts are added. Peered to the hub, with a UDR `0.0.0.0/0` → hub firewall. Reserve: APIM (per D12: classic `/27` recommended, ≥ `/29`; v2 `injection`/`integration` ≥ `/27`, `/24` recommended; dedicated to one instance; delegated to `Microsoft.Web/hostingEnvironments` for `injection` or `Microsoft.Web/serverFarms` for `integration`, none for classic; `Microsoft.Web` RP registered), PE `/26`, agent `/24`, **ASE `/24`** (only for `usage_pipeline.logic_app.hosting = "ase_v3"` without a shared ASE — see [Keyless usage pipeline](#keyless-usage-pipeline-ase-v3)), CI runner `/27`. | Phase 2 #6 / 2b |
| P3 | Hub DNS (platform) — **`alz_spoke` only** (greenfield creates its own zones) | Zones in the connectivity subscription and linked to the resolver: `privatelink.openai.azure.com`, `privatelink.services.ai.azure.com`, `privatelink.azure-api.net`, `privatelink.redis.azure.net` (not in the ALZ DINE set). Plus resolution of `<ase>.appserviceenvironment.net` (`ase_v3`), either by a VNet link from the workload zone to the hub/resolver VNet or by a forwarding ruleset. **APIM `internal`/`injection` (D12):** resolution of the per-FQDN zones `<apim>.azure-api.net` (+ `.portal.`, `.developer.`, `.management.`, `.scm.` for classic). Never an apex `azure-api.net` zone. | Phase 2 #6 / 2b |
| P4 | DNS / network RBAC (platform) — `alz_spoke` only | For the apply identity (D13): `Microsoft.Network/privateDnsZones/join/action` on the four zones above; `Microsoft.Network/virtualNetworks/join/action` (e.g. Network Contributor) on the hub or resolver VNet when the ASE zone is linked to it (`app-hosting.tfvars` `dns.vnet_link_ids`); Network Contributor on the vended spoke VNet (subnets). For both pipeline identities: Reader on the central Log Analytics workspace when `monitoring.log_analytics_workspace_id` points at it | Phase 2 #7 |
| P5 | Firewall rules (platform) | APIM per D12: classic `external`/`internal` management-plane dependencies (inbound 3443 from `ApiManagement`, the `ApiManagement` → Internet route, Storage/SQL/KV/Monitor outbound); v2 `injection`/`integration` outbound 443 to `AzureKeyVault` plus backends. Foundry agent egress (allow-list), ASE v3 outbound dependencies when egress goes through the hub (`ase_v3`; Windows Update, monitoring, etc.), AWS Bedrock / external LLM endpoints, GitHub runner egress | Phase 2 #8 / 2b |
| P6 | Policy exemptions (platform) | Only if D6/D12 use any V2 SKU (StandardV2 or PremiumV2, **including PremiumV2 injection**): an exemption on `Enforce-GR-APIM` `Deny-Apim-Sku-Vnet`, scoped to the APIM resource. The built-in's allowed-SKU parameter has no V2 values, so a parameter override can't work. `Deny-Apim-without-Vnet` doesn't evaluate V2 SKUs. Also a time-boxed `Deny-Storage-Shared-Key` exemption for sandbox/dev WS Logic Apps (D3: dev / quick-start keep `workflow_standard`, a documented shared-key exception). `ase_v3` environments need no storage exemption. | Phase 2b |
| P7 | Pipeline identities (platform or bootstrap) | **Two UAMIs per environment** (D13): `id-tf-<workload>-<env>-plan` with Reader + *Terraform Plan Reader* + state Blob Data Reader + Graph `Application.Read.All`, federated to GitHub environment `<env>-plan`; `id-tf-<workload>-<env>-apply` with Contributor + conditioned RBAC Administrator (+ Resource Policy Contributor) on the workload resource group, state Blob Data Contributor, Graph `Application.ReadWrite.OwnedBy` + `Application.Read.All`, federated to `<env>` (see the implementation plan, decision D13) | Phase 3 |
| P8 | Private CI runners (platform/DevOps) | GitHub-hosted private networking (network settings resource + delegated subnet) or a self-hosted runner subnet with the UDR. For `ase_v3` the runner that runs `apply` must reach the Logic App storage **blob private endpoint** (run-from-package upload) and, for `deployment = "zip_deploy"`, resolve and reach `*.scm.<ase>.appserviceenvironment.net` | Phase 2b |
| P9 | ALZ-shaped sandbox MG (platform) | A sandbox MG with the ALZ `landing_zones` + `corp` archetypes, `Enforce-GR-*` set to `Default`, used for the weekly convergence gate | Phase 4 |
| P10 | Cost approval (FinOps) | ASE v3 fixed charge + Isolated v2 instances per environment (D3); APIM Premium units | Phase 2b |

## Keyless usage pipeline (ASE v3)

Environments with `usage_pipeline.logic_app.hosting = "ase_v3"` in
`platform.tfvars` (used by the production-shaped examples, e.g.
[examples/alz-corp](../../examples/alz-corp/platform.tfvars)) run the
usage-ingestion Logic App keyless in an App Service Environment v3, created by
[stacks/app-hosting](../../stacks/app-hosting/). Unless a shared ASE is used
(`usage_pipeline.ase.app_service_environment_id`), ask for:

| Need | Detail | Request |
|---|---|---|
| ASE subnet | `/24` recommended (`/27` minimum), delegated to `Microsoft.Web/hostingEnvironments`, with an NSG. In `greenfield` / `alz_spoke` the network stack creates it (with its NSG) — reserve the range in the spoke; in `byo` the platform creates it, empty, and passes it as `ase.subnet_id` in `app-hosting.tfvars` | P2 |
| DNS | Resolution of `<ase>.appserviceenvironment.net` (`*`, `*.scm`, `@` → the ASE internal inbound IP) from the hub/resolver if DNS is central. The app-hosting stack creates the zone and links it to the gateway VNet (`dns.create = false` in `app-hosting.tfvars` if the hub owns it) | P3 |
| Firewall | ASE v3 outbound dependencies, when egress goes through the hub firewall | P5 |
| Deployment runner | Private access to the storage private endpoint (workflow package upload); for `zip_deploy`, also the ASE SCM endpoint | P8 |
| Cost | ASE v3 + Isolated v2 instances (autoscale between `worker_count` and `max_worker_count`) | P10 |

No `Deny-Storage-Shared-Key` exemption is needed for these environments; if
the platform doesn't assign that policy, set `deny_storage_shared_key = true`
in `platform.tfvars` to assign it on the resource group.

## Ticket template

Copy this into the subscription-vending / platform ticket and fill in the placeholders.

```text
Workload: AI Gateway (APIM + Foundry + usage pipeline) — environment: <env>
Management group: Corp
Spoke: /22 (or /21 with agents/MCP) in <region>; subnets: snet-apim (see APIM line), snet-pe /26, snet-agent /24, snet-ase /24 (ase_v3; delegation Microsoft.Web/hostingEnvironments, NSG), snet-cicd /27
APIM network (D12): vnet_mode = <internal|external|injection|integration|none>; snet-apim dedicated to one instance:
     internal/external (Developer/Premium) → /27, no delegation, APIM route table (ApiManagement → Internet), classic NSG rules
     injection (PremiumV2)                 → /24 (min /27), delegation Microsoft.Web/hostingEnvironments, NSG outbound 443 AzureKeyVault
     integration (StandardV2/PremiumV2)    → /24 (min /27), delegation Microsoft.Web/serverFarms, NSG outbound 443 AzureKeyVault
     Microsoft.Web resource provider registered in the subscription
Routing: platform UDR 0.0.0.0/0 → hub firewall on all subnets
DNS: hub zones privatelink.openai.azure.com, privatelink.services.ai.azure.com, privatelink.azure-api.net, privatelink.redis.azure.net (+ standard ALZ set);
     ase_v3: resolution of <ase-name>.appserviceenvironment.net (VNet link or resolver ruleset);
     APIM internal/injection: resolution of per-FQDN zones <apim>.azure-api.net (+ .portal/.developer/.management/.scm for classic) — never an apex azure-api.net zone
RBAC: privateDnsZones/join/action on the 4 zones above for id-tf-<workload>-<env>-apply
Firewall: APIM per vnet_mode (classic: management plane + dependencies; v2: AzureKeyVault + backends), ASE v3 outbound dependencies (ase_v3, egress via hub), Foundry agent egress allow-list, external LLM endpoints, GitHub runner egress
Runner (ase_v3): deployment runner with private access to the Logic App storage private endpoint (+ ASE SCM endpoint for zip_deploy)
Identities (2): id-tf-<workload>-<env>-plan  → OIDC subject repo:<org>/<repo>:environment:<env>-plan  (Reader + Terraform Plan Reader; state Blob Data Reader; Graph Application.Read.All)
                id-tf-<workload>-<env>-apply → OIDC subject repo:<org>/<repo>:environment:<env>        (Contributor + RBAC Admin conditioned; state Blob Data Contributor; Graph Application.ReadWrite.OwnedBy + Application.Read.All)
Exemptions (if applicable): Enforce-GR-APIM Deny-Apim-Sku-Vnet for ANY V2 SKU (incl. PremiumV2 injection) scoped to APIM — no parameter override possible; Deny-Storage-Shared-Key (dev WS Logic App, time-boxed)
Diagnostics: central LAW id for BYO; confirm Deploy-Diag-LogsCat scope
```

## Related repository settings

- Every subnet the network stack creates (`greenfield` and `alz_spoke`) gets its
  own NSG (ALZ `Deny-Subnet-Without-Nsg`); in `byo` mode the subnets and their
  NSGs belong to the platform.
- Access-contract secrets (`environments/<env>/access-contracts/<use-case>.tfvars`)
  expire after `secret_validity_days` (default 90, the most `Enforce-GR-KeyVault`
  allows) and are renewed every `secret_rotation_days` (default 60).
