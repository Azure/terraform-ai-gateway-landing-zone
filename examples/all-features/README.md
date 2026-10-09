# Every optional capability

A reference environment that switches on everything the stacks can deploy, so
you can copy the parts you need. It is not a recommendation to enable it all:

| Area | What is on |
|------|------------|
| Network | explicit subnet CIDRs, no default outbound access, `privatelink.monitor.azure.com`, an extra VNet linked to every private DNS zone |
| Platform | StandardV2 with VNet integration and an inbound private endpoint, two Foundry regions, Azure Managed Redis semantic cache, API Center (Standard), Azure Monitor Private Link Scope, verbose APIM logging, Event Hub capacity 2 |
| Gateway config | Entra JWT auth, PII redaction and anonymization, Content Safety, Azure AI Search, Document Intelligence, embeddings backend (semantic cache), MCP sample, API diagnostics, API Center onboarding |
| LLM APIs | universal, unified, AI model inference and OpenAI realtime APIs, aliases |
| Contracts | a multi-service contract (LLM + AI Search + Document Intelligence) writing to the platform Key Vault, and a key-less contract (`key_vault.enabled = false`) |

The semantic cache needs an embeddings deployment: `platform.tfvars` deploys
`text-embedding-3-large` and `gateway-config.tfvars` points the APIM
embeddings backend at it (`embeddings_backend_url`; take the account endpoint
from `task output STACK=platform NAME=foundry_endpoints`). The Entra auth needs the identity stack, so bootstrap runs with
`graph_permissions` on (the default; needs a Privileged Role Administrator).

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

Run from a runner with access to the private endpoints (see
`dev-greenfield-private`). A stack runs only if its `<stack>.tfvars` exists,
so the files in this folder define the topology. See
`docs/deployment-scenarios.md`.
