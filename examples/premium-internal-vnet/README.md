# APIM Premium, internal VNet (classic injection)

Premium APIM with three units across zones, injected into `snet-apim` with a
private VIP; private DNS for the five `*.azure-api.net` hostnames is created
for the VNet. Gateway callers must be in (or routed to) the VNet.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
