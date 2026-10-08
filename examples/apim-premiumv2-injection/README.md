# APIM PremiumV2, VNet injection

PremiumV2 injected into `snet-apim` (delegated to
`Microsoft.Web/hostingEnvironments`, at least /27) with a private gateway
VIP; private DNS for the gateway hostname. Injection is create-time only.
In Corp, v2 SKUs need an `Enforce-GR-APIM` exemption.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
