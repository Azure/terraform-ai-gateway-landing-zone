# No Foundry: Language and Content Safety only

For customers that don't want Foundry accounts but still want the gateway's
PII redaction and content safety. `platform.tfvars` turns Foundry off
(`foundry = { enabled = false }`) and deploys two **standalone Cognitive
Services accounts** instead, the same resource provider as a Foundry account
but a different kind:

| Account | Kind | Used for |
|---|---|---|
| `lang-<workload>-<env>-<seed>` | `TextAnalytics` (Language) | PII redaction and anonymization (`pii_service`) |
| `cs-<workload>-<env>-<seed>` | `ContentSafety` | the content-safety backend (`content_safety_service`) |

Each has a private endpoint, Entra-only auth (no keys) and the
`Cognitive Services User` role for the APIM identity.
`gateway-config.tfvars` selects them with `source = "dedicated"`; use
`source = "url"` instead to point at existing services, or switch the
features off in `gateway-config.tfvars`.

There are no Foundry deployments to derive LLM backends from, so the models
come from `extra_llm_backends` in `llm-backend-onboarding.tfvars` (here an
existing Azure OpenAI resource, called with the APIM managed identity: grant
it `Cognitive Services OpenAI User` there). No Foundry means no agent subnet
(`subnets_enabled.agent = false`), no Foundry Application Insights and no
Foundry connection in the access contract.

The Language and Content Safety services must be available in the region you
choose (`language_service.location` / `content_safety_service.location`
default to the stack location).

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md` and
DEPLOYMENT_GUIDE.md section 6.4.
