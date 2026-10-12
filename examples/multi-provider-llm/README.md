# Multi-provider LLM backends

One gateway in front of Microsoft Foundry, Azure OpenAI, AWS (two ways), Google
Gemini and an external OpenAI-compatible provider: each **backend type**, how it
authenticates, which client path reaches it, and how requests are balanced and
failed over.

| Backend | `backend_type` | Authentication | Secret in Key Vault | Client path |
|---|---|---|---|---|
| Foundry (two accounts of `platform.tfvars`) | derived, `ai-foundry` | managed identity of APIM | none | Universal LLM API `/models/chat/completions`, Azure OpenAI API, `/unified-ai/v1/chat/completions` |
| Azure OpenAI outside Foundry | `azure-openai` | `managed-identity` | none | Universal LLM API `/models/chat/completions`, Azure OpenAI API, `/unified-ai/v1/chat/completions` |
| External OpenAI-compatible | `external` | `api-key-bearer` | `Bearer <key>` | Universal LLM API `/models/chat/completions`, `/unified-ai/v1/chat/completions` |
| Google Gemini | `gemini-openai` | `api-key-bearer` | `Bearer <key>` | Universal LLM API `/models/chat/completions`, `/unified-ai/v1/chat/completions` |
| AWS Bedrock Mantle (OpenAI-compatible) | `aws-bedrock-mantle` | `api-key-bearer` | `Bearer <key>` | Universal LLM API `/models/chat/completions`, `/unified-ai/v1/chat/completions` |
| AWS Bedrock (native Converse) | `aws-bedrock` | `aws-sigv4`, signed in the gateway policy | access key id and secret key (`aws` variable) | Unified AI API `/unified-ai/bedrock/model/{modelId}/converse` |

How the key reaches the provider: for `api-key-bearer` (and `api-key-header`)
APIM adds the named value as a header of the backend (`Authorization`, or
`api-key`). APIM only substitutes a named value that is the **whole** header
value, so the Key Vault secret holds `Bearer <key>`, not the bare key.

## Balancing, failover and circuit breakers

- **Pool.** `platform.tfvars` deploys two Foundry accounts in two regions with
  `gpt-5.4-mini` on both, so APIM builds one load-balanced backend pool for that model.
- **Aliases** (`model_aliases`): `fast` fails over `gpt-5.4-mini` to `gpt-4.1` (the Azure
  OpenAI resource, another backend type) with the `priority` strategy; `balanced` splits
  traffic 80/20 between two models (`weighted`); `multi-cloud` lists a Foundry, a Bedrock
  Mantle and a Gemini model and falls back down the list (all three speak the OpenAI chat
  completions API).
- **Circuit breaker per backend** (`circuit_breaker`): the Foundry-derived backends use
  `foundry_backends.circuit_breaker`; the Azure OpenAI backend trips faster and recovers
  sooner, the external partner counts every 429 and 5xx and honours its `Retry-After`,
  Gemini and Mantle keep the defaults, and native Bedrock has none.

## Contracts

Two access contracts (`access-contracts/`), one state each:

- `team-c-multicloud`: two services (the Universal LLM API and the Unified AI API have
  different paths, so different endpoint secrets), with an allowed-model list and a token limit.
- `team-b-agents`: a project in the team's own Foundry account and the team's own Key
  Vault, with a ModelGateway connection (API key, static model list).

## Before the first apply of the llm stack

Create the secrets in the platform Key Vault (the APIM identity reads them with
`Key Vault Secrets User`, which `stacks/platform` grants, or in any vault it can read):

```bash
KV=$(task output STACK=platform ENV=<env> NAME="-raw key_vault_name")
az keyvault secret set --vault-name "$KV" -n partner-api-key        --value "Bearer <partner key>"
az keyvault secret set --vault-name "$KV" -n gemini-api-key         --value "Bearer <Google AI Studio key>"
az keyvault secret set --vault-name "$KV" -n bedrock-mantle-api-key --value "Bearer <Bedrock API key>"
az keyvault secret set --vault-name "$KV" -n aws-access-key         --value "<AWS access key id>"
az keyvault secret set --vault-name "$KV" -n aws-secret-key         --value "<AWS secret access key>"
```

Replace `<key-vault-name>` in `llm-backend-onboarding.tfvars` with that vault, the
`<aoai-resource>` and the endpoints and model names with the ones of your accounts, and
the `<team-...>` placeholders of `team-b-agents.tfvars` with the team's resources.

## Deploy

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

`task output STACK=llm-backend-onboarding ENV=<env> NAME=llm_backends` lists what
was deployed: each backend with its source, type, models and circuit breaker.

## Calling each backend

The `team-c-multicloud` contract writes two endpoint/key pairs to Key Vault
(`TEAMC-LLM-*` for the Universal LLM API, `TEAMC-UAI-*` for the Unified AI API):

```bash
LLM=$(az keyvault secret show --vault-name "$KV" -n TEAMC-LLM-ENDPOINT --query value -o tsv)
LLMKEY=$(az keyvault secret show --vault-name "$KV" -n TEAMC-LLM-KEY --query value -o tsv)
UAI=$(az keyvault secret show --vault-name "$KV" -n TEAMC-UAI-ENDPOINT --query value -o tsv)
UAIKEY=$(az keyvault secret show --vault-name "$KV" -n TEAMC-UAI-KEY --query value -o tsv)

# Foundry, Azure OpenAI, the external provider, Gemini and Bedrock Mantle (Universal LLM API): the same call for all
for MODEL in gpt-5.4-mini gpt-4.1 partner-large gemini-2.5-flash openai.gpt-oss-120b; do
  curl -s "$LLM/chat/completions" -H "api-key: $LLMKEY" -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}"
done

# The same through the Unified AI API (OpenAI-compatible surface), and the multi-cloud alias
curl -s "$UAI/v1/chat/completions" -H "api-key: $UAIKEY" -H "Content-Type: application/json" \
  -d '{"model":"gemini-2.5-flash","messages":[{"role":"user","content":"Hello"}]}'
curl -s "$UAI/v1/chat/completions" -H "api-key: $UAIKEY" -H "Content-Type: application/json" \
  -d '{"model":"multi-cloud","messages":[{"role":"user","content":"Hello"}]}'

# Bedrock, native Converse API (only on the Unified AI API, under /bedrock)
curl -s "$UAI/bedrock/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse" -H "api-key: $UAIKEY" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":[{"text":"Hello"}]}]}'
```

## Limits

- Each API surface only routes to the backend types it can speak to (the
  `compatiblePoolTypes` of its policy): the Universal LLM API and the OpenAI-compatible
  Unified surface to `ai-foundry`, `azure-openai`, `aws-bedrock-mantle`, `gemini-openai`
  and `external`; the Azure OpenAI API to `azure-openai` and `ai-foundry`; native Bedrock
  (`/unified-ai/bedrock`) to `aws-bedrock` only. `external` is this repository's addition
  to the upstream accelerator, which doesn't route to it: its endpoint carries the API
  root (`https://api.partner.example.com/v1`) and the gateway appends `/chat/completions`.
- The gateway takes the backend from the model name. Bedrock model ids contain `:`
  and `.`: keep them in `allowed_models` exactly as AWS names them. A model hosted by two
  backend types is two separate pools, so give each backend its own models unless an
  alias is meant to bridge them.
- The provider paths are built by the fragments of
  `stacks/llm-backend-onboarding/fragments` and `modules/llm-routing/templates`.
  The Azure OpenAI, Gemini, AWS and partner endpoints need accounts of yours: nothing
  here was called against them.

A stack runs only if its `<stack>.tfvars` exists, so the files in this folder
define the topology. See `docs/deployment-scenarios.md`.
