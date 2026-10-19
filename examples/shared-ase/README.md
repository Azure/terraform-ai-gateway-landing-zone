# Shared (BYO) App Service Environment


## Scenario Overview
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


## Deployment Instructions
Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`). `task up` is not used here because the
VNet peering is a manual step that has to sit between the network and platform
stacks. Run the stacks one by one instead:

1. Bootstrap, once (Contributor + User Access Administrator). It creates the
   state account, workload RG and pipeline identities, and writes
   `backend.hcl`. The ASE must already exist, because the `join/action` role
   assignment is scoped to it.

   ```bash
   task bootstrap ENV=<env>
   task preflight ENV=<env>   # Azure Policy check (task up would run it for you)
   ```

2. Network. It creates this workload's VNet and private DNS zones, and links
   the zones to the ASE VNet.

   ```bash
   task apply STACK=network ENV=<env>
   ```

3. Peer the two VNets. This is the manual step: it needs Network Contributor
   on both VNets, so the ASE owner usually runs the first command.

   ```bash
   VNET_ID=$(task output STACK=network ENV=<env> NAME="-raw vnet_id")
   ASE_VNET_ID="/subscriptions/<sub>/resourceGroups/<rg-ase>/providers/Microsoft.Network/virtualNetworks/<vnet-ase>"

   az network vnet peering create -g <rg-ase> --vnet-name <vnet-ase> -n to-<env> --remote-vnet "$VNET_ID" --allow-vnet-access
   az network vnet peering create -g rg-<workload>-<env> --vnet-name vnet-<workload>-<env> -n to-ase --remote-vnet "$ASE_VNET_ID" --allow-vnet-access
   ```

   Both peerings must show `Connected` before the platform stack runs. The
   Logic App on the ASE reaches its storage, Event Hub and Cosmos DB through
   the private endpoints in `snet-pe`:

   ```bash
   az network vnet peering show --ids "$VNET_ID/virtualNetworkPeerings/to-ase" --query peeringState -o tsv
   ```

4. Remaining stacks and the access contract:

   ```bash
   task apply STACK=platform ENV=<env>
   task apply STACK=gateway-config ENV=<env>
   task apply STACK=llm-backend-onboarding ENV=<env>
   task contracts ENV=<env>
   ```

After the peering exists, `task up ENV=<env> PREFLIGHT=false` is safe for
later re-applies; it plans the network stack again (no changes) and keeps
going. `task down` does not delete the peering. Remove both peerings
(`az network vnet peering delete`) after `task down` and before you delete the
ASE VNet's DNS links or reuse the address space.

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See [`DEPLOYMENT_SCENARIOS.md`](../../docs/DEPLOYMENT_SCENARIOS.md) and
[`DEPLOYMENT_GUIDE.md`](../../docs/DEPLOYMENT_GUIDE.md).
