# Shared (BYO) App Service Environment

The keyless usage pipeline runs on an ASE v3 that **another team owns** (for
example a central platform ASE shared by several workloads). There is no
`app-hosting.tfvars`, so the app-hosting stack is skipped and no ASE is
created; `usage_pipeline.ase.app_service_environment_id` in `platform.tfvars`
points the Isolated v2 plan and the Logic App at the shared one. Everything
else is the greenfield private shape of `dev-greenfield-private`.

What you need from the ASE owner:

- The apply identity needs `Microsoft.Web/hostingEnvironments/join/action` on
  the ASE (`bootstrap.tfvars` grants it through
  `additional_apply_role_assignments`).
- Network line of sight: the Logic App's storage, Event Hub and Cosmos DB
  private endpoints live in this workload's `snet-pe`. The ASE VNet must be
  peered with this VNet and linked to its private DNS zones
  (`network.tfvars` `private_dns.extra_vnet_link_ids`); the peering itself is
  not created here.
- The ASE's own `<ase>.appserviceenvironment.net` zone stays with its owner.
  Publishing the workflows (`code_deploy`) needs a runner that resolves it.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
