# AI Citadel Governance Hub — Variable Reference

Comprehensive reference for all input variables exposed by the **root Terraform module** ([variables.tf](variables.tf)). These are the only variables consumers set directly (typically via a copy of [environments/dev.tfvars.example](environments/dev.tfvars.example) / [environments/prod.tfvars.example](environments/prod.tfvars.example)). Sub-module variables are wired from these root values in [main.tf](main.tf), [network.tf](network.tf), [apis.tf](apis.tf) and [policy-fragments.tf](policy-fragments.tf) and are noted per section when relevant.

> Legend — ★ = required, ☆ = optional with default, 🔒 = sensitive.

### Typed inputs

Most settings are grouped into five **typed objects** declared in [interfaces.tf](interfaces.tf): [`apim`](#5-api-management-apim--other-skus), [`network`](#4-networking-network), [`features`](#6-feature-flags-features), [`usage_pipeline`](#8-usage-pipeline--network-access-usage_pipeline) and [`monitoring`](#7-log-analytics--azure-monitor-monitoring). Every attribute is optional; omit an attribute (or the whole object) to take its default. `interfaces.tf` also computes the effective configuration (`local.apim_cfg`, `local.network_cfg`, `local.features`, `local.usage_cfg`, `local.monitoring_cfg`) that the rest of the configuration reads.

---

## Table of Contents

1. [Basic Configuration](#1-basic-configuration)
2. [Resource Naming](#2-resource-naming)
3. [Security / Key Vault](#3-security--key-vault)
4. [Networking (`network`)](#4-networking-network)
5. [API Management (`apim`) & Other SKUs](#5-api-management-apim--other-skus)
6. [Feature Flags (`features`)](#6-feature-flags-features)
7. [Log Analytics & Azure Monitor (`monitoring`)](#7-log-analytics--azure-monitor-monitoring)
8. [Usage Pipeline & Network Access (`usage_pipeline`)](#8-usage-pipeline--network-access-usage_pipeline)
9. [Entra ID Authentication](#9-entra-id-authentication)
10. [AI Foundry](#10-ai-foundry)
11. [LLM Backend Routing](#11-llm-backend-routing)
12. [Diagnostic Logging](#12-diagnostic-logging)
13. [Redis (Azure Managed Redis)](#13-redis-azure-managed-redis)
14. [Optional APIM Extra APIs](#14-optional-apim-extra-apis)
15. [API Center](#15-api-center)
16. [AI Search Instances](#16-ai-search-instances)
17. [Azure Monitor Private Link](#17-azure-monitor-private-link)
18. [Foundry Embeddings](#18-foundry-embeddings)
19. [Logic App Content Share](#19-logic-app-content-share)
20. [APIM Logic Plane (JWT / PII / MCP)](#20-apim-logic-plane-jwt--pii--mcp)
21. [Entra ID Add-On (App Registration)](#21-entra-id-add-on-app-registration)
22. [Foundry → APIM Connection](#22-foundry--apim-connection)
23. [Sub-Module Variable Map](#23-sub-module-variable-map)
24. [Outputs](#24-outputs)

---

## 1. Basic Configuration

| Variable | Type | Default | Notes |
|---|---|---|---|
| ★ `subscription_id` | string | — | Azure subscription for the deployment. |
| ☆ `environment_name` | string | `citadel-dev` | 3–24 lower-case alphanum/hyphen. Used in naming and tags. |
| ☆ `location` | string | `eastus` | Primary Azure region for the resource group. |
| ☆ `tags` | map(string) | `{}` | Merged with defaults (`azd-env-name`, `Solution`, `ManagedBy`). |
| ☆ `purge_soft_delete_on_destroy` | bool | `false` | If `true`, purges soft-deleted Key Vault / Cosmos on destroy (dev convenience). |
| ☆ `rollout_phase` | string | `full` | `full` = deploy everything configured. `core` = first phase of a phased rollout (`scripts/deploy.sh --phased` / `deploy.ps1 -Phased` pass `-var=rollout_phase=core` for phase 1): forces the add-ons off — Entra ID setup, JWT auth, the Foundry → APIM connections, `features.mcp_sample` and `features.api_center_onboarding` — so the core platform converges first; the next run with `full` adds them. Resource names are known at plan time, so a single `full` apply works too. |
| ☆ `enable_telemetry` | bool | `true` | Let the Azure Verified Modules (AVM) send their usage telemetry to Microsoft ([aka.ms/avm/telemetryinfo](https://aka.ms/avm/telemetryinfo)). No deployment data is sent. |

## 2. Resource Naming

Leave values empty (`""`) to auto-generate (`<prefix>-<resource_token>`, or a 6-character suffix such as `redis-<environment_name>-<suffix>` for globally unique names) via [modules/naming](modules/naming/README.md). Generated names are deterministic — the token and the 6-character suffix are derived from the resource group, environment and subscription — so they are known at plan time. The APIM name is set with `apim.name` (see [§5](#5-api-management-apim--other-skus)).

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `resource_group_name` | string | `""` | Auto: `rg-<environment_name>`. |
| ☆ `use_existing_resource_group` | bool | `false` | `true` looks the existing RG up instead of creating it. |
| ☆ `cosmos_db_account_name` | string | `""` | Auto: `cosmos-<token>`. |
| ☆ `eventhub_namespace_name` | string | `""` | Auto: `evhns-<token>`. |
| ☆ `log_analytics_name` | string | `""` | Auto: `law-<token>`. |
| ☆ `key_vault_name` | string | `""` | Auto: `kv-<token>`. |
| ☆ `name_overrides` | map(string) | `{}` | Logical role → explicit resource name (keys: the `names` output of [modules/naming](modules/naming/README.md), e.g. `apim`, `key_vault`, `redis`, `logic_app`). Empty values are ignored; the dedicated `*_name` variables take precedence. |

## 3. Security / Key Vault

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `soft_delete_retention_days` | number | `7` | 1–90. |
| ☆ `purge_protection_enabled` | bool | `true` | Prevents permanent deletion. |
| ☆ `rbac_authorization_enabled` | bool | `true` | RBAC vs access policies. |
| ☆ `network_acl_default_action` | string | `Deny` | `Allow` or `Deny`. |
| ☆ `kv_public_network_access_enabled` | bool | `false` | Enable public network access to Key Vault. |
| ☆ `kv_deployer_ip_rules` | list(string) | `[]` | Optional public IPs / CIDRs added to KV `network_acls.ip_rules`. Use to let a CI runner or admin workstation perform data-plane writes (secrets) when `network_acl_default_action = "Deny"`. Accepts `"203.0.113.4"` or `"203.0.113.0/24"`. **When non-empty, `public_network_access_enabled` is automatically forced to `true`** — Azure ignores `ip_rules` when public access is fully disabled. Default-action `Deny` still restricts traffic to the allowlist + private endpoints. Leave empty in production; prefer running Terraform from inside the VNet. |
| ☆ `kv_auto_detect_deployer_ip` | bool | `false` | When `true`, auto-detects the current public IP (via `https://api.ipify.org`) and appends `<ip>/32` to `kv_deployer_ip_rules`. Same auto-flip of `public_network_access_enabled` applies. Convenient for local bootstrap. Not recommended for CI with unstable egress IPs. |
| ☆ `create_apim_gateway_key_secret` | bool | `false` | When `true`, writes a placeholder `apim-gateway-key` secret (value `PLACEHOLDER-update-after-apim-deploy`) to Key Vault for optional downstream tooling. Nothing in this stack reads it; validation notebooks fetch the real key via `az apim subscription show`. Enabling it requires KV data-plane write access from the deployer IP (see `kv_deployer_ip_rules` / `kv_auto_detect_deployer_ip`) and is the most common cause of 403 `ForbiddenByFirewall` errors on first apply. |
| ☆ `key_vault_sku` | string | `standard` | `standard` or `premium`. |

## 4. Networking (`network`)

Typed object declared in [interfaces.tf](interfaces.tf). Greenfield VNets are built by [modules/networking](modules/networking/README.md) (`module "networking"` in [network.tf](network.tf), `count = 0` in BYO mode); with `mode = "alz_spoke"` the platform-vended spoke VNet is looked up by name and [modules/networking](modules/networking/README.md) creates the subnets inside it; with `mode = "byo"` the VNet and subnets are looked up by name (`data.azurerm_virtual_network.byo` / `data.azurerm_subnet.byo`). Private DNS zones and VNet links are handled by [modules/private-dns](modules/private-dns/README.md).

```hcl
network = {
  mode                    = "greenfield"        # or "alz_spoke" / "byo"
  resource_group_name     = null                # required for alz_spoke / byo
  vnet_name               = null                # null = generated (greenfield)
  hub_firewall_ip         = null                # required for alz_spoke
  default_outbound_access = null                # null = true (greenfield), false (alz_spoke)
  address_space           = "10.170.0.0/24"
  subnets = {
    apim             = { name = "snet-citadel-apim",      prefix = "10.170.0.0/26" }
    private_endpoint = { name = "snet-citadel-pe",        prefix = "10.170.0.64/26" }
    logic_app        = { name = "snet-citadel-functions", prefix = "10.170.0.128/26" }
    agent            = { enabled = true, name = "snet-agents", prefix = "10.170.0.192/26" }
    ase              = { name = "snet-citadel-ase",       prefix = "10.170.1.0/24" }
  }
  private_dns = {
    resource_group_name = null
    zone_ids            = {}                      # empty = create the zones
    zone_groups_managed_by_policy = false         # true = Azure Policy creates the PE DNS zone groups
  }
}
```

| Attribute | Type | Default | Notes |
|---|---|---|---|
| ☆ `mode` | string | `greenfield` | `greenfield` = create the VNet and subnets; `alz_spoke` = Azure Landing Zone spoke: the platform vends the VNet (looked up by `resource_group_name` + `vnet_name`, peered to the hub) and this deployment creates the subnets in it, each with an NSG and a route table sending `0.0.0.0/0` to `hub_firewall_ip`. No private DNS zones are created — supply `private_dns.zone_ids` or leave the zone groups to the platform's `Deploy-Private-DNS-Zones` policy; `byo` = look up an existing VNet (`resource_group_name` + `vnet_name`) and its subnets by name. |
| ☆ `resource_group_name` | string | `null` | Existing VNet's resource group. Required when `mode = "alz_spoke"` or `"byo"` (validated). |
| ☆ `vnet_name` | string | `null` | Existing VNet (alz_spoke / byo) or name for the new one; `null` = generated by [modules/naming](modules/naming/README.md). |
| ☆ `hub_firewall_ip` | string | `null` | `alz_spoke` only (required, validated): private IP of the hub firewall, the next hop for `0.0.0.0/0` on every subnet. |
| ☆ `default_outbound_access` | bool | `null` | Default outbound internet access on the subnets this deployment creates. `null` = `true` for greenfield (no other egress path), `false` for alz_spoke (egress through the hub firewall). |
| ☆ `address_space` | string | `10.170.0.0/24` | Greenfield only. |
| ☆ `subnets.apim.name` / `.prefix` | string | `snet-citadel-apim` / `10.170.0.0/26` | V2 SKUs: dedicated to APIM outbound VNet integration and delegated to `Microsoft.Web/serverFarms` (automatic for a new VNet; in byo mode the subnet must already be empty and delegated). |
| ☆ `subnets.private_endpoint.name` / `.prefix` | string | `snet-citadel-pe` / `10.170.0.64/26` | |
| ☆ `subnets.logic_app.name` / `.prefix` | string | `snet-citadel-functions` / `10.170.0.128/26` | |
| ☆ `subnets.agent.enabled` | bool | `true` | Create a dedicated subnet for Foundry agent network injection. |
| ☆ `subnets.agent.name` / `.prefix` | string | `snet-agents` / `10.170.0.192/26` | Agent subnet (prefix used for a new VNet). |
| ☆ `subnets.ase.name` / `.prefix` | string | `snet-citadel-ase` / `10.170.1.0/24` | ASE v3 subnet; only used when `usage_pipeline.logic_app.hosting = "ase_v3"` and this deployment creates the ASE (`usage_pipeline.ase.app_service_environment_id = null`; a shared / BYO ASE brings its own subnet, so none is created). Min `/27`, `/24` recommended. Greenfield: appended to the VNet as an extra address space when outside `address_space`. Byo: must already exist, be empty and be delegated to `Microsoft.Web/hostingEnvironments`. |
| ☆ `private_dns.resource_group_name` | string | `null` | Existing private DNS zones RG. |
| ☆ `private_dns.zone_ids` | map(string) | `{}` | Map zone → resource ID. Empty (and no `resource_group_name`) = create the private DNS zones (greenfield / byo); otherwise use the zone IDs supplied. |
| ☆ `private_dns.zone_groups_managed_by_policy` | bool | `false` | `true` = Azure Policy (ALZ `Deploy-Private-DNS-Zones`) creates the private endpoint DNS zone groups; Terraform doesn't create or remove them and no zone IDs are required. Automatically `true` for `alz_spoke` without `zone_ids`. |

> Subnet prefixes are used in greenfield and alz_spoke modes; in byo mode only the names matter. Every subnet created in greenfield / alz_spoke mode has an NSG (Azure Landing Zone `Deny-Subnet-Without-Nsg`).

## 5. API Management (`apim`) & Other SKUs

Typed object declared in [interfaces.tf](interfaces.tf), consumed by [modules/apim](modules/apim/README.md).

```hcl
apim = {
  name                  = null            # null = generated
  sku                   = "StandardV2"
  capacity              = 1
  publisher_email       = "admin@contoso.com"
  publisher_name        = "AI Citadel Admin"
  vnet_mode             = null            # Developer/Premium: none | external | internal; StandardV2: none | integration; PremiumV2: none | integration | injection
  private_endpoint      = true            # v2 SKUs
  public_network_access = true            # v2 SKUs
}
```

| Attribute | Type | Default | Notes |
|---|---|---|---|
| ☆ `name` | string | `null` | `null` = generated by [modules/naming](modules/naming/README.md) (`apim-<token>`). |
| ☆ `sku` | string | `StandardV2` | `Developer`, `Premium`, `StandardV2`, `PremiumV2` (validated). **Region-constrained:** `StandardV2` / `PremiumV2` (v2 platform) are only available in a subset of regions — if your `location` doesn't support v2, use `Premium` (classic) which is globally available. Verify with `az apim list-skus --location <region>` or [API Management region availability](https://learn.microsoft.com/azure/api-management/api-management-region-availability). |
| ☆ `capacity` | number | `1` | Scale units. The `Developer` SKU must stay at `1` (validated on `apim`, and a precondition in [modules/apim](modules/apim/main.tf)). |
| ☆ `publisher_email` | string | `admin@contoso.com` | |
| ☆ `publisher_name` | string | `AI Citadel Admin` | |
| ☆ `vnet_mode` | string | `null` | `Developer` / `Premium`: `none`, `external` or `internal` (classic VNet injection). `StandardV2`: `none` or `integration` (outbound VNet integration, subnet delegated to `Microsoft.Web/serverFarms`). `PremiumV2`: `none`, `integration` or `injection` (private VIP, subnet delegated to `Microsoft.Web/hostingEnvironments`, ≥ /27). `null` = `external` for classic SKUs, `integration` for v2 SKUs. `none` creates no APIM subnet. With `internal` (five hostnames) or `injection` (gateway hostname), private DNS zones pointing at the APIM private IP are created and linked to the VNet (skipped when BYO / platform DNS is used). See [docs/operations/apim-network-modes.md](docs/operations/apim-network-modes.md) for the matrix and how to change modes. |
| `public_ip_address_id` | string | `null` | Classic `external` / `internal` only: Standard-SKU public IP resource ID for the service. |
| ☆ `private_endpoint` | bool | `true` | V2 SKUs: create the inbound private endpoint. |
| ☆ `public_network_access` | bool | `true` | V2 SKUs: allow public inbound access. Setting it to `false` requires `private_endpoint = true` (otherwise the gateway is unreachable — enforced by a precondition). Azure rejects creating a service with public access disabled, so the service is created public and `false` takes effect on the **next apply**, once the service and its private endpoint exist (existence probe in [modules/apim](modules/apim/main.tf)). |

Other SKU & sizing inputs (flat):

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `api_center_sku` | string | `Free` | |

## 6. Feature Flags (`features`)

Typed object declared in [interfaces.tf](interfaces.tf). All attributes are `bool`.

| Attribute | Default | Notes |
|---|---|---|
| ☆ `api_center` | `true` | Deploy API Center as AI Registry. |
| ☆ `api_center_onboarding` | `false` | Register the enabled gateway APIs in API Center ([api-center-registration.tf](api-center-registration.tf) → [modules/api-center-registration](modules/api-center-registration/README.md)). |
| ☆ `pii_redaction` | `true` | PII detection via the Foundry Language endpoint (`piiServiceUrl` named value + PII Event Hub logger). |
| ☆ `pii_anonymization` | `true` | Policy fragments for PII anonymize / deanonymize. |
| ☆ `content_safety` | `true` | Content Safety named value + backend. |
| ☆ `semantic_cache` | `false` | Deploy Azure Managed Redis as the APIM external cache (see [§13](#13-redis-azure-managed-redis)). |
| ☆ `unified_ai_api` | `false` | Wildcard Unified AI API (+ product and its fragments). |
| ☆ `openai_realtime` | `false` | Realtime WebSocket API. |
| ☆ `document_intelligence` | `false` | Doc Intel legacy + v4 APIs. |
| ☆ `ai_model_inference` | `false` | Azure AI Model Inference API. |
| ☆ `azure_ai_search` | `false` | AI Search Index API. |
| ☆ `embeddings_backend` | `false` | Register the embeddings backend in APIM (see [§18](#18-foundry-embeddings)). |
| ☆ `mcp_sample` | `false` | Sample Weather API + Weather MCP + Microsoft Learn MCP APIs. |

## 7. Log Analytics & Azure Monitor (`monitoring`)

Typed object declared in [interfaces.tf](interfaces.tf). When `log_analytics_workspace_id` is set, the root module looks the workspace up (`data.azurerm_log_analytics_workspace.byo` in [main.tf](main.tf)) and passes it to [modules/monitoring](modules/monitoring/README.md).

| Attribute | Type | Default | Notes |
|---|---|---|---|
| ☆ `log_analytics_workspace_id` | string | `null` | `null` = create a workspace; set = use this (BYO / platform) workspace. Must be a full workspace resource ID (`/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>`, validated). |
| ☆ `log_analytics_subscription_id` | string | `null` | Subscription of the BYO workspace when it differs from `subscription_id`. |
| ☆ `private_link_scope` | bool | `false` | Create an Azure Monitor Private Link Scope (AMPLS) for private ingestion. |
| ☆ `app_insights_dashboards` | bool | `true` | Create the Application Insights dashboards. |

## 8. Usage Pipeline & Network Access (`usage_pipeline`)

Typed object for the usage ingestion pipeline (Event Hub → Logic App → Cosmos DB), declared in [interfaces.tf](interfaces.tf).

```hcl
usage_pipeline = {
  eventhub  = { capacity = 1, public_network_access = "Enabled", disaster_recovery = null }
  cosmos    = { public_network_access = "Disabled", local_auth_enabled = false }
  logic_app = {
    hosting            = "workflow_standard"  # or "ase_v3"
    sku                = null                 # null = WS1 (workflow_standard) / I1v2 (ase_v3)
    worker_count       = 1                    # ase_v3: autoscale minimum
    max_worker_count   = 3                    # ase_v3: autoscale maximum
    deployment         = "run_from_package"   # ase_v3: or "zip_deploy"
    content_share_name = ""
    code_deploy        = false
    code_source_path   = ""
  }
  ase = {
    app_service_environment_id   = null       # set = use a shared / BYO ASE
    internal_load_balancing_mode = "Web, Publishing"
    zone_redundant               = false
    create_private_dns_zone      = true
  }
}
```

| Attribute | Type | Default | Notes |
|---|---|---|---|
| ☆ `eventhub.capacity` | number | `1` | Event Hub capacity units. |
| ☆ `eventhub.public_network_access` | string | `Enabled` | `Enabled`/`Disabled`. Must be Enabled on first deploy. |
| ☆ `eventhub.disaster_recovery` | object | `null` | `{ partner_namespace_id, alias = "default" }` for geo-DR pairing. |
| ☆ `cosmos.public_network_access` | string | `Disabled` | `Enabled`/`Disabled`. |
| ☆ `cosmos.local_auth_enabled` | bool | `false` | Key / connection-string auth on Cosmos DB. `false` = Entra ID (RBAC) only; the Logic App's Cosmos connection uses its system-assigned managed identity. Set `true` only if an external client (e.g. a Power BI report refreshed with the account key) still needs keys. |
| ☆ `logic_app.hosting` | string | `workflow_standard` | `workflow_standard` (WS plan + regional VNet integration; storage account **must keep shared-key access** for the Azure Files content share) or `ase_v3` (Isolated v2 plan in a dedicated ASE v3; runtime storage via the usage UAMI, no content share, **shared-key access disabled**). See [Logic App hosting on ASE v3](#logic-app-hosting-on-ase-v3). |
| ☆ `logic_app.sku` | string | `null` | `workflow_standard`: `WS1`/`WS2`/`WS3` (default `WS1`). `ase_v3`: Isolated v2 SKU `I1v2`–`I6v2`, `I1mv2`–`I5mv2` (default `I1v2`). Validated against `hosting`. |
| ☆ `logic_app.worker_count` | number | `1` | ASE v3 only: Isolated v2 instance count and lower bound of the CPU autoscale. |
| ☆ `logic_app.max_worker_count` | number | `3` | ASE v3 only: upper bound of the CPU autoscale (`azurerm_monitor_autoscale_setting`: +1 instance above 70 % CPU, −1 below 30 %). Validated `>= worker_count`. |
| ☆ `logic_app.deployment` | string | `run_from_package` | ASE v3 only: how the workflow code is published. `run_from_package` = the zip is uploaded to the keyless storage account and the site runs it with the usage UAMI (no SCM access); `zip_deploy` = `az` pushes the zip to the site's SCM endpoint. Validated (`run_from_package` / `zip_deploy`). Workflow Standard always uses `zip_deploy`. See [Logic App hosting on ASE v3](#logic-app-hosting-on-ase-v3). |
| ☆ `logic_app.content_share_name` | string | `""` | `WEBSITE_CONTENTSHARE`; auto-derived if blank. Ignored with `hosting = "ase_v3"` (no content share). |
| ☆ `logic_app.code_deploy` | bool | `false` | Zip + publish the Logic App Standard workflows after infra is ready: `az functionapp deployment source config-zip` (`zip_deploy`; requires the `az` CLI on the deployer, no extra extension) or a package blob in the runtime storage account (`run_from_package`, ASE v3). The example tfvars set `code_deploy = true`. See [DEPLOYMENT_GUIDE.md §7.8](DEPLOYMENT_GUIDE.md#78-logic-app-workflow-code-off-by-default). |
| ☆ `logic_app.code_source_path` | string | `""` | Path to the Logic App Standard project folder to publish. Blank = the vendored `logicapp-src/usage-ingestion-logicapp` (root fallback in [main.tf](main.tf)). |
| ☆ `ase.app_service_environment_id` | string | `null` | `null` = this deployment creates a dedicated ASE v3 ([modules/app-hosting](modules/app-hosting/README.md)) in `network.subnets.ase`. Set to the resource ID of a shared / BYO ASE v3 to host the plan there: no ASE, no ASE subnet and no ASE DNS zone are created (the `internal_load_balancing_mode` and `create_private_dns_zone` settings below are then ignored). |
| ☆ `ase.internal_load_balancing_mode` | string | `Web, Publishing` | `Web, Publishing` = internal (ILB) ASE; `None` = external (public VIP). |
| ☆ `ase.zone_redundant` | bool | `false` | Zone-redundant ASE v3 (region must support AZs; raises minimum billed instances) and zone balancing of the Isolated v2 plan (also applied with a shared ASE). |
| ☆ `ase.create_private_dns_zone` | bool | `true` | ILB ASE only: create `<ase>.appserviceenvironment.net` (`*`, `*.scm`, `@` → ILB IP) and link it to the gateway VNet. Set `false` when DNS is centralised in a hub. |

Keyless lock-in (flat, [variables.tf](variables.tf); assignment in [policy.tf](policy.tf)):

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `deny_storage_shared_key` | bool | `false` | Assigns the built-in policy *Storage accounts should prevent shared key access* (`8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54`) with effect **Deny** on the resource group, after the Logic App storage account exists. Requires `usage_pipeline.logic_app.hosting = "ase_v3"` (precondition — Workflow Standard needs shared keys). Leave `false` when the platform already assigns the ALZ `Deny-Storage-Shared-Key` policy. `true` in [prod.tfvars.example](environments/prod.tfvars.example). |

Other network access inputs (flat):

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `ai_foundry_external_access` | bool | `false` | |

### Logic App hosting on ASE v3

Logic Apps Standard on the **Workflow Service Plan** (WS1/WS2/WS3) keeps its site content on an Azure Files share that is mounted with the storage account key, so [shared-key access cannot be disabled](https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account). That is a documented exception to the ALZ `Deny-Storage-Shared-Key` policy; the dev / quick-start template ([dev.tfvars.example](environments/dev.tfvars.example)) keeps `workflow_standard` on purpose (decision D3). Set `usage_pipeline.logic_app.hosting = "ase_v3"` for the **keyless** usage pipeline — the production template ([prod.tfvars.example](environments/prod.tfvars.example)) does, and [asetest.tfvars.example](environments/asetest.tfvars.example) walks through a test. This mode:

- **ASE v3** — with `usage_pipeline.ase.app_service_environment_id = null`, the root `module "app_hosting"` ([modules/app-hosting](modules/app-hosting/README.md), AVM `avm-res-web-hostingenvironment` 2.0.1) creates a dedicated ASE v3 in the subnet `network.subnets.ase` (delegated to `Microsoft.Web/hostingEnvironments`; the default `/24` VNet is full, so the ASE prefix, default `10.170.1.0/24`, is added as a second VNet address space). It is internal by default (`Web, Publishing`), with internal encryption on, TLS 1.0, FTP and remote debugging off, and zone redundancy from `usage_pipeline.ase.zone_redundant`. For an internal ASE it also creates the private DNS zone `<ase>.appserviceenvironment.net` (AVM `avm-res-network-privatednszone` 0.5.0; `*`, `*.scm` and `@` → the internal inbound IP), linked to the gateway VNet. Set `app_service_environment_id` to use a shared / BYO ASE instead — then no ASE, ASE subnet or DNS zone is created here.
- **Plan** — an Isolated v2 plan (`usage_pipeline.logic_app.sku`, default `I1v2`) in the ASE, zone-balanced when `ase.zone_redundant = true`, with a CPU autoscale setting: +1 instance above 70 % average CPU, −1 below 30 %, between `worker_count` and `max_worker_count`.
- **Keyless runtime storage** — shared keys disabled, OAuth by default, public network access disabled, network rules `Deny` with no bypass, infrastructure encryption, allowed copy scope `PrivateLink`, cross-tenant replication and local users off, 7-day container delete retention. Private endpoints for `blob`, `queue` and `table` only (no content share, so no `file` endpoint). The configuration never reads a storage account key on this path, so none ends up in state.
- **Site** — deployed with `azapi` (`Microsoft.Web/sites`, kind `functionapp,workflowapp`) because `azurerm_logic_app_standard` always requires a storage key. `publicNetworkAccess = Disabled`, FTPS disabled, remote debugging off, Always On, TLS 1.2, basic publishing credentials (FTP and SCM) disabled. Runtime storage uses the identity-based `AzureWebJobsStorage__*` settings with the usage UAMI. A precondition rejects key-based settings (`AzureWebJobsStorage`, `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`, `WEBSITE_CONTENTSHARE`, `AzureCosmosDB_connectionString`).
- **Workflow code** (`usage_pipeline.logic_app.deployment`):
  - `run_from_package` (default) — the workflow zip is uploaded as a content-addressed blob (`usage-ingestion-<sha>.zip`) to the storage account's `deployments` container; the identity running `apply` gets *Storage Blob Data Contributor* on that container. The site gets `WEBSITE_RUN_FROM_PACKAGE` (the blob URL) and `WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID` (the usage UAMI), and each new package triggers a site restart plus `syncfunctiontriggers`. No SCM access is needed, but the upload goes to the storage data plane, which has no public endpoint: **run `apply` from a machine or runner that reaches the storage private endpoint**, or skip the publish for that run (`-SkipLogicAppCode` / `skip_logic_app_code_deploy = true`). *Still to be confirmed in a live spike: that Logic Apps Standard loads workflows from a package fetched with a managed identity — fallback `deployment = "zip_deploy"`.*
  - `zip_deploy` — `az` pushes the zip to `<app>.scm.<ase>.appserviceenvironment.net`, which on an internal ASE only resolves and is only reachable inside the VNet: run `apply` from a runner in the VNet.
- The `snet-citadel-functions` subnet (`network.subnets.logic_app`) is kept but unused.
- Optional: `deny_storage_shared_key = true` locks the resource group keyless with a Deny policy (see the table above).

The `workflow_standard` path is unchanged: WS plan with regional VNet integration, shared-key content share (with a `file` private endpoint), `azurerm_logic_app_standard`, and `zip_deploy`. The `module.logic_app` output `hosting` summarises the result (`model`, `keyless_storage`, `deployment_method`, `package_url`, `app_setting_names`).

Things to plan for:

- **Cost:** an ASE v3 is billed for at least one Windows I1v2 instance even when empty, so it costs considerably more than WS1; zone redundancy raises the minimum billed instances.
- **Duration:** creating an ASE v3 takes roughly 1–4 hours.
- **Network access for `apply`:** see *Workflow code* above, and [docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md) for what to ask the platform team (ASE subnet, DNS, firewall, deployment runner).
- **Hosting model is a first-deploy choice:** this codebase targets fresh installs; to change the model, deploy a new environment (or destroy and redeploy) rather than switching in place.
- **Cosmos DB:** independent of hosting model, the workflows' Cosmos DB connection uses the Logic App's managed identity and Cosmos key auth is off by default (`usage_pipeline.cosmos.local_auth_enabled`).

## 9. Entra ID Authentication

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `entra_auth_enabled` | bool | `false` | Turn on JWT validation in APIM. |
| ☆ `entra_tenant_id` | string | `""` | |
| ☆ `entra_client_id` | string | `""` | Application (client) ID. |
| ☆ `entra_audience` | string | `""` | JWT `aud`. |

## 10. AI Foundry

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `foundry_network_injection_enabled` | bool | `true` | Global default for injecting Foundry accounts into the VNet (agent subnet). Per-instance `network_injection_enabled` overrides this. |
| ☆ `foundry_outbound_allowed_fqdns` | list(string) | `null` | Opt-in egress allow-list: restrict the AI Foundry accounts' outbound network access (incl. the Agent Service) to these FQDNs. `null` = unrestricted. List every endpoint your agents and tools call. |

### `ai_foundry_instances` (list of object)

```hcl
{
  name                      = optional(string, "")     # auto-generated if blank
  location                  = string                   # required
  custom_subdomain          = optional(string, "")
  default_project_name      = optional(string, "citadel-governance-project")
  network_injection_enabled = optional(bool, true)     # per-instance VNet injection override
}
```

### `ai_foundry_models` (list of object)

```hcl
{
  name             = string                       # e.g. "gpt-4o"
  publisher        = optional(string, "OpenAI")
  version          = string
  sku              = optional(string, "GlobalStandard")
  capacity         = optional(number, 100)
  ai_service_index = optional(number, 0)          # index into ai_foundry_instances
}
```

## 11. LLM Backend Routing

### Auto-derivation (default)

**No manual configuration required.** `llm_backend_config` defaults to `[]`, which triggers auto-derivation in [main.tf](main.tf) (`locals.auto_llm_backends`):

- One APIM backend per entry in `ai_foundry_instances` (Foundry is always deployed).
- `backend_id = "foundry-${location}-${index}"`, `priority = 1` for index `0` and `2` for subsequent, `auth_scheme = "managedIdentity"` (`auth_type = "managed-identity"`).
- `endpoint` sourced from `module.foundry.foundry_endpoints[i]` (late-bound; known after apply — no second-phase apply required).
- Models grouped by `ai_service_index`: every `ai_foundry_models` entry targeting instance `i` is attached to that instance's backend.

This produces a fully-routed gateway in a single `terraform apply`.

### `llm_backend_config` — full override (optional)

Populate ONLY when you need to replace the auto-derived list entirely (e.g. external Azure OpenAI, third-party LLM gateway, on-prem endpoint). Non-empty value takes full precedence; auto-derivation is skipped.

```hcl
{
  backend_id   = string                            # unique
  backend_type = string                            # "ai-foundry" | "azure-openai" | "external"
  endpoint     = string                            # https://...
  auth_scheme  = string                            # "managedIdentity" | "apiKey" | "token"
  auth_type    = optional(string)                  # "managed-identity"|"aws-sigv4"|"api-key-bearer"|"api-key-header"|"none"
  auth_config  = optional(object({                 # e.g. named value holding the key
    named_value_key = optional(string)
  }))
  priority     = optional(number, 1)
  weight       = optional(number, 100)
  supported_models = list(object({
    name                = string
    sku                 = optional(string, "Standard")
    capacity            = optional(number, 100)
    modelFormat         = optional(string, "OpenAI")
    modelVersion        = optional(string, "1")
    apiVersion          = optional(string, "2024-02-15-preview")
    timeout             = optional(number, 120)
    inferenceApiVersion = optional(string, "")
    retirementDate      = optional(string, "")
  }))
}
```

### `extra_llm_backends` — append to auto-derived list (optional)

Same object shape as `llm_backend_config` (including the optional `auth_type` / `auth_config` fields). Leave `llm_backend_config = []` and populate this to mix Foundry (auto) with external backends in the same gateway. Ignored when `llm_backend_config` is non-empty.

```hcl
extra_llm_backends = [
  {
    backend_id   = "external-aoai-0"
    backend_type = "azure-openai"
    endpoint     = "https://my-aoai-resource.openai.azure.com/"
    auth_scheme  = "apiKey"
    priority     = 2
    weight       = 100
    supported_models = [
      { name = "gpt-4.1", sku = "GlobalStandard", capacity = 100, modelFormat = "OpenAI", modelVersion = "2025-04-14" },
    ]
  },
]
```

## 12. Diagnostic Logging

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `apim_log_verbosity` | string | `information` | `verbose`/`information`/`error`. |
| ☆ `apim_log_body_bytes` | number | `8192` | Body bytes per log entry. |

## 13. Redis (Azure Managed Redis)

Used only when `features.semantic_cache = true`.

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `redis_sku_name` | string | `Balanced_B10` | `Microsoft.Cache/redisEnterprise` SKU. |
| ☆ `redis_sku_capacity` | number | `2` | Only for `Enterprise_*`/`EnterpriseFlash_*`. |
| ☆ `redis_public_network_access` | string | `Disabled` | |
| ☆ `redis_minimum_tls_version` | string | `1.2` | |

## 14. Optional APIM Extra APIs

The extra APIs themselves are switched on through [`features`](#6-feature-flags-features) (`ai_model_inference`, `document_intelligence`, `azure_ai_search`, `openai_realtime`, `unified_ai_api`, `mcp_sample`) and are defined in the API catalogue in [apis.tf](apis.tf).

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `inference_api_type` | string | `OpenAIV1` | Universal LLM API inference contract. One of `AzureOpenAI`, `AzureAI`, `OpenAI`, `OpenAIV1`. |

## 15. API Center

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `apic_location` | string | `""` | Override region if APIC not in primary. |

API Center itself and API registration are enabled with `features.api_center` / `features.api_center_onboarding` ([§6](#6-feature-flags-features)).

## 16. AI Search Instances

`ai_search_instances` — existing AI Search endpoints registered as APIM backends.

```hcl
[
  { name = "search1", endpoint = "https://...search.windows.net" }
]
```

## 17. Azure Monitor Private Link

Set `monitoring.private_link_scope = true` to create an AMPLS for private ingestion (see [§7](#7-log-analytics--azure-monitor-monitoring)).

## 18. Foundry Embeddings

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `embeddings_backend_url` | string | `""` | Used only when `features.embeddings_backend = true`. |

## 19. Logic App Content Share

The content share and workflow-code publish settings are attributes of `usage_pipeline.logic_app` (`content_share_name`, `code_deploy`, `code_source_path`, `deployment`) — see [§8](#8-usage-pipeline--network-access-usage_pipeline).

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `skip_logic_app_code_deploy` | bool | `false` | Skip publishing the Logic App workflow code on this run even when `usage_pipeline.logic_app.code_deploy = true` (what `scripts/deploy.sh --skip-logic-app-code` / `deploy.ps1 -SkipLogicAppCode` pass), e.g. when the deployer can't reach the SCM endpoint (`zip_deploy`) or the runtime storage private endpoint (`run_from_package`, ASE v3) from where `apply` runs. |

## 20. APIM Logic Plane (JWT / PII / MCP)

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `configure_circuit_breaker` | bool | `true` | Per-backend circuit breakers. |
| ☆ `ms_learn_mcp_backend_url` | string | `https://learn.microsoft.com/api/mcp` | Only used when `features.mcp_sample = true`. |
| ☆ `enable_jwt_auth` | bool | `false` | Populate JWT-* named values. |
| ☆ `jwt_tenant_id` | string | `""` | |
| ☆ `jwt_app_registration_id` | string | `""` | |
| ☆ `azure_login_endpoint` | string | `https://login.microsoftonline.com/` | For sovereign clouds. |

## 21. Entra ID Add-On (App Registration)

Port of `entra-id-setup/setup.ps1`. When enabled, creates an app registration + SP + client secret and writes the secret to Key Vault. The generated `client_id`/`tenant_id` **overrides** `jwt_*` and populates APIM JWT named values.

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `enable_entra_id_setup` | bool | `false` | Master switch. |
| ☆ `entra_app_display_name_prefix` | string | `ai-citadel-gateway` | Suffixed with `environment_name`. |
| ☆ `entra_client_secret_name` | string | `ENTRA-APP-CLIENT-SECRET` | KV secret name. |
| ☆ `entra_client_secret_rotation_days` | number | `730` | Rotate after N days. |

## 22. Foundry → APIM Connection

| Variable | Type | Default | Notes |
|---|---|---|---|
| ☆ `enable_foundry_apim_connection` | bool | `false` | Creates the dedicated `foundry-apim-connection` APIM subscription and, in every Foundry project, one `ApiManagement` connection per `foundry_apim_connections` entry (ApiKey = that subscription's key). |
| ☆ `foundry_apim_connections` | list(object) | Universal LLM API (`/models`, discovery via `/deployments`) | APIs exposed to Foundry projects. Fields mirror the Foundry connection metadata: `api_name`, `api_path`, `connection_name` (default `apim-<apim>-<api>`), `deployment_in_path`, `inference_api_version`, `list_models_endpoint` / `get_model_endpoint` / `deployment_provider` (dynamic discovery) or `static_models`, `custom_headers`. |

---

## 23. Sub-Module Variable Map

Sub-modules are not configured directly — their inputs are wired from the root variables and the effective-config locals of [interfaces.tf](interfaces.tf) (`local.apim_cfg`, `local.network_cfg`, `local.features`, `local.usage_cfg`, `local.monitoring_cfg`) in [main.tf](main.tf), [network.tf](network.tf), [apis.tf](apis.tf), [policy-fragments.tf](policy-fragments.tf) and [api-center-registration.tf](api-center-registration.tf). Each module has a generated README with its full input/output tables; only internals that extend root-level behavior are listed here.

### [modules/naming](modules/naming/README.md)
Generates every resource name (`names` output) from `environment_name` / subscription; honours `name_overrides` and the dedicated `*_name` variables.

### Root `module "identity"` ([main.tf](main.tf))
The two user-assigned managed identities (`apim`, `usage`) on AVM `avm-res-managedidentity-userassignedidentity` 0.5.3, called directly from the root (no local wrapper). All AVM modules receive `enable_telemetry`.

### [modules/apim](modules/apim/README.md)
APIM service + private endpoint on AVM `avm-res-apimanagement-service` 0.9.0, public-access flip (existence probe), named values, non-LLM backends, default product, Foundry subscription, internal DNS and the Redis external cache. Consumes `local.apim_cfg` (SKU, capacity, publisher, network type, v2 private endpoint / public access), `entra_*`, `jwt_*`, the PII / content-safety endpoints, `ms_learn_mcp_backend_url`, `ai_search_instances`, `embeddings_backend_url` and the Foundry-connection inputs. Preconditions enforce the SKU × network matrix (v2 private access needs the private endpoint; Developer capacity = 1; classic injection needs a subnet).

### [modules/llm-routing](modules/llm-routing/README.md)
LLM backends, backend pools and the four generated routing fragments. Consumes the effective `llm_backend_config` (auto-derived, overridden or extended — see [§11](#11-llm-backend-routing)) and `configure_circuit_breaker`.

### [modules/apim-policy-fragments](modules/apim-policy-fragments/README.md)
Deploys the fragment catalogue from [policy-fragments.tf](policy-fragments.tf) (gated by `features.unified_ai_api` / `features.pii_anonymization`).

### [modules/gateway-api](modules/gateway-api/README.md)
One instance per API in the catalogue in [apis.tf](apis.tf) (gated by `features.*`, `inference_api_type`, `entra_auth_enabled`, `enable_extra_api_diagnostics` / `extra_api_log_settings`).

### [modules/apim-telemetry](modules/apim-telemetry/README.md)
APIM loggers and global diagnostics. Consumes `apim_log_verbosity`, `apim_log_body_bytes` and `features.pii_redaction`.

### [modules/api-center-registration](modules/api-center-registration/README.md)
Registers the enabled APIs in API Center when `features.api_center_onboarding = true`.

### [modules/networking](modules/networking/README.md)
Greenfield and alz_spoke (`count = 0` for `network.mode = "byo"`). Built on AVM `avm-res-network-virtualnetwork` 0.22.2 (VNet; its `subnet` submodule for alz_spoke subnets in the existing spoke VNet) and `avm-res-network-networksecuritygroup` 0.6.0 (one NSG per subnet). Consumes the VNet name/address space, subnet names + prefixes, the APIM network type, `existing_vnet_id` + `hub_firewall_ip` (alz_spoke: per-subnet route table sending `0.0.0.0/0` to the hub firewall), `default_outbound_access` and the computed `is_apim_vnet` / `enable_ase_subnet` flags. No DNS and no BYO lookups (those live in [network.tf](network.tf) and [modules/private-dns](modules/private-dns/README.md)).

### [modules/private-dns](modules/private-dns/README.md)
Private DNS zones + VNet links (AVM `avm-res-network-privatednszone` 0.5.0). Creates the zones (greenfield / byo), or uses the zone IDs from `network.private_dns.zone_ids`; no zones are created in alz_spoke mode; a `required_zone_keys` precondition checks that every zone needed by the enabled features is supplied (skipped when `zone_groups_managed_by_policy` is in effect).

### [modules/security](modules/security/README.md)
Key Vault on AVM `avm-res-keyvault-vault` 0.11.0. Receives Key Vault naming/SKU, soft-delete/purge/RBAC toggles, tenant + deployer + MI object IDs, and Foundry principal IDs for RBAC grants.

### [modules/foundry](modules/foundry/README.md)
Foundry accounts and model deployments (`cognitive_deployments`, created one at a time) on AVM `avm-res-cognitiveservices-account` 0.11.1 (projects stay azapi). Receives `ai_foundry_instances` and `ai_foundry_models`, `foundry_outbound_allowed_fqdns` → `outbound_allowed_fqdns`, external-access flag, and APIM-connection parameters. Internally uses `enable_apim_connections`, `apim_connections` (per-API connection definitions), and `disable_key_auth`.

### [modules/apic](modules/apic/README.md)
Receives `features.api_center`, `api_center_sku` and `apic_location`.

### [modules/monitoring](modules/monitoring/README.md)
Log Analytics on AVM `avm-res-operationalinsights-workspace` 0.5.1 and Application Insights on AVM `avm-res-insights-component` 0.4.0. Receives `existing_log_analytics_workspace = { id, workspace_id }` (looked up by the root from `monitoring.log_analytics_workspace_id`, else a new workspace is created), `create_dashboards` (`monitoring.app_insights_dashboards`), and AMPLS settings (`monitoring.private_link_scope`, subnet/dns zone).

### [modules/cosmosdb](modules/cosmosdb/README.md)
Account, database, SQL containers and private endpoint on AVM `avm-res-documentdb-databaseaccount` 0.11.0. Receives account name, `usage_pipeline.cosmos.public_network_access`, `usage_pipeline.cosmos.local_auth_enabled` → `local_authentication_enabled`, subnet/dns wiring, and MI principal.

### [modules/eventhub](modules/eventhub/README.md)
Namespace, event hubs, RBAC and private endpoint on AVM `avm-res-eventhub-namespace` 0.1.1. Receives namespace name, `usage_pipeline.eventhub.capacity`, `usage_pipeline.eventhub.public_network_access`, APIM + Logic App MI principals, and `usage_pipeline.eventhub.disaster_recovery` → `disaster_recovery_config`.

### [modules/logic-app](modules/logic-app/README.md)
Usage-pipeline storage account on AVM `avm-res-storage-storageaccount` 0.10.0 and App Service plan on AVM `avm-res-web-serverfarm` 2.0.8. Consumes `usage_pipeline.logic_app` (`hosting` → `hosting_model`, `sku` → `sku_size` / `ase_sku_size`, `worker_count` / `max_worker_count` → `ase_worker_count` / `ase_max_worker_count`, `deployment` → `deployment_method`, `content_share_name` (workflow_standard only), `code_deploy` / `code_source_path` → `enable_code_deploy` / `code_source_path`), `usage_pipeline.ase.zone_redundant` → `ase_zone_redundant`, the ASE ID (`app_service_environment_id`: the shared / BYO ID or `module.app_hosting`'s), Cosmos/Event Hub endpoints, MI trio, PE subnet + DNS zones for the storage account, and toggles for storage PEs / Cosmos role / azuremonitorlogs API connection. Outputs a `hosting` summary (`model`, `keyless_storage`, `deployment_method`, `package_url`, `app_setting_names`). See [Logic App hosting on ASE v3](#logic-app-hosting-on-ase-v3).

### [modules/app-hosting](modules/app-hosting/README.md)
Root `module "app_hosting"` ([main.tf](main.tf)): dedicated App Service Environment v3 on AVM `avm-res-web-hostingenvironment` 2.0.1 plus, for an internal ASE, the `<ase>.appserviceenvironment.net` private DNS zone on AVM `avm-res-network-privatednszone` 0.5.0. Created only when `usage_pipeline.logic_app.hosting = "ase_v3"` and `usage_pipeline.ase.app_service_environment_id = null`. Consumes the generated ASE name, the ASE subnet, `usage_pipeline.ase` (`internal_load_balancing_mode`, `zone_redundant`, `create_private_dns_zone`) and the gateway VNet ID for the DNS zone link.

### Workload policy ([policy.tf](policy.tf))
`deny_storage_shared_key = true` assigns the built-in *Storage accounts should prevent shared key access* policy (Deny) on the resource group — see [§8](#8-usage-pipeline--network-access-usage_pipeline).

### [modules/redis](modules/redis/README.md)
Deployed when `features.semantic_cache = true`. Stays on its own azapi resources (the AVM Redis Enterprise module, 0.2.0, can't set `accessKeysAuthentication`, which the APIM external cache needs). Mirrors all `redis_*` root variables plus `use_private_endpoint`, subnet + DNS zone.

### [modules/entra-id](modules/entra-id/README.md)
Mirrors `enable_entra_id_setup`, `entra_app_display_name_prefix`, `entra_client_secret_name`, `entra_client_secret_rotation_days`, and receives the Key Vault ID.

---

## 24. Outputs

Defined in [outputs.tf](outputs.tf). Read with `terraform output <name>` (add
`-raw` for a single scalar, `-json` for objects/lists).

| Output | Type | Notes |
|---|---|---|
| `resource_group_name` | string | Deployed resource group. |
| `location` | string | Primary region. Added for the validation notebooks. |
| `subscription_id` | string | Subscription of the deployment. Added for the validation notebooks. |
| `apim_name` | string | API Management service name. |
| `apim_gateway_url` | string | APIM gateway base URL. |
| `key_vault_name` | string | Key Vault name. Added for the validation notebooks. |
| `key_vault_uri` | string | Key Vault URI. |
| `cosmos_db_endpoint` / `cosmos_db_account_name` | string | Cosmos DB account. |
| `eventhub_namespace` / `event_hub_name` | string | Event Hub namespace + AI-usage hub. |
| `log_analytics_workspace_id` / `app_insights_name` | string | Monitoring resources. |
| `vnet_id` | string | Virtual network resource ID. |
| `ai_foundry_endpoints` | list(string) | Foundry account endpoints. |
| `ai_foundry_project_endpoints` | list(string) | Foundry project endpoints (one per account). |
| `ai_foundry_services` | list(object) | Foundry accounts in the azd `AI_FOUNDRY_SERVICES` shape (`cognitiveServiceName` + `foundryProjectEndpoint`). Added for the validation notebooks. |
| `llm_backend_config` | list(object) | Effective (auto-derived or overridden) APIM LLM backend config. Added for the validation notebooks. |
| `universal_llm_api_url` | string | `POST /models/chat/completions` endpoint. |
| `azure_openai_api_url` | string | Azure OpenAI compatible base URL. |
| `apim_managed_identity_client_id` / `..._principal_id` | string | APIM UAMI. |
| `usage_managed_identity_client_id` / `..._principal_id` | string | Logic App / usage UAMI. |

The `location`, `subscription_id`, `key_vault_name`, `ai_foundry_services`, and
`llm_backend_config` outputs are consumed by the validation notebooks via the
Terraform-output bridge in [shared/utils.py](shared/utils.py) (azd-var → output
alias map). See [validation/README.md](validation/README.md) and
[DEPLOYMENT_GUIDE.md §9.3](DEPLOYMENT_GUIDE.md#93-validation-notebooks-validation--shared).

---

**See also:** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) · [APIM_POLICY_ARCHITECTURE.md](APIM_POLICY_ARCHITECTURE.md) · [README.md](README.md)
