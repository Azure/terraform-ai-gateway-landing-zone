# Access Contracts Guide

An **access contract** onboards one use case (a team's application) to the AI gateway. It decides
which gateway APIs the use case may call, with which models, how much, how callers authenticate,
and where the use case finds its endpoint and key. This guide covers everything a contract can do
and every setting it has.

- Stack: [stacks/access-contracts](../stacks/access-contracts/) (one Terraform state per use case)
- Module: [modules/access-contract](../modules/access-contract/) (products, policies, subscriptions,
  secrets, Foundry connections)
- Upstream equivalent: `citadel-access-contracts` in the
  [AI Citadel accelerator](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator)

Contents:
1. [Concepts](#1-concepts)
2. [What a contract creates](#2-what-a-contract-creates)
3. [Lifecycle and commands](#3-lifecycle-and-commands)
4. [Configuration reference](#4-configuration-reference)
5. [Features](#5-features)
6. [The generated product policy](#6-the-generated-product-policy)
7. [Custom product policy (`policy_xml`)](#7-custom-product-policy-policy_xml)
8. [Using a contract (client side)](#8-using-a-contract-client-side)
9. [Examples](#9-examples)
10. [Testing a contract](#10-testing-a-contract)
11. [Troubleshooting](#11-troubleshooting)
12. [Limits and design notes](#12-limits-and-design-notes)

---

## 1. Concepts

```
environments/<env>/access-contracts/team-a-chatbot.tfvars          (one file = one use case = one state)
  │
  ├─ service LLM ──► APIM product  LLM-TeamA-Chatbot-DEV ── policy (generated from properties)
  │                    ├─ APIs: universal-llm-api, azure-openai-api   (api_name_mapping.LLM)
  │                    ├─ subscription LLM-TeamA-Chatbot-DEV-SUB-01 ── key ──► Key Vault secret teama-llm-key
  │                    │                                                       (+ endpoint secret teama-llm-endpoint)
  │                    └─ Foundry connection Hub-TeamA-Chatbot-DEV-LLM (optional)
  │
  └─ service SRCH ─► APIM product  SRCH-TeamA-Chatbot-DEV ── ...
```

| Term | Meaning |
|---|---|
| **Use case** | `business_unit` + `use_case_name` + `environment`, e.g. `TeamA / Chatbot / DEV`. Every name derives from it. |
| **Service** | One entry of `services`, identified by a **code** (`LLM`, `SRCH`, `DOC`, `TOOL`, `MULTI`, any string). Each service becomes one APIM **product** with its own policy, subscription and key. |
| **API mapping** | `api_name_mapping[code]`: the published gateway APIs the service's product grants. |
| **Product policy** | The rules of the service (models, limits, JWT, cache, events). Generated from the service's properties; `policy_xml` replaces it. |
| **Subscription key** | What callers send (`api-key` header for the LLM APIs). It identifies the contract: limits, model access and usage are per subscription. |

The gateway APIs themselves (Universal LLM API, Azure OpenAI API, AI Search, …) belong to other
stacks. A contract only **grants** them. A request runs the API's policy, and at the API's
`<base />` the product policy of the caller's contract (section 6).

---

## 2. What a contract creates

Per service (`code`), with `postfix = <business_unit>-<use_case_name>-<environment>`:

| Resource | Name | Notes |
|---|---|---|
| APIM product | ID `<code>-<postfix>`, display name `<code> <bu> <use case> <env>` | subscription required, no approval, published, up to 100 subscriptions, terms = `product_terms` |
| Product ↔ API links | one per API in `api_name_mapping[code]` | the APIs must already exist (section 3.1) |
| Product policy | — | generated (section 6) or `policy_xml` |
| Subscription | `<code>-<postfix>-SUB-01`, scope = the product | azapi resource: its keys are never read into state |
| Key Vault secret: endpoint | `lower(endpoint_secret_name)`, `_` → `-` | `https://<apim>.azure-api.net/<path of the first mapped API>`, content type `url` |
| Key Vault secret: key | `lower(api_key_secret_name)`, `_` → `-` | the subscription's primary key, write-only (never in state), content type `apim-subscription-key` |
| Foundry connection | `<connection_name_prefix or Hub-<postfix>>-<code>` | optional, on a Foundry project (section 5.10) |

Per contract: a `time_rotating` clock (`secret_rotation_days`) that rewrites the key secrets and
moves their expiry.

**Keys never reach Terraform state.** The key is read with an ephemeral `listSecrets` action and
written only to write-only arguments (the secret's `value_wo`, the Foundry connection's
`sensitive_body`). Outputs never contain keys.

---

## 3. Lifecycle and commands

### 3.1 Prerequisites

Apply these stacks first; the contract finds everything by name:

| Stack | Provides |
|---|---|
| platform | APIM, the platform Key Vault, the Foundry project |
| gateway-config | service APIs (AI Search, Document Intelligence, MCP samples) and shared fragments the policy includes (`set-asset-kind`, `usage-event`, `semantic-cache-*`, `security-handler`, `pii-*`) |
| llm-backend-onboarding | the LLM APIs and the LLM fragments (`set-llm-requested-model`, `validate-model-access`) |

The identity that applies a contract needs:
- APIM: create products, policies and subscriptions, and `listSecrets` on them (*API Management
  Service Contributor*);
- Key Vault (when `key_vault.enabled`): *Key Vault Secrets Officer* on the vault (the platform vault
  or a team vault in `key_vault.id`);
- Foundry (when `foundry.enabled`): write connections on the project.

### 3.2 Files and state

```
environments/<env>/
├── common.tfvars                      # workload, environment, location, subscription, naming
├── backend.hcl
└── access-contracts/
    ├── team-a-chatbot.tfvars          # one use case
    └── retail-assistant.tfvars
```

Each file has its own state: container `access-contracts`, key `<file name>.tfstate`, in the
environment's state account. A broken or destroyed contract never affects another one.

### 3.3 Commands

```bash
task contract  ENV=dev USE_CASE=team-a-chatbot     # plan + apply one contract
task contracts ENV=dev                             # every file in environments/dev/access-contracts/
task up        ENV=dev                             # every stack, then every contract
task plan-all  ENV=dev                             # read-only plan of every stack and contract

# plan only
task plan STACK=access-contracts ENV=dev STATE_KEY=team-a-chatbot.tfstate \
  VAR_FILE=$PWD/environments/dev/access-contracts/team-a-chatbot.tfvars

# remove one contract (its products, subscriptions, secrets and connections)
task destroy STACK=access-contracts ENV=dev STATE_KEY=team-a-chatbot.tfstate \
  VAR_FILE=$PWD/environments/dev/access-contracts/team-a-chatbot.tfvars
```

After a destroy, delete the file (otherwise `task contracts` recreates it) and, optionally, the
empty state blob `<use case>.tfstate`. `task down` destroys every contract before the stacks.

Without Task:

```bash
E=environments/dev
terraform -chdir=stacks/access-contracts init -reconfigure \
  -backend-config=../../$E/backend.hcl -backend-config=key=team-a-chatbot.tfstate
terraform -chdir=stacks/access-contracts apply \
  -var-file=../../$E/common.tfvars -var-file=../../$E/access-contracts/team-a-chatbot.tfvars
```

### 3.4 What a change does

| Change | Effect |
|---|---|
| a policy property (`allowed_models`, `token_limit`, `jwt_required`, …) or `policy_xml` | the product policy is updated in place; the key stays |
| an API added to / removed from `api_name_mapping[code]` | the product gains / loses the API; the key stays. Changing the **first** API changes the endpoint secret. |
| a service added / removed | a product, subscription, key and secrets are created / destroyed |
| `use_case` or a service `code` | **new names**: the old product and subscription are destroyed and new ones created, so **the key changes** |
| `endpoint_secret_name` / `api_key_secret_name` | the secret is recreated under the new name |
| `secret_rotation_days` elapsed | the next apply rewrites the key secrets (same key) with a new expiry |

---

## 4. Configuration reference

A complete file, with every option (defaults shown where an option is optional):

```hcl
use_case = {
  business_unit = "TeamA"
  use_case_name = "Chatbot"
  environment   = "DEV"
}

api_name_mapping = {
  LLM = ["universal-llm-api", "azure-openai-api"]   # the first API is the endpoint
}

services = [
  {
    code                 = "LLM"
    endpoint_secret_name = "TEAMA-LLM-ENDPOINT"
    api_key_secret_name  = "TEAMA-LLM-KEY"

    # Generated product policy
    allowed_models          = []        # [] = every model
    token_limit             = null      # { tokens_per_minute, token_quota, token_quota_period = "Monthly" }
    enable_response_headers = true
    semantic_cache          = false
    usage_events            = false
    jwt_required            = false
    jwt_audience            = null
    jwt_issuer              = null
    jwt_openid_config_url   = null
    required_roles          = []

    # Mixed asset types
    tool_apis   = []
    tool_limit  = null                  # { calls_per_minute, call_quota, call_quota_period = "Monthly" }
    agent_apis  = []
    agent_limit = null

    policy_xml = ""                     # a complete policy that replaces the generated one
  },
]

product_terms        = ""
key_vault            = { enabled = true, id = null }
foundry              = { enabled = false, account_name = "", project_name = "citadel-governance-project", project_id = null }
foundry_config       = { auth_type = "ProjectManagedIdentity", connection_category = "ApiManagement" /* … */ }
secret_rotation_days = 60
secret_validity_days = 90
```

`common.tfvars` provides `workload`, `environment`, `location`, `subscription_id` and `naming`,
which the stack uses to find APIM, Key Vault and Foundry by name.

### 4.1 `use_case` (required)

| Field | Use |
|---|---|
| `business_unit` | e.g. `TeamA`, `Retail` |
| `use_case_name` | e.g. `Chatbot` |
| `environment` | the use case's stage, e.g. `DEV`, `PROD`. Independent of the landing zone's environment: a dev gateway can host a team's `PROD` contract name if you want. |

They form `<code>-<business_unit>-<use_case_name>-<environment>`. APIM product IDs allow letters,
digits and `-`, so keep the values to those.

### 4.2 `api_name_mapping` (required)

Service code → APIM API **names** (resource names, not display names). Every code in `services`
needs an entry. The first API's path forms the endpoint URL (secret and Foundry connection), so put
the main API first.

APIs this repository publishes:

| API name | Path | Key header / query | Published by | Enabled by |
|---|---|---|---|---|
| `universal-llm-api` | `/models` (`inference_api_type = OpenAIV1`, default; `openai` / `inference` for the others) | `api-key` / `api-key` | llm-backend-onboarding | always |
| `azure-openai-api` | `/openai` | `api-key` / `api-key` | llm-backend-onboarding | always |
| `unified-ai-api` | `/unified-ai` | `api-key` / `api-key` | llm-backend-onboarding | `features.unified_ai_api` |
| `ai-model-inference-api` | `/ai-inference` | `api-key` / `api-key` | llm-backend-onboarding | `features.ai_model_inference` |
| `openai-realtime-ws-api` | `/openai/realtime` (WebSocket) | `api-key` | llm-backend-onboarding | `features.openai_realtime` |
| `azure-ai-search-index-api` | `/search` | `api-key` / `api-key` | gateway-config | `features.azure_ai_search` |
| `document-intelligence-api` | `/documentintelligence` | `Ocp-Apim-Subscription-Key` / `subscription-key` | gateway-config | `features.document_intelligence` |
| `document-intelligence-api-legacy` | `/formrecognizer` | `Ocp-Apim-Subscription-Key` / `subscription-key` | gateway-config | `features.document_intelligence` |
| `weather-api` (mock), `weather-mcp`, `ms-learn-mcp` (MCP) | `/weather`, `/weather-mcp`, `/ms-learn-mcp` | APIM default (`Ocp-Apim-Subscription-Key`); **subscription not required** | gateway-config | `features.mcp_sample` |

Your own APIs (MCP servers, A2A agents, REST services) can be mapped the same way once they are in
APIM.

Each service is its own product, with its own key, limits and endpoint. Split APIs into services
when they need different rules or a different endpoint: the Unified AI API, for instance, has its
own path, so [team-c-multicloud](../examples/multi-provider-llm/access-contracts/team-c-multicloud.tfvars)
maps it to a second service (`UAI`) with its own model list and token limit.

### 4.3 `services` (required)

**Identity of the service:**

| Field | Required | Meaning |
|---|---|---|
| `code` | yes | key into `api_name_mapping`; unique per contract; becomes the product prefix |
| `endpoint_secret_name` | yes | Key Vault secret for the endpoint URL (unused without a vault) |
| `api_key_secret_name` | yes | Key Vault secret for the key |

**Generated policy properties** (ignored when `policy_xml` is set):

| Field | Default | Effect | Section |
|---|---|---|---|
| `allowed_models` | `[]` = every model | only these models and aliases (403 otherwise) | [5.1](#51-model-access-allowed_models) |
| `token_limit` | `null` = no limit | per-subscription tokens per minute and / or a token quota per period | [5.2](#52-token-limits-and-quotas-token_limit) |
| `enable_response_headers` | `true` | the `UAIG-*` debug response headers | [5.5](#55-debug-response-headers-enable_response_headers) |
| `semantic_cache` | `false` | answer similar chat prompts from Redis | [5.6](#56-semantic-cache-semantic_cache) |
| `usage_events` | `false` | one event per request to Event Hubs → Cosmos DB | [5.7](#57-usage-events-usage_events) |
| `jwt_required` | `false` | a valid JWT next to the key | [5.4](#54-authentication-key-jwt-app-roles) |
| `jwt_audience`, `jwt_issuer`, `jwt_openid_config_url` | `null` = the gateway's | another identity provider for this product | [5.4](#54-authentication-key-jwt-app-roles) |
| `required_roles` | `[]` | the token must carry one of these app roles | [5.4](#54-authentication-key-jwt-app-roles) |
| `tool_apis`, `agent_apis` | `[]` | APIs of the mapping that are tools (MCP) / agents (A2A) | [5.3](#53-tools-and-agents-in-one-product) |
| `tool_limit`, `agent_limit` | `null` | request-count limits for tools / agents | [5.3](#53-tools-and-agents-in-one-product) |
| `policy_xml` | `""` | complete custom product policy | [7](#7-custom-product-policy-policy_xml) |

**Validation** (fails at plan time):
- `code` values are unique;
- `allowed_models` entries: letters, digits and `. _ : / -`, no spaces or commas;
- `token_limit` needs `tokens_per_minute` and / or `token_quota`, each > 0; periods are `Hourly`,
  `Daily`, `Weekly`, `Monthly` or `Yearly`;
- `tool_apis` / `agent_apis` are API names, appear in `api_name_mapping[code]`, and an API isn't
  both a tool and an agent;
- `tool_limit` / `agent_limit` need `calls_per_minute` and / or `call_quota` (> 0) and the
  matching `*_apis`;
- `required_roles`, `jwt_audience`, `jwt_issuer`, `jwt_openid_config_url` need `jwt_required = true`;
  role values are letters, digits and `. _ : -`; the overrides are literal, non-empty values
  (no `{{named value}}`), and the issuer and OpenID URL are `https://`.

### 4.4 `product_terms`

Terms of use shown to subscribers in the developer portal. Default `""`.

### 4.5 `key_vault`

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `true` | write the endpoint and key secrets. `false`: no secrets; read the endpoint from the outputs and the key from APIM on demand ([finance-batch](../examples/all-features/access-contracts/finance-batch.tfvars)) |
| `id` | `null` = the platform Key Vault | a team-owned vault (resource ID); the apply identity needs *Key Vault Secrets Officer* on it |

### 4.6 `foundry` and `foundry_config`

`foundry` creates one Foundry project connection per service, pointing at the service's endpoint:

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `false` | create the connections |
| `account_name` | `""` = the platform's primary Foundry account | another account of the platform |
| `project_name` | `citadel-governance-project` | project on that account |
| `project_id` | `null` | full project resource ID; overrides both names (a team's own project, any subscription) |

`foundry_config` (all optional):

| Field | Default | Meaning |
|---|---|---|
| `auth_type` | `ProjectManagedIdentity` | `ProjectManagedIdentity`: the project's managed identity sends an Entra token **and** the key as the `api-key` custom header (no stored credential; the product must validate the token, see 5.10). `ApiKey`: the key is the connection's credential. |
| `managed_identity_audience` | `https://cognitiveservices.azure.com` | audience of the project identity's token; also what the generated policy validates |
| `connection_category` | `ApiManagement` | `ApiManagement` or `ModelGateway` |
| `connection_name_prefix` | `""` = `Hub-<bu>-<use case>-<env>` | connection name = `<prefix>-<code>` |
| `deployment_in_path` | `"false"` | `"true"`: the model is in the URL path; `"false"`: in the body |
| `inference_api_version`, `deployment_api_version` | `""` | API versions Foundry sends |
| `static_models` | `[]` | a fixed model list for the connection (used when the discovery endpoints below aren't set) |
| `list_models_endpoint`, `get_model_endpoint`, `deployment_provider` | `""` | custom model discovery (all three together; provider `AzureOpenAI` or `OpenAI`) |
| `custom_headers` | `{}` | extra headers Foundry sends |
| `auth_config` | `{}` | extra authentication metadata |
| `is_shared_to_all` | `false` | share the connection with every project user |

### 4.7 Secret rotation and validity

| Variable | Default | Meaning |
|---|---|---|
| `secret_rotation_days` | `60` | after this many days the next apply rewrites the key secrets and moves their expiry |
| `secret_validity_days` | `90` | secret expiry (`expiration_date`). The ALZ policy *Enforce-GR-KeyVault* allows at most 90 days. Reading an expired secret keeps working; the expiry is a compliance signal. |

Rotation rewrites the **current** key; it doesn't regenerate it. To roll a key: regenerate it in
APIM (subscription → *Regenerate primary key*), then rewrite the secrets and Foundry connection at
once:

```bash
task apply STACK=access-contracts ENV=dev STATE_KEY=team-a-chatbot.tfstate \
  VAR_FILE=$PWD/environments/dev/access-contracts/team-a-chatbot.tfvars \
  'PLAN_ARGS=-replace=module.contract.time_rotating.secrets'
```

---

## 5. Features

### 5.1 Model access (`allowed_models`)

```hcl
allowed_models = ["gpt-5.4-mini", "fast"]
```

- The policy reads the requested model (`set-llm-requested-model`: the deployment in the path,
  `/deployments/{model}/…`, else the `model` field of the body) and compares it, case-insensitively, with the
  list (`validate-model-access`).
- A model outside the list gets **403**:
  `{"error": {"code": "unauthorized_model_access", "type": "access_error", "message": "Access to model 'x' is not allowed for this product.", "allowed_models": "…"}}`.
- **Aliases** (llm-backend-onboarding `model_aliases`, e.g. `fast` → several real models) are
  matched by name: allowing `fast` doesn't allow its member models, and allowing a member doesn't
  allow the alias. List what clients send.
- Requests without a model (`GET /models`, `GET /deployments`, other GET operations) are not
  checked. An LLM request without a `model` gets **400** `extraction_missing_model_parameter`.
- `[]` allows every model the gateway routes.

### 5.2 Token limits and quotas (`token_limit`)

```hcl
token_limit = { tokens_per_minute = 2000, token_quota = 50000, token_quota_period = "Daily" }
```

- One `llm-token-limit` per subscription (`counter-key` = the subscription ID), so per service of the
  contract.
- `tokens_per_minute` → **429** "Token limit is exceeded. Try again in N seconds." with
  `Retry-After`.
- `token_quota` per `token_quota_period` → **403** when exhausted (`Hourly`, `Daily`, `Weekly`,
  `Monthly`, `Yearly`).
- Counts come from the model's `usage` (`estimate-prompt-tokens = false`): a request is allowed
  while the counter is below the limit, and its tokens are counted when the response arrives. A
  single large request can overshoot; the next one is rejected.
- Semantic cache hits don't count (no model call).
- Only LLM APIs: for a mixed product the limit sits in the LLM branch (5.3).
- Per-model limits (different TPM per model) aren't a property: use `policy_xml`.

### 5.3 Tools and agents in one product

A product can grant LLM APIs, **tools** (MCP servers) and **agents** (A2A) together. APIM doesn't
expose the API type to policy, so the contract lists which mapped APIs are tools or agents; every
other mapped API is an LLM API.

```hcl
api_name_mapping = {
  MULTI = ["universal-llm-api", "azure-openai-api", "weather-mcp", "ms-learn-mcp"]
}
services = [{
  code                 = "MULTI"
  endpoint_secret_name = "HR-MULTI-ENDPOINT"
  api_key_secret_name  = "HR-MULTI-KEY"

  allowed_models = ["fast", "balanced"]                                   # LLM only
  token_limit    = { tokens_per_minute = 20000, token_quota = 2000000 }   # LLM only

  tool_apis  = ["weather-mcp", "ms-learn-mcp"]
  tool_limit = { calls_per_minute = 60, call_quota = 10000, call_quota_period = "Monthly" }

  # agent_apis  = ["hr-chat-agent"]
  # agent_limit = { calls_per_minute = 30, call_quota = 5000 }
}]
```

| Asset kind | Controls | Rejection |
|---|---|---|
| `llm` | `allowed_models`, `token_limit`, `enable_response_headers`, `semantic_cache` | 403 model / 429 TPM / 403 quota |
| `tool` | `tool_limit`: `rate-limit-by-key` (`calls_per_minute`) and `quota-by-key` (`call_quota` per `call_quota_period`), counter = subscription + `:tool` | 429 rate / 403 quota |
| `agent` | `agent_limit`, the same with `:agent` | 429 / 403 |

- The policy sets `contractToolApis` / `contractAgentApis`, includes `set-asset-kind` (sets
  `assetKind`) and branches with `<choose>`. JWT settings and usage events apply to every kind.
- With `tool_apis` / `agent_apis` set the policy always classifies, even without limits.
- Tokens don't exist for a tool call or an agent turn, so their limits count requests.
- A tools-only contract: [tools-only](../examples/all-features/access-contracts/tools-only.tfvars).
- The sample MCP APIs are published with *subscription required* off: a client that sends no key
  reaches them anonymously and no contract policy (or limit) runs. Publish your MCP servers with
  subscription required to enforce contracts.
- This repository publishes no A2A agent APIs; publish yours, map them, then list them in
  `agent_apis`.

### 5.4 Authentication: key, JWT, app roles

**The subscription key is always required** on the LLM, AI Search and Document Intelligence APIs.
It identifies the contract; a token never replaces it.

```hcl
jwt_required   = true
required_roles = ["Model.Invoke"]     # optional: any one of them
```

- `jwt_required = true`: the request also needs `Authorization: Bearer <token>`, validated by the
  `security-handler` fragment against the gateway's identity provider (gateway-config `entra_auth`:
  named values `JWT-AppRegistrationId`, `JWT-Issuer`, `JWT-OpenIdConfigUrl`).
- `required_roles`: the token's `roles` claim must hold at least one (OR).
- **Another identity provider for this product only** (a partner tenant, Auth0, Okta): set any of

  | Property | Policy variable | Default |
  |---|---|---|
  | `jwt_audience` | `jwtAudience` | `JWT-AppRegistrationId` |
  | `jwt_issuer` | `jwtIssuer` | `JWT-Issuer` |
  | `jwt_openid_config_url` | `jwtOpenIdConfigUrl` | `JWT-OpenIdConfigUrl` |

  Unset ones keep the default ([partner-tenant](../examples/entra-jwt-auth/access-contracts/partner-tenant.tfvars)).
- A contract with a `ProjectManagedIdentity` Foundry connection defaults the three to the project
  identity's token (5.10).

| Response | Cause |
|---|---|
| 401 (APIM) "missing / invalid subscription key" | no key, a wrong key, or a key whose product doesn't grant this API |
| 401 `jwt_required` | the product requires a JWT, none sent |
| 401 invalid token | wrong `aud` / `iss`, expired, wrong signing keys |
| 403 `insufficient_role` | valid token without any of `required_roles` |
| 503 `jwt_not_configured` | JWT required, but `entra_auth` is off and the contract sets no overrides |

Setup of the gateway app, client identities and the `task jwt-test` suite:
[DEPLOYMENT_GUIDE §6.6](DEPLOYMENT_GUIDE.md#66-entra-id-jwt-authentication).

### 5.5 Debug response headers (`enable_response_headers`)

On by default. The `set-response-headers` fragment adds `UAIG-*` headers to the LLM API responses:

| Header | Content |
|---|---|
| `UAIG-Request-Id` | APIM request ID: the `CorrelationId` in the gateway logs and the `id` of the usage event |
| `UAIG-Subscription`, `UAIG-User-Id`, `UAIG-Auth-Type` | caller (`api-key`, `jwt`, `api-key-jwt`) |
| `UAIG-Model-Id`, `UAIG-Alias`, `UAIG-Resolved-Model` | requested model, alias, the model the alias resolved to |
| `UAIG-Backend`, `UAIG-Auth-Type-Backend` | backend chosen, how the gateway authenticated to it |
| `UAIG-API-Type`, `UAIG-API-Version`, `UAIG-Processed-Path`, `UAIG-Final-Path`, `UAIG-Is-Streaming` | routing details |
| `UAIG-Gateway-Region` | gateway region |
| `UAIG-Cache-Operation`, `UAIG-Semantic-Cache` | routing cache; semantic cache `hit` / `miss` |

Turn them off for production contracts that shouldn't expose routing details.

### 5.6 Semantic cache (`semantic_cache`)

`semantic_cache = true` sets `semanticCacheEnabled`: the LLM APIs look up non-streaming chat
completions in Azure Managed Redis and store new ones. Answers are partitioned by subscription and
model, so a contract never gets another contract's answer. Needs platform `features.semantic_cache`
and gateway-config `semantic_cache.enabled`; other contracts never use the cache.
Details: [DEPLOYMENT_GUIDE §6.9](DEPLOYMENT_GUIDE.md#69-semantic-cache).

### 5.7 Usage events (`usage_events`)

`usage_events = true` writes **one event per request** to the `ai-usage` Event Hub; the
`ai-usage-ingestion` Logic App stores it in Cosmos DB (`ai-usage-container`). Every outcome is
recorded:

| `outcome` | Examples |
|---|---|
| `response` | the backend answered: tokens from the model's `usage` (or, for streams, the token limit's count) |
| `gateway` | the gateway answered: model not allowed (403), PII blocked (400), mock API, deployments list |
| `error` | 429 token limit, 403 quota, 5xx backend failures |

A contract without `token_limit` gets a metering-only token limit (100,000,000 TPM) so streamed
responses still have a token count. Token metrics (`llm-usage`, hourly aggregates) run for every
contract regardless; don't add both in reports. Fields, PII audit events and key rejections:
[DEPLOYMENT_GUIDE §6.10](DEPLOYMENT_GUIDE.md#610-usage-and-pii-audit-events-event-hubs).

### 5.8 PII anonymization, PII blocking, content safety

Not properties: add them with `policy_xml` (section 7). Both need their gateway-config feature
(`features.pii_anonymization`, `features.content_safety`).

- **PII anonymization**: `piiAnonymizationEnabled` + `pii-anonymization` in inbound replaces
  entities with placeholders (`<Person_0>`); `pii-deanonymization` in outbound restores them.
- **PII blocking**: `piiBlockingEnabled` instead rejects a prompt with PII (400 `pii_detected`, with
  the categories found).
- **PII audit**: `piiAuditEnabled` + `pii-audit` writes an event with counts per category, no PII.
- **Content safety**: `<llm-content-safety backend-id="content-safety-backend" …>` (403 when a
  category exceeds its threshold, or a prompt attack is detected with `shield-prompt`).

Copy-ready snippets: `SNIPPETS["pii"]` and `SNIPPETS["content_safety"]` in
[validation/shared/acceptance.py](../validation/shared/acceptance.py). A complete PII contract is in
section 7; blocking and the audit event are in
[DEPLOYMENT_GUIDE §6.10](DEPLOYMENT_GUIDE.md#610-usage-and-pii-audit-events-event-hubs).

### 5.9 Alerts

The `raise-alert-events` fragment (included by the gateway's API policies) emits the `AI Gateway
Alert` metric (namespace `ai-gateway-alerts`) for throttling, quota, backend failures and, when
opted in, client-side failures. A custom `policy_xml` can tune it per contract with inbound
variables:

| Variable | Default | Alerts on |
|---|---|---|
| `alertsEnabled` | `true` | master switch for the product |
| `alertOnThrottling` | `true` | 429 |
| `alertOnQuotaExceeded` | `true` | 403 token quota |
| `alertOnBackendFailure` | `true` | 5xx |
| `alertOnAuthFailure` | `false` | 401 / 403 (key, JWT, model access) |
| `alertOnContentSafety` | `false` | content safety blocks |
| `alertOnPiiFailure` | `false` | PII service failures |

Turn the client-side ones on for mission-critical use cases only; they are noisy.

### 5.10 Foundry connection

`foundry = { enabled = true }` creates a connection per service on the project, so agents and
playgrounds in that project use the gateway (and the contract's policy) instead of the models
directly.

| `auth_type` | Foundry sends | Contract must |
|---|---|---|
| `ProjectManagedIdentity` (default) | an Entra token of the project's managed identity for `managed_identity_audience` **and** the key in the `api-key` custom header | set `jwt_required = true` on every service: the generated policy then validates that token (audience = `managed_identity_audience`, issuer `https://sts.windows.net/<tenant>/`, tenant = the deploying identity's). A `check` warns on every plan otherwise. |
| `ApiKey` | the key | nothing; `jwt_required` stays off |

With `ProjectManagedIdentity` and `jwt_required`, **direct callers** of the same product also need a
token for that audience; give them a separate contract if that's unwanted. A project in another
tenant: set `jwt_issuer` and `jwt_openid_config_url` with that tenant.
Details: [DEPLOYMENT_GUIDE §6.3](DEPLOYMENT_GUIDE.md#63-foundry-connection-authentication).

---

## 6. The generated product policy

Template: [modules/access-contract/policies/product-policy.xml.tftpl](../modules/access-contract/policies/product-policy.xml.tftpl)
(+ `llm-rules.xml.tftpl`, `asset-rules.xml.tftpl`). For the team-a-chatbot properties above
(`allowed_models`, `token_limit`, `usage_events`):

```xml
<policies>
    <inbound>
        <base />
        <set-variable name="usageEventsEnabled" value="true" />          <!-- usage_events -->
        <include-fragment fragment-id="set-llm-requested-model" />
        <set-variable name="allowedModels" value="gpt-5.4-mini,fast" />  <!-- allowed_models -->
        <include-fragment fragment-id="validate-model-access" />
        <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="2000"
                         token-quota="50000" token-quota-period="Daily" estimate-prompt-tokens="false"
                         tokens-consumed-variable-name="tokensConsumed" />  <!-- token_limit -->
        <set-variable name="enableResponseHeaders" value="@(true)" />   <!-- enable_response_headers -->
    </inbound>
    <backend><base /></backend>
    <outbound>
        <base />
        <include-fragment fragment-id="usage-event" />                   <!-- usage_events -->
    </outbound>
    <on-error>
        <base />
        <include-fragment fragment-id="usage-event" />                   <!-- usage_events -->
    </on-error>
</policies>
```

| Property | Adds |
|---|---|
| `usage_events` | `usageEventsEnabled` first; `usage-event` in outbound and on-error; `tokensConsumed` on the token limit (or the metering limit) |
| `jwt_required` (+ overrides, roles) | `jwtRequired`, `jwtAudience`, `jwtIssuer`, `jwtOpenIdConfigUrl`, `requiredRoles` |
| `allowed_models` | `allowedModels` + `validate-model-access` |
| `token_limit` | `llm-token-limit` |
| `enable_response_headers` | `enableResponseHeaders` |
| `semantic_cache` | `semanticCacheEnabled` |
| `tool_apis` / `agent_apis` | `contractToolApis`, `contractAgentApis`, `set-asset-kind` and a `<choose>` on `assetKind`, with the LLM rules in the `llm` branch and `rate-limit-by-key` / `quota-by-key` in the `tool` / `agent` branches |

**Execution order.** A request to an LLM API runs the API policy's inbound section; its `<base />`
(first line) runs the product policy above. The API policy then continues with `security-handler`
(which reads the `jwt*` variables), model validation, the semantic cache, routing and backend
authentication. Product variables therefore have to be set in the product policy's inbound section
to take effect. The full picture: [APIM_POLICY_ARCHITECTURE.md](APIM_POLICY_ARCHITECTURE.md).

See a deployed policy:

```bash
az rest --method get --url "https://management.azure.com<apim-id>/products/LLM-TeamA-Chatbot-DEV/policies/policy?api-version=2024-05-01&format=rawxml" \
  --query properties.value -o tsv
```

---

## 7. Custom product policy (`policy_xml`)

For what the properties don't cover (PII, content safety, per-model limits, alert tuning, extra
headers), set `policy_xml` to a **complete** policy. It replaces the generated one: every property of
section 4.3's policy table is then ignored, and the `jwt` output is `null` for that service.

```hcl
services = [{
  code                 = "PII"
  endpoint_secret_name = "TEAMB-PII-ENDPOINT"
  api_key_secret_name  = "TEAMB-PII-KEY"
  policy_xml           = <<-XML
    <policies>
        <inbound>
            <base />
            <set-variable name="usageEventsEnabled" value="true" />
            <include-fragment fragment-id="set-llm-requested-model" />
            <set-variable name="allowedModels" value="gpt-5.4-mini,fast" />
            <include-fragment fragment-id="validate-model-access" />
            <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="20000"
                             estimate-prompt-tokens="false" tokens-consumed-variable-name="tokensConsumed" />
            <set-variable name="enableResponseHeaders" value="@(true)" />
            <set-variable name="piiAnonymizationEnabled" value="true" />
            <set-variable name="piiInputContent" value="@(context.Request.Body.As<string>(preserveContent: true))" />
            <include-fragment fragment-id="pii-anonymization" />
            <set-body>@(context.Variables.GetValueOrDefault<string>("piiAnonymizedContent"))</set-body>
        </inbound>
        <backend><base /></backend>
        <outbound>
            <base />
            <include-fragment fragment-id="usage-event" />
            <choose>
                <when condition="@(context.Variables.ContainsKey("piiMappings"))">
                    <set-variable name="piiDeanonymizeContentInput" value="@(context.Response.Body.As<string>(preserveContent: true))" />
                    <include-fragment fragment-id="pii-deanonymization" />
                    <set-body>@(context.Variables.GetValueOrDefault<string>("piiDeanonymizedContentOutput"))</set-body>
                </when>
            </choose>
            <set-variable name="piiAuditEnabled" value="true" />
            <include-fragment fragment-id="pii-audit" />
        </outbound>
        <on-error>
            <base />
            <include-fragment fragment-id="usage-event" />
        </on-error>
    </policies>
  XML
}]
```

Checklist (to keep what the properties would have given you):

| To keep | Write |
|---|---|
| everything the API does | `<base />` first in every section |
| model access | `set-llm-requested-model`, then `allowedModels` + `validate-model-access` |
| token limit | `llm-token-limit` with `counter-key="@(context.Subscription.Id)"` |
| usage events | `usageEventsEnabled` = `"true"` right after inbound `<base />`; `usage-event` after `<base />` in outbound **and** on-error; `tokens-consumed-variable-name="tokensConsumed"` on the token limit for stream totals |
| JWT | `jwtRequired` = `"true"` (+ `jwtAudience`, `jwtIssuer`, `jwtOpenIdConfigUrl`, `requiredRoles`). With a `ProjectManagedIdentity` Foundry connection the plan-time `check` looks for `jwtRequired` in the XML. |
| response headers | `<set-variable name="enableResponseHeaders" value="@(true)" />` (a boolean expression, not the string `"true"`) |
| semantic cache | `semanticCacheEnabled` = `"true"` |
| tools / agents | `contractToolApis`, `contractAgentApis`, `set-asset-kind` and your own `<choose>` |

Tips:
- Start from the generated policy (section 6) and add to it.
- Fragments the policy includes must exist: PII fragments need gateway-config
  `features.pii_anonymization`; `usage-event`, `set-asset-kind` and the semantic cache fragments come
  from gateway-config; the LLM fragments from llm-backend-onboarding.
- APIM validates the XML on apply; a wrong fragment ID or expression fails the apply with
  `ValidationError`.
- Policy expressions run in APIM's restricted C# (no `JsonConvert.ToString`, no `Regex.Escape`, …).

---

## 8. Using a contract (client side)

**Endpoint and key**, with a Key Vault:

```bash
KV=<key-vault-name>
ENDPOINT=$(az keyvault secret show --vault-name $KV -n teama-llm-endpoint --query value -o tsv)  # https://<apim>.azure-api.net/models
KEY=$(az keyvault secret show --vault-name $KV -n teama-llm-key --query value -o tsv)
```

Secret names are the configured names, lower-cased, with `_` replaced by `-`. Without a vault
(`key_vault.enabled = false`):

```bash
terraform -chdir=stacks/access-contracts output -json endpoints     # after init with the contract's state key
az rest --method post --url "https://management.azure.com<subscription id from the subscriptions output>/listSecrets?api-version=2024-05-01" \
  --query primaryKey -o tsv
```

**Calls** (Universal LLM API, OpenAI v1 style; the model goes in the body):

```bash
curl -s "$ENDPOINT/chat/completions" -H "api-key: $KEY" -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.4-mini","messages":[{"role":"user","content":"Hello"}]}'

curl -s "$ENDPOINT/embeddings" -H "api-key: $KEY" -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-3-small","input":"Hello"}'

curl -s "$ENDPOINT" -H "api-key: $KEY"        # GET /models: the models the gateway routes
```

Azure OpenAI API (`/openai`, the model is the deployment in the path):

```bash
curl -s "https://<apim>.azure-api.net/openai/deployments/gpt-5.4-mini/chat/completions?api-version=2024-10-21" \
  -H "api-key: $KEY" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

With `jwt_required`, add `-H "Authorization: Bearer $TOKEN"` (a token for the gateway app,
`api://<client id>/.default`, or the audience the contract overrides).

The same key works on every API of the product; each API has its own path under the gateway URL.
The endpoint secret holds the first one only.

**Outputs** of the stack (`terraform output` in the contract's state):

| Output | Content |
|---|---|
| `products` | code → product ID |
| `subscriptions` | code → subscription resource ID (keys are never output) |
| `endpoints` | code → endpoint URL |
| `key_vault_secret_names` | code → `{ endpoint, key }` secret names |
| `foundry_connections` | code → connection name |
| `foundry_connection_auth` | `auth_type` and the audience the policy must validate |
| `jwt` | code → `required`, `required_roles` and the overrides in effect (`null` with `policy_xml`) |

---

## 9. Examples

| File | Shows |
|---|---|
| [quickstart/team-a-chatbot](../examples/quickstart/access-contracts/team-a-chatbot.tfvars) | the basic contract: LLM APIs, model list, token limit, Key Vault |
| [all-features/retail-assistant](../examples/all-features/access-contracts/retail-assistant.tfvars) | three services (LLM, AI Search, Document Intelligence), Foundry connections with JWT, semantic cache, usage events, monthly secret rotation |
| [all-features/hr-assistant-multi](../examples/all-features/access-contracts/hr-assistant-multi.tfvars) | one product for LLM + MCP tools with separate limits |
| [all-features/tools-only](../examples/all-features/access-contracts/tools-only.tfvars) | tools only, request-count limits |
| [all-features/finance-batch](../examples/all-features/access-contracts/finance-batch.tfvars) | no Key Vault, no Foundry: endpoint from outputs, key from APIM |
| [entra-jwt-auth/team-a-jwt](../examples/entra-jwt-auth/access-contracts/team-a-jwt.tfvars), [team-b-roles](../examples/entra-jwt-auth/access-contracts/team-b-roles.tfvars), [partner-tenant](../examples/entra-jwt-auth/access-contracts/partner-tenant.tfvars) | JWT, app roles, another tenant |
| [multi-provider-llm/team-b-agents](../examples/multi-provider-llm/access-contracts/team-b-agents.tfvars) | team-owned Key Vault and Foundry project, `ModelGateway` connection with `ApiKey` and static models |
| [multi-provider-llm/team-c-multicloud](../examples/multi-provider-llm/access-contracts/team-c-multicloud.tfvars) | Universal and Unified AI APIs as two services, models from several clouds |

---

## 10. Testing a contract

| Tool | What it checks |
|---|---|
| `task validate ENV=<env>` | post-deploy smoke tests |
| `task jwt-test ENV=<env>` | key / JWT / app-role cases on every product that requires a JWT |
| [validation/citadel-access-contracts-tests.ipynb](../validation/citadel-access-contracts-tests.ipynb) | creates three contracts (Key Vault, Key Vault + Foundry, outputs only), load-tests them and plots throttling |
| [validation/citadel-acceptance-tests.ipynb](../validation/citadel-acceptance-tests.ipynb) | the customer acceptance catalogue (authentication, authorization, AI policies, usage, token accounting, …); for features the generated policy doesn't enable it prints the `policy_xml` or tfvars to add |
| [validation/citadel-backend-and-contract-tests.ipynb](../validation/citadel-backend-and-contract-tests.ipynb) | test one contract (or backend, model, alias, MCP server) by name: calls with the contract's key and token, plus guardrail checks (no key → 401, model outside `allowed_models` → 403, missing role → 403) |

`terraform test` in `modules/access-contract` and `stacks/access-contracts` checks the generated
policies without Azure.

---

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| plan: `data.azurerm_api_management_api.first` not found | the first API of a mapping isn't published: apply gateway-config / llm-backend-onboarding, or check the feature flag and the API **name** |
| apply: `ValidationError` on the product policy | `policy_xml` includes a fragment that isn't deployed, or has an invalid expression |
| apply: 403 on Key Vault secrets | the apply identity lacks *Key Vault Secrets Officer* on the vault (or can't reach a private vault) |
| plan warning `foundry_mi_policy_validates_jwt` | `ProjectManagedIdentity` connection without `jwt_required = true` on every service |
| 401 "invalid subscription key" with the right key | the product doesn't grant that API (`api_name_mapping`), or the subscription is suspended |
| 401 `jwt_required` from Foundry agents | the product requires a JWT but the connection uses `auth_type = "ApiKey"` (no token sent): use `ProjectManagedIdentity`, or drop `jwt_required` |
| 403 `unauthorized_model_access` | the model or alias isn't in `allowed_models` (an alias and its members are separate names) |
| 403 after many successful calls | `token_quota` / `call_quota` used up for the period (gateway logs: `LastErrorReason`) |
| 429 | `tokens_per_minute` / `calls_per_minute` reached; wait `Retry-After` |
| 400 `extraction_missing_model_parameter` | LLM request without `model` in the body |
| no `UAIG-*` headers | `enable_response_headers = false`, or a `policy_xml` without `enableResponseHeaders` |
| no usage events | `usage_events` off, or a `policy_xml` without `usageEventsEnabled` / the `usage-event` includes |
| new key after an apply | `use_case` or `code` changed (new product and subscription) |

---

## 12. Limits and design notes

- **One subscription per service** (`…-SUB-01`). Several apps sharing a contract share its key and
  limits; give each app its own contract (or service) for separate limits and usage.
- **Products allow up to 100 subscriptions** and need no approval; extra subscriptions created
  outside Terraform aren't managed by the contract.
- **Limits are per subscription**, not per end user. For per-user limits, write a `policy_xml` with
  a counter key from a JWT claim.
- **The endpoint secret and Foundry connection point at the first mapped API** only. Per-API
  secrets aren't generated.
- **Mixed-asset classification is by API name**; an API not in `tool_apis` / `agent_apis` is LLM.
- **Properties cover the common cases**; PII, content safety, per-model limits and alert tuning are
  `policy_xml` only, and a custom policy owns all the rules of its product.
- **No secrets in state or outputs**: keys are read ephemerally and written write-only.
- **Contracts are independent**: own state, own lock; applying one never plans another.
