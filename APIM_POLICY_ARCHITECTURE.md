# AI Citadel Governance Hub - APIM Policy Architecture — Terraform

> **Scope:** How every API Management policy, fragment, and named value in
> this repo is modeled, wired up, and applied at runtime. Covers the core
> inference APIs (`universal-llm-api`, `azure-openai-api`), the wildcard
> `unified-ai-api`, operation-level policies, product-level policies
> (including the `citadel-access-contracts` add-on), and the MCP sample APIs.
>
> **Related files:**
> [policy-fragments.tf](policy-fragments.tf) ·
> [apis.tf](apis.tf) ·
> [modules/apim-policy-fragments/](modules/apim-policy-fragments/README.md) ·
> [modules/llm-routing/main.tf](modules/llm-routing/main.tf) ·
> [modules/gateway-api/](modules/gateway-api/README.md) ·
> [modules/apim-telemetry/](modules/apim-telemetry/README.md) ·
> [modules/apim/main.tf](modules/apim/main.tf) ·
> [modules/apim/named-values-extras.tf](modules/apim/named-values-extras.tf) ·
> [modules/apim/backends.tf](modules/apim/backends.tf) ·
> [citadel-access-contracts/main.tf](citadel-access-contracts/main.tf) ·
> [llm-backend-onboarding/main.tf](llm-backend-onboarding/main.tf)
>
> The two standalone root modules `citadel-access-contracts/` and
> `llm-backend-onboarding/` apply the same product/fragment/named-value
> model against an **already-deployed** APIM (via `data` sources) for
> day-2 onboarding. See [§9](#9-standalone-onboarding-modules).

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
must exist **before** any policy that references them. Terraform enforces
this via `depends_on`.

---

## 2. How `.tf` files become a module

Terraform automatically loads **every `.tf` file in a module directory** and
merges them into one configuration — there is no `include` or `import`
directive, and file names are purely organizational. The APIM policy model
is split across the root module and several focused child modules:

```
<repo root>/
  policy-fragments.tf          # Fragment catalogue (static, unified-AI, PII) → module "policy_fragments"
  apis.tf                      # API catalogue (gateway_apis_raw / dependent_apis_raw) → module "api" / "api_dependent"
  api-center-registration.tf   # API Center registration of the enabled APIs (optional)
  main.tf                      # module "apim", "apim_telemetry", "llm_routing", ... calls
  policies/fragments/          # frag-*.xml bodies of the catalogue fragments
  apis/<api>/                  # Per-API OpenAPI specs + policy XML (apis/shared/ = shared operation/MCP policies)

modules/
  apim/                        # APIM service, PE, named values, non-LLM backends, default product, Foundry subscription
    main.tf                    #   service, private endpoint, public-access flip, core named values, default product, Redis cache
    named-values-extras.tf     #   JWT-* and aws-* named values
    backends.tf                #   content safety, AI search, embeddings, ms-learn MCP backends
    foundry-subscription.tf    #   dedicated APIM subscription for Foundry (optional)
    internal-dns.tf            #   internal-mode DNS records
  apim-policy-fragments/       # Generic: deploys a map of fragments (azurerm, or azapi for the PII set)
  llm-routing/                 # LLM backends, backend pools + the 4 generated routing fragments
    templates/                 #   frag-set-backend-pools.xml, frag-get-available-models.xml, ...
  gateway-api/                 # Generic API: http / websocket / mcp, operation policies, diagnostics, optional product
  apim-telemetry/              # APIM loggers (App Insights, Azure Monitor, Event Hub) + global diagnostics
```

These pieces plug into the dependency graph via:

1. **Module outputs** — e.g. `local.all_pools` is computed inside
   [modules/llm-routing](modules/llm-routing/main.tf) from
   `var.llm_backend_config` and consumed there by `local.backend_pools_code`;
   `module.apim.apim_id` feeds every fragment / API module's
   `api_management_id`.
2. **Explicit dependency lists** — `module.policy_fragments` receives
   `depends_on_ids = module.apim.named_value_ids`, and every API created
   through [modules/gateway-api](modules/gateway-api/README.md) receives
   `policy_depends_on = local.api_policy_depends_on` (all fragment IDs from
   `module.policy_fragments` + `module.llm_routing`, the named values, and
   the `module.apim_telemetry` loggers) so APIM's server-side validation
   finds every `<include-fragment>`, `{{named-value}}` and logger reference.

---

## 3. Fragments (the reusable building blocks)

The reusable fragments are catalogued in the root
[policy-fragments.tf](policy-fragments.tf) and deployed by
[modules/apim-policy-fragments](modules/apim-policy-fragments/README.md);
their XML bodies live in [policies/fragments/](policies/fragments/)
prefixed with `frag-` (a single copy, also read by
[llm-backend-onboarding/](llm-backend-onboarding/)). The generated routing
fragments are owned by [modules/llm-routing](modules/llm-routing/main.tf).
There are three kinds.

### 3.1 Static fragments (unconditional)

Mirrored from Bicep's `policy-fragments.bicep`. Declared as a catalogue map
(`name → { description, file }`) and passed to the generic fragments module,
which creates them with `for_each`:

```hcl
module "policy_fragments" {
  source            = "./modules/apim-policy-fragments"
  api_management_id = module.apim.apim_id

  fragments = {
    for k, f in local.all_static_fragments : k => {
      xml         = file("${local.fragments_dir}/${f.file}")   # policies/fragments/
      description = f.description
    }
  }
  azapi_fragments = { /* local.pii_fragments, same shape */ }

  depends_on_ids = module.apim.named_value_ids
}
```

The map `local.all_static_fragments = merge(local.static_fragments, local.unified_ai_fragments)`:

| Sub-map | Always on? | Fragment IDs |
|---|---|---|
| `static_fragments` | Yes | `set-backend-authorization`, `set-target-backend-pool`, `set-llm-usage`, `set-llm-requested-model`, `validate-model-access`, `ai-usage`, `raise-throttling-events`, `throttling-events`, `security-handler`, `entra-auth`, `aad-auth`, `aad-auth-custom`, `ai-foundry-deployments`, `llm-usage`, `openai-usage`, `openai-usage-streaming`, `ai-foundry-compatibility`, `set-response-headers`, `responses-id-security`, `responses-id-cache-store`, `strip-backend-headers` |
| `unified_ai_fragments` | `features.unified_ai_api = true` | `central-cache-manager`, `request-processor`, `path-builder` |

> **PII fragments are not part of this `for_each` merge.** The
> `pii-anonymization` / `pii-deanonymization` / `pii-state-saving`
> fragments (`local.pii_fragments`, gated on `features.pii_anonymization`)
> are passed as `azapi_fragments` and created by
> `azapi_resource.this` in
> [modules/apim-policy-fragments](modules/apim-policy-fragments/main.tf)
> (a direct idempotent PUT) because the `azurerm` fragment resource hit an
> LRO polling bug (404 *PolicyFragment not found* during `CreateOrUpdate`).

> **`responses-id-security` / `responses-id-cache-store`** enforce
> per-subscription ownership of Responses API objects; **`strip-backend-headers`**
> removes browser / App Service (ARR) / `X-Forwarded-*` headers before the
> request is forwarded to an AI backend.

### 3.2 Dynamic fragments (computed from `var.llm_backend_config` + `var.model_aliases`)

Mirrored from Bicep's `llm-policy-fragments.bicep`. Owned by
[modules/llm-routing](modules/llm-routing/README.md) (called as
`module "llm_routing"` from the root [main.tf](main.tf)). Each one takes a
placeholder-based XML template from
[modules/llm-routing/templates/](modules/llm-routing/templates/) and injects
generated code into it at plan time via `replace()`. They are **always
created** (even when `llm_backend_config` is empty) because the core API
policies reference them unconditionally and APIM validates fragment IDs at
policy-save time.

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
policy or fragment that references them. Declared in two files:

| Named value | File | Populated from |
|---|---|---|
| `uami-client-id` | [main.tf](modules/apim/main.tf) | `var.managed_identity_client_id` |
| `piiServiceUrl` | [main.tf](modules/apim/main.tf) | `var.pii_service_endpoint` (count-gated on PII) |
| `contentSafetyServiceUrl` | [main.tf](modules/apim/main.tf) | `var.content_safety_endpoint` (count-gated on content safety) |
| `tenant-id`, `client-id`, `audience`, `entra-auth` | [main.tf](modules/apim/main.tf) | `var.entra_*` with safe placeholder fallbacks |
| `JWT-TenantId`, `JWT-AppRegistrationId`, `JWT-Issuer`, `JWT-OpenIdConfigUrl` | [named-values-extras.tf](modules/apim/named-values-extras.tf) | `var.jwt_*` or `not-configured` |
| `aws-access-key`, `aws-secret-key`, `aws-region` | [named-values-extras.tf](modules/apim/named-values-extras.tf) | Non-secret `NOT_CONFIGURED` placeholders — always created so the `set-backend-authorization` fragment compiles even without an AWS Bedrock backend. `lifecycle.ignore_changes` lets [llm-backend-onboarding](llm-backend-onboarding/main.tf) own the real values (Key Vault references) |
| `backend_api_key` (per-backend) | [llm-backend-onboarding/main.tf](llm-backend-onboarding/main.tf) | One per backend whose `auth_config.named_value_key` is set; a secret Key Vault reference when `key_vault_secret_uri` is supplied, otherwise an explicit `secret_value` (testing only, non-compliant) or a non-secret `NOT_CONFIGURED` placeholder |

Secret named values are only ever created as Key Vault references (resolved
via the APIM user-assigned identity) to satisfy the Azure Policy *API
Management secret named values should be stored in Azure Key Vault*; the
sole exception is the testing-only `backend_api_key` `secret_value` path.

Every catalogue fragment depends on **all** named values above
(`module.apim.named_value_ids` → `depends_on_ids`) so APIM can resolve
`{{…}}` tokens at fragment-create time.

---

## 4. Policy scopes in this repo

### 4.1 API-level policies

Each API is one entry in the API catalogue in [apis.tf](apis.tf)
(`local.gateway_apis_raw`, plus `local.dependent_apis_raw` for APIs that must
be created after another API or backend) and is deployed by the generic
[modules/gateway-api](modules/gateway-api/README.md) module
(`module.api["<name>"]` / `module.api_dependent["<name>"]`). Each API loads a
full policy document from `apis/<api>/` and wires in behavior by
`<include-fragment>`ing the fragments above. Only APIs whose `features.*`
flag is on are in the catalogue.

| API (catalogue key) | Policy XML | Uses fragments |
|---|---|---|
| `universal-llm-api` (`module.api`) | [apis/universal-llm-api/universal-llm-api-policy-v2.xml](apis/universal-llm-api/universal-llm-api-policy-v2.xml) | `security-handler`, `set-llm-requested-model`, `validate-model-access`, `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `set-llm-usage`, `ai-foundry-compatibility`, `set-response-headers`, `raise-throttling-events` |
| `azure-openai-api` (`module.api`) | [apis/azure-openai-api/azure-open-ai-api-policy.xml](apis/azure-openai-api/azure-open-ai-api-policy.xml) | `security-handler`, `set-llm-requested-model`, `validate-model-access`, `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `set-llm-usage`, `set-response-headers`, `raise-throttling-events` |
| `unified-ai-api` (`module.api`) | [apis/unified-ai-api/unified-ai-api-policy.xml](apis/unified-ai-api/unified-ai-api-policy.xml) | `security-handler`, `central-cache-manager`, `request-processor`, `path-builder`, `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `set-response-headers` |
| `azure-ai-search-index-api` (`module.api`) | [apis/azure-ai-search-index-api/ai-search-index-api-policy.xml](apis/azure-ai-search-index-api/ai-search-index-api-policy.xml) | `security-handler`, `ai-usage` |
| `document-intelligence-api-legacy` (`module.api`) + `document-intelligence-api` (`module.api_dependent`) | [apis/document-intelligence-api/doc-intelligence-api-policy.xml](apis/document-intelligence-api/doc-intelligence-api-policy.xml) | `security-handler`, `ai-usage` |
| `ai-model-inference-api` (`module.api`) | [apis/ai-model-inference-api/ai-model-inference-api-policy.xml](apis/ai-model-inference-api/ai-model-inference-api-policy.xml) | `security-handler`, `ai-usage` |
| `openai-realtime-ws-api` (`module.api`, `type = "websocket"`) | [apis/openai-realtime-ws-api/openai-realtime-policy.xml](apis/openai-realtime-ws-api/openai-realtime-policy.xml) — **not attached**: WebSocket APIs don't accept an API-scope policy (it belongs on the upgraded WebSocket operation) | WebSocket auth only |
| `weather-api` (`module.api`) | [apis/weather-api/policy.xml](apis/weather-api/policy.xml) | None (sample) |
| `weather-mcp` + `ms-learn-mcp` (`module.api_dependent`, `type = "mcp"`) | [apis/shared/mcp-default-policy.xml](apis/shared/mcp-default-policy.xml) | MCP default auth |

Every API instance receives:

```hcl
policy_depends_on = local.api_policy_depends_on   # apis.tf
# = concat(values(module.policy_fragments.ids),
#          values(module.llm_routing.fragment_ids),
#          module.apim.named_value_ids,
#          module.apim_telemetry.dependency_ids)
```

so APIM finds every `<include-fragment>` target, named value and logger at
validation time.

### 4.2 Operation-level policies

Declared per catalogue entry in [apis.tf](apis.tf) (`operation_policies` /
`azapi_operation_policies`) and applied by
[modules/gateway-api](modules/gateway-api/README.md). Policies shared by
several APIs live in [apis/shared/](apis/shared/).

| Operation | API | Policy XML |
|---|---|---|
| `deployments` (GET `/deployments`) | `universal-llm-api` | [apis/shared/universal-llm-api-deployments-policy.xml](apis/shared/universal-llm-api-deployments-policy.xml) |
| `deployment-by-name` (GET `/deployments/{id}`) | `universal-llm-api` | [apis/shared/universal-llm-api-deployment-by-name-policy.xml](apis/shared/universal-llm-api-deployment-by-name-policy.xml) |
| `listModels` / `retrieveModel` (only when `inference_api_type = "OpenAIV1"`) | `universal-llm-api` | Same two files as above |
| `deployments` (GET `/deployments`) | `azure-openai-api` | [apis/shared/universal-llm-api-deployments-policy.xml](apis/shared/universal-llm-api-deployments-policy.xml) |
| `deployment-by-name` (GET `/deployments/{id}/info`) | `azure-openai-api` | [apis/shared/universal-llm-api-deployment-by-name-policy.xml](apis/shared/universal-llm-api-deployment-by-name-policy.xml) |
| `deployments` + `deployment-by-name` (unified-AI, via azapi) | `unified-ai-api` | [apis/unified-ai-api/unified-ai-api-deployments-policy.xml](apis/unified-ai-api/unified-ai-api-deployments-policy.xml), [apis/unified-ai-api/unified-ai-api-deployment-by-name-policy.xml](apis/unified-ai-api/unified-ai-api-deployment-by-name-policy.xml) |

The `deployments` / `deployment-by-name` operation policies
`<include-fragment fragment-id="get-available-models" />`. On
`universal-llm-api` and `azure-openai-api` they are **gated** on
`local.has_llm_backends` (`length(local.effective_llm_backend_config) > 0`) —
if no LLM backends are configured these operation policies aren't attached.

### 4.3 Product-level policies

| Product | Policy XML | Where |
|---|---|---|
| `default-ai-access` | None (inline policy not set here) | [modules/apim/main.tf](modules/apim/main.tf) |
| `unified-ai-product` | [apis/unified-ai-api/unified-ai-product-subscription.xml](apis/unified-ai-api/unified-ai-product-subscription.xml) | `product` attribute of the `unified-ai-api` entry in [apis.tf](apis.tf) (created by [modules/gateway-api](modules/gateway-api/README.md)) |
| Per-use-case access-contract products | Per-service `policy_xml`, or [citadel-access-contracts/policies/default-ai-product-policy.xml](citadel-access-contracts/policies/default-ai-product-policy.xml) when blank | [citadel-access-contracts/main.tf](citadel-access-contracts/main.tf) |

Access-contract product policies set context variables (e.g. the
`allowedModels` set-variable and `enableResponseHeaders`) and include the
`set-llm-requested-model`, `validate-model-access`, and `set-response-headers`
fragments to enforce per-product rules. See [§9.1](#91-access-contracts-onboarding).

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
     <set-variable name="allowedBackendPools" .../>   // per-instance RBAC
     <set-variable name="defaultBackendPool" .../>
     <include-fragment id="validate-model-access"/>  // enforces contract allowedModels
     <include-fragment id="set-backend-pools"/>      // DYNAMIC: injects pool defs from llm_backend_config
     <include-fragment id="set-target-backend-pool"/> // picks pool for requested model
     <include-fragment id="set-backend-authorization"/> // MI token, key, or OAuth
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
     <include-fragment id="set-response-headers"/>   // UAIG-* diagnostic headers
   }

5. on-error {
     <base/>
     <include-fragment id="raise-throttling-events"/> // pushes 429 metrics to Monitor
     <include-fragment id="set-response-headers"/>
   }
```

The two dynamic fragments (`set-backend-pools`, `get-available-models`) are
what make this pipeline generic — re-apply with a new `llm_backend_config`
and the routing logic updates without touching any XML.

---

## 6. Apply-time ordering (why `depends_on` matters)

Terraform's graph resolves to roughly this order across the APIM modules:

```text
1. module.apim          azurerm_api_management.citadel
2. module.apim          Named values (uami, pii, content-safety, entra-*, JWT-*, aws-*)
   module.apim_telemetry  Loggers (App Insights, Azure Monitor, Event Hub, PII Event Hub) + global diagnostics
3. module.policy_fragments  azurerm_api_management_policy_fragment.this   (catalogue, for_each)
                            azapi_resource.this                            (PII, when enabled)
   module.llm_routing       set_backend_pools / get_available_models / metadata_config / resolve_model_alias
4. module.llm_routing   azapi_resource.llm_backend / llm_backend_pool
   module.apim          content-safety / ai_search / embeddings / ms-learn-mcp backends
5. module.api[*]        API (azurerm_api_management_api or azapi_resource for websocket / mcp)
6. module.api[*]        API policy + operation policies   ← validates <include-fragment> + {{named-value}}
                        API diagnostics                    ← validates logger IDs
                        Optional product + product policy + product-API link
7. module.api_dependent[*]  Second wave (document-intelligence-api, weather-mcp, ms-learn-mcp)
```

If you ever see a 400 at apply time like
*"Policy reference is not resolved: The fragment 'xxx' cannot be found"* or
*"Named value 'yyy' is not defined"*, the fix is always to add the missing
entry to `local.api_policy_depends_on` in [apis.tf](apis.tf) (or to
`depends_on_ids` of `module.policy_fragments` for a named value referenced by
a fragment) — the graph doesn't know about `<include-fragment>` text inside
an XML file.

---

## 7. Feature-flag matrix

| Variable | Effect on fragments | Effect on policies |
|---|---|---|
| `features.unified_ai_api` | Creates 3 unified-AI fragments (`central-cache-manager`, `request-processor`, `path-builder`) | Creates unified-AI API + its policy + 2 op policies + product + product policy |
| `features.pii_anonymization` | Creates 3 PII fragments via `azapi_resource.this` in `module.policy_fragments` | No direct policy; referenced from universal-llm + unified-ai |
| `features.pii_redaction` | — | Creates `piiServiceUrl` named value + `pii-usage-eventhub-logger` (in `module.apim_telemetry`; Language service auth uses the APIM managed identity) |
| `features.content_safety` | — | Creates `contentSafetyServiceUrl` named value + content-safety backend |
| `enable_jwt_auth` | — | Populates 4 JWT-* named values (else placeholders) |
| `features.azure_ai_search` | — | Creates `azure-ai-search-index-api` + its policy + `ai_search` backends |
| `features.document_intelligence` | — | Creates two document intelligence APIs + policies |
| `features.ai_model_inference` | — | Creates `ai-model-inference-api` + policy |
| `features.openai_realtime` | — | Creates the WebSocket API via azapi (no API-scope policy) |
| `features.mcp_sample` | — | Creates weather-api + weather-mcp + ms-learn-mcp + 3 policies |
| `length(local.effective_llm_backend_config) > 0` | Dynamic fragments carry real pool/model data (they are always created) | Enables the `deployments` / `deployment-by-name` operation policies on universal-llm / azure-openai |
| `length(var.model_aliases) > 0` ([modules/llm-routing](modules/llm-routing/README.md) / [llm-backend-onboarding](llm-backend-onboarding/) input) | Injects alias deployments into `get-available-models` / `metadata-config` and populates `resolve-model-alias` | Aliases resolve to underlying models at request time |
| Standalone `citadel-access-contracts/` (`var.services` + `var.use_case`) | — | Creates per-use-case products + product-API links + subscription + policy (+ optional KV secrets / Foundry connection) against existing APIM |

---

## 8. Where to change things

| Task | Edit this file |
|---|---|
| Add a new reusable policy snippet (available in all APIs) | Add XML to [policies/fragments/](policies/fragments/) (`frag-<name>.xml`) + add a `name = { description, file }` entry to the catalogue (`local.static_fragments`, or the feature-gated `local.unified_ai_fragments` / `local.pii_fragments`) in [policy-fragments.tf](policy-fragments.tf) |
| Change which fragments an API uses | Edit the API's policy XML (e.g. [apis/universal-llm-api/universal-llm-api-policy-v2.xml](apis/universal-llm-api/universal-llm-api-policy-v2.xml)); no Terraform changes needed |
| Add a new API with its own policy | Put the spec + policy XML under `apis/<api>/` and add an entry to the catalogue in [apis.tf](apis.tf) — `local.gateway_apis_raw`, or `local.dependent_apis_raw` if it must be created after another API/backend (set `api_depends_on`). [modules/gateway-api](modules/gateway-api/README.md) creates the API, policies, diagnostics and optional product; fragment/named-value/logger dependencies are already wired via `local.api_policy_depends_on` |
| Add a new named value | Add resource in [modules/apim/main.tf](modules/apim/main.tf) or [modules/apim/named-values-extras.tf](modules/apim/named-values-extras.tf) + add its ID to the `named_value_ids` output in [modules/apim/outputs.tf](modules/apim/outputs.tf) |
| Change the generated routing fragments | Edit the templates in [modules/llm-routing/templates/](modules/llm-routing/templates/) or the generator `locals` in [modules/llm-routing/main.tf](modules/llm-routing/main.tf) |
| Add a new backend pool routing rule | Add to `var.llm_backend_config` — dynamic fragments regenerate automatically |
| Add a per-use-case access contract | Add a service entry to `var.services` (+ `var.api_name_mapping`) in the standalone [citadel-access-contracts/](citadel-access-contracts/) module (no XML edits unless you need custom per-service `policy_xml`) |
| Onboard an LLM backend to a live APIM | Add to `var.llm_backend_config` in the standalone [llm-backend-onboarding/](llm-backend-onboarding/) module |

---

## 9. Standalone onboarding modules

Two root modules re-use the same policy model but target an **already-running**
APIM via `data` sources (no APIM creation). They are for day-2 onboarding and
are not wired from the core deployment.

### 9.1 Access contracts onboarding

[citadel-access-contracts/main.tf](citadel-access-contracts/main.tf) onboards a
single use-case. Inputs are `var.apim`, `var.use_case`
(`{ business_unit, use_case_name, environment }`), `var.api_name_mapping`
(service code → existing APIM API names), and `var.services` (list of
`{ code, endpoint_secret_name, api_key_secret_name, policy_xml }`). Per service
`code` it creates:

- An APIM product `<code>-<business_unit>-<use_case_name>-<environment>`.
- Product→API links from `var.api_name_mapping[code]`.
- A product policy (`policy_xml`, else `policies/default-ai-product-policy.xml`).
- A subscription `<…>-SUB-01`.
- Optional Key Vault secrets for the endpoint + key (`var.use_target_key_vault`; secret names lower-cased, `_`→`-`).
- An optional Foundry connection (`var.use_target_foundry`) via
  `azapi_resource.foundry_connection`, type
  `Microsoft.CognitiveServices/accounts/projects/connections@2026-03-01`
  (auth `ApiKey`, metadata from `var.foundry_config`).

> This replaces the older `enable_access_contracts` + `var.access_contracts`
> wiring. The unused in-graph `modules/access-contracts/` duplicate was removed;
> `citadel-access-contracts/` is the single implementation.

### 9.2 LLM backend onboarding

[llm-backend-onboarding/main.tf](llm-backend-onboarding/main.tf) registers LLM
backends + routing against an existing APIM (`data.azurerm_api_management.citadel`).
It creates:

- `azapi_resource.llm_backend` (`Microsoft.ApiManagement/service/backends@2024-06-01-preview`) per backend, with circuit-breaker rules gated on `var.configure_circuit_breaker`, and `<model>-backend-pool`s for any model served by 2+ backends.
- The 3 dynamic fragments (`set-backend-pools`, `get-available-models`, `metadata-config`) plus `resolve-model-alias`, all with `var.model_aliases` support.
- A focused static-fragment set: `set-backend-authorization`, `set-target-backend-pool`, `set-llm-requested-model`, `set-llm-usage`, `validate-model-access`, `responses-id-security`, `responses-id-cache-store`.
- Named values `aws-access-key` / `aws-secret-key` (Key Vault references via `aws_access_key_secret_uri` / `aws_secret_key_secret_uri`, otherwise non-secret `NOT_CONFIGURED` placeholders) and `aws-region` (AWS Bedrock auth), and a per-backend `backend_api_key` named value (Key Vault reference or explicit value) for each backend with `auth_config.named_value_key`.
