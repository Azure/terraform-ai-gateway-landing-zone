# Minimal dev (cheapest)

Smallest useful gateway: APIM StandardV2 without VNet integration (public,
private endpoints for the data services only), no API Center, no Redis, one
Foundry model, Workflow Standard usage pipeline, no identity stack.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
