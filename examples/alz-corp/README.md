# Azure Landing Zone, Corp (production)

Application landing zone under the Corp management group. Subscription
vending provides the spoke VNet (peered, UDR to the hub firewall), the
workload resource group and the two pipeline identities; the hub owns the
`privatelink.*` zones and the ALZ `Deploy-Private-DNS-Zones` policy binds
most of them. This repository adds subnets + NSGs + UDRs (`alz_spoke`), the
ILB ASE v3, Premium APIM with classic internal VNet injection, and keyless
services only. Runs from a private runner. Platform-team requests:
`docs/operations/platform-team-requests.md`.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
