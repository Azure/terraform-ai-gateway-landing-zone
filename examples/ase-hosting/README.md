# ASE v3 hosting, every setting explained

The usage pipeline (Event Hub to Logic App to Cosmos DB) runs **keyless** on an
App Service Environment v3: Isolated v2 plan, internal load balancer, no
storage account keys. This folder is a reference for how that hosting is
configured. Every ASE setting is set explicitly, with the alternatives in
comments. The rest is a small greenfield gateway (StandardV2, one Foundry
account, one contract) so the environment is complete.

Where each setting lives:

| Stack file | Setting | Value here | What it does |
|---|---|---|---|
| `network.tfvars` | `subnets_enabled.ase` | `true` | creates `snet-ase`, delegated to `Microsoft.Web/hostingEnvironments`, with its NSG |
| | `subnet_prefixes.ase` | `10.170.1.0/24` | the subnet's range: a dedicated `/24` (`/27` minimum), empty |
| `app-hosting.tfvars` | `ase.internal_load_balancing_mode` | `Web, Publishing` | internal ASE: apps and SCM reachable only from the VNet. `None` is an external ASE (public inbound address, no private DNS zone); Corp forbids it (`AseDenyPublicIP`) |
| | `ase.zone_redundant` | `true` | spreads the ASE over availability zones (the region needs them) |
| | `ase.subnet_id` | unset | greenfield finds `snet-ase` by name; `alz_spoke` / `byo` give the subnet ID |
| | `dns.create` | `true` | creates `<ase>.appserviceenvironment.net` (`*`, `*.scm`, `@` to the inbound IP). `false` when a hub owns the zone |
| | `dns.vnet_link_ids` | unset | links the zone to the gateway VNet; set it to link more (runner, hub). It replaces the default |
| `platform.tfvars` | `usage_pipeline.logic_app.hosting` | `ase_v3` | Isolated v2 plan in the ASE, keyless storage |
| | `…logic_app.sku` | `I2v2` | Isolated v2 size, `I1v2` to `I6v2` (the memory-optimised `I1mv2` to `I5mv2` aren't supported by the App Service plan module yet) |
| | `…logic_app.worker_count` / `max_worker_count` | `2` / `6` | the plan autoscales on CPU between them (+1 above 70 %, -1 below 30 %) |
| | `…logic_app.deployment` | `run_from_package` | the workflow zip is a blob that the app loads through its managed identity; `zip_deploy` pushes it to the SCM endpoint instead |
| | `…logic_app.code_deploy` | `true` | `false` creates the app without publishing the workflows |
| | `usage_pipeline.ase.zone_redundant` | `true` | zone-balances the plan |
| | `usage_pipeline.ase.app_service_environment_id` | unset | a shared ASE owned by someone else (see [shared-ase](../shared-ase/)) |
| | `deny_storage_shared_key` | `true` | assigns the "Storage accounts should prevent shared key access" policy on the workload resource group |

**Zone redundancy is set twice** and the two must agree: `ase.zone_redundant`
in `app-hosting.tfvars` makes the ASE zone redundant, and
`usage_pipeline.ase.zone_redundant` in `platform.tfvars` zone-balances the plan
inside it. Turn both on or both off.

**Where it runs from.** The apply uploads the workflow package to the keyless
storage account, which has no public endpoint, so run it from a runner that
reaches the storage private endpoint: GitHub-hosted runners with Azure private
networking in `snet-cicd` (repository variable `RUNNER_<env>`) or a self-hosted
runner VM (`cicd_subnet_delegation = "none"`). With `deployment = "zip_deploy"`
the runner must also resolve `<app>.scm.<ase>.appserviceenvironment.net`, which
means a VNet link to the ASE zone. For non-production laptop runs see
`dev_access` in [DEPLOYMENT_GUIDE.md](../../docs/DEPLOYMENT_GUIDE.md) section 4.5.

**Time and cost.** Creating the ASE takes 2 to 4 hours (`app-hosting`), and an
ASE v3 carries a fixed hourly charge on top of the Isolated v2 instances. Apply
`app-hosting` on its own the first time (`task apply STACK=app-hosting
ENV=<env>`) with a long timeout; `task up` runs it for you in order.

These files are checked against the stacks with mocked providers
(`scripts/ci/check-examples.sh`). The internal-ASE shape with `run_from_package`
was deployed live; the sizes, zone redundancy and the alternatives in the
comments are validated by plan only.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
