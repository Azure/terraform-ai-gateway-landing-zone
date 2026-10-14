# Every optional capability

A reference environment that switches on everything the stacks can deploy, so
you can copy the parts you need. It is not a recommendation to enable it all:

| Area | What is on |
|------|------------|
| Network | explicit subnet CIDRs, no default outbound access, the Azure Monitor private link zones (`monitor`, `oms`, `ods`, `agentsvc`), an extra VNet linked to every private DNS zone |
| Platform | StandardV2 with VNet integration and an inbound private endpoint, two Foundry regions, Azure Managed Redis semantic cache, API Center (Standard, with a remote MCP server catalogued), Azure Monitor Private Link Scope with Log Analytics and App Insights public ingestion off, managed identity ingestion only on the APIM and Logic App components (`app_insights_entra_ingestion`), and public query off on the Logic App and Foundry components (kept on the workspace and the APIM component, which the usage pipeline's Logic App connector reads), verbose APIM logging, Event Hub capacity 2 |
| Gateway config | Entra JWT auth, PII redaction and anonymization, Content Safety, Azure AI Search, Document Intelligence, embeddings backend (semantic cache), MCP sample, API diagnostics, API Center onboarding |
| LLM APIs | universal, unified, AI model inference and OpenAI realtime APIs, aliases |
| Contracts | a multi-service contract (LLM + AI Search + Document Intelligence) writing to the platform Key Vault, a key-less contract (`key_vault.enabled = false`), a **mixed-asset contract** (LLM + MCP tools in one product, with per-type limits) and a **tools-only contract** |

The semantic cache needs an embeddings deployment: `platform.tfvars` deploys
`text-embedding-3-large` and `gateway-config.tfvars` points the APIM
embeddings backend at it (`embeddings_backend_url`; take the account endpoint
from `task output STACK=platform NAME=foundry_endpoints`). The Entra auth needs the identity stack, so bootstrap runs with
`graph_permissions` on (the default; needs a Privileged Role Administrator).

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

Run from a runner with access to the private endpoints (see
`dev-greenfield-private`). A stack runs only if its `<stack>.tfvars` exists,
so the files in this folder define the topology. See
`docs/deployment-scenarios.md`.
