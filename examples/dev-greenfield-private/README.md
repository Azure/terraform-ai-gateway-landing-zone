# Dev, greenfield, fully private

Everything private in a VNet this repository owns (no platform-team
dependency): greenfield VNet, subnets and all `privatelink.*` zones; APIM
StandardV2 with outbound integration and an inbound private endpoint (public
access off); keyless usage pipeline on an ILB ASE v3 (run-from-package);
Entra JWT auth from the identity stack; a CI runner subnet (`snet-cicd`) for
a GitHub-hosted runner with Azure private networking. Apply from that runner
(repository variable `RUNNER_<env>`); a laptop can't reach the private data
planes.

Monitoring is private too: an Azure Monitor Private Link Scope with a private
endpoint (the five Azure Monitor zones, `private_dns.link_monitor_zone`).
Log Analytics and every App Insights component accept telemetry only through
it; the Logic App and Foundry components accept queries only through it. The
workspace and the APIM component keep public query: the usage pipeline's
Logic App connector reads the APIM component through Resource Manager, which
can't use private links, and its data lives in the workspace. So the other
components' data also stays queryable through the workspace (RBAC applies).
Portal queries of the closed components work only from a network connected to
the scope (the runner VNet, or a jump box linked with
`private_dns.extra_vnet_link_ids`).

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
