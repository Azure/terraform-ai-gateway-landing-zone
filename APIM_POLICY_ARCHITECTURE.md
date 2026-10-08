# AI Citadel Governance Hub - APIM Policy Architecture — Terraform

> **Scope:** How every API Management policy, fragment, and named value in
> this repo is modeled, wired up, and applied at runtime. Covers the core
> inference APIs (`universal-llm-api`, `azure-openai-api`), the wildcard
> `unified-ai-api`, operation-level policies, product-level policies
> (including the access contracts), and the service and MCP sample APIs.
>
> **Related files:**
> [stacks/platform/apim.tf](stacks/platform/apim.tf) ·
> [stacks/gateway-config/named-values.tf](stacks/gateway-config/named-values.tf) ·
> [stacks/gateway-config/fragments.tf](stacks/gateway-config/fragments.tf) ·
> [stacks/gateway-config/backends.tf](stacks/gateway-config/backends.tf) ·
> [stacks/gateway-config/apis.tf](stacks/gateway-config/apis.tf) ·
> [stacks/llm-backend-onboarding/named-values.tf](stacks/llm-backend-onboarding/named-values.tf) ·
> [stacks/llm-backend-onboarding/fragments.tf](stacks/llm-backend-onboarding/fragments.tf) ·
> [stacks/llm-backend-onboarding/backends.tf](stacks/llm-backend-onboarding/backends.tf) ·
> [stacks/llm-backend-onboarding/apis.tf](stacks/llm-backend-onboarding/apis.tf) ·
> [stacks/access-contracts/main.tf](stacks/access-contracts/main.tf) ·
> [modules/apim-policy-fragments/](modules/apim-policy-fragments/README.md) ·
> [modules/llm-routing/main.tf](modules/llm-routing/main.tf) ·
> [modules/gateway-api/](modules/gateway-api/README.md) ·
> [modules/apim-telemetry/](modules/apim-telemetry/README.md) ·
> [modules/access-contract/main.tf](modules/access-contract/main.tf) ·
> [modules/apim/main.tf](modules/apim/main.tf)
>
> The policy model is split across four stacks that each target the APIM
> service of `stacks/platform` by its deterministic name (`data` sources, no
> remote state): `gateway-config` (shared configuration and service APIs),
> `llm-backend-onboarding` (LLM backends, routing and APIs) and
> `access-contracts` (one state per use case). See
> [§9](#9-onboarding-stacks).

---

## 1. Mental model

APIM policies are XML documents that run at one of four **scopes**. Each
scope maps 1:1 to a distinct Terraform resource type:

| Scope | Terraform resource | What it controls |
|---|---|---|
| **Global** | `azurerm_api_management_policy` | All APIs across the service. Not currently used in this port. |
| **Product** | `azurerm_api_management_product_policy` | All APIs attached to a given product. Used for access contracts + unified-ai. |
| **API** | `azurerm_api_management_api_policy` | One API's inbound/backend/outbound/on-error pipeline. Used by every inference API. |
| **Operation** | `azurerm_api_management_api_operation_policy` | A single operation inside an API. Used for `deployments` + `deployment-by-name`. |

Policy **fragments** are separate, reusable chunks that live alongside those
four scopes. A fragment is a standalone APIM resource
(`azurerm_api_management_policy_fragment`) that is uploaded **once** and
then referenced from any policy document with:

```xml
<include-fragment fragment-id="security-handler" />
```

APIM validates every `<include-fragment>` tag and every `{{named-value}}`
reference at the moment the policy is saved, so the fragments + named values
must exist **before** any policy that references them. Inside a stack,
Terraform enforces this via `depends_on`; across stacks, the apply order does
(see [§6](#6-apply-time-ordering-why-depends_on-matters)).

---

## 2. How `.tf` files become a module

Terraform automatically loads **every `.tf` file in a module directory** and
merges them into one configuration — there is no `include` or `import`
directive, and file names are purely organizational. Each stack under
`stacks/` is its own root module with its own state. The APIM policy model is
split across these stacks and several focused child modules:

```
stacks/
  platform/                    # APIM service + telemetry (no child configuration)
    apim.tf                    #   module "apim" (service) + module "apim_telemetry" (loggers, diagnostics)
  gateway-config/              # Model-agnostic configuration, owned once per gateway
    named-values.tf            #   uami-client-id, tenant-id, client-id, audience, entra-auth, JWT-*, piiServiceUrl, contentSafetyServiceUrl
    fragments.tf               #   shared fragment catalogue → module "shared_fragments"
    fragments/                 #   frag-*.xml bodies of the shared fragments
    backends.tf                #   content-safety-backend, ai_search, embeddings-backend, ms-learn-mcp-backend
    apis.tf                    #   service API catalogue → module "api" / "api_dependent"
    apis/<api>/                #   per-API specs + policy XML (apis/shared/ = MCP default policy)
    api-center.tf              #   API Center registration of the enabled APIs (optional)
  llm-backend-onboarding/      # Model-aware configuration
    data.tf                    #   APIM, entra-auth named value, Foundry accounts + deployments
    named-values.tf            #   aws-access-key, aws-secret-key, aws-region, per-backend keys
    fragments.tf               #   LLM fragment catalogue → module "llm_fragments"
    fragments/                 #   frag-*.xml bodies of the LLM fragments
    backends.tf                #   module "llm_routing" (backends, pools, generated routing fragments)
    apis.tf                    #   LLM API catalogue → module "llm_api"
    apis/<api>/                #   per-API specs + policy XML (apis/shared/ = deployments operation policies)
    api-center.tf              #   API Center registration of the LLM APIs (optional)
  access-contracts/            # One use case per state → module "contract"

modules/
  apim/                        # APIM service (AVM), plan-time service rules, existence probe, Redis external cache
    main.tf
    internal-dns.tf            #   internal-mode DNS records
  apim-policy-fragments/       # Generic: deploys a map of fragments (azurerm, or azapi for the PII set)
  llm-routing/                 # LLM backends, backend pools + the 4 generated routing fragments
    templates/                 #   frag-set-backend-pools.xml, frag-get-available-models.xml, ...
  gateway-api/                 # Generic API: http / websocket / mcp, operation policies, diagnostics, optional product
  apim-telemetry/              # APIM loggers (App Insights, Azure Monitor, Event Hub) + global diagnostics
  access-contract/             # Products, product policies, subscriptions, Key Vault secrets, Foundry connection
    policies/                  #   default-ai-product-policy.xml
```

Each fragment file has exactly one owner:
[scripts/ci/check-policy-assets.sh](scripts/ci/check-policy-assets.sh) fails
if a `stacks/<stack>/fragments/frag-<name>.xml` file isn't wired up in that
stack's `fragments.tf`, or if an XML file name exists in two places.

These pieces plug into the dependency graph via:

1. **Module outputs** — e.g. `local.all_pools` is computed inside
   [modules/llm-routing](modules/llm-routing/main.tf) from
   `var.llm_backend_config` and consumed there by `local.backend_pools_code`;
   `local.apim_id` (from `data.azurerm_api_management.this`) feeds every
   fragment / API module's `api_management_id`.
2. **Explicit dependency lists** — `module.shared_fragments` receives
   `depends_on_ids` = the gateway-config named values, and
   `module.llm_fragments` the `aws-*` and per-backend named values. Every API
   created through [modules/gateway-api](modules/gateway-api/README.md)
   receives `policy_depends_on = local.api_policy_depends_on` (the stack's
   fragment IDs, plus the named values in gateway-config and the
   `module.llm_routing` fragments in llm-backend-onboarding) so APIM's
   server-side validation finds every `<include-fragment>` and
   `{{named-value}}` reference.
3. **Deterministic names across stacks** — the loggers
   (`appinsights-logger`, `azuremonitor`, ...) of `module.apim_telemetry` and
   the gateway-config fragments are referenced by name from the later stacks.
   llm-backend-onboarding checks that the shared fragments it needs exist
   (`check "shared_fragments_exist"` in
   [data.tf](stacks/llm-backend-onboarding/data.tf)).

---

## 3. Fragments (the reusable building blocks)

The reusable fragments are split by owner. Each stack catalogues its
fragments in `fragments.tf` and deploys them with
[modules/apim-policy-fragments](modules/apim-policy-fragments/README.md); the
XML bodies live next to it, prefixed with `frag-`:

* [stacks/gateway-config/fragments/](stacks/gateway-config/fragments/) —
  model-agnostic fragments (`module.shared_fragments`).
* [stacks/llm-backend-onboarding/fragments/](stacks/llm-backend-onboarding/fragments/) —
  model-aware fragments (`module.llm_fragments`).

The generated routing fragments are owned by
[modules/llm-routing](modules/llm-routing/main.tf), called from
llm-backend-onboarding. There are three kinds.

### 3.1 Static fragments (unconditional)

Mirrored from Bicep's `policy-fragments.bicep`. Each stack declares a
catalogue map (`name → description`; the file is `fragments/frag-<name>.xml`)
and passes it to the generic fragments module, which creates them with
`for_each`:

```hcl
module "shared_fragments" {              # stacks/gateway-config/fragments.tf
  source            = "../../modules/apim-policy-fragments"
  api_management_id = local.apim_id

  fragments = {
    for k, d in local.shared_fragments : k => {
      xml         = file("${local.fragments_dir}/frag-${k}.xml")   # fragments/
      description = d
    }
  }
  azapi_fragments = { /* local.pii_fragments, same shape */ }

  depends_on_ids = [for nv in azurerm_api_management_named_value.plain : nv.id]
}
```

`module "llm_fragments"` in
[stacks/llm-backend-onboarding/fragments.tf](stacks/llm-backend-onboarding/fragments.tf)
has the same shape, over `local.llm_fragments`.

| Catalogue | Always on? | Fragment IDs |
|---|---|---|
| gateway-config `local.shared_fragments` | Yes | `ai-usage`, `raise-throttling-events`, `throttling-events`, `security-handler`, `entra-auth`, `aad-auth`, `aad-auth-custom`, `llm-usage`, `openai-usage`, `openai-usage-streaming`, `ai-foundry-compatibility`, `set-response-headers`, `strip-backend-headers` |
| gateway-config `local.pii_fragments` | `features.pii_anonymization = true` | `pii-anonymization`, `pii-deanonymization`, `pii-state-saving` |
| llm-backend-onboarding `local.llm_fragments` | Yes | `set-backend-authorization`, `set-target-backend-pool`, `set-llm-usage`, `set-llm-requested-model`, `validate-model-access`, `responses-id-security`, `responses-id-cache-store`, `ai-foundry-deployments` |
| llm-backend-onboarding `local.llm_fragments` | `features.unified_ai_api = true` | `central-cache-manager`, `request-processor`, `path-builder` |

> **PII fragments are not part of the `fragments` `for_each`.** The
> `pii-anonymization` / `pii-deanonymization` / `pii-state-saving`
> fragments are passed as `azapi_fragments` and created by
> `azapi_resource.this` in
> [modules/apim-policy-fragments](modules/apim-policy-fragments/main.tf)
> (a direct idempotent PUT) because the `azurerm` fragment resource hit an
> LRO polling bug (404 *PolicyFragment not found* during `CreateOrUpdate`).

> **`responses-id-security` / `responses-id-cache-store`** enforce
> per-subscription ownership of Responses API objects; **`strip-backend-headers`**
> removes browser / App Service (ARR) / `X-Forwarded-*` headers before the
> request is forwarded to an AI backend.

### 3.2 Dynamic fragments (computed from the LLM backend config + `var.model_aliases`)

Mirrored from Bicep's `llm-policy-fragments.bicep`. Owned by
[modules/llm-routing](modules/llm-routing/README.md) (called as
`module "llm_routing"` from
[stacks/llm-backend-onboarding/backends.tf](stacks/llm-backend-onboarding/backends.tf)).
Each one takes a placeholder-based XML template from
[modules/llm-routing/templates/](modules/llm-routing/templates/) and injects
generated code into it at plan time via `replace()`. They are **always
created** (even when the backend config is empty) because the core API
policies reference them unconditionally and APIM validates fragment IDs at
policy-save time.

The stack builds the backend config in `local.llm_backend_config`: by default
one backend per Foundry account of `stacks/platform`, with its models read
from the account's deployments (`azapi_resource_list`), plus
`var.extra_llm_backends`. A non-empty `var.llm_backend_config` replaces the
derived list.

| Fragment | Source XML | Placeholder | Injected content |
|---|---|---|---|
| `set-backend-pools` | `frag-set-backend-pools.xml` | `//{backendPoolsCode}` | C# `JObject` literals for every pool in `local.all_pools` |
| `get-available-models` | `frag-get-available-models.xml` | `//{modelDeploymentsCode}` | C# `JObject` literals for every model across all backends **plus an alias deployment entry per `var.model_aliases`** |
| `metadata-config` | `frag-metadata-config.xml` | `//{modelsConfigCode}` / `//{modelAliasesCode}` | JSON mapping `model → {pool, apiVersion, timeout}` + alias-to-model mappings |
| `resolve-model-alias` | `frag-resolve-model-alias.xml` | `//{inlineAliasesCode}` | C# alias→underlying-model lookup generated from `var.model_aliases` (own resource `azurerm_api_management_policy_fragment.resolve_model_alias`, always created) |

The generators live in `locals { … }` blocks in
[modules/llm-routing/main.tf](modules/llm-routing/main.tf), which also
creates the LLM backends (`azapi_resource.llm_backend`) and backend pools
(`azapi_resource.llm_backend_pool`):

- `local.backend_pools_code` iterates `local.all_pools` (derived in the
  same file by grouping `var.llm_backend_config` by supported model).
- `local.model_deployments_code` iterates a flattened list of all models
  across all backends.
- `local.metadata_models_code` produces a `model → pool` lookup using the
  first backend that advertises support for each model.

Each `replace(file(...), "//{placeholder}", local.generated)` produces the
final XML string stored in `local.set_backend_pools_xml`,
`local.get_available_models_xml`, and `local.metadata_config_xml`, which is
what `azurerm_api_management_policy_fragment.{set_backend_pools,
get_available_models, metadata_config}` upload.

### 3.3 Named values (variables fragments consume)

Named values are APIM's `{{key}}` substitutions. They must exist before any
policy or fragment that references them. Each one has a single owner:

| Named value | File | Populated from |
|---|---|---|
| `uami-client-id` | [stacks/gateway-config/named-values.tf](stacks/gateway-config/named-values.tf) | Client ID of the APIM user-assigned identity of `stacks/platform` (looked up by name) |
| `piiServiceUrl` | [stacks/gateway-config/named-values.tf](stacks/gateway-config/named-values.tf) | Endpoint of the primary Foundry account (only with `features.pii_redaction`) |
| `contentSafetyServiceUrl` | [stacks/gateway-config/named-values.tf](stacks/gateway-config/named-values.tf) | Endpoint of the primary Foundry account (only with `features.content_safety`) |
| `tenant-id`, `client-id`, `audience`, `entra-auth` | [stacks/gateway-config/named-values.tf](stacks/gateway-config/named-values.tf) | With `entra_auth.enabled`: `entra_auth.*`, or the gateway app of `stacks/identity` looked up by name when no explicit IDs are set. Otherwise safe placeholders, and `entra-auth = "false"` |
| `JWT-TenantId`, `JWT-AppRegistrationId`, `JWT-Issuer`, `JWT-OpenIdConfigUrl` | [stacks/gateway-config/named-values.tf](stacks/gateway-config/named-values.tf) | Derived from the same Entra values and `entra_auth.login_endpoint`, or `not-configured` |
| `aws-access-key`, `aws-secret-key`, `aws-region` | [stacks/llm-backend-onboarding/named-values.tf](stacks/llm-backend-onboarding/named-values.tf) | Key Vault references from `aws.access_key_secret_uri` / `aws.secret_key_secret_uri` and `aws.region`, otherwise non-secret `NOT_CONFIGURED` placeholders. Always created so the `set-backend-authorization` fragment compiles without an AWS Bedrock backend |
| `backend_api_key` (per-backend) | [stacks/llm-backend-onboarding/named-values.tf](stacks/llm-backend-onboarding/named-values.tf) | One per backend whose `auth_config.named_value_key` is set; a secret Key Vault reference when `key_vault_secret_uri` is supplied, otherwise an explicit `secret_value` (testing only, non-compliant; a `check` warns) or a non-secret `NOT_CONFIGURED` placeholder |

The gateway-config values are one resource,
`azurerm_api_management_named_value.plain`, with `for_each` over
`local.plain_named_values`.

Secret named values are only ever created as Key Vault references (resolved
via the APIM user-assigned identity) to satisfy the Azure Policy *API
Management secret named values should be stored in Azure Key Vault*; the
sole exception is the testing-only `backend_api_key` `secret_value` path.

Every fragment depends on the named values of its own stack
(`depends_on_ids`) so APIM can resolve `{{…}}` tokens at fragment-create time.

---

## 4. Policy scopes in this repo

### 4.1 API-level policies

Each API is one entry in an API catalogue and is deployed by the generic
[modules/gateway-api](modules/gateway-api/README.md) module:

* Service APIs: [stacks/gateway-config/apis.tf](stacks/gateway-config/apis.tf)
  (`local.first_wave_raw` → `module.api["<name>"]`, plus
  `local.second_wave_raw` → `module.api_dependent["<name>"]` for APIs that must
  be created after another API or backend).
* LLM APIs: [stacks/llm-backend-onboarding/apis.tf](stacks/llm-backend-onboarding/apis.tf)
  (`local.llm_apis_raw` → `module.llm_api["<name>"]`).

Each API loads a full policy document from the stack's `apis/<api>/` folder
and wires in behavior by `<include-fragment>`ing the fragments above. Only
APIs whose `features.*` flag is on are in the catalogue.

| API (catalogue key) | Policy XML | Uses fragments |
|---|---|---|
| `universal-llm-api` (`module.llm_api`) | [universal-llm-api-policy-v2.xml](stacks/llm-backend-onboarding/apis/universal-llm-api/universal-llm-api-policy-v2.xml) | `security-handler`, `set-llm-requested-model`, `responses-id-security`, `validate-model-access`, `resolve-model-alias`, `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `strip-backend-headers`, `set-llm-usage`, `ai-foundry-compatibility`, `responses-id-cache-store`, `set-response-headers`, `raise-throttling-events` |
| `azure-openai-api` (`module.llm_api`) | [azure-open-ai-api-policy.xml](stacks/llm-backend-onboarding/apis/azure-openai-api/azure-open-ai-api-policy.xml) | `security-handler`, `set-llm-requested-model`, `responses-id-security`, `validate-model-access`, `resolve-model-alias`, `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `strip-backend-headers`, `set-llm-usage`, `responses-id-cache-store`, `set-response-headers`, `raise-throttling-events` |
| `unified-ai-api` (`module.llm_api`) | [unified-ai-api-policy.xml](stacks/llm-backend-onboarding/apis/unified-ai-api/unified-ai-api-policy.xml) | `security-handler`, `metadata-config`, `central-cache-manager`, `request-processor`, `responses-id-security`, `validate-model-access`, `resolve-model-alias`, `path-builder`, `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `strip-backend-headers`, `set-llm-usage`, `ai-foundry-compatibility`, `responses-id-cache-store`, `set-response-headers`, `raise-throttling-events` |
| `ai-model-inference-api` (`module.llm_api`) | [ai-model-inference-api-policy.xml](stacks/llm-backend-onboarding/apis/ai-model-inference-api/ai-model-inference-api-policy.xml) | None |
| `openai-realtime-ws-api` (`module.llm_api`, `type = "websocket"`) | [openai-realtime-policy.xml](stacks/llm-backend-onboarding/apis/openai-realtime-ws-api/openai-realtime-policy.xml) — **not attached**: WebSocket APIs don't accept an API-scope policy (it belongs on the upgraded WebSocket operation) | WebSocket auth only |
| `azure-ai-search-index-api` (`module.api`) | [ai-search-index-api-policy.xml](stacks/gateway-config/apis/azure-ai-search-index-api/ai-search-index-api-policy.xml) | None (managed-identity auth via `{{uami-client-id}}`) |
| `document-intelligence-api-legacy` (`module.api`) + `document-intelligence-api` (`module.api_dependent`) | [doc-intelligence-api-policy.xml](stacks/gateway-config/apis/document-intelligence-api/doc-intelligence-api-policy.xml) | None |
| `weather-api` (`module.api`) | [policy.xml](stacks/gateway-config/apis/weather-api/policy.xml) | None (sample) |
| `weather-mcp` + `ms-learn-mcp` (`module.api_dependent`, `type = "mcp"`) | [mcp-default-policy.xml](stacks/gateway-config/apis/shared/mcp-default-policy.xml) | MCP default auth |

`universal-llm-api`, `azure-openai-api` and `openai-realtime-ws-api` set
`subscription_required` from gateway-config's `entra-auth` named value, read
with `data "azapi_resource" "entra_auth"`: with Entra auth on they take a JWT
instead of a subscription key. `unified-ai-api` and `ai-model-inference-api`
always require a subscription.

Every API instance receives:

```hcl
policy_depends_on = local.api_policy_depends_on
# gateway-config:          concat(values(module.shared_fragments.ids),
#                                 [for nv in azurerm_api_management_named_value.plain : nv.id])
# llm-backend-onboarding:  concat(values(module.llm_fragments.ids),
#                                 values(module.llm_routing.fragment_ids))
```

so APIM finds every `<include-fragment>` target and named value at validation
time. Fragments, named values and loggers owned by an earlier stack already
exist because of the apply order.

### 4.2 Operation-level policies

Declared per catalogue entry in
[stacks/llm-backend-onboarding/apis.tf](stacks/llm-backend-onboarding/apis.tf)
(`operation_policies` / `azapi_operation_policies`) and applied by
[modules/gateway-api](modules/gateway-api/README.md). Policies shared by
several APIs live in
[stacks/llm-backend-onboarding/apis/shared/](stacks/llm-backend-onboarding/apis/shared/).

| Operation | API | Policy XML |
|---|---|---|
| `deployments` (GET `/deployments`) | `universal-llm-api` | [universal-llm-api-deployments-policy.xml](stacks/llm-backend-onboarding/apis/shared/universal-llm-api-deployments-policy.xml) |
| `deployment-by-name` (GET `/deployments/{id}`) | `universal-llm-api` | [universal-llm-api-deployment-by-name-policy.xml](stacks/llm-backend-onboarding/apis/shared/universal-llm-api-deployment-by-name-policy.xml) |
| `listModels` / `retrieveModel` (only when `inference_api_type = "OpenAIV1"`) | `universal-llm-api` | Same two files as above |
| `deployments` (GET `/deployments`) | `azure-openai-api` | [universal-llm-api-deployments-policy.xml](stacks/llm-backend-onboarding/apis/shared/universal-llm-api-deployments-policy.xml) |
| `deployment-by-name` (GET `/deployments/{id}/info`) | `azure-openai-api` | [universal-llm-api-deployment-by-name-policy.xml](stacks/llm-backend-onboarding/apis/shared/universal-llm-api-deployment-by-name-policy.xml) |
| `deployments` + `deployment-by-name` (unified-AI, via azapi) | `unified-ai-api` | [unified-ai-api-deployments-policy.xml](stacks/llm-backend-onboarding/apis/unified-ai-api/unified-ai-api-deployments-policy.xml), [unified-ai-api-deployment-by-name-policy.xml](stacks/llm-backend-onboarding/apis/unified-ai-api/unified-ai-api-deployment-by-name-policy.xml) |

The `deployments` / `deployment-by-name` operation policies
`<include-fragment fragment-id="get-available-models" />`. On
`universal-llm-api` and `azure-openai-api` they are **gated** on
`local.has_llm_backends` (`length(local.llm_backend_config) > 0`) —
if no LLM backends are configured these operation policies aren't attached.

### 4.3 Product-level policies

| Product | Policy XML | Where |
|---|---|---|
| `unified-ai-product` | [unified-ai-product-subscription.xml](stacks/llm-backend-onboarding/apis/unified-ai-api/unified-ai-product-subscription.xml) | `product` attribute of the `unified-ai-api` entry in [stacks/llm-backend-onboarding/apis.tf](stacks/llm-backend-onboarding/apis.tf) (created by [modules/gateway-api](modules/gateway-api/README.md)) |
| Per-use-case access-contract products | Per-service `policy_xml`, or [modules/access-contract/policies/default-ai-product-policy.xml](modules/access-contract/policies/default-ai-product-policy.xml) when blank | [modules/access-contract/main.tf](modules/access-contract/main.tf), called from [stacks/access-contracts/main.tf](stacks/access-contracts/main.tf) |

There is no built-in default product: a general-purpose product (formerly
`default-ai-access`) or a Foundry → gateway connection is an access contract
like any other use case.

Access-contract product policies set context variables (e.g. the
`allowedModels` set-variable and `enableResponseHeaders`) and include the
`set-llm-requested-model` fragment; the API policies then apply them through
`validate-model-access` and `set-response-headers`. The default policy also
sets a per-subscription `llm-token-limit`. See [§9.1](#91-access-contracts).

---

## 5. End-to-end request flow (Universal LLM API)

What happens at runtime when a client calls
`POST /models/chat/completions`:

```text
1. APIM matches request → universal-llm-api (policy: universal-llm-api-policy-v2.xml)

2. inbound {
     <base/>                                  // inherits global + product policy
     <include-fragment id="security-handler"/>       // API-key + optional JWT
     <include-fragment id="set-llm-requested-model"/> // reads body.model
     <include-fragment id="responses-id-security"/>  // Responses API ownership check
     <set-variable name="allowedBackendPools" .../>   // per-instance RBAC
     <set-variable name="defaultBackendPool" .../>
     <include-fragment id="validate-model-access"/>  // enforces contract allowedModels
     <include-fragment id="resolve-model-alias"/>    // DYNAMIC: alias → underlying model
     <include-fragment id="set-backend-pools"/>      // DYNAMIC: injects pool defs from the backend config
     <include-fragment id="set-target-backend-pool"/> // picks pool for requested model
     <include-fragment id="set-backend-authorization"/> // MI token, key, or OAuth
     <include-fragment id="strip-backend-headers"/>  // drops browser / ARR / X-Forwarded-* headers
     <include-fragment id="set-llm-usage"/>          // captures token usage for EH
     <include-fragment id="ai-foundry-compatibility"/> // CORS
   }

3. backend {
     <retry count="2" condition="...">              // retries 429 + 5xx (not pool-exhausted)
       <forward-request buffer-request-body="true"/>
     </retry>
   }

4. outbound {
     <base/>
     <include-fragment id="responses-id-cache-store"/> // records Responses API ownership
     <include-fragment id="set-response-headers"/>   // UAIG-* diagnostic headers
   }

5. on-error {
     <base/>
     <include-fragment id="raise-throttling-events"/> // pushes 429 metrics to Monitor
     <include-fragment id="set-response-headers"/>
   }
```

The dynamic fragments (`set-backend-pools`, `get-available-models`,
`resolve-model-alias`) are what make this pipeline generic — re-apply
llm-backend-onboarding with new Foundry deployments or a new backend config
and the routing logic updates without touching any XML.

---

## 6. Apply-time ordering (why `depends_on` matters)

`task up ENV=<env>` applies the stacks in order (identity, network,
app-hosting, platform, gateway-config, llm-backend-onboarding, then every
access contract). Across the APIM pieces that gives roughly this order:

```text
stacks/platform
1. module.apim              APIM service (AVM)
2. module.apim_telemetry    Loggers (App Insights, Azure Monitor, Event Hub, PII Event Hub) + global diagnostics

stacks/gateway-config
3. azurerm_api_management_named_value.plain   (uami, tenant/client/audience, entra-auth, JWT-*, pii, content-safety)
4. module.shared_fragments  azurerm_api_management_policy_fragment.this   (catalogue, for_each)
                            azapi_resource.this                            (PII, when enabled)
   Non-LLM backends         content-safety-backend / ai_search / embeddings-backend / ms-learn-mcp-backend
5. module.api[*]            API + API policy + operation policies + diagnostics (+ optional product)
6. module.api_dependent[*]  Second wave (document-intelligence-api, weather-mcp, ms-learn-mcp)

stacks/llm-backend-onboarding
7. aws-* + backend_api_key named values
8. module.llm_fragments     LLM static fragments
   module.llm_routing       llm_backend / llm_backend_pool + set_backend_pools / get_available_models /
                            metadata_config / resolve_model_alias
9. module.llm_api[*]        API + API policy + operation policies   ← validates <include-fragment> + {{named-value}}
                            API diagnostics                         ← validates logger IDs
                            Optional product + product policy + product-API link

stacks/access-contracts (one state per use case)
10. module.contract         products + product policies + product-API links + subscriptions
                            (+ Key Vault secrets / Foundry connection)
```

If you ever see a 400 at apply time like
*"Policy reference is not resolved: The fragment 'xxx' cannot be found"* or
*"Named value 'yyy' is not defined"*, check two things: that the stack that
owns it was applied first (e.g. gateway-config before llm-backend-onboarding),
and, inside a stack, that the missing entry is in `local.api_policy_depends_on`
in the stack's `apis.tf` (or in `depends_on_ids` of the fragments module for a
named value referenced by a fragment) — the graph doesn't know about
`<include-fragment>` text inside an XML file.

---

## 7. Feature-flag matrix

| Variable | Effect on fragments | Effect on policies |
|---|---|---|
| llm `features.unified_ai_api` | Creates 3 unified-AI fragments (`central-cache-manager`, `request-processor`, `path-builder`) | Creates unified-AI API + its policy + 2 op policies + product + product policy |
| gateway-config `features.pii_anonymization` | Creates 3 PII fragments via `azapi_resource.this` in `module.shared_fragments` | No direct policy; referenced from universal-llm + unified-ai |
| gateway-config `features.pii_redaction` | — | Creates the `piiServiceUrl` named value (the `pii-usage-eventhub-logger` is always created by `module.apim_telemetry` in the platform; Language service auth uses the APIM managed identity) |
| gateway-config `features.content_safety` | — | Creates `contentSafetyServiceUrl` named value + content-safety backend |
| gateway-config `entra_auth.enabled` | — | Populates `tenant-id`, `client-id`, `audience`, `entra-auth` and the 4 JWT-* named values (else placeholders); the LLM APIs then don't require a subscription key |
| gateway-config `features.azure_ai_search` | — | Creates `azure-ai-search-index-api` + its policy + `ai_search` backends |
| gateway-config `features.document_intelligence` | — | Creates two document intelligence APIs + policies |
| llm `features.ai_model_inference` | — | Creates `ai-model-inference-api` + policy |
| llm `features.openai_realtime` | — | Creates the WebSocket API via azapi (no API-scope policy) |
| gateway-config `features.mcp_sample` | — | Creates weather-api + weather-mcp + ms-learn-mcp + 3 policies |
| `length(local.llm_backend_config) > 0` (llm) | Dynamic fragments carry real pool/model data (they are always created) | Enables the `deployments` / `deployment-by-name` operation policies on universal-llm / azure-openai |
| `length(var.model_aliases) > 0` (llm) | Injects alias deployments into `get-available-models` / `metadata-config` and populates `resolve-model-alias` | Aliases resolve to underlying models at request time |
| Access contract (`environments/<env>/access-contracts/<use-case>.tfvars`: `services` + `use_case`) | — | Creates per-use-case products + product-API links + subscription + policy (+ optional KV secrets / Foundry connection) against the existing APIM |

---

## 8. Where to change things

| Task | Edit this file |
|---|---|
| Add a new reusable policy snippet | Model-agnostic: add `frag-<name>.xml` to [stacks/gateway-config/fragments/](stacks/gateway-config/fragments/) and a `"<name>" = "<description>"` entry to `local.shared_fragments` (or the feature-gated `local.pii_fragments`) in [stacks/gateway-config/fragments.tf](stacks/gateway-config/fragments.tf). Model-aware: same in [stacks/llm-backend-onboarding/fragments/](stacks/llm-backend-onboarding/fragments/) and `local.llm_fragments` in [stacks/llm-backend-onboarding/fragments.tf](stacks/llm-backend-onboarding/fragments.tf). If an LLM policy needs a new shared fragment, also add it to `local.required_shared_fragments` there |
| Change which fragments an API uses | Edit the API's policy XML (e.g. [universal-llm-api-policy-v2.xml](stacks/llm-backend-onboarding/apis/universal-llm-api/universal-llm-api-policy-v2.xml)); no Terraform changes needed |
| Add a new service API with its own policy | Put the spec + policy XML under `stacks/gateway-config/apis/<api>/` and add an entry to `local.first_wave_raw` in [stacks/gateway-config/apis.tf](stacks/gateway-config/apis.tf), or `local.second_wave_raw` if it must be created after another API/backend (set `api_depends_on`). [modules/gateway-api](modules/gateway-api/README.md) creates the API, policies, diagnostics and optional product; fragment/named-value dependencies are already wired via `local.api_policy_depends_on` |
| Add a new LLM API | Same, under `stacks/llm-backend-onboarding/apis/<api>/` and `local.llm_apis_raw` in [stacks/llm-backend-onboarding/apis.tf](stacks/llm-backend-onboarding/apis.tf) |
| Add a new named value | Model-agnostic: add a key to `local.plain_named_values` in [stacks/gateway-config/named-values.tf](stacks/gateway-config/named-values.tf) (already in `depends_on_ids` / `api_policy_depends_on`). Backend credentials: add a resource in [stacks/llm-backend-onboarding/named-values.tf](stacks/llm-backend-onboarding/named-values.tf) and add it to `depends_on_ids` of `module.llm_fragments` |
| Change the generated routing fragments | Edit the templates in [modules/llm-routing/templates/](modules/llm-routing/templates/) or the generator `locals` in [modules/llm-routing/main.tf](modules/llm-routing/main.tf) |
| Add a new backend pool routing rule | Add the model to `foundry.models` in `platform.tfvars` and re-apply platform, then llm-backend-onboarding; or add to `extra_llm_backends` / `llm_backend_config` in `environments/<env>/llm-backend-onboarding.tfvars` — dynamic fragments regenerate automatically |
| Add a per-use-case access contract | Add `environments/<env>/access-contracts/<use-case>.tfvars` with `use_case`, `services` and `api_name_mapping`, then run `task contract ENV=<env> USE_CASE=<use-case>` (no XML edits unless you need custom per-service `policy_xml`) |
| Onboard an LLM backend to a live APIM | Edit `environments/<env>/llm-backend-onboarding.tfvars` and run `task apply STACK=llm-backend-onboarding ENV=<env>` |

---

## 9. Onboarding stacks

`stacks/access-contracts` and `stacks/llm-backend-onboarding` target the
**already-running** APIM of `stacks/platform` via `data` sources (no APIM
creation). They are part of `task up ENV=<env>` and can also be applied on
their own for day-2 onboarding.

### 9.1 Access contracts

[stacks/access-contracts/main.tf](stacks/access-contracts/main.tf) onboards a
single use case per state (`environments/<env>/access-contracts/<use-case>.tfvars`,
applied with `task contract`) by calling
[modules/access-contract](modules/access-contract/main.tf). Inputs are
`var.use_case` (`{ business_unit, use_case_name, environment }`),
`var.api_name_mapping` (service code → existing APIM API names), and
`var.services` (list of `{ code, endpoint_secret_name, api_key_secret_name,
policy_xml }`). Per service `code` it creates:

- An APIM product `<code>-<business_unit>-<use_case_name>-<environment>`.
- Product→API links from `var.api_name_mapping[code]`.
- A product policy (`policy_xml`, else `policies/default-ai-product-policy.xml`).
- A subscription `<…>-SUB-01`, created with `azapi_resource` so the keys never
  enter state. The key is read through an ephemeral `azapi_resource_action`
  (`listSecrets`) and written only to write-only arguments.
- Optional Key Vault secrets for the endpoint + key (`var.key_vault`; the key
  via `value_wo`; secret names lower-cased, `_`→`-`, rotated every
  `secret_rotation_days`).
- An optional Foundry connection (`var.foundry`) via
  `azapi_resource.foundry_connection`, type
  `Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01`
  (auth `ApiKey`, key via `sensitive_body`, metadata from `var.foundry_config`).

### 9.2 LLM backend onboarding

[stacks/llm-backend-onboarding](stacks/llm-backend-onboarding/) registers LLM
backends, routing and the LLM APIs against the existing APIM
(`data.azurerm_api_management.this`). It creates:

- Through `module.llm_routing` ([backends.tf](stacks/llm-backend-onboarding/backends.tf)):
  `azapi_resource.llm_backend` (`Microsoft.ApiManagement/service/backends@2024-06-01-preview`)
  per backend, with circuit-breaker rules gated on `var.configure_circuit_breaker`,
  `<model>-backend-pool`s for any model served by 2+ backends, and the 3 dynamic
  fragments (`set-backend-pools`, `get-available-models`, `metadata-config`)
  plus `resolve-model-alias`, all with `var.model_aliases` support. Backends
  are derived from the Foundry deployments unless `var.llm_backend_config` is set.
- The model-aware static fragments of `module.llm_fragments` (§3.1).
- Named values `aws-access-key` / `aws-secret-key` / `aws-region` and a
  per-backend `backend_api_key` named value (§3.3). This stack is their only
  owner.
- The LLM APIs of `module.llm_api` (§4.1) and their API Center registration.
