# APIM StandardV2, private endpoint + outbound integration

StandardV2 with outbound VNet integration (`snet-apim` delegated to
`Microsoft.Web/serverFarms`) and an inbound private endpoint; public access
is closed on the second apply (Azure rejects creating it closed). Bicep
parity for v2 SKUs.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
