# Citadel Governance Hub - Testing & Validation Guide

## Executive Summary

This testing suite provides a comprehensive, end-to-end validation framework for the Citadel Governance Hub — an enterprise-grade AI gateway built on Azure API Management (APIM). The notebooks in this directory enable platform teams to onboard LLM backends, validate the full model surface area through the Universal LLM API, provision access contracts for different business units, and validate model-alias routing — all through guided, reproducible Jupyter workflows.

The recommended execution order is:

> **Strongly recommended baseline (steps 1–3):** these three notebooks together exercise the core gateway plumbing — backend onboarding, full model surface area, and access-contract provisioning. Run them in order on every new Governance Hub deployment before moving on to the optional model-aliases notebook.

1. **Backend Contracts (LLM Onboarding)** — Register AI backends and deploy routing logic into APIM ⭐ *strongly recommended*
2. **Universal LLM API — All-Models Tests** — Validate every gateway-configured model (chat / embeddings / Responses API) through `/models` ⭐ *strongly recommended*
3. **Access Contracts** — Create per-team access contracts with Key Vault and Foundry integrations ⭐ *strongly recommended*
4. **Model Aliases** — Validate the shared `resolve-model-alias` policy fragment across the LLM APIs (priority + weighted strategies, RBAC, discovery)

Each notebook is self-contained with initialization, deployment, testing, visualization, and cleanup stages, enabling both interactive exploration and repeatable CI/CD validation.

---

## Prerequisites

Before running any notebook, ensure the following are in place:

- **Citadel Governance Hub** deployed (see the [repository README](../README.md#-quick-start) — `task bootstrap ENV=dev` then `task up ENV=dev`), so `environments/<env>/common.tfvars` and `environments/<env>/backend.hcl` exist
- **Terraform** installed; [Task](https://taskfile.dev) is used by the notebooks when it is on `PATH` (otherwise they run `terraform -chdir=stacks/<stack>` directly)
- **Azure CLI** installed and authenticated (`az login`)
- **Python 3.10+** with a virtual environment activated
- **Dependencies** installed:
  ```bash
  pip install -r requirements.txt
  ```
  (or the equivalent comprehensive list in [`../shared/requirements.txt`](../shared/requirements.txt))
- **VS Code** with the Jupyter extension (recommended for running notebooks)

### Optional (per notebook)

| Capability | Required By | Details |
|---|---|---|
| Universal LLM API (`models`) imported in APIM | Universal LLM All-Models Tests, Model Aliases | Required for `/models` discovery and per-model operation tests |
| Azure Key Vault | Access Contracts | A Key Vault with secrets for LLM endpoint and API key |
| Azure AI Foundry | Access Contracts | A Foundry account and project for connection integration |
| `resolve-model-alias` policy fragment + alias-aware backend onboarding | Model Aliases | Re-deployed by the notebook itself via the `stacks/llm-backend-onboarding` stack with `model_aliases` populated |
| Unified AI API (`unified-ai`) imported in APIM | Model Aliases (full cross-API coverage) | Required for the wildcard `/unified-ai/**` routing patterns |

---

## Configuring Notebook Variables

Open the init cell, set `env` (default `"dev"`, the folder under
`environments/`) and `repo_root` (default: the repository root), replace any
`"REPLACE"` sentinel values (and inline config blocks such as
`llm_backends_config` / `model_aliases`) with values that match your deployment,
then run the cell.

### How It Works

Each notebook's init cell follows the same pattern:

```python
env       = "dev"                     # environments/<env>
repo_root = os.path.abspath("..")     # repository root (Taskfile.yml, stacks/, environments/)
# Fill these in to match your Citadel Governance Hub deployment ("REPLACE"/"" = read from the stacks).
governance_hub_resource_group = "REPLACE"   # e.g. "rg-citadel-dev"
location                      = "REPLACE"   # e.g. "eastus", "swedencentral"
# ... other notebook-specific values (backends, aliases, Key Vault, Foundry) ...
```

`governance_hub_resource_group` and `location` left as `"REPLACE"` (or empty)
are read from the `platform` stack outputs and `environments/<env>/common.tfvars`.

Notebooks that deploy (backend onboarding, access contracts, model aliases,
all-models) write their variable files into the environment folder and deploy
them with `utils.run_stack(...)` from [`../shared/utils.py`](../shared/utils.py):

| Stack | Generated file | Equivalent command |
|---|---|---|
| `stacks/llm-backend-onboarding` | `environments/<env>/llm-backend-onboarding.tfvars` (or the name in `llm_backend_tfvars_name`; an existing hand-written file is backed up to `.bak` first) | `task apply STACK=llm-backend-onboarding ENV=<env> [VAR_FILE=...]` |
| `stacks/access-contracts` | `environments/<env>/access-contracts/<use-case>.tfvars` (state key `<use-case>.tfstate`) | `task contract ENV=<env> USE_CASE=<use-case>` |

Without Task the helper runs `terraform -chdir=stacks/<stack> init -reconfigure
-backend-config=environments/<env>/backend.hcl [-backend-config=key=<use-case>.tfstate]`,
then `plan -out=tfplan -var-file=environments/<env>/common.tfvars -var-file=<file>`
and `apply tfplan`. Results are read back with `terraform -chdir=stacks/<stack>
output -json` (`utils.stack_outputs(...)`). Subscription keys are never in state
or outputs: they are read from the contract's Key Vault secret (`az keyvault
secret show`) when `key_vault` is enabled, otherwise with `az rest --method post
--url "https://management.azure.com<subscription id>/listSecrets?api-version=2024-05-01"`.

> **Tip:** `task output STACK=platform ENV=dev` prints the platform outputs
> (`resource_group_name`, `apim_name`, `apim_gateway_url`, `key_vault_name`, ...);
> `task output STACK=llm-backend-onboarding ENV=dev` prints the onboarded
> `models`, `backend_ids` and `universal_llm_api_url`.

### Per-Notebook Variable Map

The table below summarizes the variables you set in each notebook's init cell.
Variables in *italics* are optional / only used when the notebook actually
exercises the corresponding integration.

| Notebook | Variables to set manually |
|---|---|
| `llm-backend-onboarding-runner` | `env`<br>`backend_mode` (`foundry` \| `extra` \| `override`)<br>`llm_backends_config` (inline JSON, for `extra` / `override`)<br>*`model_aliases`*<br>*`inference_api_type` / `features`*<br>*`aws_*` Key Vault secret URIs + region*<br>*`llm_backend_tfvars_name`* |
| `citadel-universal-llm-api-all-models-tests` | `env` |
| `citadel-access-contracts-tests` | `env`<br>*`keyvault_id`* (`""` = platform Key Vault)<br>*`foundry_account_name` / `foundry_project_name` / `foundry_project_id`* (`""` = platform defaults)<br>*`foundry_auth_type`* (`ProjectManagedIdentity` default \| `ApiKey`)<br>*`foundry_managed_identity_audience`* (default `https://cognitiveservices.azure.com`) |
| `citadel-model-aliases-tests` | `env`<br>`backend_mode`<br>`llm_backends_config` (inline JSON)<br>`model_aliases`<br>`direct_test_model` |

All notebooks also accept `governance_hub_resource_group` / `location` overrides.

> **Multi-environment teams:** To point a notebook at a different deployment,
> change `env` (and any environment-specific values) in the init cell before
> running it.

---

## Notebooks

### 1. LLM Backend Onboarding Runner

| | |
|---|---|
| **Notebook** | [`llm-backend-onboarding-runner.ipynb`](llm-backend-onboarding-runner.ipynb) |
| **Purpose** | Onboard AI backends into the Citadel Governance Hub and deploy routing logic |
| **Run this** | First — before any other notebook |

#### What It Does

This notebook automates the full lifecycle of registering LLM backends with your APIM gateway. It extracts the current backend configuration, generates `environments/<env>/llm-backend-onboarding.tfvars` with per-model metadata (SKU, capacity, model format, version), deploys the backends and policy fragments, and verifies the deployment through multiple API formats.

#### Steps

| Step | Description |
|---|---|
| 0 | **Initialize variables** — Configure resource group, location, and backend endpoints |
| 1 | **Verify Azure CLI** — Confirm authentication and subscription context |
| 2 | **Initialize APIM Client** — Connect to the existing Governance Hub deployment |
| 3 | **Extract current backends** — Retrieve existing backend pools and routing configuration |
| 4 | **Discover managed identity** — Display the APIM user-assigned managed identity (informational; the stack finds it by name) |
| 5 | **Generate variables file** — Write `environments/<env>/llm-backend-onboarding.tfvars` (`foundry_backends` / `llm_backend_config` / `extra_llm_backends`, `model_aliases`, `features`, `aws`) |
| 6 | **Deploy** — Apply `stacks/llm-backend-onboarding` (`task apply STACK=llm-backend-onboarding ENV=<env>`) to create backends, pools, and policy fragments |
| 7 | **Verify deployment** — Confirm backends and policy fragments were created |
| 8 | **Verify GET /deployments** — Test the `get-available-models` policy fragment for Foundry integration |
| Test | **Test models** — Validate via Universal LLM API, Azure OpenAI API, Python SDK, and streaming |

#### Key Configuration

```python
env = "dev"                                # environments/<env>
llm_backend_tfvars_name = "llm-backend-onboarding.tfvars"

# "foundry" = derive backends from the platform Foundry accounts,
# "extra" = Foundry-derived + llm_backends_config, "override" = llm_backends_config only
backend_mode = "override"

llm_backends_config = [
    {
        "backendId": "aif-citadel-primary",
        "backendType": "ai-foundry",           # 'ai-foundry' | 'azure-openai' | 'external'
        "endpoint": "https://...",
        "authScheme": "managedIdentity",        # 'managedIdentity' | 'apiKey' | 'token'
        "supportedModels": [
            { "name": "gpt-4o", "sku": "GlobalStandard", "capacity": 100, "modelFormat": "OpenAI", "modelVersion": "2024-11-20" }
        ],
        "priority": 1,
        "weight": 100
    }
]
```

#### Output

- Deployed APIM backends with circuit breaker support
- Backend pools with priority/weight-based load balancing
- `set-backend-pools` and `get-available-models` policy fragments
- Verified model routing through both API formats

---

### 2. Universal LLM API — All-Models Tests

| | |
|---|---|
| **Notebook** | [`citadel-universal-llm-api-all-models-tests.ipynb`](citadel-universal-llm-api-all-models-tests.ipynb) |
| **Purpose** | Validate the Universal LLM API (`/models`) against every model exposed by the gateway |
| **Run this** | Immediately after backend onboarding to confirm the full model catalogue is reachable |

#### What It Does

This notebook provisions a single access contract with **`allowedModels = ""`** (no model restriction), then dynamically discovers the live model catalogue via `GET /models/models` and exercises the appropriate OpenAI v1 operation for each model. It is the fastest way to confirm that every onboarded backend pool is end-to-end reachable through the Universal LLM API surface.

#### Operations Exercised Per Model

| Model name pattern | Operations exercised |
|---|---|
| Contains `embedding` | `POST /models/embeddings` |
| Contains `gpt`       | `POST /models/chat/completions` **and** the full Responses API trio: `POST /models/responses`, `GET /models/responses/{response_id}`, `GET /models/responses/{response_id}/input_items?limit=20` |
| Anything else        | `POST /models/chat/completions` |

#### Steps

| Step | Description |
|---|---|
| 0 | **Initialize variables** — Configure resource group, location, API versions, and optional model cap |
| 1 | **Verify Azure CLI** — Confirm authentication and subscription context |
| 2 | **Initialize APIM Client** — Discover the Universal LLM API and supported models |
| 3 | **Provision access contract** — Write `environments/<env>/access-contracts/testing-universalllmallmodels-dev.tfvars` and apply it (`task contract`) — an APIM product + subscription with `allowedModels = ""` and a generous capacity allocation |
| 4 | **Retrieve API key** — Get the subscription key via APIM `listSecrets` on the subscription ID output |
| 5 | **Discover models** — Call `GET /models/models` to enumerate the live model catalogue |
| 6 | **Per-model operation loop** — Auto-classify each model and run chat / embeddings / Responses API operations |
| 7 | **Summary table** — Aggregate per-model pass/fail across all exercised operations |
| Cleanup | **Delete test products** — Optionally remove the unrestricted access contract |

#### Key Configuration

```python
env = "dev"                                    # environments/<env>

targetInferenceApi    = "models"               # Universal LLM API
inference_api_version = "2024-05-01-preview"
openai_api_version    = "2024-12-01-preview"

# 0 = test every discovered model; set a positive int to cap for quick smoke tests
max_models_to_test = 0

# Delay between POST /responses and the subsequent GET /responses/{id} calls
responses_get_delay_seconds = 0
```

#### Output

- One APIM product + subscription with no model RBAC restriction
- Live discovery of every gateway-configured model via `GET /models/models`
- Per-model results for chat, embeddings, and (where applicable) Responses API operations
- Summary table highlighting any model that failed an expected operation

---

### 3. Citadel Access Contracts Tests

| | |
|---|---|
| **Notebook** | [`citadel-access-contracts-tests.ipynb`](citadel-access-contracts-tests.ipynb) |
| **Purpose** | Create, deploy, and load-test multiple access contracts with different integration patterns |
| **Run this** | After backend onboarding and the Universal LLM all-models smoke test |

#### What It Does

This notebook provisions three distinct access contracts, each representing a different integration pattern. It generates one `environments/<env>/access-contracts/<use-case>.tfvars` per contract, deploys the contracts (one state each) as APIM products with subscriptions, performs load testing, and visualizes throttling behavior and token bucket dynamics across all contracts.

#### Access Contracts Created

| Contract | Business Unit | Integration | Description |
|---|---|---|---|
| **Sales-Assistant** | Sales | Key Vault only | Secrets (endpoint + API key) resolved from Azure Key Vault |
| **HR-ChatAgent** | HR | Key Vault + Foundry | Optionally creates a Foundry project connection for agent integration (`ProjectManagedIdentity` by default: project-MI JWT + `api-key` header, with a matching JWT validation policy) |
| **Support-Bot** | Support | Direct output | No external integrations — uses direct APIM subscription output |

#### Steps

| Step | Description |
|---|---|
| 0 | **Initialize variables** — Configure resource group, Key Vault, and Foundry settings |
| 1 | **Verify Azure CLI** — Confirm authentication and subscription context |
| 2 | **Initialize APIM Client** — Discover APIs and supported models |
| 3 | **Define contracts** — Configure three access contracts with varying integration patterns |
| 4 | **Create variables files** — Write `environments/<env>/access-contracts/<use-case>.tfvars` (with policy XML) for each contract |
| 5 | **Deploy contracts** — Apply `stacks/access-contracts` once per use case (state `<use-case>.tfstate`) |
| 6 | **Retrieve API keys** — Read each key from Key Vault (Key Vault contracts) or APIM `listSecrets` |
| 7 | **Load test** — Send concurrent API requests to each contract and record metrics |
| 8 | **Visualize results** — Compare success/throttled/error rates across contracts |
| 9 | **Token bucket analysis** — Simulate and visualize token bucket refill behavior |
| Cleanup | **Destroy test contracts** — Optionally destroy each contract's state and remove its variables file |

#### Key Configuration

```python
env = "dev"

# Optional integrations (contract inputs key_vault / foundry)
use_keyvault_integration = True
keyvault_id = ""              # "" = platform Key Vault, or a team-owned vault resource ID

use_foundry_integration = True
foundry_account_name = ""     # "" = platform primary Foundry account
foundry_project_name = ""     # "" = its default project
foundry_project_id   = ""     # full project resource ID (overrides both names)

# Foundry connection auth -> foundry_config.auth_type / managed_identity_audience in the tfvars
foundry_auth_type = "ProjectManagedIdentity"                       # or "ApiKey" (subscription key only)
foundry_managed_identity_audience = "https://cognitiveservices.azure.com"
```

#### Foundry Connection Auth (`ProjectManagedIdentity`)

By default, Foundry-targeted contracts (`use_foundry = True`) create the connection with `auth_type = "ProjectManagedIdentity"`:
the Foundry **project's** managed identity presents an Entra ID JWT for `foundry_managed_identity_audience` and the APIM
subscription key is sent as the `api-key` custom header (no credential is stored in the connection). The notebook therefore:

- **Generates the product policy with JWT validation** — after `<base />` it sets `jwtRequired = "true"`, `jwtAudience` (the audience),
  `jwtIssuer = https://sts.windows.net/<tenant>/` and `jwtOpenIdConfigUrl = https://login.microsoftonline.com/<tenant>/v2.0/.well-known/openid-configuration`,
  consumed by the gateway's `security-handler` fragment. The tenant ID is baked in as a literal (from `az account show`) because the
  `{{JWT-TenantId}}` named value is `not-configured` unless Entra auth is enabled in `gateway-config`. Model RBAC and capacity policy content is unchanged.
- **Sends both credentials in the direct tests** — for these contracts the HTTP tests send the subscription key as `api-key` plus
  `Authorization: Bearer <token>` where the token comes from `az account get-access-token --resource <audience>`. A negative check confirms
  the key alone (no token) is rejected with `401`.
- Contracts that are not Foundry-targeted, or `foundry_auth_type = "ApiKey"`, behave exactly as before (api-key only, no JWT policy).

> **Caveat:** when the product policy requires JWT, any app that uses the contract's subscription key directly (for example the key
> read from Key Vault) must **also** present an Entra ID token for the same audience, otherwise the gateway returns `401`.
> The Foundry project must have a managed identity enabled (Project → Identity).

#### Output

- Three deployed APIM products with subscription keys
- Key Vault secrets populated (if enabled)
- Foundry connection created (if enabled), with `ProjectManagedIdentity` JWT validation in the product policy
- Performance charts comparing all contracts
- Token bucket behavior visualization

---

### 4. Citadel Model Aliases Tests

| | |
|---|---|
| **Notebook** | [`citadel-model-aliases-tests.ipynb`](citadel-model-aliases-tests.ipynb) |
| **Purpose** | Validate the shared `resolve-model-alias` policy fragment across the LLM API surfaces (Universal LLM, Azure OpenAI, and — when imported — Unified AI) |
| **Run this** | After backend onboarding (notebook 1). Can be run independently of notebook 3. |

#### What It Does

This notebook re-applies the `stacks/llm-backend-onboarding` stack with `model_aliases` populated, which (re)deploys the shared `resolve-model-alias` policy fragment with the configured aliases inlined. It then provisions an access contract scoped to **alias names only** (least-privilege RBAC) and exercises the same aliases through the available LLM API surfaces, inspecting the `UAIG-*` debug response headers to verify the gateway's routing decisions end-to-end.

Two alias strategies are validated:

| Alias | Strategy | Behavior |
|---|---|---|
| `adv-gpt` | `priority` | First underlying model wins; remaining models act as cross-model fallback (deterministic per-call) |
| `gpt-blend` | `weighted` | Random-weighted picking across underlying models — useful for A/B model swaps |

#### Steps

| Step | Description |
|---|---|
| 0 | **Initialize variables** — Set `env`, paste `llm_backends_config` (or use `backend_mode = "foundry"`), and define the two aliases and a direct-test model |
| 1 | **Verify Azure CLI & APIM Client** — Confirm subscription context and discover the APIM resource |
| 2 | **Generate variables file** — Write `environments/<env>/llm-backend-onboarding.tfvars` with the backends + the two aliases |
| 3 | **Deploy onboarding** — Re-apply `stacks/llm-backend-onboarding` so the `resolve-model-alias` fragment is regenerated with the aliases inlined |
| 4 | **Create access contract** — Write `environments/<env>/access-contracts/validation-aliastests-dev.tfvars` and apply it: an APIM product whose `allowedModels` lists ONLY the alias names + `direct_test_model`, with `enableResponseHeaders=true` for `UAIG-*` debug headers |
| 5 | **Resolve API key** — Read the contract subscription's key via APIM `listSecrets` |
| 6 | **Discover endpoints** — Universal LLM (`/models`), Azure OpenAI (`/openai`), Unified AI (`/unified-ai`, when imported) |
| Discovery | **`GET /deployments` honors `allowedModels`** — Aliases appear as `type: "alias"` entries with descriptions; underlying real models that aren't in `allowedModels` are filtered out |
| 7 | **Direct model control test** — Call `direct_test_model` on the available APIs; resolver should be a no-op (no `UAIG-Alias` header) |
| 8 | **Priority alias test** — Call `adv-gpt`; resolves deterministically to the first underlying model |
| 9 | **Weighted alias single call** — Call `gpt-blend` once on each API |
| 10 | **Weighted distribution test** — Send N=30 requests through `gpt-blend` and tally `UAIG-Resolved-Model` against configured weights |
| 11 | **Negative RBAC test** — Send a model NOT in `allowedModels`; expect HTTP 403 `unauthorized_model_access` |
| Summary | **Results overview** — Cross-API consistency check + alias resolution observations |
| Cleanup | **Destroy access contract** — `do_cleanup` flag (default `False`) destroys the contract state and removes its variables file; LLM backends and the `resolve-model-alias` fragment are intentionally preserved |

#### `UAIG-*` Response Headers Inspected

| Header | Meaning |
|---|---|
| `UAIG-Model-Id` | Model that was actually routed to (post alias resolution) |
| `UAIG-Alias` | Original alias name the client sent (only present when alias was used) |
| `UAIG-Resolved-Model` | Real model the alias resolved to |
| `UAIG-Backend` | Backend pool / backend that served the request |
| `UAIG-API-Type` | Detected API type (Unified AI only) |
| `UAIG-Final-Path` | Reconstructed backend path (Unified AI only) |
| `UAIG-Auth-Type` | Auth method enforced by `security-handler` (Unified AI only) |
| `UAIG-Cache-Operation` | `cache-hit` / `cache-miss` for `metadata-config` |
| `UAIG-Request-Id` | APIM request id for log correlation |

#### Key Configuration

```python
env                           = "dev"
backend_mode                  = "override"  # or "foundry" / "extra"
llm_backends_config           = []          # paste your backend config inline (see notebook 1)

model_aliases = [
    { "name": "adv-gpt",   "models": ["gpt-5.2", "gpt-5.4-mini", "gpt-4.1"], "strategy": "priority" },
    { "name": "gpt-blend", "models": ["gpt-5.4-mini", "gpt-4.1"],            "strategy": "weighted", "weights": [70, 30] },
]

direct_test_model     = "gpt-4.1"            # control test (must exist in llm_backends_config)
inference_api_version = "2024-05-01-preview"
```

#### Output

- Re-deployed `resolve-model-alias` policy fragment with the two aliases inlined as a static `JObject`
- Access contract scoped to alias names (proves alias-name RBAC works without exposing underlying real models)
- Per-API report of `UAIG-*` headers showing alias → real-model resolution
- Distribution table for the weighted alias compared against the configured weights
- Filtered `GET /deployments` response showing aliases as first-class entries with `properties.capabilities.description`
- 403 negative-test confirmation that unauthorized models are blocked at the gateway

---

## Recommended Execution Order

> **Strongly recommended baseline:** run notebooks **1 → 3** in order on every new Citadel Governance Hub deployment. Step **4** is an optional, scenario-specific validation that can be run independently afterwards.

```
┌──────────────────────────────────────────────┐
│  1. llm-backend-onboarding-runner            │  ⭐ Onboard LLM backends & routing
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│  2. citadel-universal-llm-api-all-models-    │  ⭐ Smoke-test EVERY onboarded model
│     tests                                    │     (chat / embeddings / Responses API)
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│  3. citadel-access-contracts-tests           │  ⭐ Create access contracts & load test
└──────────────┬───────────────────────────────┘
               │   ── End of strongly recommended baseline ──
               ▼
┌──────────────────────────────────────────────┐
│  4. citadel-model-aliases-tests              │  Optional: alias routing
│                                              │     (priority + weighted strategies)
└──────────────────────────────────────────────┘
```

> **Note:** Notebook 4 creates its own access contract and can be run independently after backend onboarding. It re-applies the LLM backend onboarding stack with `model_aliases` populated (the `resolve-model-alias` fragment is regenerated); full cross-API coverage additionally requires the Unified AI API (`unified-ai`) to be imported into APIM.

## Shared Utilities

All notebooks import shared helper modules from the [`../shared/`](../shared/) directory:

| Module | Description |
|---|---|
| `utils.py` | CLI command runner, stack helpers (`env_dir`, `write_tfvars`, `run_stack`, `stack_outputs`, `terraform_output_get`, `get_contract_subscription_key`), formatted output helpers (`print_ok`, `print_error`, `print_info`) |
| `apimtools.py` | `APIMClientTool` class for APIM discovery, API key retrieval, policy fragment parsing, and backend management |

## Cleanup

Each notebook that creates access contracts includes an optional cleanup cell at the end that destroys them (`task destroy STACK=access-contracts ENV=<env> STATE_KEY=<use-case>.tfstate`) — including the Key Vault secrets and Foundry connections they created — and deletes their `environments/<env>/access-contracts/<use-case>.tfvars` files so `task up` does not recreate them. Cleanup is controlled by a per-notebook flag (e.g. `cleanup_enabled` / `do_cleanup`).

> **Important:** Cleanup does not remove the LLM backend configuration (`stacks/llm-backend-onboarding`); restore or edit `environments/<env>/llm-backend-onboarding.tfvars` (a `.bak` copy is kept of a hand-written file the notebooks replaced) and re-apply the stack to change it.

## Troubleshooting

| Issue | Resolution |
|---|---|
| `az account show` fails | Run `az login` and set the correct subscription with `az account set --subscription <id>` |
| APIM Client Tool initialization fails | Verify `env` / `governance_hub_resource_group` are correct (`task output STACK=platform ENV=<env>`) and your identity has Reader access |
| `Missing environments/<env>/common.tfvars` / `backend.hcl` | Create the environment folder from `examples/quickstart` and run `task bootstrap ENV=<env>` |
| Model not found in backend pool | Run the backend onboarding notebook to register the model |
| Key Vault access denied | Ensure your identity has `Key Vault Secrets User` role on the Key Vault |
| Foundry connection fails | Verify the Foundry account, project, and connection names are correct |
| Alias not resolving / no `UAIG-Alias` header | Re-run the model-aliases notebook so the `resolve-model-alias` fragment is redeployed with `modelAliases` populated |
| 429 Throttled responses | Expected during load testing — the token bucket policy is working correctly |
