# Every kind of LLM backend

One gateway in front of Microsoft Foundry, AWS (two ways), Google Gemini and an
external OpenAI-compatible provider. [multi-provider-llm](../multi-provider-llm/)
shows load balancing and aliases; this example shows each **backend type**, how
it authenticates and which client path reaches it.

| Backend | `backend_type` | Authentication | Secret in Key Vault | Client path |
|---|---|---|---|---|
| Foundry (account of `platform.tfvars`) | derived, `ai-foundry` | managed identity of APIM | none | Universal LLM API `/models/chat/completions`, Azure OpenAI API, `/unified-ai/v1/chat/completions` |
| External OpenAI-compatible | `external` | `api-key-bearer` | `Bearer <key>` | Universal LLM API `/models/chat/completions` |
| Google Gemini | `gemini-openai` | `api-key-bearer` | `Bearer <key>` | Unified AI API `/unified-ai/v1/chat/completions` |
| AWS Bedrock Mantle (OpenAI-compatible) | `aws-bedrock-mantle` | `api-key-bearer` | `Bearer <key>` | Unified AI API `/unified-ai/v1/chat/completions` |
| AWS Bedrock (native Converse) | `aws-bedrock` | `aws-sigv4`, signed in the gateway policy | access key id and secret key (`aws` variable) | Unified AI API `/unified-ai/model/{modelId}/converse` |

How the key reaches the provider: for `api-key-bearer` (and `api-key-header`)
APIM adds the named value as a header of the backend (`Authorization`, or
`api-key`). APIM only substitutes a named value that is the **whole** header
value, so the Key Vault secret holds `Bearer <key>`, not the bare key.

The model alias `multi-cloud` lists a Foundry, a Bedrock Mantle and a Gemini model:
a request for it goes to Foundry first and falls back to the others when that
fails (all three speak the OpenAI chat completions API).

## Before the first apply of the llm stack

Create the secrets in the platform Key Vault (the APIM identity reads them with
`Key Vault Secrets User`, which `stacks/platform` grants):

```bash
KV=$(task output STACK=platform ENV=<env> NAME="-raw key_vault_name")
az keyvault secret set --vault-name "$KV" -n partner-api-key        --value "Bearer <partner key>"
az keyvault secret set --vault-name "$KV" -n gemini-api-key         --value "Bearer <Google AI Studio key>"
az keyvault secret set --vault-name "$KV" -n bedrock-mantle-api-key --value "Bearer <Bedrock API key>"
az keyvault secret set --vault-name "$KV" -n aws-access-key         --value "<AWS access key id>"
az keyvault secret set --vault-name "$KV" -n aws-secret-key         --value "<AWS secret access key>"
```

Replace `<key-vault-name>` in `llm-backend-onboarding.tfvars` with that vault,
and the endpoints and model names with the ones of your accounts.

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

The contract writes two endpoint/key pairs to Key Vault (`TEAMC-LLM-*` for the
Universal LLM API, `TEAMC-UAI-*` for the Unified AI API):

```bash
LLM=$(az keyvault secret show --vault-name "$KV" -n TEAMC-LLM-ENDPOINT --query value -o tsv)
LLMKEY=$(az keyvault secret show --vault-name "$KV" -n TEAMC-LLM-KEY --query value -o tsv)
UAI=$(az keyvault secret show --vault-name "$KV" -n TEAMC-UAI-ENDPOINT --query value -o tsv)
UAIKEY=$(az keyvault secret show --vault-name "$KV" -n TEAMC-UAI-KEY --query value -o tsv)

# Foundry, and the external provider (Universal LLM API)
curl -s "$LLM/chat/completions" -H "api-key: $LLMKEY" -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.4-mini","messages":[{"role":"user","content":"Hello"}]}'
curl -s "$LLM/chat/completions" -H "api-key: $LLMKEY" -H "Content-Type: application/json" \
  -d '{"model":"partner-large","messages":[{"role":"user","content":"Hello"}]}'

# Gemini, Bedrock Mantle and the multi-cloud alias (Unified AI API, OpenAI-compatible)
curl -s "$UAI/v1/chat/completions" -H "api-key: $UAIKEY" -H "Content-Type: application/json" \
  -d '{"model":"gemini-2.5-flash","messages":[{"role":"user","content":"Hello"}]}'
curl -s "$UAI/v1/chat/completions" -H "api-key: $UAIKEY" -H "Content-Type: application/json" \
  -d '{"model":"multi-cloud","messages":[{"role":"user","content":"Hello"}]}'

# Bedrock, native Converse API
curl -s "$UAI/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse" -H "api-key: $UAIKEY" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":[{"text":"Hello"}]}]}'
```

## Limits

- `external` backends are served by the Universal LLM API only (there is no path
  template for them in the Unified AI API), and the Universal LLM API rewrites
  the URL for Foundry and Azure OpenAI only: that's why Gemini and Bedrock go
  through `/unified-ai`, and why the external endpoint carries its `/v1`.
- The Unified AI API takes the backend from the model name. Bedrock model ids
  contain `:` and `.`: keep them in `allowed_models` exactly as AWS names them.
- The provider paths are built by the fragments of
  `stacks/llm-backend-onboarding/fragments` and `modules/llm-routing/templates`.
  The Gemini, AWS and partner endpoints need accounts of yours: the Foundry
  path is the one the quickstart verifies.

A stack runs only if its `<stack>.tfvars` exists, so the files in this folder
define the topology. See `docs/deployment-scenarios.md`.
