# AI Citadel Governance Hub — Terraform Deployment Guide

> **Scope:** This document covers the full deployment lifecycle for the Terraform
> port of the AI Hub Gateway Citadel accelerator: prerequisites, ordering,
> rollout strategies, every optional add-on, and the exact commands for each
> scenario.
>
> **Related files:**
> [scripts/deploy.sh](scripts/deploy.sh) / [scripts/deploy.ps1](scripts/deploy.ps1) ·
> [environments/dev.tfvars.example](environments/dev.tfvars.example) ·
> [environments/prod.tfvars.example](environments/prod.tfvars.example)

---

## 1. Mental model: how this differs from Bicep

The Bicep accelerator deploys its stack in **two tiers**:

1. **`main.bicep`** — core resource plane + APIM + APIC.
2. **Follow-on sub-deployments** (separate `az deployment sub create`
   invocations) for pieces that `main.bicep` cannot express inline:
   - `entra-id-setup/setup.ps1` — needs MS Graph (not ARM).
   - `foundry-integration/connection-apim.bicep` — needs the APIM subscription
     key as a **runtime input**.
   - `citadel-access-contracts/main.bicep` — per-use-case products that change
     often post-deploy.
   - `llm-backend-onboarding/` — adding/removing models.
   - `apim-gateway-upgrade/` — changing APIM SKU.

**Terraform has no such split.** The port folds every follow-on into the root
graph and resolves ordering through resource references + `depends_on`. As a
result:

- A single `terraform apply` can deploy the entire stack, including Entra ID
  and the Foundry→APIM connection: every resource name is derived
  deterministically, so all names are known at plan time. Per-use-case access
  contracts are a separate root module,
  [citadel-access-contracts/](citadel-access-contracts/README.md).
- All follow-ons are gated by **feature-flag variables** (`enable_*` and the
  typed `features` object) so you still choose what to roll out.
- If you prefer the Bicep workflow (stage core, validate, then enable
  add-ons), the `--phased` deploy-script mode gives you two sequential
  `plan`/`apply` passes against the same state: phase 1 with
  `rollout_phase = "core"` (add-ons forced off), phase 2 with the add-ons.

---

## 2. Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Terraform | ≥ 1.11 (CI uses the version in `.terraform-version`) | Declared in [terraform.tf](terraform.tf) |
| Azure CLI (`az`) | ≥ 2.57 | Used for auth + RP registration + Logic App code publish (uses core `az functionapp` commands; no extensions needed) |
| `azurerm` provider | `~> 4.0` | Auto-installed by `terraform init` |
| `azapi` provider | `~> 2.0` | Used for APIM v2 backends, MCP, APIC |
| `azuread` provider | `~> 3.0` | Only installed/used when `enable_entra_id_setup = true` |
| `archive` / `null` providers | `~> 2.5` / `~> 3.2` | Used by the Logic App workflow-code publish step |
| Azure subscription | Owner or equivalent | Creates RBAC role assignments |
| Tenant permissions (Entra add-on only) | `Application.ReadWrite.All` | Required to create app registrations |

Sign in before anything else:

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2.1 Script flavors: Bash & PowerShell

Every helper in [scripts/](scripts/) ships in **two interchangeable flavors** —
Bash (`*.sh`) and PowerShell 7+ (`*.ps1`). Both drive the same Terraform graph;
pick whichever suits your shell. This guide's examples use the Bash form, but
every `./scripts/*.sh` command has a `./scripts/*.ps1` equivalent. The only
difference is flag syntax: Bash uses `--kebab-case` flags, PowerShell uses
`-PascalCase` switches.

| Bash (`deploy.sh`) | PowerShell (`deploy.ps1`) |
|---|---|
| `dev` / `prod` (positional) | `dev` / `prod` (positional) |
| `--auto-approve` | `-AutoApprove` |
| `--phased` | `-Phased` |
| `--with-entra` | `-WithEntra` |
| `--with-foundry-conn` | `-WithFoundryConn` |
| `--with-jwt` | `-WithJwt` |
| `--all-addons` | `-AllAddons` |
| `--skip-logic-app-code` | `-SkipLogicAppCode` |
| `--logic-app-code-only` | `-LogicAppCodeOnly` |
| `--help` | `-Help` |

**Example (identical result):**

```bash
./scripts/deploy.sh prod --all-addons --phased --auto-approve
```

```powershell
./scripts/deploy.ps1 prod -AllAddons -Phased -AutoApprove
```

The same mapping applies to the other helpers:
[bootstrap-state](scripts/bootstrap-state.ps1),
[validate](scripts/validate.ps1) and [destroy](scripts/destroy.ps1) all expose `.ps1` equivalents
with positional `dev`/`prod` arguments.

---

## 3. Execution ordering (what runs and when)

Terraform builds a DAG from every explicit reference + `depends_on` clause.
The effective order for a full deployment is:

```text
0. Naming (deterministic, known at plan time) + Resource Group
1. networking         ── VNet, subnets, NSGs, route table (greenfield); subnets + NSGs + UDR to
                         the hub firewall in the vended VNet (alz_spoke); BYO = data lookups in network.tf
   private_dns        ── private DNS zones + VNet links (created or supplied IDs; none in alz_spoke)
2. eventhub           ── namespace + ai-usage/pii-usage hubs + consumer groups
   cosmosdb           ── account + usage-db + 4 containers
   monitoring         ── LAW + 3 App Insights + 3 dashboards + AMPLS
   foundry / apic     ── Foundry account + project, API Center scaffold
                       (all run in parallel — no cross-dependencies)
3. security           ── Key Vault + Foundry KV RBAC
4. redis              ── Azure Managed Redis + PE + APIM caches link
5. entra_id           ── (optional) azuread_application + SP + KV secret
6. apim               ── APIM service + identity + PE + named values (JWT-*, AWS placeholders);
                         v2 private access applied on the next apply (§5.3)
   ├─ backends        ── content safety + AI search + embeddings + MS Learn MCP
   └─ foundry-sub     ── (optional) dedicated APIM subscription for Foundry
   apim_telemetry     ── loggers + global diagnostics
   llm_routing        ── per-model LLM backends + pools + 4 generated routing fragments
   policy_fragments   ── static (+ unified-AI / PII) policy fragments (policy-fragments.tf)
   api / api_dependent── one modules/gateway-api instance per API (apis.tf):
                         Universal LLM, Azure OpenAI, Unified AI, AI Search,
                         DocIntel×2, Inference, Realtime, Weather, Weather MCP,
                         MS Learn MCP — with their API + operation policies
   api_center_registration ── (optional) register each API in APIC
7. app_hosting        ── (ase_v3, no shared ASE) App Service Environment v3 +
                         <ase>.appserviceenvironment.net private DNS zone (1–4 h)
   logic_app          ── Logic App Standard + runtime storage PEs + MI RBAC
                         workflow_standard: WS plan, shared-key content share, 4 PEs
                         ase_v3: Isolated v2 plan + CPU autoscale, keyless storage
                         (blob/queue/table PEs), azapi site
   └─ workflow code   ── zip of logicapp-src/usage-ingestion-logicapp (4 workflows +
                         host.json + connections.json); on in the example tfvars,
                         gated by `usage_pipeline.logic_app.code_deploy`:
                         zip_deploy: `az functionapp deployment source config-zip`
                         run_from_package (ase_v3 default): blob upload → site
                         restart → syncfunctiontriggers
   deny_storage_shared_key
                      ── (optional, ase_v3) Deny shared-key policy on the RG,
                         assigned after the keyless storage account exists
8. foundry.connection_apim
                      ── (optional) Foundry project → APIM connection
```

Per-use-case access contracts (APIM products + policies) are applied
separately, from [citadel-access-contracts/](citadel-access-contracts/README.md).

Anything upstream is mandatory; anything marked `(optional)` is gated by a
feature flag.

---

## 4. Feature flags (what's optional)

Every add-on defaults to **off** unless listed otherwise. You can set them in
`environments/<env>.tfvars`, via `-var=…=true` on the command line, or via
the `--with-*` shortcuts in [scripts/deploy.sh](scripts/deploy.sh).

Gateway capabilities live in the typed `features` object (see
[VARIABLES.md §6](VARIABLES.md#6-feature-flags-features)) and are set in the
tfvars only — the deploy-script shortcuts cover the identity / connection
add-ons. `rollout_phase = "core"` (what `--phased` passes for phase 1) forces
every add-on below that has a shortcut flag, plus `features.mcp_sample` and
`features.api_center_onboarding`, off.

| Variable | Default | Shortcut flag | Effect |
|---|---|---|---|
| `enable_entra_id_setup` | `false` | `--with-entra` | Creates Entra ID app registration, service principal, client secret → KV; auto-populates APIM JWT-* named values. |
| `enable_foundry_apim_connection` | `false` | `--with-foundry-conn` | Creates Foundry project → APIM connection (ApiKey) + dedicated APIM subscription. |
| `features.mcp_sample` | `false` | — | Enables Weather API + Weather MCP + MS Learn MCP APIs. |
| `enable_jwt_auth` | `false` | `--with-jwt` | Populates JWT-* named values from `jwt_tenant_id` / `jwt_app_registration_id`. Auto-overridden by `enable_entra_id_setup`. |
| `features.api_center_onboarding` | `false` | — | Registers each APIM API in API Center with version + definition + deployment records. |
| `features.unified_ai_api` | depends on tfvars | — | Wildcard unified AI API. |
| `features.azure_ai_search` | depends on tfvars | — | AI Search Index API + backends from `ai_search_instances`. |
| `features.document_intelligence` | depends on tfvars | — | Legacy `/formrecognizer` + current `/documentintelligence` APIs. |
| `features.ai_model_inference` | depends on tfvars | — | Model Inference API. |
| `features.openai_realtime` | depends on tfvars | — | WebSocket Realtime API. |
| `features.embeddings_backend` | `false` | — | Dedicated embeddings backend for semantic cache. |
| `features.pii_anonymization` | `true` | — | PII anonymization policy fragments (authenticates to the Language service with the APIM managed identity). |
| `features.api_center` | `true` | — | Provisions the API Center service (workspace, environments, metadata schemas). |
| `usage_pipeline.eventhub.disaster_recovery` | empty | — | Optional EH DR namespace pairing. |
| `configure_circuit_breaker` | `false` | — | Adds circuit-breaker rules to LLM backends. |
| `usage_pipeline.logic_app.code_deploy` | `false` (`true` in the example tfvars) | `--skip-logic-app-code` (sets `skip_logic_app_code_deploy = true` for that run) | Zips and publishes `logicapp-src/usage-ingestion-logicapp` to the Logic App Standard site after infra is ready (zip deploy, or run-from-package on ASE v3). See §7.8. |
| `deny_storage_shared_key` | `false` (`true` in prod.tfvars.example) | — | Assigns the built-in *Storage accounts should prevent shared key access* policy (Deny) on the RG. Requires `usage_pipeline.logic_app.hosting = "ase_v3"`; skip when the platform assigns ALZ `Deny-Storage-Shared-Key`. |

---

## 5. First deployment: step by step

### 5.1 Configure your environment

The `environments/*.tfvars` files are git-ignored — only the `.example`
templates are committed. Copy the template for your target environment and fill
in the values:

```bash
cp environments/dev.tfvars.example environments/dev.tfvars
# (prod) cp environments/prod.tfvars.example environments/prod.tfvars
```

Then edit `environments/dev.tfvars` (see
[environments/dev.tfvars.example](environments/dev.tfvars.example) for every
attribute):

```hcl
subscription_id        = "YOUR-SUBSCRIPTION-ID"   # auto-rewritten by deploy.sh
location               = "swedencentral"
environment_name       = "citadel-dev"
resource_group_name    = "rg-citadel-dev"

# Feature flags (start conservative, enable more over time)
features = {
  azure_ai_search       = false
  document_intelligence = false
  unified_ai_api        = true
  api_center            = true
  api_center_onboarding = false
}
enable_jwt_auth = false
```

### 5.2 Bootstrap (first time only)

```bash
# Verify Azure login
az account show

# Register required resource providers (deploy.sh does this too)
./scripts/bootstrap-state.sh     # (optional) set up remote state
```

### 5.3 Core-only deployment

```bash
./scripts/deploy.sh dev
```

This is equivalent to `main.bicep` with everything but APIC onboarding
disabled. Adds ~35 resources. Expect 25–35 minutes for the first run
(APIM + Redis dominate).

**APIM private access on v2 SKUs (`apim.public_network_access = false`).**
Azure rejects creating an API Management service with public network access
disabled (`ActivateServiceWithPrivateEndpointAccessNotAllowed`); it needs an
approved private endpoint first. The first apply therefore creates the service
**public** together with its private endpoint; the requested setting is applied
on the **next apply**, once the service and its private endpoint exist
(`modules/apim` probes for the existing service at plan time). Run the deploy
twice for a private gateway.
`public_network_access = false` requires `apim.private_endpoint = true`
(precondition); classic SKUs always keep public access.

### 5.4 Verify

```bash
./scripts/validate.sh dev
terraform output
```

### 5.5 LLM backend routing (auto-derived, single apply)

As of this revision, the §5.3 core apply produces a **fully-routed gateway
in one shot**. `llm_backend_config` is auto-derived in
[main.tf](main.tf) from `enable_ai_foundry` + `ai_foundry_instances` +
`ai_foundry_models`, with endpoints sourced from
`module.foundry.foundry_endpoints` (late-bound — known after apply, which
Terraform handles transparently because `for_each` keys are deterministic
`foundry-${location}-${index}` strings).

**What you get automatically:**

- One APIM backend (`azapi_resource.llm_backend`) per Foundry instance,
  priority `1` for index `0`, priority `2` for subsequent instances.
- Models grouped into pools by `ai_service_index` — every model you list
  under `ai_foundry_models` targeting instance `i` is attached to that
  instance's backend.
- The three dynamic policy fragments (`set-backend-pools`,
  `get-available-models`, `metadata-config`) are populated with real
  routing tables.
- Named values for the backend IDs / pool IDs are created automatically
  (they're gated on `length(llm_backend_config) > 0` internally — the
  auto-derived list lights them up).

**When to override (optional).** Populate either of these variables in your
tfvars:

- `llm_backend_config` — **full override.** Non-empty value replaces the
  auto-derived list entirely. Use when you need non-Foundry backends
  exclusively (external Azure OpenAI, third-party LLM gateway, on-prem
  model server).
- `extra_llm_backends` — **append.** Added on top of the auto-derived
  Foundry list. Use to mix Foundry (auto) with external backends in the
  same gateway. Same object shape as `llm_backend_config`.

```hcl
# Example: keep Foundry auto-derive + add an external Azure OpenAI backend
llm_backend_config = []  # or omit entirely — default is []
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

**Discover the auto-derived endpoints** (for verification / external
scripts):

```bash
terraform output -json ai_foundry_endpoints | jq -r '.[]'
```

**Rules to keep in mind (apply to both auto-derived and overridden
configs):**

- `backend_type` is one of `ai-foundry`, `azure-openai`, or `external`.
- `auth_scheme = "managedIdentity"` works out of the box for Foundry — the
  APIM UAMI already has `Cognitive Services OpenAI User` on every Foundry
  account deployed by the stack. Use `apiKey` for external backends.
- Multiple backends advertising the same `supported_models[*].name` at the
  same `priority` form a load-balanced pool with automatic failover. Use
  different `priority` values for active/standby routing.

---

## 6. Add-on deployments

### 6.1 Single-apply mode (Terraform-native)

Deploy everything in one pass (with `features.mcp_sample` and
`features.api_center_onboarding` set in the tfvars if you want them):

```bash
./scripts/deploy.sh dev --with-entra --with-foundry-conn
```

Or the shorthand:

```bash
./scripts/deploy.sh dev --all-addons
```

Terraform computes the full graph and creates dependencies correctly in one
`apply` — every resource name is known at plan time. This is the **recommended path** for most environments — it's
faster, atomic, and gives you a single state snapshot.

### 6.2 Phased mode (Bicep-style follow-ons)

When you want to deploy core first, validate, then layer add-ons on top:

```bash
./scripts/deploy.sh prod --all-addons --phased
```

The script performs:

| Phase | What runs | What's forced off |
|---|---|---|
| Phase 1 — `core` | networking, monitoring, data, APIM service + backends + fragments + APIs | `-var=rollout_phase=core` forces off Entra ID setup, JWT auth, the Foundry → APIM connections, `features.mcp_sample` and `features.api_center_onboarding` |
| Phase 2 — `add-ons` | Re-applies with `rollout_phase = "full"` (default) and the selected `--with-*` flags enabled; only the add-on resources change | nothing forced — uses your flag selection and tfvars |

This mirrors the Bicep "deploy + follow-on" workflow without splitting the
state. If you pass `--phased` without any `--with-*` flags (and with
`features.mcp_sample` / `features.api_center_onboarding` off), phase 2 is a
no-op (plan reports "no changes").

### 6.3 Single add-on later

After a successful core deployment, enable just one add-on:

```bash
./scripts/deploy.sh dev --with-entra
```

Terraform plan shows exactly the new resources (≈6 for Entra, ≈2–5 for
Foundry connection). You can keep re-running with
different flags without touching anything else.

---

## 7. Add-on reference

### 7.1 Entra ID (`--with-entra`)

**Bicep parity:** `entra-id-setup/setup.ps1` (uses MS Graph, runs outside
`main.bicep` in Bicep).

**What gets created** ([modules/entra-id/](modules/entra-id/)):

- `azuread_application` — display name `ai-citadel-gateway-<env>`, OAuth2
  `access_as_user` scope, 4 app roles (`Task.ReadWrite`, `Models.Read`,
  `MCP.Read`, `Agent.Read`) with the same canonical GUIDs as the PowerShell
  script (idempotent re-runs), + MS Graph `User.Read`.
- `azuread_application_identifier_uri` — `api://<client_id>` (split to avoid
  self-reference).
- `azuread_service_principal`.
- `azuread_application_password` — rotated every
  `entra_client_secret_rotation_days` (default 730 = 2 years).
- `azurerm_key_vault_secret` — writes the secret to KV as
  `ENTRA-APP-CLIENT-SECRET`.

**Side effect:** When enabled, `local.effective_{enable_jwt_auth,
jwt_tenant_id, jwt_app_registration_id}` override the bare `jwt_*` variables
on the APIM module, so the `JWT-TenantId` and `JWT-AppRegistrationId` named
values auto-populate from the live app registration + tenant.

**Variables:**

| Variable | Default |
|---|---|
| `enable_entra_id_setup` | `false` |
| `entra_app_display_name_prefix` | `"ai-citadel-gateway"` |
| `entra_client_secret_name` | `"ENTRA-APP-CLIENT-SECRET"` |
| `entra_client_secret_rotation_days` | `730` |

**Example:**

```bash
./scripts/deploy.sh dev --with-entra
```

### 7.2 Foundry → APIM connection (`--with-foundry-conn`)

**Bicep parity:** `foundry-integration/connection-apim.bicep`.

**What gets created:**

- [modules/apim/foundry-subscription.tf](modules/apim/foundry-subscription.tf) — dedicated APIM subscription that
  exposes a primary key as an output.
- `modules/foundry/connection-apim.tf` —
  `Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview`
  per (foundry project × selected API) with Custom Keys auth, plus metadata
  (`deploymentInPath`, `inferenceAPIVersion`, `deploymentAPIVersion`,
  `modelDiscovery`, `models`, `customHeaders`).

**Why it was a follow-on in Bicep:** Bicep couldn't wire the APIM subscription
key into the Foundry connection at plan time. Terraform uses the output of
the subscription resource directly.

**Example:**

```bash
./scripts/deploy.sh dev --with-foundry-conn
```

### 7.3 Access contracts (separate root module)

**Bicep parity:** `citadel-access-contracts/main.bicep` + its 3 sub-modules.

Access contracts are not part of the root deployment and have no deploy-script
flag: they are applied from [citadel-access-contracts/](citadel-access-contracts/README.md),
an independent root module with its own state, against an already-deployed hub.

**What gets created** — for the `use_case` in its tfvars, per entry in `services`:

- `azurerm_api_management_product` + display name, description, terms.
- `azurerm_api_management_product_api` (per allowed API).
- `azurerm_api_management_product_policy` — with allow-list of permitted
  deployments rendered from the contract's `models` list; can also enforce
  JWT.
- `azurerm_api_management_subscription`.
- (optional) `azurerm_key_vault_secret` for the primary key.
- (optional) Foundry project connection created against this product.

**Example:**

```bash
cd citadel-access-contracts
cp terraform.tfvars.example terraform.tfvars   # fill in apim, use_case, services
./scripts/deploy.sh
```

### 7.4 MCP samples (`features.mcp_sample`)

**Bicep parity:** `mcp-from-api.bicep` + `mcp-existing.bicep`.

Enables two APIM MCP resources:

- **Weather API + Weather MCP** — demo API converted into an MCP server.
- **MS Learn MCP** — external MCP endpoint registered via
  `azapi_resource.ms_learn_mcp_backend` + `azapi_resource.ms_learn_mcp`.

**Example:**

```hcl
# environments/dev.tfvars
features = {
  # …
  mcp_sample = true
}
```

```bash
./scripts/deploy.sh dev
```

### 7.5 API Center onboarding (`features.api_center_onboarding`)

**Bicep parity:** `apim/api-center-onboarding.bicep`.

Registers each enabled APIM API in API Center with:

- `Microsoft.ApiCenter/services/workspaces/apis@2024-03-01`
- `…/versions`
- `…/definitions` (with the OpenAPI spec or import link)
- `…/deployments` (pointing at the running APIM gateway URL +
  `api-dev` / `mcp-dev` / `api-prod` / `mcp-prod` environment)

The APIC service itself is created unconditionally when `features.api_center =
true` (default); this flag (`features.api_center_onboarding`, wired through
[api-center-registration.tf](api-center-registration.tf) →
[modules/api-center-registration](modules/api-center-registration/README.md))
only controls the per-API record creation.

**Example:**

```hcl
# environments/dev.tfvars
features = {
  # …
  api_center_onboarding = true
}
```

```bash
./scripts/deploy.sh dev
```

### 7.6 JWT auth without Entra (`--with-jwt`)

Use this when you already have an app registration and just want APIM to
enforce JWT against its tenant/app-reg IDs.

```bash
./scripts/deploy.sh dev \
  --with-jwt \
  -- -var=jwt_tenant_id=<tid> -var=jwt_app_registration_id=<aid>
```

(Or set them in `dev.tfvars`.)

> ⚠️ The `--` isn't parsed by the script; pass extra Terraform vars via
> `TF_VAR_*` environment variables or tfvars instead:
> ```bash
> export TF_VAR_jwt_tenant_id=<tid>
> export TF_VAR_jwt_app_registration_id=<aid>
> ./scripts/deploy.sh dev --with-jwt
> ```

### 7.7 Enabling `--with-entra` implies JWT

`enable_entra_id_setup = true` derives `effective_enable_jwt_auth = true`
automatically, populating all four JWT-* named values from the live app
registration. You don't need to pass `--with-jwt` alongside `--with-entra`.

### 7.8 Logic App workflow code (off by default)

**Bicep parity:** `azd deploy usageProcessingLogicApp` in the upstream
accelerator's `azure.yaml`.

**What gets created** ([modules/logic-app/code-deploy.tf](modules/logic-app/code-deploy.tf)):

- `data.archive_file.workflow_code` — zips the Logic App Standard project
  folder (`host.json`, `connections.json`, and the 4 `workflow.json` files
  under `ai-usage-ingestion/`, `ai-usage-streaming-ingestion/`,
  `llm-usage-ingestion/`, `pii-usage-ingestion/`). Excludes
  `workflow-designtime/`, `.funcignore`, and `local.settings.json`.
- Then one of two publish methods (`usage_pipeline.logic_app.deployment`;
  Workflow Standard always uses `zip_deploy`):

| Method | Used by | What runs | Network access needed by `apply` |
|---|---|---|---|
| `zip_deploy` | `workflow_standard`; `ase_v3` opt-in | `null_resource.publish_workflows` runs `az functionapp deployment source config-zip` (Logic App Standard is built on the Functions runtime; ships in core Azure CLI, no extension) | The site's SCM endpoint: `<sitename>.scm.azurewebsites.net`, or on an internal ASE `<sitename>.scm.<ase>.appserviceenvironment.net`, which only resolves and is only reachable inside the VNet |
| `run_from_package` | `ase_v3` default | `azurerm_storage_blob.package` uploads the zip as `usage-ingestion-<sha>.zip` to the keyless storage account's `deployments` container (the apply identity gets *Storage Blob Data Contributor* on that container); the site gets `WEBSITE_RUN_FROM_PACKAGE` = blob URL and `WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID` = usage UAMI; `azapi_resource_action` restarts the site and calls `syncfunctiontriggers` for each new package | The storage **blob private endpoint** (the account has no public endpoint). No SCM access, no `az` CLI |

> **To confirm:** that Logic Apps Standard loads its workflows from a package
> fetched with a managed identity still needs a live spike. If it doesn't, set
> `usage_pipeline.logic_app.deployment = "zip_deploy"` (and run `apply` from a
> runner inside the VNet).

**Runtime prerequisites:**

- `zip_deploy`: `az` CLI ≥ 2.57 (no extra extensions) and a signed-in principal
  with **Logic App Contributor** (or higher) on the RG — the same identity
  that runs `terraform apply`. Network reachability to `management.azure.com`
  and the SCM endpoint above. For public-network Workflow Standard sites
  (`apim.public_network_access = true`) SCM is reachable from anywhere;
  behind a private endpoint or an internal ASE the deployer must run from
  inside the VNet.
- `run_from_package`: the apply identity must be able to create role
  assignments (it grants itself the container-scoped blob role) and must
  reach the storage private endpoint — run `apply` from a VPN-connected
  machine or a private runner (see
  [docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md)),
  or skip the publish with `--skip-logic-app-code` / `-SkipLogicAppCode`.

**Trigger behaviour:**

| Change | Effect on next apply |
|---|---|
| Edit any file under `logicapp-src/usage-ingestion-logicapp/` | `zip_deploy`: `code_sha256` trigger changes → re-publish. `run_from_package`: new content hash → new blob and URL → app setting update, restart and trigger sync. |
| Logic App site is recreated | `zip_deploy`: `logic_app_id` trigger changes → re-publish. `run_from_package`: the new site gets the package URL in its app settings. |
| Infrastructure-only edits elsewhere | No re-publish. |

**Variables:**

| Variable | Default |
|---|---|
| `usage_pipeline.logic_app.code_deploy` | `false` (`true` in the example tfvars) |
| `usage_pipeline.logic_app.code_source_path` | `""` = the vendored `logicapp-src/usage-ingestion-logicapp` (the root falls back to it); set a path to publish another project tree |
| `usage_pipeline.logic_app.deployment` | `run_from_package` (ASE v3 only) |
| `skip_logic_app_code_deploy` | `false` (`--skip-logic-app-code` / `-SkipLogicAppCode` set it for one run) |

**Examples:**

```bash
# Default — publish as part of the normal apply
./scripts/deploy.sh dev

# Iterate on IaC without re-publishing the workflows
./scripts/deploy.sh dev --skip-logic-app-code

# Iterate on workflow JSON only (zip_deploy) — skips full plan/apply and retargets
# `module.logic_app.null_resource.publish_workflows[0]`
./scripts/deploy.sh dev --logic-app-code-only

# Point at a fork or a locally-modified project tree: set
# usage_pipeline.logic_app.code_source_path = "/path/to/my/workflows"
# in environments/dev.tfvars, then
./scripts/deploy.sh dev --logic-app-code-only

# run_from_package (ASE v3): publish with a normal apply from a runner that
# reaches the storage private endpoint
./scripts/deploy.sh prod
```

`--logic-app-code-only` / `-LogicAppCodeOnly` covers both methods: with
`zip_deploy` it re-runs the `az` push; with `run_from_package` it uploads the new
package blob, points the site at it and re-syncs the triggers (run it from a
machine that reaches the storage private endpoint).

**Rollback:** there is no native slot history on Logic App Standard. To roll
back, check out an earlier commit of `logicapp-src/usage-ingestion-logicapp/`
and re-publish (`./scripts/deploy.sh <env> --logic-app-code-only` for
`zip_deploy`, a normal apply for `run_from_package`).

---

## 8. Full rollout scenarios

### 8.1 Developer sandbox (one-shot, everything)

```bash
./scripts/deploy.sh dev --all-addons --auto-approve
```

Approx. 40 resources beyond core. Good for local demos.

### 8.2 Production (staged, reviewed)

```bash
# Phase 1: core only — validate gateway endpoints, logs, dashboards
./scripts/deploy.sh prod

# Smoke-test APIM gateway
./scripts/validate.sh prod

# Phase 2: identity
./scripts/deploy.sh prod --with-entra

# Verify Entra secret landed in KV, then set features.api_center_onboarding = true
# in environments/prod.tfvars
./scripts/deploy.sh prod --with-entra

# Phase 3: downstream consumers
./scripts/deploy.sh prod --with-entra --with-foundry-conn

# Per-use-case access contracts: citadel-access-contracts/ (separate state)
```

Each run is idempotent; re-running with the same flags is a no-op.

[prod.tfvars.example](environments/prod.tfvars.example) uses the keyless usage
pipeline (`usage_pipeline.logic_app.hosting = "ase_v3"`, run-from-package,
`deny_storage_shared_key = true`): the first apply creates an App Service
Environment v3 (roughly 1–4 hours), and the workflow package upload needs a
runner that reaches the storage private endpoint — see §7.8 and
[docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md).

### 8.3 Bicep-style single-command phased

```bash
./scripts/deploy.sh prod --all-addons --phased
```

The script executes:

1. `terraform plan -var=rollout_phase=core … -out=plan-core` → apply
2. `terraform plan -var=enable_entra_id_setup=true … -out=plan-addons` → apply

Same end state as `--all-addons` without `--phased`, but with an
intermediate checkpoint.

### 8.4 Disabling an add-on

Run without the flag. Terraform plans a destroy of just that module:

```bash
# Was: ./scripts/deploy.sh dev --with-foundry-conn
./scripts/deploy.sh dev            # plan shows destroy of the Foundry connections
```

Destroys are limited to the feature-flagged resources; core stays.

---

## 9. Interactions with existing tooling

### 9.1 LLM backend onboarding

The Bicep accelerator ships a separate `llm-backend-onboarding/` sub-deployment.
Terraform handles this inline — edit `llm_backend_config` in your tfvars and
re-run `./scripts/deploy.sh <env>`. Changes are diff'd; only the affected
backends + pools + the 3 dynamic policy fragments get re-applied.

### 9.2 APIM SKU upgrade

The Bicep `apim-gateway-upgrade/` sub-deployment isn't needed. Change
`apim.sku` + `apim.capacity` in your tfvars and re-run — Terraform
applies the SKU change in place on the existing APIM resource.

### 9.3 Validation notebooks (`validation/` + `shared/`)

The Jupyter test suite ported from the upstream accelerator lives in
[validation/](validation/) with its Python helpers in [shared/](shared/). The
suite is four notebooks that exercise a **live** deployment: LLM backend
onboarding, the Universal LLM API across every model, access contracts, and
model-alias routing.

Each notebook is configured **manually**: open the first (config) cell and
replace the `"REPLACE"` sentinel values — plus any inline config blocks such as
`llm_backends_config` / `model_aliases` — with values that match your
deployment, then run the cell. Any value left as `"REPLACE"` is flagged with a
warning so you can see what still needs filling in.

If you deployed with this repo's Terraform flow, pull the values you need
straight from state and paste them into the config cell:

```bash
terraform output -raw resource_group_name
terraform output -raw location
terraform output -json llm_backend_config
terraform output -raw key_vault_name
```

[shared/utils.py](shared/utils.py) also provides a Terraform-output bridge:
`azd_env_get()` resolves a requested key from `terraform output -json`, with an
internal alias map translating each azd-style variable name into the matching
Terraform output:

| Notebook variable / azd name | Terraform output |
|---|---|
| `AZURE_RESOURCE_GROUP`, `GOVERNANCE_HUB_RESOURCE_GROUP` | `resource_group_name` |
| `AZURE_LOCATION`, `LOCATION` | `location` |
| `AZURE_SUBSCRIPTION_ID` | `subscription_id` |
| `KEY_VAULT_NAME` | `key_vault_name` |
| `AI_FOUNDRY_SERVICES` | `ai_foundry_services` |
| `LLM_BACKEND_CONFIG`, `LLM_BACKENDS_CONFIG` | `llm_backend_config` |
| `APIM_NAME` | `apim_name` |
| `APIM_GATEWAY_URL` | `apim_gateway_url` |

The `location`, `subscription_id`, `key_vault_name`, `ai_foundry_services`, and
`llm_backend_config` outputs were added to [outputs.tf](outputs.tf) for this
purpose; they only appear in state after a `terraform apply`. The bridge
resolves the Terraform root as the parent of `shared/` (the repo root);
override with the `CITADEL_TF_DIR` environment variable to point at another
state directory (e.g. `llm-backend-onboarding/`). `apimtools.py` is
deployment-tool-agnostic — it uses `az` + the Azure SDK with the resource group
/ APIM name passed as parameters.

```bash
pip install -r shared/requirements.txt
# then open any notebook in validation/ and run the first (config) cell
```

See [validation/README.md](validation/README.md) for the full per-notebook
variable map.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform init` downloads `azuread` even with `enable_entra_id_setup = false` | Provider is declared globally | Expected; the provider is harmless until a resource is created. |
| `A resource with the ID "…applications/…" already exists` | Azure AD app with same display name exists from a prior run | Delete the leftover app registration (`az ad app delete --id <app-id>`) or change `entra_app_display_name_prefix`, then re-run. |
| `Unauthorized: The client does not have authorization to perform action 'Microsoft.KeyVault/vaults/secrets/write'` | Current user lacks KV Secrets Officer role | Use the printed `az role assignment create` command from the Key Vault module outputs. |
| APIM deployment stuck ~30 min | First-time APIM provisioning is slow | Normal; don't cancel. Use `az apim list -g <rg>` to check `provisioningState`. |
| `enable_jwt_auth=true` but JWT fails at runtime | `jwt_tenant_id`/`jwt_app_registration_id` placeholders | Enable Entra add-on (`--with-entra`) or set the variables explicitly. |
| Foundry connection fails with "missing subscription key" | APIM subscription hasn't finished provisioning | Re-run `./scripts/deploy.sh <env> --with-foundry-conn`. |
| `az: command not found` during `publish_workflows` | Deployer doesn't have Azure CLI installed | Install `az` CLI or run with `--skip-logic-app-code` and publish manually. |
| Workflow publish fails with `AuthorizationFailed` | Signed-in principal lacks **Website Contributor** / **Logic App Contributor** on the RG | Grant the role or run the zip-deploy as a different principal. |
| Workflow publish hangs / `403 Ip Forbidden` on SCM | Logic App is behind a private endpoint and the deployer isn't on the VNet | Run `--logic-app-code-only` from a jumpbox inside the VNet, or temporarily flip `apim.public_network_access = true`. |
| Logic App runs trigger but workflows are empty | Code-publish skipped or first apply crashed before the publish | Run `./scripts/deploy.sh <env> --logic-app-code-only` (for `run_from_package`, from a runner that reaches the storage private endpoint); if the package is in place but the workflows still don't load, switch to `usage_pipeline.logic_app.deployment = "zip_deploy"`. |
| `run_from_package`: `azurerm_storage_blob.package` fails with `403 AuthorizationFailure` / a timeout | The keyless storage account has no public endpoint and the machine running `apply` can't reach its blob private endpoint (or the new blob role assignment hasn't propagated yet) | Run `apply` from a VPN-connected machine or a private runner, or once with `--skip-logic-app-code`; re-run after a few minutes if the role was just granted. |
| `RequestDisallowedByPolicy` on the Logic App storage account | A platform policy such as ALZ `Deny-Storage-Shared-Key` blocks the shared-key storage that Workflow Standard needs | Use `usage_pipeline.logic_app.hosting = "ase_v3"`, or get a time-boxed exemption for dev (decision D3). |
| `deny_storage_shared_key needs usage_pipeline.logic_app.hosting = "ase_v3"` | Precondition in [policy.tf](policy.tf) | Set `hosting = "ase_v3"` or `deny_storage_shared_key = false`. |
| Apply sits on the App Service Environment for hours | First-time ASE v3 creation takes roughly 1–4 hours | Normal; don't cancel. |

---

## 11. Tearing down

```bash
./scripts/destroy.sh dev
```

This performs `terraform destroy` with the dev tfvars. Some resources may
linger in Azure for purge-protection reasons:

- **Key Vault** — soft-deleted; purged on destroy when
  `purge_soft_delete_on_destroy = true` (see [providers.tf](providers.tf)).
- **APIM** — soft-deleted; same purge behaviour.
- **Cognitive Services** — soft-deleted; same purge behaviour.

For a hard reset set the var to `true` in your tfvars and re-run destroy.

---

## 12. Reference: command cheatsheet

```bash
# Help
./scripts/deploy.sh --help

# Core only
./scripts/deploy.sh dev
./scripts/deploy.sh prod --auto-approve

# Individual add-ons
./scripts/deploy.sh dev --with-entra
./scripts/deploy.sh dev --with-foundry-conn
./scripts/deploy.sh dev --with-jwt
# (MCP samples / API Center onboarding: features.mcp_sample /
#  features.api_center_onboarding in the tfvars)

# Combinations
./scripts/deploy.sh dev --with-entra --with-foundry-conn
./scripts/deploy.sh prod --all-addons

# Phased rollout
./scripts/deploy.sh prod --phased
./scripts/deploy.sh prod --all-addons --phased
./scripts/deploy.sh prod --with-entra --with-foundry-conn --phased

# Logic App workflow code
./scripts/deploy.sh dev --skip-logic-app-code     # infra only
./scripts/deploy.sh dev --logic-app-code-only     # republish workflows only

# Validation + teardown
./scripts/validate.sh dev
./scripts/destroy.sh dev

# Notebook test suite (against a live deployment)
pip install -r shared/requirements.txt   # then run validation/*.ipynb
```

### PowerShell equivalents

Every command above has a PowerShell twin (see §2.1 for the full flag map):

```powershell
# Help
./scripts/deploy.ps1 -Help

# Core only
./scripts/deploy.ps1 dev
./scripts/deploy.ps1 prod -AutoApprove

# Individual add-ons
./scripts/deploy.ps1 dev -WithEntra
./scripts/deploy.ps1 dev -WithFoundryConn
./scripts/deploy.ps1 dev -WithJwt

# Combinations
./scripts/deploy.ps1 dev -WithEntra -WithFoundryConn
./scripts/deploy.ps1 prod -AllAddons

# Phased rollout
./scripts/deploy.ps1 prod -Phased
./scripts/deploy.ps1 prod -AllAddons -Phased
./scripts/deploy.ps1 prod -WithEntra -WithFoundryConn -Phased

# Logic App workflow code
./scripts/deploy.ps1 dev -SkipLogicAppCode     # infra only
./scripts/deploy.ps1 dev -LogicAppCodeOnly     # republish workflows only

# Validation + teardown
./scripts/validate.ps1 dev
./scripts/destroy.ps1 dev
```

---

## 13. See also

- [README.md](README.md) — project overview.
- [VARIABLES.md](VARIABLES.md) — detailed reference for every variable, including the feature flags.
- [validation/README.md](validation/README.md) — notebook test suite + per-notebook variable map.
- [full-deployment-guide.md (upstream Bicep)](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/full-deployment-guide.md)
  — the original Bicep deployment guide, for comparison.
