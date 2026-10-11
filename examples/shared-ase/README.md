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
  not created here. Azure allows one private DNS zone per name on a VNet, so
  the ASE VNet must not already be linked to `privatelink.*` zones of the same
  names (the link fails with "a virtual network cannot be linked to multiple
  zones with overlapping namespaces"); remove its own links first.
- The ASE's own `<ase>.appserviceenvironment.net` zone stays with its owner.
  Publishing the workflows (`code_deploy`) uploads the package to this
  workload's storage account (Entra ID data plane) and the site runs from it,
  so the runner needs access to that storage account, not to the ASE.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

`bootstrap` needs the ASE to exist (the role assignment is scoped to it). The
peering is the one manual step, between `task apply STACK=network` and the
platform stack:

```bash
az network vnet peering create -g <rg-ase> --vnet-name <vnet-ase> -n to-<env> --remote-vnet <this-vnet-id> --allow-vnet-access
az network vnet peering create -g rg-<workload>-<env> --vnet-name vnet-<workload>-<env> -n to-ase --remote-vnet <ase-vnet-id> --allow-vnet-access
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
