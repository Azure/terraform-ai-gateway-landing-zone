# Gateway on an existing APIM

You already have an API Management service (and its resource group and
user-assigned managed identity) and only want this repository's gateway
configuration on it: the shared policy fragments, named values, service
APIs, the LLM backends and routing, and the access contracts. There is no
`network.tfvars`, `app-hosting.tfvars` or `platform.tfvars`, so those stacks
are skipped. `naming.name_overrides` in `common.tfvars` points the stacks at
the existing resources.

**Prerequisites on the existing APIM** (this repository doesn't create them
in this scenario):

- the APIM service uses a user-assigned managed identity (`uami_apim`), and
  that identity can call the backends you list (`Cognitive Services User` /
  `Cognitive Services OpenAI User`);
- an Application Insights logger named `appinsights-logger` and an Azure
  Monitor logger named `azuremonitor`; the shared APIs reference them;
- the `usage-eventhub-logger` and `pii-usage-eventhub-logger` loggers if you
  want usage and PII-usage logging (the fragments reference them);
- a Key Vault the apply identity can write secrets to (`Key Vault Secrets
  Officer`), named in each contract's `key_vault.id`.

It is a **fresh install of the gateway configuration**: APIs, products,
fragments and named values with the same names must not already exist on that
APIM (there is no import path). The Foundry-derived PII and Content Safety
features and the Foundry-derived backends need the platform's Foundry
naming contract, so they're off here; backends are listed in
`extra_llm_backends`.

Bootstrap runs with `create_workload_resource_group = false`. It still grants
the apply identity `Contributor` and a conditional `Role Based Access Control
Administrator` on that existing resource group (it is the workload group
here), which is more than the gateway configuration needs if the group is
shared with other services; review those two assignments before running
`task bootstrap` against a shared group.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
