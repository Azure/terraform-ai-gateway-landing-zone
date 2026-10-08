# 🏰 AI Gateway Landing Zone — Terraform

Complete Terraform implementation of the [AI Gateway Landing Zone - Bicep](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1) solution accelerator. Mirrors the Bicep reference architecture using Terraform + AzureRM + AzAPI providers.

---

## 📐 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Resource Group                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │            Virtual Network (hub or spoke)            │   │
│  │  ┌───────────────┐ ┌──────────────┐ ┌────────────┐   │   │
│  │  │  APIM Subnet  │ │   PE Subnet  │ │  LA Subnet │   │   │
│  │  └──────┬────────┘ └──────┬───────┘ └─────┬──────┘   │   │
│  └─────────┼────────────────┼───────────────┼───────────┘   │
│            │                │               │               │
│   ┌────────▼──────┐  Private Endpoints:     │               │
│   │  API Mgmt     │  • Key Vault            │               │
│   │  (Citadel     │  • Cosmos DB     ┌──────▼───────┐       │
│   │   Gateway)    │  • Event Hub     │  Logic App   │       │
│   └──────┬────────┘  • AI Services   │  (Usage      │       │
│          │           • Storage       │   Ingestion) │       │
│          │                           └──────┬───────┘       │
│   Named Values:                             │               │
│   • uami-client-id   ┌──────────────────────▼─────────┐     │
│   • piiServiceUrl    │         Cosmos DB              │     │
│   • entra-auth       │  usage-db / model-pricing      │     │
│                      └────────────────────────────────┘     │
│                                                             │
│  Supporting:  Key Vault · Log Analytics · App Insights      │
│               Event Hub · AI Foundry · Language Service     │
│               Content Safety · API Center                   │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start

> **In a hurry?** See [QUICK_START.md](QUICK_START.md) for a concise, copy-paste
> deployment walkthrough (dev & prod, add-ons, and common operations).

### Prerequisites

| Tool | Min Version | Install |
|------|-------------|---------|
| Terraform | ≥ 1.11 | [Install](https://developer.hashicorp.com/terraform/install) |
| Azure CLI | ≥ 2.50 | [Install](https://aka.ms/installazurecli) |
| Git | Any | [Install](https://git-scm.com) |
| Bash shell (`scripts/*.sh`) | Any | macOS/Linux: built-in. Windows: use [Git Bash](https://git-scm.com) or [WSL](https://learn.microsoft.com/windows/wsl/install). |
| PowerShell (`scripts/*.ps1`) | 7+ | Cross-platform on macOS/Linux/Windows — [Install pwsh](https://learn.microsoft.com/powershell/scripting/install/installing-powershell). |

### 1 — Clone and configure

```bash
git clone https://github.com/Azure/terraform-ai-gateway-landing-zone.git
cd citadel-terraform

```

### 2 — (Optional) Set up remote state backend

```bash
# Bash (Linux/macOS):
# -------------------
./scripts/bootstrap-state.sh eastus
# Then uncomment the backend block in terraform.tf and re-run terraform init
```

```powershell
# PowerShell (cross-platform pwsh):
# --------------------------------
./scripts/bootstrap-state.ps1 eastus
```

### 3 — Deploy

```bash
# Copy the environment template and fill in your values
cp environments/dev.tfvars.example environments/dev.tfvars
# Edit environments/dev.tfvars — set subscription_id and other required values
# (for production: cp environments/prod.tfvars.example environments/prod.tfvars)

# Bash (Linux/macOS):
# -------------------
# Development environment (30-45 min for APIM)
./scripts/deploy.sh dev

# Production environment
./scripts/deploy.sh prod

# Skip confirmation prompt
./scripts/deploy.sh dev --auto-approve
```

```powershell
# PowerShell (cross-platform pwsh):
# ---------------------------------
./scripts/deploy.ps1 dev
./scripts/deploy.ps1 prod

# Skip confirmation prompt
./scripts/deploy.ps1 dev -AutoApprove
```

### 4 — Validate

```bash
# Bash
./scripts/validate.sh dev
```

```powershell
# PowerShell
./scripts/validate.ps1 dev
```

### 5 — Tear down

```bash
# Bash
./scripts/destroy.sh dev
```

```powershell
# PowerShell
./scripts/destroy.ps1 dev
```

---

## 🔧 Configuration

All configuration is done through `.tfvars` files in `environments/`. Key settings:

### T-Shirt Sizing

| Size | APIM SKU | Cosmos RU/s | Event Hub Units | Use Case |
|------|----------|-------------|-----------------|----------|
| Small (dev) | `Developer` | 400 | 1 | Dev/test, no SLA |
| Medium | `StandardV2` | 400 | 1 | Non-prod with SLA |
| Large | `PremiumV2` | 1000 | 2 | Multi-zone production |

### Network Approach

**Greenfield (new VNet):**
```hcl
network = {
  mode          = "greenfield"
  address_space = "10.170.0.0/24"
}
apim = {
  sku       = "Developer"
  vnet_mode = "external"   # or "internal" for fully private (Developer/Premium); v2 SKUs use "integration"
}
```

**Brownfield (existing enterprise VNet):**
```hcl
network = {
  mode                = "byo"
  resource_group_name = "rg-network-hub"
  vnet_name           = "vnet-hub-prod-eastus"
  subnets = {
    apim = { name = "snet-citadel-apim" }
  }
  private_dns = {
    resource_group_name = "rg-network-dns"
    # Zones in another subscription: pass their full resource IDs instead
    # zone_ids = { key_vault = "/subscriptions/<sub>/resourceGroups/rg-network-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net", ... }
  }
}
```

**Azure Landing Zone spoke (platform-vended VNet):**
```hcl
network = {
  mode                = "alz_spoke"
  resource_group_name = "rg-spoke-network"     # the vended spoke VNet
  vnet_name           = "vnet-spoke-citadel"
  hub_firewall_ip     = "10.0.0.4"             # UDR next hop for 0.0.0.0/0
  # No private DNS zones are created. Supply private_dns.zone_ids, or leave the
  # PE DNS zone groups to the platform's Deploy-Private-DNS-Zones policy.
}
```
This deployment creates the subnets inside the spoke VNet, each with an NSG and a route table sending `0.0.0.0/0` to the hub firewall; default outbound access is off. See [docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md) for what to request from the platform team.

### Entra ID Authentication

```hcl
entra_auth_enabled = true
entra_tenant_id    = "your-tenant-id"
entra_client_id    = "your-client-id"
entra_audience     = "api://ai-citadel-prod"
```

### AI Foundry Multi-Region

```hcl
ai_foundry_instances = [
  { location = "eastus",  default_project_name = "citadel-prod" },
  { location = "eastus2", default_project_name = "citadel-prod-secondary" }
]
ai_foundry_models = [
  { name = "gpt-4o", version = "2024-11-20", capacity = 100, ai_service_index = 0 },
  { name = "gpt-4o", version = "2024-11-20", capacity = 100, ai_service_index = 1 }
]
```

### Usage pipeline: keyless Logic App on ASE v3

The usage-ingestion Logic App has two hosting models (`usage_pipeline.logic_app.hosting`):

- `workflow_standard` (default, used by [dev.tfvars.example](environments/dev.tfvars.example)) — WS plan with a key-based Azure Files content share; a documented exception to the ALZ `Deny-Storage-Shared-Key` policy.
- `ase_v3` (used by [prod.tfvars.example](environments/prod.tfvars.example)) — keyless: an Isolated v2 plan (CPU autoscale) in a dedicated, internal App Service Environment v3 ([modules/app-hosting](modules/app-hosting/README.md)) or a shared / BYO one, runtime storage with shared keys and public access disabled, and the workflows run from a package read with the usage managed identity.

```hcl
usage_pipeline = {
  logic_app = {
    hosting          = "ase_v3"
    sku              = "I1v2"
    worker_count     = 2                    # autoscale minimum
    max_worker_count = 4                    # autoscale maximum
    deployment       = "run_from_package"   # or "zip_deploy"
    code_deploy      = true
  }
  ase = {
    zone_redundant = true
    # app_service_environment_id = "<shared ASE resource ID>"   # BYO: no ASE / ASE subnet created here
  }
}
deny_storage_shared_key = true   # Deny policy on the RG; skip if ALZ Deny-Storage-Shared-Key is assigned
```

Creating an ASE takes roughly 1–4 hours. The package upload uses the storage data plane, which has no public endpoint, so run `apply` from a machine or runner that reaches the storage private endpoint (or pass `--skip-logic-app-code` / `-SkipLogicAppCode`). Details: [VARIABLES.md — Logic App hosting on ASE v3](VARIABLES.md#logic-app-hosting-on-ase-v3); platform prerequisites: [docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md).

---

## 🌐 API Endpoints (post-deploy)

| API | URL Pattern | Use Case |
|-----|-------------|---------|
| Universal LLM | `{gateway_url}/models/chat/completions` | Recommended — all models |
| Azure OpenAI Compat | `{gateway_url}/openai/deployments/{model}/chat/completions` | SDK compatibility |
| List Models | `GET {gateway_url}/models/` | Discover available models |

### Test the gateway

```bash
# Get subscription key from APIM portal → Subscriptions
APIM_URL=$(terraform output -raw universal_llm_api_url)
SUB_KEY="your-apim-subscription-key"

curl -X POST "$APIM_URL" \
  -H "Content-Type: application/json" \
  -H "api-key: $SUB_KEY" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello from Citadel!"}]}'
```

---

## 🧪 Validation Notebooks

The [validation/](validation/) folder contains the Jupyter test notebooks ported
from the upstream accelerator, plus their Python helpers in [shared/](shared/).
They exercise a **live** deployment, and the recommended baseline order is steps
1–4 (run them on every new Governance Hub deployment before the scenario-specific
ones):

| # | Notebook | Purpose |
|---|----------|---------|
| 1 | [llm-backend-onboarding-runner.ipynb](validation/llm-backend-onboarding-runner.ipynb) ⭐ | Register AI backends and deploy routing logic into APIM (run first). Drives the [`llm-backend-onboarding/`](llm-backend-onboarding/) module. |
| 2 | [citadel-universal-llm-api-all-models-tests.ipynb](validation/citadel-universal-llm-api-all-models-tests.ipynb) ⭐ | Validate every gateway-configured model (chat / embeddings / Responses API) through `/models`. |
| 3 | [citadel-access-contracts-tests.ipynb](validation/citadel-access-contracts-tests.ipynb) ⭐ | Provision per-team access contracts with Key Vault + Foundry integration. Drives the [`citadel-access-contracts/`](citadel-access-contracts/) module. |
| 4 | [citadel-model-aliases-tests.ipynb](validation/citadel-model-aliases-tests.ipynb) | Validate the shared `resolve-model-alias` policy fragment (priority + weighted strategies, RBAC, discovery). |

See [validation/README.md](validation/README.md) for the full per-notebook
variable map, prerequisites, and execution guide.

### Terraform autoload (no azd required)

The notebooks were written for an `azd`-deployed environment and bootstrap their
config with `init_from_azd = True`. This repo deploys with **Terraform, not azd**,
so [shared/utils.py](shared/utils.py) adds a transparent bridge:
`azd_env_get()` tries `azd` first, then falls back to `terraform output -json`.
An internal alias map translates each azd-style variable the notebooks request
into the matching Terraform output, so the existing `init_from_azd = True` /
`utils.load_azd_env(...)` cells work **unchanged**:

| azd env var | Terraform output |
|---|---|
| `AZURE_RESOURCE_GROUP`, `GOVERNANCE_HUB_RESOURCE_GROUP` | `resource_group_name` |
| `AZURE_LOCATION`, `LOCATION` | `location` |
| `AZURE_SUBSCRIPTION_ID` | `subscription_id` |
| `KEY_VAULT_NAME` | `key_vault_name` |
| `AI_FOUNDRY_SERVICES` | `ai_foundry_services` |
| `LLM_BACKEND_CONFIG`, `LLM_BACKENDS_CONFIG` | `llm_backend_config` |
| `APIM_NAME` | `apim_name` |
| `APIM_GATEWAY_URL` | `apim_gateway_url` |

The bridge resolves the Terraform root as the parent of `shared/` (the repo
root). Override with the `CITADEL_TF_DIR` environment variable to point the
notebooks at a different state directory (e.g. `llm-backend-onboarding/`).
Outputs only appear after a `terraform apply`. See
[validation/README.md](validation/README.md) for the full per-notebook variable
map.

### Run

```bash
pip install -r shared/requirements.txt
# then open any notebook in validation/ and run the first (config) cell
```

`apimtools.py` is deployment-tool-agnostic — it uses `az` + the Azure SDK with
the resource group / APIM name passed as parameters, so no azd/Terraform coupling
there.

---

## 🏗️ Modules Reference

| Module | Resources Created |
|--------|-------------------|
| `naming` | No resources — generates every resource name (honours `name_overrides`) |
| `networking` | Greenfield VNet, or subnets in the ALZ spoke VNet (`alz_spoke`); an NSG per subnet, route tables (skipped when `network.mode = "byo"`). AVM: `avm-res-network-virtualnetwork` 0.22.2, `avm-res-network-networksecuritygroup` 0.6.0 |
| `private-dns` | Private DNS zones + VNet links (created, or the zone IDs you supply; none in `alz_spoke`). AVM: `avm-res-network-privatednszone` 0.5.0 |
| `monitoring` | Log Analytics workspace, 2× Application Insights, dashboard. AVM: `avm-res-operationalinsights-workspace` 0.5.1, `avm-res-insights-component` 0.4.0 |
| `security` | Key Vault, RBAC assignments, PE. AVM: `avm-res-keyvault-vault` 0.11.0 |
| `cosmosdb` | Cosmos DB account, `usage-db` database, `usage` + `model-pricing` containers. AVM: `avm-res-documentdb-databaseaccount` 0.11.0 (account, database, containers, PE) |
| `eventhub` | Event Hub namespace, `apim-usage` + `pii-usage` hubs, auth rules, consumer groups. AVM: `avm-res-eventhub-namespace` 0.1.1 (namespace, hubs, RBAC, PE) |
| `foundry` | AI Foundry accounts (n instances), projects, model deployments, APIM connection. AVM: `avm-res-cognitiveservices-account` 0.11.1 (accounts and model deployments, created one at a time; projects stay azapi) |
| `apic` | API Center service, workspace, environments |
| `api-center-registration` | API Center registration of the enabled gateway APIs (`features.api_center_onboarding`) |
| `apim` | APIM instance, private endpoint, named values, non-LLM backends, default product, Foundry subscription, Redis external cache. AVM: `avm-res-apimanagement-service` 0.9.0 (service + PE) |
| `apim-telemetry` | APIM loggers (App Insights, Azure Monitor, Event Hub) + global diagnostics |
| `apim-policy-fragments` | Reusable policy fragments from the [policy-fragments.tf](policy-fragments.tf) catalogue |
| `llm-routing` | LLM backends, backend pools, generated routing fragments |
| `gateway-api` | One APIM API (http / websocket / mcp) + policies, diagnostics, optional product — one instance per entry in [apis.tf](apis.tf) |
| `redis` | Azure Managed Redis (semantic cache, `features.semantic_cache`). Stays on azapi: the AVM Redis Enterprise module (0.2.0) can't set `accessKeysAuthentication`, which the APIM external cache needs |
| `entra-id` | Entra app registration + rotating client secret in Key Vault |
| `app-hosting` | Dedicated, internal App Service Environment v3 + `<ase>.appserviceenvironment.net` private DNS zone for the keyless usage pipeline (`usage_pipeline.logic_app.hosting = "ase_v3"` without a shared / BYO ASE). AVM: `avm-res-web-hostingenvironment` 2.0.1, `avm-res-network-privatednszone` 0.5.0 |
| `logic-app` | Logic App Standard, App Service Plan, Storage Account (runtime). `workflow_standard`: WS plan + shared-key content share. `ase_v3`: Isolated v2 plan with CPU autoscale in the ASE, keyless storage, azapi site, run-from-package (or zip) deploy. AVM: `avm-res-storage-storageaccount` 0.10.0, `avm-res-web-serverfarm` 2.0.8 |

The two user-assigned managed identities (`apim`, `usage`) are created by the root `module "identity"` in [main.tf](main.tf) on AVM `avm-res-managedidentity-userassignedidentity` 0.5.3. AVM usage telemetry is on by default; set `enable_telemetry = false` to turn it off ([aka.ms/avm/telemetryinfo](https://aka.ms/avm/telemetryinfo)).

Each module has a generated `README.md` (terraform-docs) with its full inputs and outputs, e.g. [modules/gateway-api/README.md](modules/gateway-api/README.md).

---

## 🔌 Standalone Onboarding Modules

Beyond the root deployment, the repo ships two **independently-applyable** Terraform
root modules that target an **already-deployed** Governance Hub APIM. They are the
Terraform ports of the upstream [`bicep/infra/llm-backend-onboarding`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1/bicep/infra/llm-backend-onboarding) and
[`bicep/infra/citadel-access-contracts`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1/bicep/infra/citadel-access-contracts) modules, and each has its own state,
`terraform.tfvars`, and `scripts/` (`deploy.sh` / `destroy.sh` / `test.sh`).

### LLM Backend Onboarding — [`llm-backend-onboarding/`](llm-backend-onboarding/)

Registers LLM backends and routing logic into an existing APIM gateway. Use it to
add or update model backends without touching the core infrastructure.

| Resource | Description |
|----------|-------------|
| **APIM Backends** | One backend per LLM endpoint (native managed-identity creds for Azure OpenAI / AI Foundry) |
| **Backend Pools** | Load-balanced pools for models served by multiple backends (priority + weight) |
| **Policy Fragments** | Dynamic model-based routing, model aliases, Responses API isolation |
| **Named Values** | AWS Bedrock credentials + per-backend API-key values (Key Vault ref or explicit) |

```bash
cd llm-backend-onboarding
cp terraform.tfvars.example terraform.tfvars   # set apim + llm_backend_config
./scripts/deploy.sh
./scripts/test.sh --api-key "<apim-subscription-key>"
```

Supports **model aliases** (`model_aliases`) that expose a single client-facing
name routing to one or more real models (`priority` or `weighted` strategy),
honored by `/deployments` discovery and `validate-model-access` RBAC. See
[llm-backend-onboarding/README.md](llm-backend-onboarding/README.md) for the full
backend / model schema.

### Access Contracts — [`citadel-access-contracts/`](citadel-access-contracts/)

Onboards a **use-case** (business unit) to the gateway by provisioning per-service
APIM products, subscriptions, and inbound policies — optionally writing keys to Key
Vault and creating Azure AI Foundry connections.

| Resource | Description |
|----------|-------------|
| **APIM Product** | `<code>-<businessUnit>-<useCase>-<env>` (e.g. `LLM-Finance-CustomerSupport-DEV`) |
| **Product → API links** | Attaches published APIs from `api_name_mapping[code]` to the product |
| **Product Policy** | Per-service inbound XML or the bundled `default-ai-product-policy.xml` |
| **Subscription** | `<product>-SUB-01` with primary/secondary keys |
| **Key Vault Secrets** *(optional)* | Endpoint URL + subscription key per service (`use_target_key_vault = true`) |
| **Foundry Connection** *(optional)* | One connection per service pointing at the gateway (`use_target_foundry = true`) |

```bash
cd citadel-access-contracts
cp terraform.tfvars.example terraform.tfvars   # set apim + use_case + services
./scripts/deploy.sh
./scripts/test.sh                              # or --api-key "<key>" when keys are in Key Vault
```

Naming follows `<code>-<business_unit>-<use_case_name>-<environment>`. See
[citadel-access-contracts/README.md](citadel-access-contracts/README.md) for the
service object and Foundry connection options.

---

## 📋 Post-Deployment Checklist

- [ ] Run `./scripts/validate.sh <env>` (or `./scripts/validate.ps1 <env>`) — all checks pass
- [ ] Retrieve APIM subscription key from Azure Portal → APIM → Subscriptions
- [ ] Test `POST /models/chat/completions` with a sample request
- [ ] Load `model-pricing.json` into Cosmos DB `model-pricing` container
- [ ] Connect Power BI desktop to Cosmos DB endpoint
- [ ] For production: disable Event Hub public access post-deploy
- [ ] For production: configure APIM custom domains + TLS certificates
- [ ] Configure CI/CD pipeline to call `./scripts/deploy.sh prod --auto-approve` (or `./scripts/deploy.ps1 prod -AutoApprove`)

---

## 🔑 Sensitive Values

Never commit real secrets to source control. Use one of:

1. **Environment variables before deploy:**
   ```bash
   export TF_VAR_entra_tenant_id="your-tenant-id"
   export TF_VAR_entra_client_id="your-client-id"
   ```

2. **Azure Key Vault references in tfvars** (requires azurerm data source)

3. **CI/CD pipeline secret variables** (Azure DevOps / GitHub Actions secrets)

---


## 📁 Project Structure

```
citadel-terraform/
├── terraform.tf             # Provider + Terraform version constraints
├── .terraform.lock.hcl      # Provider lock file (committed; CI runs init -lockfile=readonly)
├── providers.tf             # AzureRM, AzAPI, Random provider config
├── main.tf                  # Root module — naming, resource group, identities (AVM), BYO Log Analytics lookup, module calls
├── interfaces.tf            # Typed inputs (apim, network, features, usage_pipeline, monitoring) + effective config
├── network.tf               # Networking (greenfield / alz_spoke module or BYO lookups) + private DNS
├── apis.tf                  # API catalogue → modules/gateway-api
├── policy-fragments.tf      # Policy-fragment catalogue → modules/apim-policy-fragments
├── policy.tf                # Workload policy: optional Deny storage shared-key assignment (deny_storage_shared_key)
├── api-center-registration.tf # API Center registration → modules/api-center-registration
├── variables.tf             # All other input variables (the typed objects live in interfaces.tf)
├── outputs.tf               # Key deployment outputs
├── tests/unit/              # Mocked unit tests — terraform test -test-directory=tests/unit
├── .github/workflows/ci.yml # CI: fmt, tflint, validate, tests, terraform-docs, checkov, gitleaks
├── .tflint.hcl  .terraform-docs.yml  .checkov.yaml  .checkov.baseline  .gitleaks.toml
├── .pre-commit-config.yaml  .terraform-version  CONTRIBUTING.md
├── .gitignore
│
├── modules/
│   ├── naming/              # Resource names
│   ├── networking/          # Greenfield VNet / ALZ spoke subnets, NSGs, route tables
│   ├── private-dns/         # Private DNS zones + VNet links
│   ├── monitoring/          # Log Analytics, Application Insights, dashboards
│   ├── security/            # Key Vault, RBAC assignments, private endpoints
│   ├── cosmosdb/            # Cosmos DB account, databases, containers
│   ├── eventhub/            # Event Hub namespace, hubs, auth rules
│   ├── foundry/             # AI Foundry accounts, projects, model deployments
│   ├── apic/                # API Center
│   ├── api-center-registration/ # API registration in API Center
│   ├── apim/                # API Management service, named values, non-LLM backends, default product
│   ├── apim-telemetry/      # APIM loggers + diagnostics
│   ├── apim-policy-fragments/ # Deploys a map of policy fragments
│   ├── llm-routing/         # LLM backends, pools, generated routing fragments
│   │   └── templates/       # Templates for the generated fragments
│   ├── gateway-api/         # Generic API module (http / websocket / mcp)
│   ├── redis/               # Azure Managed Redis (semantic cache)
│   ├── entra-id/            # Entra app registration
│   ├── app-hosting/         # App Service Environment v3 + its private DNS zone (ase_v3)
│   └── logic-app/           # Logic App Standard for usage ingestion
│
├── apis/                    # Per-API OpenAPI specs + policy XML (universal-llm-api/, azure-openai-api/,
│   │                        #   unified-ai-api/, weather-api/, ...)
│   └── shared/              # Operation / MCP policies shared by several APIs
├── policies/
│   └── fragments/           # frag-*.xml policy fragments (single copy; also read by llm-backend-onboarding)
│
├── llm-backend-onboarding/  # Standalone module — onboard LLM backends to an existing APIM
│   ├── main.tf              # Backends, backend pools, policy fragments, named values
│   ├── imports.tf           # Conditional import {} blocks — takes over the backends, fragments and named values the main deployment creates
│   ├── terraform.tfvars.example
│   ├── tests/unit/          # Mocked unit tests
│   └── scripts/             # deploy.sh / destroy.sh / test.sh
│
├── citadel-access-contracts/ # Standalone module — onboard a use-case to an existing APIM
│   ├── main.tf              # APIM products, subscriptions, policies, KV secrets, Foundry conns
│   ├── terraform.tfvars.example
│   ├── contracts/           # Per-use-case contract definitions
│   ├── policies/            # Inbound product policy XML (incl. default-ai-product-policy.xml)
│   ├── tests/unit/          # Mocked unit tests
│   └── scripts/             # deploy.sh / destroy.sh / test.sh
│
├── environments/
│   ├── dev.tfvars.example   # Development template (typed inputs; Workflow Standard Logic App) — copy to dev.tfvars and fill in
│   ├── prod.tfvars.example  # Production template (typed inputs; keyless Logic App on ASE v3) — copy to prod.tfvars and fill in
│   └── asetest.tfvars.example # Test template: Workflow Standard (phase A), then keyless ASE v3 run-from-package (phase B)
│
├── docs/operations/         # Runbooks — platform-team-requests.md (ALZ prerequisites), apim-network-modes.md
│
├── scripts/                # Bash (*.sh) + PowerShell (*.ps1) equivalents
│   ├── ci/                     # CI helpers: tf-dirs.sh, check-policy-assets.sh
│   ├── deploy.sh / .ps1        # Full deploy script (init + plan + apply)
│   ├── destroy.sh / .ps1       # Teardown script
│   ├── validate.sh / .ps1      # Post-deployment smoke tests
│   └── bootstrap-state.sh / .ps1  # One-time remote state backend setup
│
├── shared/                  # Python helpers for the validation notebooks
│   ├── utils.py             # Config bootstrap (+ Terraform-output bridge), APIM helpers
│   ├── apimtools.py         # APIMClientTool — backend/policy/trace discovery (az + SDK)
│   ├── requirements.txt     # Python deps for the notebooks
│   └── snippets/            # Standalone az/REST example scripts
│
└── validation/              # Jupyter test notebooks (run against a live deployment)
    ├── llm-backend-onboarding-runner.ipynb              # 1 — onboard LLM backends ⭐
    ├── citadel-universal-llm-api-all-models-tests.ipynb # 2 — validate all models ⭐
    ├── citadel-access-contracts-tests.ipynb            # 3 — provision access contracts ⭐
    ├── citadel-model-aliases-tests.ipynb              # 4 — model alias routing
    ├── README.md            # Variable map + Terraform autoload instructions
    └── requirements.txt
```

---

## 📚 Related Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — local quality checks (fmt, tflint, tests, checkov, gitleaks) and the rules CI enforces
- [docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md) — what to request from the Azure Landing Zone platform team
- [docs/operations/apim-network-modes.md](docs/operations/apim-network-modes.md) — APIM network modes (none / external / internal / integration / injection) and how to change them

- [AI Citadel Governance Hub README](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1)
- [Full Deployment Guide](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/full-deployment-guide.md)
- [LLM Routing Architecture](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/llm-routing-architecture.md)
- [Network Approach Guide](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/network-approach.md)

---

## 📄 License

MIT — see [LICENSE](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/LICENSE)
