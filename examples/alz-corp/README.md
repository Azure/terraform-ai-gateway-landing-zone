# Azure Landing Zone, Corp (production)

Application landing zone under the Corp management group. Subscription
vending provides the spoke VNet (peered, UDR to the hub firewall), the
workload resource group and the two pipeline identities; the hub owns the
`privatelink.*` zones and the ALZ `Deploy-Private-DNS-Zones` policy binds
most of them. This repository adds subnets + NSGs + UDRs (`alz_spoke`), the
ILB ASE v3, Premium APIM with classic internal VNet injection, and keyless
services only. Runs from a private runner. Platform-team requests:
`docs/operations/platform-team-requests.md`.

Monitoring is private: the App Insights components join the hub's Azure
Monitor Private Link Scope (`monitoring.existing_private_link_scope_id`; the
apply identity gets Monitoring Contributor on it in `bootstrap.tfvars`) and
accept telemetry only through it. Public query is closed on the Logic App and
Foundry components and stays on the APIM component, which the usage
pipeline's Logic App connector reads through Resource Manager. The central
workspace keeps the platform team's settings, but must accept public queries:
the APIM component's data lives there, and a closed workspace returns the
connector's queries empty (the usage export then silently exports nothing).
The APIM and Logic App components also accept only managed identity ingestion
(`monitoring.app_insights_entra_ingestion`, the default): the APIM logger and
the Logic App runtime send as their identities (Monitoring Metrics Publisher),
so the instrumentation key alone can't send telemetry. The loggers' credentials
are Key Vault secrets read through Key Vault-backed named values
(`apim_logging.credentials_in_key_vault`, the default), so APIM holds no secret
named values of its own ("API Management secret named values should be stored in
Azure Key Vault").
A hub-and-spoke that shares DNS takes one scope (the hub's): a second one
would overwrite the hub's records.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
